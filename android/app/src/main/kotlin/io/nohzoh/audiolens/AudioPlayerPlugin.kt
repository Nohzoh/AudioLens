package io.nohzoh.audiolens

import android.content.Context
import android.media.MediaPlayer
import android.media.PlaybackParams
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/// Owns the actual MediaPlayer for Gemini TTS's cached-WAV playback.
/// T118/T21: lock-screen/notification transport controls and audio
/// focus are handled by [PlaybackForegroundService], a separate,
/// deliberately thin service that never touches the MediaPlayer
/// directly — it only sends state updates here (notifyPlaying/Paused/
/// Stopped) and receives button-press callbacks back
/// (pauseFromSession/resumeFromSession/seekFromSession), via the
/// [instance] bridge below (same pattern as SharePlugin.instance).
/// Kept this way rather than moving the MediaPlayer into the service
/// itself, to avoid touching the already-working play/pause/stop/error
/// handling (in particular pendingPlayResult's completion tracking,
/// T76) while adding a large, separately-risky native feature.
class AudioPlayerPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {

    companion object {
        var instance: AudioPlayerPlugin? = null
    }

    private lateinit var channel: MethodChannel
    private lateinit var appContext: Context
    private var mediaPlayer: MediaPlayer? = null
    private val scope = CoroutineScope(Dispatchers.IO)

    // The Dart side of a "playWav" call awaits its result to know when
    // playback finished (T76 — chunked TTS sequencing relies on this).
    // Without tracking it here, calling "stop" while a "playWav" is still
    // in flight would leave that call's Dart-side await hanging forever,
    // since MediaPlayer.stop() alone never completes it.
    private var pendingPlayResult: MethodChannel.Result? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        appContext = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, "audio_guide/audio_player")
        channel.setMethodCallHandler(this)
        instance = this
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        mediaPlayer?.release()
        mediaPlayer = null
        if (instance == this) instance = null
    }

    /// Called by PlaybackForegroundService.sessionCallback when the
    /// lock-screen/notification pause button is pressed.
    fun pauseFromSession() {
        mediaPlayer?.pause()
        PlaybackForegroundService.notifyPaused(appContext)
    }

    /// Called by PlaybackForegroundService.sessionCallback when the
    /// lock-screen/notification play button is pressed.
    fun resumeFromSession() {
        mediaPlayer?.start()
        PlaybackForegroundService.notifyPlaying(appContext, currentTitle)
    }

    /// Called by PlaybackForegroundService.sessionCallback for the
    /// rewind/fast-forward transport controls (±10s, T118/T21).
    fun seekFromSession(deltaMs: Int) {
        seekBy(deltaMs)
    }

    private fun seekBy(deltaMs: Int) {
        mediaPlayer?.let {
            val target = (it.currentPosition + deltaMs).coerceIn(0, it.duration)
            it.seekTo(target)
        }
    }

    // Notification/lock-screen title (T118/T21) — best-effort, defaults
    // to a generic label since playWav's caller (GeminiTtsService) has
    // no concept of "the analysis title", only the WAV file path.
    private var currentTitle: String = "AudioLens"

    private fun resolvePendingPlay() {
        pendingPlayResult?.success(null)
        pendingPlayResult = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "playWav" -> {
                val path = call.argument<String>("path")
                // Multiplier on normal speed (T15), e.g. 1.5 = 50% faster.
                // Applied via PlaybackParams, which by default (no explicit
                // setPitch) time-stretches without changing pitch.
                val speed = call.argument<Double>("speed")?.toFloat() ?: 1.0f
                if (path == null) {
                    result.error("INVALID_ARGS", "path required", null)
                    return
                }
                scope.launch {
                    try {
                        mediaPlayer?.stop()
                        mediaPlayer?.release()
                        withContext(Dispatchers.Main) { resolvePendingPlay() }
                        pendingPlayResult = result
                        mediaPlayer = MediaPlayer().apply {
                            setDataSource(path)
                            prepare()
                            if (speed != 1.0f) {
                                playbackParams = PlaybackParams().setSpeed(speed)
                            }
                            start()
                            setOnCompletionListener {
                                PlaybackForegroundService.notifyStopped(appContext)
                                scope.launch(Dispatchers.Main) { resolvePendingPlay() }
                            }
                            setOnErrorListener { _, _, _ ->
                                PlaybackForegroundService.notifyStopped(appContext)
                                scope.launch(Dispatchers.Main) {
                                    pendingPlayResult?.error("PLAYBACK_ERROR", "Playback failed", null)
                                    pendingPlayResult = null
                                }
                                true
                            }
                        }
                        PlaybackForegroundService.notifyPlaying(appContext, currentTitle)
                    } catch (e: Exception) {
                        withContext(Dispatchers.Main) {
                            pendingPlayResult?.error("PLAYBACK_ERROR", e.message, null)
                            pendingPlayResult = null
                        }
                    }
                }
            }
            "pause" -> {
                mediaPlayer?.pause()
                PlaybackForegroundService.notifyPaused(appContext)
                result.success(null)
            }
            "play" -> {
                mediaPlayer?.start()
                PlaybackForegroundService.notifyPlaying(appContext, currentTitle)
                result.success(null)
            }
            "seekForward" -> {
                seekBy(call.argument<Int>("deltaMs") ?: 10000)
                result.success(null)
            }
            "seekBack" -> {
                seekBy(-(call.argument<Int>("deltaMs") ?: 10000))
                result.success(null)
            }
            "stop" -> {
                mediaPlayer?.stop(); mediaPlayer?.release()
                mediaPlayer = null
                PlaybackForegroundService.notifyStopped(appContext)
                resolvePendingPlay()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }
}
