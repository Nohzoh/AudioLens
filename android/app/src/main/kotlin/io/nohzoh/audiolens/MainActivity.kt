package io.nohzoh.audiolens

import android.content.Context
import android.content.Intent
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import io.flutter.plugin.common.MethodChannel
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
        flutterEngine.plugins.add(QuickCapturePlugin())
        flutterEngine.plugins.add(GenAiTtsPlugin())
        // #551: whether the current connection is unmetered (Wi-Fi), so the
        // home screen can suggest analyzing the photos set aside.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "audio_guide/network")
            .setMethodCallHandler { call, result ->
                if (call.method == "isUnmetered") {
                    val cm = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
                    val caps = cm.getNetworkCapabilities(cm.activeNetwork)
                    result.success(
                        caps != null &&
                            caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET) &&
                            caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_METERED)
                    )
                } else {
                    result.notImplemented()
                }
            }
        // Cold start (T97): the app was launched directly by a share
        // intent — extract now so getInitialSharedImage (called right
        // after the engine attaches, from Dart) already has it ready.
        extractSharedImage(intent)?.let { SharePlugin.pendingInitialPath = it }
        // Cold start, quick-capture widget: QuickCaptureWidgetProvider
        // records a short-lived marker before launching us (see its
        // class doc for why this isn't driven by the intent itself).
        if (QuickCaptureWidgetProvider.consumeIfFresh(this)) {
            QuickCapturePlugin.pendingCapture = true
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        // Warm start (T97): the app (launchMode="singleTop") was already
        // running when the user shared a photo from another app.
        extractSharedImage(intent)?.let { SharePlugin.instance?.emitSharedImage(it) }
        // Warm start, quick-capture widget: the app was already running
        // when the widget was tapped, so onNewIntent fires instead of a
        // fresh cold start. Same marker, same one-time consumption.
        if (QuickCaptureWidgetProvider.consumeIfFresh(this)) {
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
        if (!isAcceptableSharedUri(uri)) return null
        return try {
            val inputStream = contentResolver.openInputStream(uri) ?: return null
            val shareDir = File(cacheDir, "shared").apply { mkdirs() }
            cleanOldShares(shareDir)
            val destFile = File(shareDir, "shared_${System.currentTimeMillis()}.jpg")
            var copied = 0L
            var tooLarge = false
            inputStream.use { input ->
                FileOutputStream(destFile).use { out ->
                    val buffer = ByteArray(64 * 1024)
                    while (true) {
                        val n = input.read(buffer)
                        if (n < 0) break
                        copied += n
                        if (copied > MAX_SHARED_BYTES) { tooLarge = true; break }
                        out.write(buffer, 0, n)
                    }
                }
            }
            if (tooLarge || !looksLikeImage(destFile)) {
                destFile.delete()
                null
            } else destFile.absolutePath
        } catch (e: Exception) {
            null
        }
    }

    /// #536: only another app's content:// URI. A file:// URI, or one from
    /// our own FileProvider, would be opened with *our* permissions and
    /// could hand a private file (database, preferences) to the pipeline
    /// as if it were a photo.
    private fun isAcceptableSharedUri(uri: Uri): Boolean {
        if (uri.scheme != "content") return false
        val authority = uri.authority ?: return false
        return !authority.startsWith(packageName)
    }

    /// JPEG, PNG, WebP, GIF or HEIF/HEIC signature in the first bytes.
    private fun looksLikeImage(file: File): Boolean {
        val head = ByteArray(12)
        val n = try { file.inputStream().use { it.read(head) } } catch (e: Exception) { -1 }
        if (n < 12) return false
        fun at(i: Int, vararg b: Int) = b.withIndex().all { (k, v) -> head[i + k] == v.toByte() }
        return at(0, 0xFF, 0xD8, 0xFF) ||
            at(0, 0x89, 0x50, 0x4E, 0x47) ||
            (at(0, 0x52, 0x49, 0x46, 0x46) && at(8, 0x57, 0x45, 0x42, 0x50)) ||
            at(0, 0x47, 0x49, 0x46, 0x38) ||
            at(4, 0x66, 0x74, 0x79, 0x70)
    }

    /// Shared copies are only needed until Dart has stored the photo.
    private fun cleanOldShares(dir: File) {
        val cutoff = System.currentTimeMillis() - 24 * 60 * 60 * 1000L
        dir.listFiles()?.forEach { if (it.lastModified() < cutoff) it.delete() }
    }

    companion object {
        /// #536: a photo is a few MB; anything this big isn't one.
        private const val MAX_SHARED_BYTES = 30L * 1024 * 1024
    }
}
