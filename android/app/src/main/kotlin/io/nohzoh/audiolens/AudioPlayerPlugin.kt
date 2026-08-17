package io.nohzoh.audiolens

import android.media.MediaPlayer
import android.media.PlaybackParams
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

class AudioPlayerPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {

    private lateinit var channel: MethodChannel
    private var mediaPlayer: MediaPlayer? = null
    private val scope = CoroutineScope(Dispatchers.IO)

    // The Dart side of a "playWav" call awaits its result to know when
    // playback finished (T76 — chunked TTS sequencing relies on this).
    // Without tracking it here, calling "stop" while a "playWav" is still
    // in flight would leave that call's Dart-side await hanging forever,
    // since MediaPipe.stop() alone never completes it.
    private var pendingPlayResult: MethodChannel.Result? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(binding.binaryMessenger, "audio_guide/audio_player")
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        mediaPlayer?.release()
        mediaPlayer = null
    }

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
                                scope.launch(Dispatchers.Main) { resolvePendingPlay() }
                            }
                            setOnErrorListener { _, _, _ ->
                                scope.launch(Dispatchers.Main) {
                                    pendingPlayResult?.error("PLAYBACK_ERROR", "Playback failed", null)
                                    pendingPlayResult = null
                                }
                                true
                            }
                        }
                    } catch (e: Exception) {
                        withContext(Dispatchers.Main) {
                            pendingPlayResult?.error("PLAYBACK_ERROR", e.message, null)
                            pendingPlayResult = null
                        }
                    }
                }
            }
            "pause" -> { mediaPlayer?.pause(); result.success(null) }
            "play" -> { mediaPlayer?.start(); result.success(null) }
            "stop" -> {
                mediaPlayer?.stop(); mediaPlayer?.release()
                mediaPlayer = null
                resolvePendingPlay()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }
}
