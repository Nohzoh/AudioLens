package io.nohzoh.audiolens

import android.content.Context
import android.media.AudioAttributes
import com.google.mlkit.genai.common.FeatureStatus
import com.google.mlkit.genai.texttospeech.SpeechSynthesis
import com.google.mlkit.genai.texttospeech.SpeechSynthesizer
import com.google.mlkit.genai.texttospeech.SpeechSynthesizerOptions
import com.google.mlkit.genai.texttospeech.SpeechSynthesizerRequest
import com.google.mlkit.genai.texttospeech.SpeechSynthesizerResponse
import com.google.mlkit.genai.texttospeech.VoiceInfo
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.Locale
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.TimeoutCancellationException
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeout

/**
 * #485: probe for ML Kit's on-device generative Text to Speech
 * (genai-text-to-speech, alpha). Not wired into the guide's voice chain
 * yet: the documentation leaves open whether the synthesizer plays the
 * audio itself, what format its audio chunks are in, and how long a text
 * it accepts. This plugin answers those on a real device (Settings >
 * Voice Lab) before any production integration.
 */
class GenAiTtsPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {

    private lateinit var channel: MethodChannel
    private lateinit var context: Context
    private val scope = CoroutineScope(Dispatchers.IO)
    private var probeJob: Job? = null

    companion object {
        const val CHANNEL = "audio_guide/genai_tts"
        private const val PROBE_TIMEOUT_MS = 120_000L
        private const val PROBE_FILE = "genai_tts_probe.bin"
    }

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, CHANNEL)
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        probeJob?.cancel()
    }

    private fun newClient(locale: Locale): SpeechSynthesizer =
        SpeechSynthesis.getClient(SpeechSynthesizerOptions.builder(locale).build())

    private fun statusName(status: Int): String = when (status) {
        FeatureStatus.UNAVAILABLE -> "unavailable"
        FeatureStatus.DOWNLOADABLE -> "downloadable"
        FeatureStatus.DOWNLOADING -> "downloading"
        FeatureStatus.AVAILABLE -> "available"
        else -> "unknown($status)"
    }

    private suspend fun findVoice(
        client: SpeechSynthesizer,
        locale: Locale,
        name: String?,
    ): VoiceInfo? {
        val voices: List<VoiceInfo> = client.getSupportedVoices(locale)
        return voices.firstOrNull { name != null && it.name == name } ?: voices.firstOrNull()
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        val locale = Locale.forLanguageTag(call.argument<String>("locale") ?: "fr-FR")
        when (call.method) {
            // Voices offered for the locale, each with its model status.
            "voices" -> {
                scope.launch {
                    val client = newClient(locale)
                    try {
                        val voices: List<VoiceInfo> = client.getSupportedVoices(locale)
                        val payload = voices.map { voice ->
                            val status = try {
                                statusName(client.checkStatus(voice))
                            } catch (e: Exception) {
                                "error: ${e.javaClass.simpleName}"
                            }
                            mapOf(
                                "name" to voice.name,
                                "status" to status,
                                "details" to voice.toString()
                            )
                        }
                        withContext(Dispatchers.Main) { result.success(payload) }
                    } catch (e: Exception) {
                        withContext(Dispatchers.Main) {
                            result.error("VOICES_ERROR", "${e.javaClass.simpleName}: ${e.message}", null)
                        }
                    } finally {
                        client.close()
                    }
                }
            }

            // Downloads the model of one voice; returns the statuses seen.
            "download" -> {
                val voiceName = call.argument<String>("voice")
                scope.launch {
                    val client = newClient(locale)
                    try {
                        val voice = findVoice(client, locale, voiceName)
                            ?: throw Exception("No voice for $locale")
                        val seen = mutableListOf<String>()
                        client.download(voice).collect { status ->
                            val label = status.javaClass.simpleName
                            if (seen.lastOrNull() != label) seen.add(label)
                        }
                        withContext(Dispatchers.Main) { result.success(seen) }
                    } catch (e: Exception) {
                        withContext(Dispatchers.Main) {
                            result.error("DOWNLOAD_ERROR", "${e.javaClass.simpleName}: ${e.message}", null)
                        }
                    } finally {
                        client.close()
                    }
                }
            }

            // Synthesizes one text and reports everything observable:
            // the sequence of status updates with timings, the audio
            // chunks (count, sizes, first bytes) and any error. The raw
            // audio bytes are written to a cache file for offline
            // inspection of their format.
            "probe" -> {
                val text = call.argument<String>("text")
                val voiceName = call.argument<String>("voice")
                if (text.isNullOrBlank()) {
                    result.error("INVALID_ARGS", "text required", null)
                    return
                }
                probeJob?.cancel()
                probeJob = scope.launch {
                    val client = newClient(locale)
                    val start = System.nanoTime()
                    fun ms(): Long = (System.nanoTime() - start) / 1_000_000
                    val events = mutableListOf<String>()
                    val chunkSizes = mutableListOf<Int>()
                    var totalBytes = 0L
                    var firstChunkMs: Long? = null
                    var firstBytesHex: String? = null
                    var error: String? = null
                    var voiceLabel: String? = null
                    val file = File(context.cacheDir, PROBE_FILE)
                    try {
                        val voice = findVoice(client, locale, voiceName)
                            ?: throw Exception("No voice for $locale")
                        voiceLabel = voice.name
                        events.add("${ms()} ms voice status: ${statusName(client.checkStatus(voice))}")
                        val request = SpeechSynthesizerRequest(
                            input = SpeechSynthesizerRequest.Input.Text(text, voice),
                            audioAttributes = AudioAttributes.Builder()
                                .setUsage(AudioAttributes.USAGE_MEDIA)
                                .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                                .build()
                        )
                        file.outputStream().use { out ->
                            withTimeout(PROBE_TIMEOUT_MS) {
                                client.synthesize(request).collect { response ->
                                    when (response) {
                                        is SpeechSynthesizerResponse.StatusUpdate ->
                                            events.add("${ms()} ms status: ${response.status}")
                                        is SpeechSynthesizerResponse.AudioAvailable -> {
                                            val audio = response.audio
                                            if (firstChunkMs == null) {
                                                firstChunkMs = ms()
                                                firstBytesHex = audio.take(16)
                                                    .joinToString(" ") { "%02x".format(it) }
                                                events.add("${ms()} ms first audio chunk")
                                            }
                                            chunkSizes.add(audio.size)
                                            totalBytes += audio.size
                                            out.write(audio)
                                        }
                                        is SpeechSynthesizerResponse.Error ->
                                            events.add("${ms()} ms error: ${response.errorCode}")
                                        else -> events.add("${ms()} ms other: $response")
                                    }
                                }
                            }
                        }
                        events.add("${ms()} ms flow completed")
                    } catch (e: TimeoutCancellationException) {
                        error = "timeout after ${PROBE_TIMEOUT_MS / 1000} s"
                    } catch (e: Exception) {
                        error = "${e.javaClass.simpleName}: ${e.message}"
                    } finally {
                        client.close()
                    }
                    val payload = mapOf(
                        "voice" to voiceLabel,
                        "textLength" to text.length,
                        "events" to events,
                        "chunkCount" to chunkSizes.size,
                        "chunkSizes" to chunkSizes.take(40),
                        "totalBytes" to totalBytes,
                        "firstChunkMs" to firstChunkMs,
                        "firstBytesHex" to firstBytesHex,
                        "totalMs" to ms(),
                        "audioFile" to (if (totalBytes > 0) file.absolutePath else null),
                        "error" to error
                    )
                    // NonCancellable: a probe stopped by "stop" must still
                    // answer its caller, with whatever it had collected.
                    withContext(NonCancellable + Dispatchers.Main) { result.success(payload) }
                }
            }

            "stop" -> {
                probeJob?.cancel()
                probeJob = null
                result.success(null)
            }

            else -> result.notImplemented()
        }
    }
}
