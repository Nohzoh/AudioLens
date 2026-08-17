package io.nohzoh.audiolens

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat

/// Exists purely to protect the app process's priority while an analysis
/// (GPS + AI + TTS, or TTS-only replay) is in flight — without it, Android
/// can kill the whole process while backgrounded (T85), silently dropping
/// the analysis. It does not run any of the analysis work itself: that
/// keeps happening on the existing Flutter engine/isolate exactly as
/// before, this service just needs to exist and hold a foreground
/// notification for the OS to leave the process alone.
class AnalysisForegroundService : Service() {

    companion object {
        const val CHANNEL_ID = "analysis_progress"
        const val NOTIFICATION_ID = 4201
    }

    override fun onCreate() {
        super.onCreate()
        val manager = getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(
            NotificationChannel(
                CHANNEL_ID,
                "Analyse en arrière-plan",
                NotificationManager.IMPORTANCE_LOW,
            )
        )
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val notification: Notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("AudioLens")
            .setContentText("AudioLens est actif en arrière-plan")
            .setSmallIcon(R.mipmap.ic_notification)
            .setOngoing(true)
            .setSilent(true)
            .build()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC)
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
        return START_NOT_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        stopForeground(STOP_FOREGROUND_REMOVE)
        super.onDestroy()
    }
}
