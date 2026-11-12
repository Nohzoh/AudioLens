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
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.PrintWriter
import java.io.StringWriter
import java.util.Locale
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.TimeoutCancellationException
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeout

/**
 * #485: probe for ML Kit's on-device generative Text to Speech
 * (genai-text-to-speech, alpha). Not wired into the guide's voice chain.
 *
 * Reading the library (1.0.0-alpha1) shows it is a wrapper around
 * Android's own TextToSpeech bound to Google's engine
 * (com.google.android.tts): it picks a Voice by name with setVoice() and
 * calls speak(), so the engine plays the audio itself; AudioAvailable
 * relays UtteranceProgressListener.onAudioAvailable (raw audio, whose
 * sample rate the library does not pass on). What it adds is the list of
 * generative voices and the download of their models.
 *
 * So the open question for production is whether the app's existing
 * native voice (flutter_tts, same Android API) can simply select these
 * voices by name. This probe reports, on a real device, each voice's
 * engine-side name and what one synthesis does.
 */
class GenAiTtsPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {

    private lateinit var channel: MethodChannel
    private lateinit var context: Context
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private var probeJob: Job? = null

    companion object {
        const val CHANNEL = "audio_guide/genai_tts"
        private const val PROBE_TIMEOUT_MS = 120_000L
        private const val PROBE_FILE = "genai_tts_probe.bin"
        private const val CRASH_FILE = "voice_lab_crash.txt"
        // Raw audio kept for sharing: 24 kHz 16-bit mono is ~2.9 MB/min.
        private const val MAX_AUDIO_BYTES = 24 * 1024 * 1024
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

    private fun describe(t: Throwable): String {
        val writer = StringWriter()
        t.printStackTrace(PrintWriter(writer))
        return writer.toString().take(6000)
    }

    // #501: the first probe on a device crashed the whole app, with no
    // way to see why (no logcat in the field). While a probe runs, any
    // exception that would kill the process — on whatever thread, ours
    // or the library's — is first written to a file the Voice Lab shows
    // on its next opening. The previous handler still runs afterwards,
    // so the crash itself is unchanged.
    private fun installCrashRecorder(): Thread.UncaughtExceptionHandler? {
        val previous = Thread.getDefaultUncaughtExceptionHandler()
        val crashFile = File(context.filesDir, CRASH_FILE)
        Thread.setDefaultUncaughtExceptionHandler { thread, throwable ->
            try {
                crashFile.writeText(
                    "Voice Lab probe crashed on thread \"${thread.name}\"\n${describe(throwable)}"
                )
            } catch (e: Throwable) {
                // Nothing more can be done here.
            }
            previous?.uncaughtException(thread, throwable)
        }
        return previous
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

    // Name of the voice inside Google's TTS engine — the one a plain
    // TextToSpeech.setVoice() would need. Not part of the public API
    // (obfuscated accessor of alpha1), hence reflection and null on any
    // failure.
    private fun engineVoiceName(voice: VoiceInfo): String? = try {
        voice.javaClass.getMethod("zza").invoke(voice) as? String
    } catch (e: Exception) {
        null
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
                            } catch (e: Throwable) {
                                "error: ${e.javaClass.simpleName}"
                            }
                            mapOf(
                                "name" to voice.name,
                                "status" to status,
                                "details" to "${voice.locale.toLanguageTag()}, ${voice.gender.name.lowercase()}",
                                "engineName" to engineVoiceName(voice)
                            )
                        }
                        withContext(Dispatchers.Main) { result.success(payload) }
                    } catch (e: Throwable) {
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
                    } catch (e: Throwable) {
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
            // Stack trace left by a probe that crashed the app, if any.
            "lastCrash" -> {
                val file = File(context.filesDir, CRASH_FILE)
                result.success(if (file.exists()) file.readText() else null)
            }

            "clearCrash" -> {
                File(context.filesDir, CRASH_FILE).delete()
                result.success(null)
            }

            "probe" -> {
                val text = call.argument<String>("text")
                val voiceName = call.argument<String>("voice")
                if (text.isNullOrBlank()) {
                    result.error("INVALID_ARGS", "text required", null)
                    return
                }
                probeJob?.cancel()
                // #501: collected on the main thread, as in Google's own
                // sample (lifecycleScope) — the library drives Android's
                // TextToSpeech, whose usual home is the main thread.
                probeJob = scope.launch(Dispatchers.Main) {
                    val previousHandler = installCrashRecorder()
                    val start = System.nanoTime()
                    fun ms(): Long = (System.nanoTime() - start) / 1_000_000
                    val events = mutableListOf<String>()
                    val chunkSizes = mutableListOf<Int>()
                    var totalBytes = 0L
                    var firstChunkMs: Long? = null
                    var startMs: Long? = null
                    var doneMs: Long? = null
                    var firstBytesHex: String? = null
                    var error: String? = null
                    var voiceLabel: String? = null
                    val audio = ByteArrayOutputStream()
                    val file = File(context.cacheDir, PROBE_FILE)
                    var client: SpeechSynthesizer? = null
                    // Throwable, not Exception: a NoSuchMethodError or a
                    // NoClassDefFoundError from a library mismatch must end
                    // up in the report, not kill the app.
                    try {
                        client = newClient(locale)
                        events.add("${ms()} ms client created")
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
                        events.add("${ms()} ms synthesize called")
                        withTimeout(PROBE_TIMEOUT_MS) {
                            client.synthesize(request).collect { response ->
                                when (response) {
                                    is SpeechSynthesizerResponse.StatusUpdate -> {
                                        events.add("${ms()} ms status: ${response.status}")
                                        when (response.status) {
                                            SpeechSynthesizerResponse.Status.START -> startMs = ms()
                                            SpeechSynthesizerResponse.Status.DONE -> doneMs = ms()
                                            else -> {}
                                        }
                                    }
                                    is SpeechSynthesizerResponse.AudioAvailable -> {
                                        val chunk = response.audio
                                        if (firstChunkMs == null) {
                                            firstChunkMs = ms()
                                            firstBytesHex = chunk.take(16)
                                                .joinToString(" ") { "%02x".format(it) }
                                            events.add("${ms()} ms first audio chunk")
                                        }
                                        chunkSizes.add(chunk.size)
                                        totalBytes += chunk.size
                                        if (audio.size() + chunk.size <= MAX_AUDIO_BYTES) {
                                            audio.write(chunk)
                                        }
                                    }
                                    is SpeechSynthesizerResponse.Error ->
                                        events.add("${ms()} ms error: ${response.errorCode}")
                                    else -> events.add("${ms()} ms other: $response")
                                }
                            }
                        }
                        events.add("${ms()} ms flow completed")
                    } catch (e: TimeoutCancellationException) {
                        error = "timeout after ${PROBE_TIMEOUT_MS / 1000} s"
                    } catch (e: kotlinx.coroutines.CancellationException) {
                        error = "stopped"
                    } catch (e: Throwable) {
                        error = describe(e)
                    } finally {
                        try {
                            client?.close()
                        } catch (e: Throwable) {
                            events.add("${ms()} ms close failed: ${e.javaClass.simpleName}")
                        }
                    }
                    var audioPath: String? = null
                    if (audio.size() > 0) {
                        try {
                            withContext(NonCancellable + Dispatchers.IO) {
                                file.writeBytes(audio.toByteArray())
                            }
                            audioPath = file.absolutePath
                        } catch (e: Throwable) {
                            events.add("${ms()} ms audio file not written: ${e.javaClass.simpleName}")
                        }
                    }
                    val payload = mapOf(
                        "voice" to voiceLabel,
                        "textLength" to text.length,
                        "events" to events,
                        "chunkCount" to chunkSizes.size,
                        "chunkSizes" to chunkSizes.take(40),
                        "totalBytes" to totalBytes,
                        "firstChunkMs" to firstChunkMs,
                        "startMs" to startMs,
                        "doneMs" to doneMs,
                        "firstBytesHex" to firstBytesHex,
                        "totalMs" to ms(),
                        "audioFile" to audioPath,
                        "error" to error
                    )
                    Thread.setDefaultUncaughtExceptionHandler(previousHandler)
                    // NonCancellable: a probe stopped by "stop" must still
                    // answer its caller, with whatever it had collected.
                    withContext(NonCancellable + Dispatchers.Main) {
                        try {
                            result.success(payload)
                        } catch (e: Throwable) {
                            // Reply already sent or engine detached.
                        }
                    }
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
