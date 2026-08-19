package io.nohzoh.audiolens

import android.content.Intent
import android.net.Uri
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import java.io.File
import java.io.FileOutputStream

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        flutterEngine.plugins.add(GeminiNanoPlugin())
        flutterEngine.plugins.add(LocationPlugin())
        flutterEngine.plugins.add(AudioPlayerPlugin())
        flutterEngine.plugins.add(ForegroundServicePlugin())
        flutterEngine.plugins.add(SharePlugin())
        // Cold start (T97): the app was launched directly by a share
        // intent — extract now so getInitialSharedImage (called right
        // after the engine attaches, from Dart) already has it ready.
        extractSharedImage(intent)?.let { SharePlugin.pendingInitialPath = it }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        // Warm start (T97): the app (launchMode="singleTop") was already
        // running when the user shared a photo from another app.
        extractSharedImage(intent)?.let { SharePlugin.instance?.emitSharedImage(it) }
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
