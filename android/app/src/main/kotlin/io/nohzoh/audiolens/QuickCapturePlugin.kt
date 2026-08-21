package io.nohzoh.audiolens

import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/// Bridges the home-screen quick-capture widget's tap to Dart — same
/// shape as SharePlugin (T97): a method channel for the cold-start case
/// (Dart asks once, right after launch) and an event channel for the
/// warm-start case (the app was already running when the widget was
/// tapped, so Dart needs to be pushed the event live). See
/// QuickCaptureWidgetProvider.kt (the widget itself) and
/// MainActivity.kt (which detects ACTION_QUICK_CAPTURE and drives this).
class QuickCapturePlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    private lateinit var methodChannel: MethodChannel
    private lateinit var eventChannel: EventChannel
    private var eventSink: EventChannel.EventSink? = null

    companion object {
        // Set by MainActivity before Flutter's engine attaches, from the
        // Activity's launch intent — consumed (and cleared) by the first
        // consumePendingCapture call so a later engine restart doesn't
        // replay the same tap.
        var pendingCapture: Boolean = false

        // The live plugin instance, so MainActivity.onNewIntent can reach
        // the event sink without re-plumbing a channel reference itself.
        var instance: QuickCapturePlugin? = null
    }

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        methodChannel = MethodChannel(binding.binaryMessenger, "audio_guide/quick_capture")
        methodChannel.setMethodCallHandler(this)
        eventChannel = EventChannel(binding.binaryMessenger, "audio_guide/quick_capture_stream")
        eventChannel.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, sink: EventChannel.EventSink) {
                eventSink = sink
            }
            override fun onCancel(arguments: Any?) {
                eventSink = null
            }
        })
        instance = this
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        methodChannel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
        if (instance == this) instance = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "consumePendingCapture" -> {
                result.success(pendingCapture)
                pendingCapture = false
            }
            else -> result.notImplemented()
        }
    }

    fun emitCapture() {
        eventSink?.success(null)
    }
}
