package io.nohzoh.audiolens

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import java.io.File
import java.io.FileOutputStream

class MainActivity : FlutterActivity() {
    companion object {
        private const val TAG = "AudioLens"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        flutterEngine.plugins.add(GeminiNanoPlugin())
        flutterEngine.plugins.add(LocationPlugin())
        flutterEngine.plugins.add(AudioPlayerPlugin())
        flutterEngine.plugins.add(ForegroundServicePlugin())
        flutterEngine.plugins.add(SharePlugin())
        flutterEngine.plugins.add(QuickCapturePlugin())
        // Cold start (T97): the app was launched directly by a share
        // intent — extract now so getInitialSharedImage (called right
        // after the engine attaches, from Dart) already has it ready.
        extractSharedImage(intent)?.let { SharePlugin.pendingInitialPath = it }
        // Cold start, quick-capture widget: same idea, see SharePlugin's
        // comment above and QuickCaptureWidgetProvider.kt.
        if (isFreshQuickCapture(intent)) {
            QuickCapturePlugin.pendingCapture = true
        }
    }

    /// True only for a quick-capture launch the user just performed.
    ///
    /// The widget's PendingIntent (FLAG_ACTIVITY_NEW_TASK) becomes the
    /// task's base intent, and Android reuses that base intent when it
    /// resumes or recreates the task — including when the process was
    /// killed in the background and the user then taps the *normal*
    /// launcher icon. Without this check, that ordinary launch replays
    /// the last widget tap and drops the user straight into the camera
    /// (see the linked issue for the reported symptom).
    ///
    /// FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY is set by the system precisely
    /// for those relaunch-from-history cases, so it distinguishes "the
    /// user tapped the widget just now" from "Android handed us back an
    /// old intent", which the action alone cannot.
    private fun isFreshQuickCapture(intent: Intent?): Boolean {
        if (intent?.action != QuickCaptureWidgetProvider.ACTION_QUICK_CAPTURE) return false
        val fromHistory =
            (intent.flags and Intent.FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY) != 0
        if (fromHistory) {
            Log.i(TAG, "Ignoring quick-capture action: relaunched from history, not a fresh widget tap")
        }
        return !fromHistory
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        // Warm start (T97): the app (launchMode="singleTop") was already
        // running when the user shared a photo from another app.
        extractSharedImage(intent)?.let { SharePlugin.instance?.emitSharedImage(it) }
        // Warm start, quick-capture widget: the app was already running
        // when the widget was tapped. Same freshness guard as the cold
        // path — resuming from Recents can redeliver the task's original
        // intent here too.
        if (isFreshQuickCapture(intent)) {
            QuickCapturePlugin.instance?.emitCapture()
        }
    }

    /// ACTION_SEND with an image delivers a content:// URI in EXTRA_STREAM
    /// — copied into the app's cache dir since the rest of the analysis
    /// pipeline (EXIF reading, image_picker's own flow) expects a real
    /// file path, not a content resolver reference.
    private fun extractSharedImage(intent: Intent?): String? {
        if (intent?.action != Intent.ACTION_SEND) return null
        if (intent.type?.startsWith("image/") != true) return null
        val uri = (if (Build.VERSION.SDK_INT >= 33) {
            intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
        } else {
            @Suppress("DEPRECATION")
            intent.getParcelableExtra(Intent.EXTRA_STREAM)
        }) ?: return null
        return try {
            val inputStream = contentResolver.openInputStream(uri) ?: return null
            val destFile = File(cacheDir, "shared_${System.currentTimeMillis()}.jpg")
            inputStream.use { input ->
                FileOutputStream(destFile).use { out -> input.copyTo(out) }
            }
            destFile.absolutePath
        } catch (e: Exception) {
            null
        }
    }
}
