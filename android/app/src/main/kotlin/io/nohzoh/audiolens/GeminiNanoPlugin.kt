package io.nohzoh.audiolens

import android.content.Context
import android.graphics.BitmapFactory
import android.graphics.Bitmap
import com.google.mlkit.genai.common.DownloadStatus
import com.google.mlkit.genai.common.FeatureStatus
import com.google.mlkit.genai.prompt.Generation
import com.google.mlkit.genai.prompt.GenerationConfig
import com.google.mlkit.genai.prompt.GenerativeModel
import com.google.mlkit.genai.prompt.ImagePart
import com.google.mlkit.genai.prompt.ModelPreference
import com.google.mlkit.genai.prompt.ModelReleaseStage
import com.google.mlkit.genai.prompt.TextPart
import com.google.mlkit.genai.prompt.TypedCandidate
import com.google.mlkit.genai.prompt.generateContentRequest
import com.google.mlkit.genai.prompt.generateTypedContentRequest
import com.google.mlkit.genai.prompt.generationConfig
import com.google.mlkit.genai.prompt.modelConfig
import io.nohzoh.audiolens.nano.NanoSeg1
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

        // #286: minimum exact-overlap length (chars) required before
        // dropOverlapWithAccumulated treats a match as the model echoing
        // its given excerpt back, not a legitimately short repeated
        // phrase (e.g. "de la ville de").
        private const val MIN_ECHO_OVERLAP_CHARS = 30

        // #286: buildSeg2Prompt/buildSeg3Prompt feed the model the last
        // ~200 characters of what it said so far as "Texte precedent" — a
        // hard character cut, not a sentence boundary. The on-device
        // model is far weaker at instruction-following than the cloud
        // pipeline and sometimes echoes that excerpt back near-verbatim
        // before actually continuing (often prefixed with an ellipsis, as
        // if resuming a cut-off sentence), despite the prompt explicitly
        // saying not to repeat — producing a visible duplicate once
        // segments are concatenated. Applied only when assembling
        // describeImage's final fullText — describeImageDebug (#279)
        // deliberately keeps returning each segment's raw, uncleaned
        // output, since showing exactly what the model said is its whole
        // purpose.
        private fun stripLeadingEllipsis(text: String): String {
            var t = text.trim()
            while (t.startsWith("…") || t.startsWith("...")) {
                t = t.removePrefix("…").removePrefix("...").trimStart()
            }
            return t
        }

        private fun dropOverlapWithAccumulated(accumulated: String, next: String): String {
            val cleaned = stripLeadingEllipsis(next)
            if (accumulated.isBlank() || cleaned.isBlank()) return cleaned
            val maxLen = minOf(accumulated.length, cleaned.length, 200)
            for (len in maxLen downTo MIN_ECHO_OVERLAP_CHARS) {
                if (accumulated.takeLast(len).equals(cleaned.take(len), ignoreCase = true)) {
                    return cleaned.substring(len).trimStart()
                }
            }
            return cleaned
        }

        // Tone descriptor per style (T75/T48) — default (null/unrecognized)
        // is the original wording, so the default experience is unchanged.
        private fun styleTone(style: String?): String = when (style) {
            "academic" -> "un ton documentaire et precis, avec des faits verifies"
            "anecdotal" -> "un ton complice qui met en avant anecdotes et curiosites"
            "concise" -> "un ton direct et efficace"
            // #425: for children aged 6 to 10.
            "kids" -> "un ton joyeux pour un enfant de 6 a 10 ans, en le tutoyant, avec des phrases courtes et des mots simples, sans details effrayants"
            else -> "un ton chaleureux et vivant"
        }

        fun buildSeg1Prompt(
            locationContext: String?,
            style: String? = null,
            language: String? = null,
            structured: Boolean = false,
        ): String {
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
            //
            // #434: with structured output the title is its own typed
            // field (NanoSeg1), so the bracket convention is dropped from
            // the prompt rather than asked for twice.
            val titleDirective = if (structured) {
                "Donne un titre court (3 a 6 mots, ex: Le Colisee de Rome) et un texte. Dans le texte,"
            } else {
                "Commence par un titre court entre crochets (3 a 6 mots, ex: [Le Colisee de Rome]), sur sa propre ligne. Puis,"
            }
            return "Tu es un guide audio culturel. $titleDirective sans phrase d'introduction, decris ce que tu vois sur cette image$loc avec ${styleTone(style)}. Ne mentionne pas de dates ou chiffres precis dont tu n'es pas certain. $sentences.$languageDirective"
        }

        // #434: typed finish reasons, named for the Dart-side logs.
        // Only STOP and MAX_TOKENS are public constants in beta4; the
        // parse/validation reasons are logged by their raw value.
        private fun typedFinishReasonName(reason: Int?): String? = when (reason) {
            null -> null
            TypedCandidate.TypedFinishReason.STOP -> "STOP"
            TypedCandidate.TypedFinishReason.MAX_TOKENS -> "MAX_TOKENS"
            else -> "OTHER($reason)"
        }

        private fun statusName(status: Int): String = when (status) {
            FeatureStatus.UNAVAILABLE -> "unavailable"
            FeatureStatus.DOWNLOADABLE -> "downloadable"
            FeatureStatus.DOWNLOADING -> "downloading"
            FeatureStatus.AVAILABLE -> "available"
            else -> "unknown"
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
                "kids" -> "un fait etonnant explique simplement, compare a la vie de tous les jours d'un enfant, en le tutoyant"
                else -> "le contexte historique et culturel"
            }
            val sentences = if (style == "concise") "1 phrase" else "2-3 phrases qui s'enchainent naturellement"
            return "Tu es un guide audio culturel. Suite de ton commentaire. Texte precedent : $excerpt.${locationHint(locationContext)} Continue avec $focus en $sentences, en te basant sur les faits reels ci-dessus plutot que de rester generique. Pas de repetition."
        }

        fun buildSeg3Prompt(previousText: String, style: String? = null, locationContext: String? = null): String {
            val excerpt = previousText.takeLast(200)
            val sentences = if (style == "concise") "1 phrase" else "2 phrases"
            // #425: a kids' guide ends on a question inviting the child to look.
            val ending = if (style == "kids") {
                "sur une question qui invite l'enfant a observer un detail, en le tutoyant"
            } else {
                "sur ce qui rend ce lieu unique et l'emotion qu'il inspire"
            }
            return "Tu es un guide audio culturel. Suite de ton commentaire. Texte precedent : $excerpt.${locationHint(locationContext)} Conclus en $sentences $ending, sans repeter ce qui a deja ete dit."
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

    // #431: the Nano Prompt Lab can target one model variant
    // (Stable/Preview x Fast/Full, ML Kit >= 1.0.0-beta2). No
    // releaseStage/preference argument = null = the default client
    // (Stable/Full), i.e. exactly what production has always used.
    private fun variantConfig(call: MethodCall): GenerationConfig? {
        val stageArg = call.argument<String>("releaseStage")
        val preferenceArg = call.argument<String>("preference")
        if (stageArg == null && preferenceArg == null) return null
        return generationConfig {
            modelConfig = modelConfig {
                releaseStage = if (stageArg == "preview") ModelReleaseStage.PREVIEW else ModelReleaseStage.STABLE
                preference = if (preferenceArg == "fast") ModelPreference.FAST else ModelPreference.FULL
            }
        }
    }

    private fun newClient(config: GenerationConfig?): GenerativeModel =
        if (config == null) Generation.getClient() else Generation.getClient(config)

    // #434: typed title/text for segment 1 when the device supports
    // structured output, else (or if the typed call fails in any way
    // other than a timeout) today's bracket-title text path — the
    // result must stay usable either way.
    private data class Seg1Result(
        val prompt: String,
        val title: String?,
        val text: String,
        val mode: String,
        val finishReason: String?,
        val fallbackReason: String?,
    )

    private suspend fun runSeg1(
        model: GenerativeModel,
        bitmap: Bitmap,
        locationContext: String?,
        style: String?,
        language: String?,
        maxTokens: Int,
        temperature: Float?,
    ): Seg1Result {
        var fallbackReason: String? = null
        var finishReason: String? = null
        val structuredAvailable = try {
            model.isStructuredOutputFeatureAvailable()
        } catch (e: Exception) {
            fallbackReason = "availability check failed: ${e.javaClass.simpleName}"
            false
        }
        if (structuredAvailable) {
            val prompt = buildSeg1Prompt(locationContext, style, language, structured = true)
            try {
                val base = generateContentRequest(ImagePart(bitmap), TextPart(prompt)) {
                    this.maxOutputTokens = maxTokens
                    temperature?.let { this.temperature = it }
                }
                val typedRequest = generateTypedContentRequest(base, NanoSeg1::class)
                val candidate = withTimeout(SEGMENT_TIMEOUT_MS) { model.generateContent(typedRequest) }
                    .candidates.firstOrNull()
                finishReason = typedFinishReasonName(candidate?.finishReason)
                val parsed = candidate?.response
                if (parsed != null && parsed.title.isNotBlank() && parsed.text.isNotBlank()) {
                    return Seg1Result(prompt, parsed.title.trim(), parsed.text.trim(), "structured", finishReason, null)
                }
                fallbackReason = "no usable typed response"
            } catch (e: TimeoutCancellationException) {
                // A hung call stays a timeout (#173), not a second 30s try.
                throw e
            } catch (e: Exception) {
                // Class name only: the message could echo model output.
                fallbackReason = "typed call failed: ${e.javaClass.simpleName}"
            }
        } else if (fallbackReason == null) {
            fallbackReason = "structured output unavailable"
        }

        val prompt = buildSeg1Prompt(locationContext, style, language)
        val req = generateContentRequest(ImagePart(bitmap), TextPart(prompt)) {
            this.maxOutputTokens = maxTokens
            temperature?.let { this.temperature = it }
        }
        val text = withTimeout(SEGMENT_TIMEOUT_MS) { model.generateContent(req) }
            .candidates.firstOrNull()?.text?.trim() ?: ""
        return Seg1Result(prompt, null, text, "text", finishReason, fallbackReason)
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
            //
            // #431: optional releaseStage/preference arguments check one
            // model variant instead of the default client — status is per
            // variant (one can be available while another is unavailable).
            "checkNanoStatus" -> {
                val config = variantConfig(call)
                scope.launch {
                    try {
                        val model = newClient(config)
                        val status = model.checkStatus()
                        model.close()
                        withContext(Dispatchers.Main) { result.success(statusName(status)) }
                    } catch (e: Exception) {
                        withContext(Dispatchers.Main) { result.success("unknown") }
                    }
                }
            }

            // #431: Nano Prompt Lab only — downloads one model variant
            // reported DOWNLOADABLE. Separate from "initialize", which
            // keeps owning the default client production uses.
            "downloadVariant" -> {
                val config = variantConfig(call)
                scope.launch {
                    val model = newClient(config)
                    try {
                        var failed = false
                        model.download().collect { status ->
                            if (status is DownloadStatus.DownloadFailed) failed = true
                        }
                        val downloadFailed = failed
                        withContext(Dispatchers.Main) {
                            if (downloadFailed) result.error("DOWNLOAD_ERROR", "Model download failed", null)
                            else result.success(true)
                        }
                    } catch (e: Exception) {
                        withContext(Dispatchers.Main) {
                            result.error("DOWNLOAD_ERROR", e.message, null)
                        }
                    } finally {
                        model.close()
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
                        // (#434: typed title/text when available).
                        currentSegment = 1
                        val seg1Result = runSeg1(
                            model, bitmap, locationContext, style, language,
                            nanoMaxOutputTokens, nanoTemperature
                        )
                        val seg1 = seg1Result.text

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

                        // #286: cleaned+de-duplicated at each step, not
                        // joined raw — see dropOverlapWithAccumulated.
                        var fullText = seg1
                        val cleanedSeg2 = dropOverlapWithAccumulated(fullText, seg2)
                        fullText = listOf(fullText, cleanedSeg2).filter { it.isNotBlank() }.joinToString(" ")
                        val cleanedSeg3 = dropOverlapWithAccumulated(fullText, seg3)
                        fullText = listOf(fullText, cleanedSeg3).filter { it.isNotBlank() }.joinToString(" ")

                        // #434: a map instead of the bare text, so a typed
                        // title reaches Dart without the "[Title]" parsing,
                        // plus what the Dart side logs about segment 1.
                        // "title" is null on the text path, where fullText
                        // still starts with the bracket title as before.
                        val payload = mapOf(
                            "fullText" to fullText,
                            "title" to seg1Result.title,
                            "seg1Mode" to seg1Result.mode,
                            "seg1FinishReason" to seg1Result.finishReason,
                            "seg1FallbackReason" to seg1Result.fallbackReason
                        )
                        withContext(Dispatchers.Main) { result.success(payload) }
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
                // #431: optional model variant (Nano Prompt Lab selector).
                val config = variantConfig(call)

                if (imagePath == null) {
                    result.error("INVALID_ARGS", "imagePath required", null)
                    return
                }
                val sharedModel = generativeModel
                if (config == null && sharedModel == null) {
                    result.error("NOT_INITIALIZED", "Call initialize first", null)
                    return
                }

                var currentSegment = 0

                scope.launch {
                    val model = if (config != null) newClient(config) else sharedModel!!
                    try {
                        val opts = BitmapFactory.Options().apply { inSampleSize = 2 }
                        val bitmap = BitmapFactory.decodeFile(imagePath, opts)
                            ?: throw Exception("Cannot decode image")

                        currentSegment = 1
                        val seg1Result = runSeg1(
                            model, bitmap, locationContext, style, language,
                            nanoMaxOutputTokens, nanoTemperature
                        )
                        val seg1Prompt = seg1Result.prompt
                        val seg1 = seg1Result.text

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
                            "seg1Title" to seg1Result.title,
                            "seg1Mode" to seg1Result.mode,
                            "seg1FinishReason" to seg1Result.finishReason,
                            "seg1FallbackReason" to seg1Result.fallbackReason,
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
                    } finally {
                        if (config != null) model.close()
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
                // #431: optional model variant (Nano Prompt Lab selector).
                val config = variantConfig(call)
                val sharedModel = generativeModel
                if (config == null && sharedModel == null) {
                    result.error("NOT_INITIALIZED", "Call initialize first", null)
                    return
                }
                val imagePath = call.argument<String>("imagePath")
                val rawMaxOutputTokens = call.argument<Int>("maxOutputTokens") ?: 256
                val rawTemperature = call.argument<Double>("temperature")?.toFloat()

                scope.launch {
                    val model = if (config != null) newClient(config) else sharedModel!!
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
                    } finally {
                        if (config != null) model.close()
                    }
                }
            }

            else -> result.notImplemented()
        }
    }
}
