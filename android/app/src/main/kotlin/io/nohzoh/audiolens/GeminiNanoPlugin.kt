package io.nohzoh.audiolens

import android.content.Context
import android.graphics.BitmapFactory
import com.google.mlkit.genai.common.DownloadStatus
import com.google.mlkit.genai.prompt.Generation
import com.google.mlkit.genai.prompt.GenerativeModel
import com.google.mlkit.genai.prompt.ImagePart
import com.google.mlkit.genai.prompt.TextPart
import com.google.mlkit.genai.prompt.generateContentRequest
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.TimeoutCancellationException
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeout

class GeminiNanoPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {

    private lateinit var channel: MethodChannel
    private lateinit var context: Context
    private var generativeModel: GenerativeModel? = null
    private val scope = CoroutineScope(Dispatchers.IO)

    companion object {
        const val CHANNEL = "audio_guide/gemini_nano"

        // #173: no equivalent existed before — a hung AICore call had
        // nothing bounding it. Per-segment (not one timeout for all 3)
        // so a slow segment doesn't eat into the others' budget, and so
        // the error can name which segment actually hung.
        //
        // Bumped 15s -> 30s: a real device (Pixel, GPS-resolved location
        // with Wikipedia context, #244) hit this timeout on segment 1 —
        // the heaviest call (image + text, and the one most likely to
        // also carry AICore's first-inference-after-idle model warmup
        // cost). 15s wasn't a reliability margin, it was regularly too
        // tight for real-world multimodal inference.
        private const val SEGMENT_TIMEOUT_MS = 30_000L

        // Tone descriptor per style (T75/T48) — default (null/unrecognized)
        // is the original wording, so the default experience is unchanged.
        private fun styleTone(style: String?): String = when (style) {
            "academic" -> "un ton documentaire et precis, avec des faits verifies"
            "anecdotal" -> "un ton complice qui met en avant anecdotes et curiosites"
            "concise" -> "un ton direct et efficace"
            else -> "un ton chaleureux et vivant"
        }

        fun buildSeg1Prompt(locationContext: String?, style: String? = null, language: String? = null): String {
            // #171: locationContext already arrives pre-truncated for
            // Nano's budget (see GeminiNanoService._maxLocationContextChars
            // on the Dart side) — this only adds the same grounding-
            // priority instruction the cloud prompt has, mirrored in
            // Nano's shorter phrasing style, so a specific place named in
            // the context isn't left un-leaned-on the way a bare
            // parenthetical mention risks.
            val loc = if (!locationContext.isNullOrBlank()) {
                " (prise a : $locationContext — utilise ce lieu en priorite s'il est precis, plutot que de rester generique)"
            } else ""
            val sentences = if (style == "concise") "1-2 phrases maximum" else "2-3 phrases maximum"
            // #130: only seg1 needs the language directive — seg2/seg3 are
            // continuations built from seg1's own output text, so they
            // naturally stay in whatever language seg1 established, the
            // same way they don't need styleTone() repeated either.
            val languageDirective = if (!language.isNullOrBlank()) {
                " Reponds uniquement en $language, meme si ces instructions sont en francais."
            } else ""
            // #172: asks explicitly for a short title in brackets on its
            // own line, mirroring the cloud pipeline's structured `title`
            // field — GeminiNanoService._extractTitleAndBody parses it out
            // on the Dart side (falling back to the old first-sentence
            // heuristic if the model doesn't follow the format).
            return "Tu es un guide audio culturel. Commence par un titre court entre crochets (3 a 6 mots, ex: [Le Colisee de Rome]), sur sa propre ligne. Puis, sans phrase d'introduction, decris ce que tu vois sur cette image$loc avec ${styleTone(style)}. Ne mentionne pas de dates ou chiffres precis dont tu n'es pas certain. $sentences.$languageDirective"
        }

        // #247: without locationContext here, segments 2/3 have nothing to
        // ground them beyond seg1's own already-generated text — once
        // that text drifts even slightly generic, there's no real data
        // left to pull them back, which is exactly what produced
        // unrelated filler ("Bois de Vincennes", "vestiges romains...")
        // for a real capture of a specific, named church. Reusing the
        // same parenthetical framing as seg1 rather than a separate
        // sentence keeps it a hint the model can lean on, not a second
        // instruction competing with "continue naturally from the text
        // above" for the model's attention.
        private fun locationHint(locationContext: String?): String =
            if (!locationContext.isNullOrBlank()) " Contexte du lieu : $locationContext." else ""

        fun buildSeg2Prompt(previousText: String, style: String? = null, locationContext: String? = null): String {
            val excerpt = previousText.takeLast(200)
            val focus = when (style) {
                "academic" -> "le contexte historique precis (dates, faits averes, contexte culturel)"
                "anecdotal" -> "une anecdote ou curiosite peu connue liee a ce lieu"
                "concise" -> "l'information essentielle"
                else -> "le contexte historique et culturel"
            }
            val sentences = if (style == "concise") "1 phrase" else "2-3 phrases qui s'enchainent naturellement"
            return "Tu es un guide audio culturel. Suite de ton commentaire. Texte precedent : $excerpt.${locationHint(locationContext)} Continue avec $focus en $sentences, en te basant sur les faits reels ci-dessus plutot que de rester generique. Pas de repetition."
        }

        fun buildSeg3Prompt(previousText: String, style: String? = null, locationContext: String? = null): String {
            val excerpt = previousText.takeLast(200)
            val sentences = if (style == "concise") "1 phrase" else "2 phrases"
            return "Tu es un guide audio culturel. Suite de ton commentaire. Texte precedent : $excerpt.${locationHint(locationContext)} Conclus en $sentences sur ce qui rend ce lieu unique et l'emotion qu'il inspire, sans repeter ce qui a deja ete dit."
        }
    }

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, CHANNEL)
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        generativeModel?.close()
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {

            "isAvailable" -> {
                scope.launch {
                    try {
                        val model = Generation.getClient()
                        val status = model.checkStatus()
                        model.close()
                        withContext(Dispatchers.Main) {
                            result.success(status != com.google.mlkit.genai.common.FeatureStatus.UNAVAILABLE)
                        }
                    } catch (e: Exception) {
                        withContext(Dispatchers.Main) { result.success(false) }
                    }
                }
            }

            // #283: "isAvailable" above collapses DOWNLOADABLE/DOWNLOADING/
            // AVAILABLE all into a single "true" — enough for
            // AiProviderManager to decide whether to use Nano, but not
            // enough to tell a user *why* it's unavailable when it is.
            // ML Kit GenAI's FeatureStatus.UNAVAILABLE specifically means
            // the device doesn't meet AICore's hardware/OS requirements —
            // that's the one distinction a user can't do anything about
            // (vs. DOWNLOADABLE/DOWNLOADING, which resolve on their own
            // once the model finishes downloading). Named distinctly from
            // "isAvailable" rather than changing its return type, since
            // that method implements the shared AIService.isAvailable()
            // bool contract used polymorphically for both providers.
            "checkNanoStatus" -> {
                scope.launch {
                    try {
                        val model = Generation.getClient()
                        val status = model.checkStatus()
                        model.close()
                        val statusName = when (status) {
                            com.google.mlkit.genai.common.FeatureStatus.UNAVAILABLE -> "unavailable"
                            com.google.mlkit.genai.common.FeatureStatus.DOWNLOADABLE -> "downloadable"
                            com.google.mlkit.genai.common.FeatureStatus.DOWNLOADING -> "downloading"
                            com.google.mlkit.genai.common.FeatureStatus.AVAILABLE -> "available"
                            else -> "unknown"
                        }
                        withContext(Dispatchers.Main) { result.success(statusName) }
                    } catch (e: Exception) {
                        withContext(Dispatchers.Main) { result.success("unknown") }
                    }
                }
            }

            "initialize" -> {
                scope.launch {
                    try {
                        generativeModel?.close()
                        val model = Generation.getClient()
                        // Use download().collect as per official sample
                        model.download().collect { status ->
                            when (status) {
                                is DownloadStatus.DownloadCompleted -> {
                                    generativeModel = model
                                    withContext(Dispatchers.Main) { result.success(true) }
                                }
                                is DownloadStatus.DownloadFailed -> {
                                    // Model may already be downloaded
                                    generativeModel = model
                                    withContext(Dispatchers.Main) { result.success(true) }
                                }
                                else -> { /* progress */ }
                            }
                        }
                    } catch (e: Exception) {
                        withContext(Dispatchers.Main) {
                            result.error("INIT_ERROR", e.message, null)
                        }
                    }
                }
            }

            "describeImage" -> {
                val imagePath = call.argument<String>("imagePath")
                val locationContext = call.argument<String>("locationContext")
                val style = call.argument<String>("style")
                val language = call.argument<String>("language")
                // #170: previously hardcoded (256, no temperature at all —
                // ML Kit GenAI's own unstated default applied). Now sent
                // from RemoteConfigService on the Dart side, so a stuck
                // value can be fixed remotely without an app release, same
                // as #158 was for the cloud pipeline's own maxOutputTokens.
                // Named distinctly from GenerateContentRequest.Builder's own
                // maxOutputTokens/temperature properties — those are set via
                // an implicit-receiver lambda below, where a same-named
                // local would be shadowed by the receiver's property instead
                // of being read.
                val nanoMaxOutputTokens = call.argument<Int>("maxOutputTokens") ?: 256
                val nanoTemperature = call.argument<Double>("temperature")?.toFloat()

                if (imagePath == null) {
                    result.error("INVALID_ARGS", "imagePath required", null)
                    return
                }
                val model = generativeModel
                if (model == null) {
                    result.error("NOT_INITIALIZED", "Call initialize first", null)
                    return
                }

                // #244: shared across the try/catch below so a timeout's
                // error message can actually name which of the 3 cascade
                // segments hung, instead of a generic "timed out" that
                // leaves the in-app logs no more diagnosable than a crash.
                var currentSegment = 0

                scope.launch {
                    try {
                        val opts = BitmapFactory.Options().apply { inSampleSize = 2 }
                        val bitmap = BitmapFactory.decodeFile(imagePath, opts)
                            ?: throw Exception("Cannot decode image")

                        // Segment 1: Visual description with image
                        currentSegment = 1
                        val req1 = generateContentRequest(
                            ImagePart(bitmap),
                            TextPart(buildSeg1Prompt(locationContext, style, language))
                        ) {
                            this.maxOutputTokens = nanoMaxOutputTokens
                            nanoTemperature?.let { this.temperature = it }
                        }
                        val seg1 = withTimeout(SEGMENT_TIMEOUT_MS) { model.generateContent(req1) }
                            .candidates.firstOrNull()?.text?.trim() ?: ""

                        bitmap.recycle()

                        // Segment 2: Historical context (text only, faster)
                        currentSegment = 2
                        val req2 = generateContentRequest(
                            TextPart(buildSeg2Prompt(seg1, style, locationContext))
                        ) {
                            this.maxOutputTokens = nanoMaxOutputTokens
                            nanoTemperature?.let { this.temperature = it }
                        }
                        val seg2 = withTimeout(SEGMENT_TIMEOUT_MS) { model.generateContent(req2) }
                            .candidates.firstOrNull()?.text?.trim() ?: ""

                        // Segment 3: Conclusion
                        currentSegment = 3
                        val req3 = generateContentRequest(
                            TextPart(buildSeg3Prompt("$seg1 $seg2", style, locationContext))
                        ) {
                            this.maxOutputTokens = nanoMaxOutputTokens
                            nanoTemperature?.let { this.temperature = it }
                        }
                        val seg3 = withTimeout(SEGMENT_TIMEOUT_MS) { model.generateContent(req3) }
                            .candidates.firstOrNull()?.text?.trim() ?: ""

                        val fullText = listOf(seg1, seg2, seg3)
                            .filter { it.isNotBlank() }
                            .joinToString(" ")

                        withContext(Dispatchers.Main) { result.success(fullText) }
                    } catch (e: TimeoutCancellationException) {
                        // #173: without this, a hung AICore call (e.g. the
                        // model stuck loading/inferring) left the coroutine
                        // running indefinitely, tying up whatever on the
                        // Dart side awaits this method call forever —
                        // mirrors GeminiApiService._post's own explicit
                        // HTTP timeout on the cloud pipeline.
                        withContext(Dispatchers.Main) {
                            result.error(
                                "TIMEOUT",
                                "Gemini Nano inference timed out (segment $currentSegment)",
                                null
                            )
                        }
                    } catch (e: Exception) {
                        withContext(Dispatchers.Main) {
                            result.error("INFERENCE_ERROR", e.message, null)
                        }
                    }
                }
            }

            // #276: runs the exact same 3-segment cascade as "describeImage"
            // (same prompt builders, same timeout/token/temperature
            // handling) but returns each segment's own prompt text and raw
            // output instead of only the final concatenated string — lets
            // the Nano Prompt Lab debug screen show "toutes les infos des
            // étapes intermédiaires" for a full end-to-end run (real
            // location context in, real 3-call cascade out), not just a
            // single free-form call like "rawPrompt" below.
            "describeImageDebug" -> {
                val imagePath = call.argument<String>("imagePath")
                val locationContext = call.argument<String>("locationContext")
                val style = call.argument<String>("style")
                val language = call.argument<String>("language")
                val nanoMaxOutputTokens = call.argument<Int>("maxOutputTokens") ?: 256
                val nanoTemperature = call.argument<Double>("temperature")?.toFloat()

                if (imagePath == null) {
                    result.error("INVALID_ARGS", "imagePath required", null)
                    return
                }
                val model = generativeModel
                if (model == null) {
                    result.error("NOT_INITIALIZED", "Call initialize first", null)
                    return
                }

                var currentSegment = 0

                scope.launch {
                    try {
                        val opts = BitmapFactory.Options().apply { inSampleSize = 2 }
                        val bitmap = BitmapFactory.decodeFile(imagePath, opts)
                            ?: throw Exception("Cannot decode image")

                        currentSegment = 1
                        val seg1Prompt = buildSeg1Prompt(locationContext, style, language)
                        val req1 = generateContentRequest(ImagePart(bitmap), TextPart(seg1Prompt)) {
                            this.maxOutputTokens = nanoMaxOutputTokens
                            nanoTemperature?.let { this.temperature = it }
                        }
                        val seg1 = withTimeout(SEGMENT_TIMEOUT_MS) { model.generateContent(req1) }
                            .candidates.firstOrNull()?.text?.trim() ?: ""

                        bitmap.recycle()

                        currentSegment = 2
                        val seg2Prompt = buildSeg2Prompt(seg1, style, locationContext)
                        val req2 = generateContentRequest(TextPart(seg2Prompt)) {
                            this.maxOutputTokens = nanoMaxOutputTokens
                            nanoTemperature?.let { this.temperature = it }
                        }
                        val seg2 = withTimeout(SEGMENT_TIMEOUT_MS) { model.generateContent(req2) }
                            .candidates.firstOrNull()?.text?.trim() ?: ""

                        currentSegment = 3
                        val seg3Prompt = buildSeg3Prompt("$seg1 $seg2", style, locationContext)
                        val req3 = generateContentRequest(TextPart(seg3Prompt)) {
                            this.maxOutputTokens = nanoMaxOutputTokens
                            nanoTemperature?.let { this.temperature = it }
                        }
                        val seg3 = withTimeout(SEGMENT_TIMEOUT_MS) { model.generateContent(req3) }
                            .candidates.firstOrNull()?.text?.trim() ?: ""

                        val fullText = listOf(seg1, seg2, seg3)
                            .filter { it.isNotBlank() }
                            .joinToString(" ")

                        val payload = mapOf(
                            "seg1Prompt" to seg1Prompt,
                            "seg1Output" to seg1,
                            "seg2Prompt" to seg2Prompt,
                            "seg2Output" to seg2,
                            "seg3Prompt" to seg3Prompt,
                            "seg3Output" to seg3,
                            "fullText" to fullText
                        )
                        withContext(Dispatchers.Main) { result.success(payload) }
                    } catch (e: TimeoutCancellationException) {
                        withContext(Dispatchers.Main) {
                            result.error(
                                "TIMEOUT",
                                "Gemini Nano inference timed out (segment $currentSegment)",
                                null
                            )
                        }
                    } catch (e: Exception) {
                        withContext(Dispatchers.Main) {
                            result.error("INFERENCE_ERROR", e.message, null)
                        }
                    }
                }
            }

            // Debug/prompt-iteration tool (Settings > Nano Prompt Lab) — a
            // single raw generateContent call, image optional, with no
            // prompt scaffolding (buildSeg1/2/3Prompt) applied. Exists so
            // prompt wording can be iterated against real on-device
            // inference without going through the full 3-segment
            // describeImage cascade or rebuilding the app each try.
            "rawPrompt" -> {
                val prompt = call.argument<String>("prompt")
                if (prompt.isNullOrBlank()) {
                    result.error("INVALID_ARGS", "prompt required", null)
                    return
                }
                val model = generativeModel
                if (model == null) {
                    result.error("NOT_INITIALIZED", "Call initialize first", null)
                    return
                }
                val imagePath = call.argument<String>("imagePath")
                val rawMaxOutputTokens = call.argument<Int>("maxOutputTokens") ?: 256
                val rawTemperature = call.argument<Double>("temperature")?.toFloat()

                scope.launch {
                    try {
                        var bitmap: android.graphics.Bitmap? = null
                        val req = if (imagePath != null) {
                            val opts = BitmapFactory.Options().apply { inSampleSize = 2 }
                            bitmap = BitmapFactory.decodeFile(imagePath, opts)
                                ?: throw Exception("Cannot decode image")
                            generateContentRequest(ImagePart(bitmap), TextPart(prompt)) {
                                this.maxOutputTokens = rawMaxOutputTokens
                                rawTemperature?.let { this.temperature = it }
                            }
                        } else {
                            generateContentRequest(TextPart(prompt)) {
                                this.maxOutputTokens = rawMaxOutputTokens
                                rawTemperature?.let { this.temperature = it }
                            }
                        }
                        val response = withTimeout(SEGMENT_TIMEOUT_MS) { model.generateContent(req) }
                        bitmap?.recycle()
                        val text = response.candidates.firstOrNull()?.text?.trim() ?: ""
                        withContext(Dispatchers.Main) { result.success(text) }
                    } catch (e: TimeoutCancellationException) {
                        withContext(Dispatchers.Main) {
                            result.error("TIMEOUT", "Gemini Nano inference timed out", null)
                        }
                    } catch (e: Exception) {
                        withContext(Dispatchers.Main) {
                            result.error("INFERENCE_ERROR", e.message, null)
                        }
                    }
                }
            }

            else -> result.notImplemented()
        }
    }
}
