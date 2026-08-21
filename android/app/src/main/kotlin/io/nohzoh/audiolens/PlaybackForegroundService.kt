package io.nohzoh.audiolens

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.os.Build
import android.os.IBinder
import android.support.v4.media.session.MediaSessionCompat
import android.support.v4.media.session.PlaybackStateCompat
import androidx.core.app.NotificationCompat
import androidx.media.app.NotificationCompat.MediaStyle
import androidx.media.session.MediaButtonReceiver

/// T118/T21 — hosts the MediaSession, audio focus, and lock-screen/
/// notification transport controls (play/pause + skip ±10s) for the
/// Gemini TTS cached-WAV playback path. Deliberately never touches the
/// MediaPlayer directly — [AudioPlayerPlugin] owns that — this service
/// only exchanges state with it via the small companion-object bridge
/// (notifyPlaying/notifyPaused/notifyStopped called from the plugin;
/// AudioPlayerPlugin.instance?.pauseFromSession() etc. called from here
/// when a lock-screen/notification button is pressed).
///
/// Separate from AnalysisForegroundService (T85): different foreground
/// service type (mediaPlayback vs dataSync — Android 14+ enforces these
/// strictly), different lifecycle (only runs while audio is actually
/// playing/paused, not during analysis).
///
/// Native-TTS (on-device) playback does NOT go through this service —
/// see AudioGuideService.canSkip's doc for why skip/lock-screen controls
/// are Gemini-TTS-only in this pass.
class PlaybackForegroundService : Service() {

    companion object {
        const val CHANNEL_ID = "playback_controls"
        const val NOTIFICATION_ID = 4202
        private const val ACTION_PLAYING = "io.nohzoh.audiolens.PLAYBACK_PLAYING"
        private const val ACTION_PAUSED = "io.nohzoh.audiolens.PLAYBACK_PAUSED"
        private const val ACTION_STOPPED = "io.nohzoh.audiolens.PLAYBACK_STOPPED"
        private const val EXTRA_TITLE = "title"

        fun notifyPlaying(context: Context, title: String) {
            val intent = Intent(context, PlaybackForegroundService::class.java)
                .setAction(ACTION_PLAYING)
                .putExtra(EXTRA_TITLE, title)
            context.startForegroundService(intent)
        }

        fun notifyPaused(context: Context) {
            context.startForegroundService(
                Intent(context, PlaybackForegroundService::class.java).setAction(ACTION_PAUSED)
            )
        }

        fun notifyStopped(context: Context) {
            context.startService(
                Intent(context, PlaybackForegroundService::class.java).setAction(ACTION_STOPPED)
            )
        }
    }

    private lateinit var mediaSession: MediaSessionCompat
    private lateinit var audioManager: AudioManager
    private var audioFocusRequest: AudioFocusRequest? = null
    private var currentTitle: String = "AudioLens"

    private val audioFocusListener = AudioManager.OnAudioFocusChangeListener { focusChange ->
        when (focusChange) {
            AudioManager.AUDIOFOCUS_LOSS,
            AudioManager.AUDIOFOCUS_LOSS_TRANSIENT,
            AudioManager.AUDIOFOCUS_LOSS_TRANSIENT_CAN_DUCK -> {
                // A phone call or another app's audio takes priority —
                // pause rather than duck, since spoken narration ducked
                // under something else is unintelligible either way.
                AudioPlayerPlugin.instance?.pauseFromSession()
            }
            else -> {}
        }
    }

    private val sessionCallback = object : MediaSessionCompat.Callback() {
        override fun onPlay() { AudioPlayerPlugin.instance?.resumeFromSession() }
        override fun onPause() { AudioPlayerPlugin.instance?.pauseFromSession() }
        override fun onStop() { AudioPlayerPlugin.instance?.pauseFromSession() }
        override fun onFastForward() { AudioPlayerPlugin.instance?.seekFromSession(10000) }
        override fun onRewind() { AudioPlayerPlugin.instance?.seekFromSession(-10000) }
    }

    override fun onCreate() {
        super.onCreate()
        audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        getSystemService(NotificationManager::class.java).createNotificationChannel(
            NotificationChannel(CHANNEL_ID, "Lecture audio", NotificationManager.IMPORTANCE_LOW)
        )
        mediaSession = MediaSessionCompat(this, "AudioLensPlayback").apply {
            setCallback(sessionCallback)
            isActive = true
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        // A standard media-button press (headset/Bluetooth single/double/
        // triple-tap) arrives as ACTION_MEDIA_BUTTON rather than one of
        // our own custom actions below — MediaButtonReceiver decodes the
        // embedded KeyEvent and dispatches it to sessionCallback above,
        // giving headset button handling without any extra code here.
        MediaButtonReceiver.handleIntent(mediaSession, intent)

        when (intent?.action) {
            ACTION_PLAYING -> {
                currentTitle = intent.getStringExtra(EXTRA_TITLE) ?: currentTitle
                requestAudioFocus()
                updateSessionState(PlaybackStateCompat.STATE_PLAYING)
                startForegroundCompat(buildNotification(isPlaying = true))
            }
            ACTION_PAUSED -> {
                updateSessionState(PlaybackStateCompat.STATE_PAUSED)
                startForegroundCompat(buildNotification(isPlaying = false))
            }
            ACTION_STOPPED -> {
                updateSessionState(PlaybackStateCompat.STATE_STOPPED)
                abandonAudioFocus()
                stopForeground(STOP_FOREGROUND_REMOVE)
                stopSelf()
            }
        }
        return START_NOT_STICKY
    }

    private fun startForegroundCompat(notification: Notification) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK)
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    private fun requestAudioFocus() {
        if (audioFocusRequest != null) return
        val attrs = AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_MEDIA)
            .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
            .build()
        val request = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN)
            .setAudioAttributes(attrs)
            .setOnAudioFocusChangeListener(audioFocusListener)
            .build()
        audioFocusRequest = request
        audioManager.requestAudioFocus(request)
    }

    private fun abandonAudioFocus() {
        audioFocusRequest?.let { audioManager.abandonAudioFocusRequest(it) }
        audioFocusRequest = null
    }

    private fun updateSessionState(state: Int) {
        val actions = PlaybackStateCompat.ACTION_PLAY or
            PlaybackStateCompat.ACTION_PAUSE or
            PlaybackStateCompat.ACTION_PLAY_PAUSE or
            PlaybackStateCompat.ACTION_FAST_FORWARD or
            PlaybackStateCompat.ACTION_REWIND or
            PlaybackStateCompat.ACTION_STOP
        mediaSession.setPlaybackState(
            PlaybackStateCompat.Builder()
                .setActions(actions)
                .setState(state, PlaybackStateCompat.PLAYBACK_POSITION_UNKNOWN, 1f)
                .build()
        )
    }

    private fun buildNotification(isPlaying: Boolean): Notification {
        val playPauseAction = if (isPlaying) {
            NotificationCompat.Action(
                android.R.drawable.ic_media_pause, "Pause",
                MediaButtonReceiver.buildMediaButtonPendingIntent(this, PlaybackStateCompat.ACTION_PAUSE),
            )
        } else {
            NotificationCompat.Action(
                android.R.drawable.ic_media_play, "Lecture",
                MediaButtonReceiver.buildMediaButtonPendingIntent(this, PlaybackStateCompat.ACTION_PLAY),
            )
        }
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle(currentTitle)
            .setContentText("AudioLens")
            .setSmallIcon(R.mipmap.ic_notification)
            .setOngoing(isPlaying)
            .addAction(
                android.R.drawable.ic_media_rew, "-10s",
                MediaButtonReceiver.buildMediaButtonPendingIntent(this, PlaybackStateCompat.ACTION_REWIND),
            )
            .addAction(playPauseAction)
            .addAction(
                android.R.drawable.ic_media_ff, "+10s",
                MediaButtonReceiver.buildMediaButtonPendingIntent(this, PlaybackStateCompat.ACTION_FAST_FORWARD),
            )
            .setStyle(
                MediaStyle()
                    .setMediaSession(mediaSession.sessionToken)
                    .setShowActionsInCompactView(0, 1, 2)
            )
            .build()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        abandonAudioFocus()
        mediaSession.release()
        super.onDestroy()
    }
}
