package io.nohzoh.audiolens

import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/// Bridges shared-photo intents (T97) to Dart. [MainActivity] extracts the
/// image path from incoming ACTION_SEND intents and hands it here — a
/// method channel for the cold-start case (Dart asks once, right after
/// launch) and an event channel for the warm-start case (the app was
/// already running when the share arrived, so Dart needs to be pushed the
/// path live).
class SharePlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    private lateinit var methodChannel: MethodChannel
    private lateinit var eventChannel: EventChannel
    private var eventSink: EventChannel.EventSink? = null

    companion object {
        // Set by MainActivity before Flutter's engine attaches, from the
        // Activity's launch intent — consumed (and cleared) by the first
        // getInitialSharedImage call so a later engine restart doesn't
        // replay the same share.
        var pendingInitialPath: String? = null

        // The live plugin instance, so MainActivity.onNewIntent can reach
        // the event sink without re-plumbing a channel reference itself.
        var instance: SharePlugin? = null
    }

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        methodChannel = MethodChannel(binding.binaryMessenger, "audio_guide/share_intent")
        methodChannel.setMethodCallHandler(this)
        eventChannel = EventChannel(binding.binaryMessenger, "audio_guide/share_intent_stream")
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
            "getInitialSharedImage" -> {
                result.success(pendingInitialPath)
                pendingInitialPath = null
            }
            else -> result.notImplemented()
        }
    }

    fun emitSharedImage(path: String) {
        eventSink?.success(path)
    }
}
