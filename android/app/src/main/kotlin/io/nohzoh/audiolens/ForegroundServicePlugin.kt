package io.nohzoh.audiolens

import android.content.Intent
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/// Starts/stops [AnalysisForegroundService] from Dart (T85). Fire-and-forget
/// on both ends — the Dart side doesn't need to await the service's own
/// lifecycle, just that the platform call was dispatched.
class ForegroundServicePlugin : FlutterPlugin, MethodChannel.MethodCallHandler {

    private lateinit var channel: MethodChannel
    private lateinit var appContext: android.content.Context

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        appContext = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, "audio_guide/foreground_service")
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "start" -> {
                appContext.startForegroundService(Intent(appContext, AnalysisForegroundService::class.java))
                result.success(null)
            }
            "stop" -> {
                appContext.stopService(Intent(appContext, AnalysisForegroundService::class.java))
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }
}
