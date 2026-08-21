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
/// (see MainActivity.kt's ACTION_QUICK_CAPTURE handling and
/// HomeScreen._pickImage(ImageSource.camera) on the Dart side).
class QuickCaptureWidgetProvider : AppWidgetProvider() {

    companion object {
        const val ACTION_QUICK_CAPTURE = "io.nohzoh.audiolens.ACTION_QUICK_CAPTURE"
    }

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        for (appWidgetId in appWidgetIds) {
            val launchIntent = Intent(context, MainActivity::class.java).apply {
                action = ACTION_QUICK_CAPTURE
                flags = Intent.FLAG_ACTIVITY_NEW_TASK
            }
            val pendingIntent = PendingIntent.getActivity(
                context,
                0,
                launchIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
            val views = RemoteViews(context.packageName, R.layout.widget_quick_capture).apply {
                setOnClickPendingIntent(R.id.widget_quick_capture_button, pendingIntent)
            }
            appWidgetManager.updateAppWidget(appWidgetId, views)
        }
    }
}
