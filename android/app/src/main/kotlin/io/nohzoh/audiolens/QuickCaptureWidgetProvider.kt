package io.nohzoh.audiolens

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews

/// A 1x1 home-screen widget that jumps straight to the camera, skipping
/// the extra tap of opening the app first and pressing "Take a photo" —
/// tapping it fires the exact same capture+analyze flow as that button
/// (see MainActivity.kt's quick-capture handling and
/// HomeScreen._pickImage(ImageSource.camera) on the Dart side).
///
/// The tap doesn't launch MainActivity directly. An earlier version did
/// (via a PendingIntent carrying ACTION_QUICK_CAPTURE), but that action
/// becomes the launched activity's task's *base intent*, which Android
/// replays whenever it recreates the task after the process was killed
/// — including from a completely ordinary tap on the normal launcher
/// icon, dropping the user into the camera with no widget involved
/// (issue #175). PendingIntent.getBroadcast to this receiver instead:
/// the receiver records a short-lived, single-use "capture requested"
/// marker in SharedPreferences (see requestCapture/consumeIfFresh
/// below) and only *then* starts MainActivity with a plain intent that
/// carries no quick-capture signal of its own — so there's nothing left
/// for Android to persist and replay later.
class QuickCaptureWidgetProvider : AppWidgetProvider() {

    companion object {
        const val ACTION_REQUEST_QUICK_CAPTURE =
            "io.nohzoh.audiolens.ACTION_REQUEST_QUICK_CAPTURE"
        private const val PREFS_NAME = "quick_capture"
        private const val KEY_TIMESTAMP_MS = "timestamp_ms"
        // Generous enough to cover the receiver-to-MainActivity hop
        // (a background broadcast + activity launch) but short enough
        // that a marker somehow left unconsumed (e.g. the app crashing
        // between the broadcast and MainActivity reading it) can't be
        // mistaken for a fresh tap by some later, unrelated launch.
        private const val FRESHNESS_WINDOW_MS = 10_000L

        /// Records that a capture was just requested. Called from this
        /// receiver's onReceive — never from MainActivity, which only
        /// ever consumes.
        private fun requestCapture(context: Context) {
            context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                .edit()
                .putLong(KEY_TIMESTAMP_MS, System.currentTimeMillis())
                .apply()
        }

        /// True at most once per requestCapture call: reads and
        /// immediately clears the marker, and only honors it if it was
        /// written within the freshness window.
        fun consumeIfFresh(context: Context): Boolean {
            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            val timestamp = prefs.getLong(KEY_TIMESTAMP_MS, -1L)
            if (timestamp < 0) return false
            prefs.edit().remove(KEY_TIMESTAMP_MS).apply()
            return System.currentTimeMillis() - timestamp <= FRESHNESS_WINDOW_MS
        }
    }

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == ACTION_REQUEST_QUICK_CAPTURE) {
            requestCapture(context)
            context.startActivity(
                Intent(context, MainActivity::class.java).apply {
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK
                },
            )
            return
        }
        super.onReceive(context, intent)
    }

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        for (appWidgetId in appWidgetIds) {
            val requestIntent = Intent(context, QuickCaptureWidgetProvider::class.java).apply {
                action = ACTION_REQUEST_QUICK_CAPTURE
            }
            val pendingIntent = PendingIntent.getBroadcast(
                context,
                0,
                requestIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
            val views = RemoteViews(context.packageName, R.layout.widget_quick_capture).apply {
                setOnClickPendingIntent(R.id.widget_quick_capture_button, pendingIntent)
            }
            appWidgetManager.updateAppWidget(appWidgetId, views)
        }
    }
}
