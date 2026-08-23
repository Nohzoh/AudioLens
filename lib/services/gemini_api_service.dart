import 'dart:async';
import 'dart:convert';
import 'dart:io';
import '../utils/app_logger.dart';
import '../utils/cancel_token.dart';
import '../utils/error_sanitizer.dart';
import '../utils/image_downscale.dart';
import '../utils/script_validation.dart';
import 'package:dio/dio.dart' as dio;
import 'ai_service.dart';
import 'remote_config_service.dart';

class GeminiApiService implements AIService {
  String? _lastUsedModel;
  String? get lastUsedModel => _lastUsedModel;
  List<String> _lastAttempts = [];
  List<String> get lastAttempts => _lastAttempts;
  final String apiKey;
  final dio.Dio _dio;

  /// [dioClient] allows injecting a mock Dio instance in tests (fallback
  /// logic) — see `test/support/fake_dio_adapter.dart`.
  GeminiApiService({required this.apiKey, dio.Dio? dioClient})
      : _dio = dioClient ?? dio.Dio();

  @override
  String get displayName => 'Gemini API';

  String get providerName => 'Gemini API';

  @override
  Future<bool> isAvailable() async => apiKey.isNotEmpty;

  @override
  Future<void> initialize() async {}

  @override
  void dispose() {}

  @override
  Future<AudioGuideResult> analyzeImage(
    File imageFile, {
    String? locationContext,
    CancelToken? cancelToken,
    String? style,
  }) async {
    final cfg = RemoteConfigService.current;
    // T113: downscale before upload — a full-res phone photo (10-20MB) is
    // real memory pressure and, base64-encoded, ~33% bigger again over
    // the wire. The original file (used for EXIF/history) is untouched.
    final imageBytes = await downscaleForUpload(
      imageFile,
      maxWidth: cfg.imageMaxWidth,
      quality: cfg.imageQuality,
    );
    final base64Image = base64Encode(imageBytes);

    final contextPart = locationContext != null && locationContext.isNotEmpty
        ? '\n\nContexte et informations factuelles disponibles :\n$locationContext'
        : '';

    final wordCount =
        style == 'concise' ? 'Entre 100 et 150 mots' : 'Entre 300 et 400 mots';

    final prompt = 'Tu es un guide audio de musee, passionne et erudit. '
        'Redige deux choses en JSON valide uniquement, sans markdown : '
        '{"title": "titre court et evocateur (5-8 mots max)", "script": "le texte du guide"} '
        'Le titre doit nommer precisement l\'oeuvre ou le lieu si reconnu, sinon evoquer ce qu\'on voit. '
        '${_styleGuidance(style)} '
        'Si tu reconnais l\'oeuvre, nomme-la avec des faits reels. '
        'Si le contexte fourni mentionne un lieu identifie, une adresse ou une enseigne, '
        'utilise-le en priorite pour identifier precisement l\'endroit reel plutot que de '
        'rester generique, et cherche les faits marquants qui s\'y rattachent (tournages, '
        'evenements historiques, personnalites) plutot que de decrire seulement ce qui est visible. '
        '$contextPart '
        '$wordCount pour le script, sans mise en forme ni asterisque. '
        'Ne montre jamais ton raisonnement interne. '
        'Ne commente pas le nombre de mots. '
        'Ecris uniquement le JSON final, rien d\'autre.';

    // Try primary model then fallbacks on 429
    final modelsToTry = [
      cfg.geminiModel,
      ...cfg.geminiModelFallbacks.where((m) => m != cfg.geminiModel),
    ];

    ({int statusCode, String body})? response;
    final List<String> attempts = [];

    for (final model in modelsToTry) {
      final fullUrl =
          '${cfg.geminiApiUrl}/models/$model:generateContent?key=$apiKey';

      try {
        final resp = await _post(
          Uri.parse(fullUrl),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'contents': [
              {
                'parts': [
                  {
                    'inline_data': {
                      'mime_type': 'image/jpeg',
                      'data': base64Image,
                    }
                  },
                  {'text': prompt},
                ]
              }
            ],
            'generationConfig': {
              'maxOutputTokens': cfg.geminiMaxTokens,
              'temperature': cfg.geminiTemperature,
              'thinkingConfig': {'thinkingBudget': cfg.geminiThinkingBudget, 'includeThoughts': false},
            },
          }),
          cancelToken: cancelToken,
        );

        if (resp.statusCode == 200) {
          response = resp;
          _lastUsedModel = model;
          attempts.add('✓ $model');
          AppLogger.ai('Model succeeded: $model');
          break;
        } else if (resp.statusCode == 429 || resp.statusCode == 404 || resp.statusCode == 503) {
          final err = _tryDecode(resp.body);
          final msg = err?['error']?['message'] as String? ?? 'HTTP ${resp.statusCode}';
          final short = msg.length > 80 ? msg.substring(0, 80) : msg;
          attempts.add('✗ $model (${resp.statusCode}): $short');
          AppLogger.ai('Model failed: $model (${resp.statusCode}): $short');
          continue;
        } else {
          final err = _tryDecode(resp.body);
          final msg = (err?['error']?['message'] as String?) ?? resp.body;
          attempts.add('✗ $model (${resp.statusCode}): $msg');
          throw Exception(
            'Gemini API erreur ${resp.statusCode} sur $model:\n$msg',
          );
        }
      } catch (e) {
        // A cancellation must abort the whole retry-across-models loop, not
        // be treated as "this model failed, try the next one" (T70) — the
        // user asked to stop, not to keep burning quota on fallbacks.
        if (e is CancelledException) rethrow;
        if (e is Exception && e.toString().contains('Gemini API erreur')) rethrow;
        attempts.add('✗ $model (timeout/réseau): ${sanitizeError(e.toString())}');
        continue;
      }
    }

    _lastAttempts = attempts;
    if (response == null) {
      final trace = attempts.join('\n');
      throw Exception('Gemini: tous les modèles ont échoué:\n$trace');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final text =
        data['candidates']?[0]?['content']?['parts']?[0]?['text'] as String?;

    if (text == null || text.isEmpty) {
      throw Exception('Gemini API reponse vide');
    }

    // Try JSON response {title, script}
    String title;
    String script;
    try {
      final jsonBlob = _extractJsonObject(text);
      if (jsonBlob == null) throw const FormatException('no JSON');
      final parsed = jsonDecode(jsonBlob) as Map<String, dynamic>;
      final parsedTitle = (parsed['title'] as String? ?? '').trim();
      final parsedScript = (parsed['script'] as String? ?? '').trim();
      // Require both fields — falling back to the raw (still-JSON-shaped)
      // `text` for a missing script would leak the JSON wrapper into the
      // displayed script, the same bug as T90 but on the script side.
      if (parsedTitle.isEmpty || parsedScript.isEmpty) {
        throw const FormatException('empty title or script');
      }
      title = parsedTitle;
      script = _cleanMarkdown(parsedScript);
    } catch (_) {
      // Full JSON parsing failed — often because the model left an
      // unescaped quote inside a field (not a brace-matching problem, so
      // _extractJsonObject's string-aware scan doesn't help here). Try to
      // recover title/script independently via regex before giving up:
      // "title" alone is short (5-8 words per the prompt) and rarely
      // contains a stray quote, so it's often recoverable even when the
      // whole object isn't valid JSON — but "script" is long-form prose,
      // so a stray quote inside it is much more likely to also break the
      // regex, unlike title.
      final titleMatch = RegExp(r'"title"\s*:\s*"((?:[^"\\]|\\.)*)"').firstMatch(text);
      final scriptMatch = RegExp(r'"script"\s*:\s*"((?:[^"\\]|\\.)*)"').firstMatch(text);
      final regexTitle = titleMatch != null ? _unescapeJsonString(titleMatch.group(1)!) : null;
      final regexScript = scriptMatch != null ? _unescapeJsonString(scriptMatch.group(1)!) : null;

      // A "title"/"script" key literal appearing anywhere means the
      // response was meant to be JSON — even if regex extraction above
      // only got one field or none, the raw text is JSON-shaped and must
      // never be shown verbatim as either the title or the script.
      final looksLikeJson = text.trimLeft().startsWith('{') ||
          RegExp(r'"(title|script)"\s*:').hasMatch(text);

      if (regexTitle != null &&
          regexTitle.trim().isNotEmpty &&
          regexScript != null &&
          regexScript.trim().isNotEmpty) {
        title = regexTitle.trim();
        script = _cleanMarkdown(regexScript.trim());
      } else if (looksLikeJson) {
        // Malformed beyond what regex can recover, on either field —
        // showing the raw JSON debris as the title or (worse) reading it
        // aloud as the script (T90) is a worse experience than a clear
        // failure the app's existing retry flow already handles.
        throw Exception(
          'Gemini API: reponse JSON invalide (title/script illisibles)',
        );
      } else {
        // Genuinely plain-text response (model ignored the JSON
        // instruction entirely) — legitimate, readable content, just not
        // in the expected shape.
        final cleaned = _cleanMarkdown(text);
        final first = cleaned.split(RegExp(r'[.!?]')).first.trim();
        title = first.length > 60 ? '${first.substring(0, 60)}...' : first;
        script = cleaned;
      }
    }

    return AudioGuideResult(
      title: title,
      // T117: cap runaway output before it reaches history/TTS.
      script: capScriptLength(script, maxChars: RemoteConfigService.current.scriptMaxChars),
    );
  }

  /// Tone/structure instruction for the script, keyed by [style] (T75/T48).
  /// The default ('immersive', including null/unrecognized values) is the
  /// original prompt text unchanged, so the default experience never
  /// regresses.
  static String _styleGuidance(String? style) {
    switch (style) {
      case 'academic':
        return 'Le script : documentaire et rigoureux, tu t\'adresses au visiteur avec "vous". '
            'Privilegie les faits verifies, dates precises et contexte historique '
            'detaille plutot que l\'emotion. Commence par le fait le plus '
            'significatif ou la date cle, sans effet de style superflu. '
            'Construis : mise en contexte factuelle, developpement historique, '
            'details techniques ou artistiques, conclusion sur l\'importance '
            'du lieu ou de l\'oeuvre.';
      case 'anecdotal':
        return 'Le script : complice et plein de curiosites, tu t\'adresses au '
            'visiteur avec "vous". Varie toujours l\'accroche d\'ouverture : ne '
            'commence jamais par "Arrêtez-vous", "Regardez", "Devant vous", '
            '"Contemplez" ou toute formule repetitive. Mets l\'accent sur les '
            'anecdotes, secrets et petites histoires peu connues plutot qu\'une '
            'description exhaustive, comme un ami qui partage ce qu\'il sait de '
            'plus surprenant. Construis : accroche par une anecdote, '
            'enchainement de curiosites, conclusion sur ce qui rend l\'histoire '
            'memorable.';
      case 'concise':
        return 'Le script : direct et efficace, tu t\'adresses au visiteur avec '
            '"vous". Va droit au but : l\'essentiel seulement, sans digression '
            'ni developpement long. Une accroche courte, un ou deux faits '
            'marquants, une conclusion breve.';
      default: // 'immersive'
        return 'Le script : narratif et immersif, tu t\'adresses au visiteur '
            'avec "vous". Varie toujours l\'accroche d\'ouverture : ne commence '
            'jamais par "Arrêtez-vous", "Regardez", "Devant vous", "Contemplez" '
            'ou toute formule repetitive. Sois inventif : commence par un fait '
            'surprenant, une question, une anecdote, une sensation, une date '
            'marquante, ou plonge directement dans l\'histoire. Construis : '
            'accroche originale, details fascinants, contexte historique, '
            'anecdote marquante, conclusion emotionnelle.';
    }
  }

  /// Finds the first top-level JSON object in [text] by scanning for
  /// balanced braces, tracking whether the scanner is inside a string
  /// literal so a `{`/`}` inside e.g. the "script" value's own text (or a
  /// ```` ```json ```` fence around the object) doesn't throw off the
  /// match — unlike a plain `indexOf('{')`/`lastIndexOf('}')` pair, which
  /// silently returns the wrong boundary in both cases (T90).
  static String? _extractJsonObject(String text) {
    final start = text.indexOf('{');
    if (start == -1) return null;

    var depth = 0;
    var inString = false;
    var escaped = false;
    for (var i = start; i < text.length; i++) {
      final char = text[i];
      if (inString) {
        if (escaped) {
          escaped = false;
        } else if (char == '\\') {
          escaped = true;
        } else if (char == '"') {
          inString = false;
        }
        continue;
      }
      if (char == '"') {
        inString = true;
      } else if (char == '{') {
        depth++;
      } else if (char == '}') {
        depth--;
        if (depth == 0) return text.substring(start, i + 1);
      }
    }
    return null;
  }

  /// Unescapes a raw JSON string body (the content between the quotes,
  /// as captured by a regex) by delegating to [jsonDecode] rather than
  /// hand-rolling escape handling. Returns null if [raw] isn't valid
  /// JSON string content (e.g. a truncated escape sequence).
  static String? _unescapeJsonString(String raw) {
    try {
      return jsonDecode('"$raw"') as String;
    } catch (_) {
      return null;
    }
  }

  /// Posts [body] to [uri] via dio, whose [dio.CancelToken] actually aborts
  /// the in-flight request (unlike the old `http` client + `Future.timeout`
  /// combo, which stopped *waiting* but left the request running in the
  /// background to completion regardless — T70). Wires [cancelToken] (the
  /// app's own token) to a fresh dio token for this call, and treats an
  /// exceeded [const Duration(seconds: 30)] the same way: cancel the
  /// socket, not just the wait.
  Future<({int statusCode, String body})> _post(
    Uri uri, {
    required Map<String, String> headers,
    required String body,
    CancelToken? cancelToken,
  }) async {
    final dioToken = dio.CancelToken();
    cancelToken?.onCancel.then((_) => dioToken.cancel());
    try {
      final resp = await _dio
          .postUri<String>(
            uri,
            data: body,
            cancelToken: dioToken,
            options: dio.Options(
              headers: headers,
              responseType: dio.ResponseType.plain,
              validateStatus: (_) => true,
            ),
          )
          .timeout(
            const Duration(seconds: 30),
            onTimeout: () {
              dioToken.cancel();
              throw TimeoutException('Gemini API: délai dépassé');
            },
          );
      return (statusCode: resp.statusCode ?? 0, body: resp.data ?? '');
    } on dio.DioException catch (e) {
      if (e.type == dio.DioExceptionType.cancel) {
        throw const CancelledException();
      }
      rethrow;
    }
  }

  /// Safely decodes an error body: API error pages are not always JSON.
  static Map<String, dynamic>? _tryDecode(String body) {
    try {
      final decoded = jsonDecode(body);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  String _cleanMarkdown(String text) {
    var result = text
        .replaceAll(RegExp(r'\*{1,3}'), '')
        .replaceAll(RegExp(r'^\s*[-•]\s+', multiLine: true), '')
        .replaceAll(RegExp(r'\s*\(\d+\)'), '')
        .replaceAll(RegExp(r'^#{1,6}\s+', multiLine: true), '')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
    // Remove English thinking/meta lines
    final lines = result.split('\n');
    final filtered = lines.where((line) {
      final lower = line.trim().toLowerCase();
      if (lower.isEmpty) return true;
      // Skip lines that are clearly internal reasoning in English
      final thinkingPatterns = [
        'rough estimate', 'word count', 'let me ', "let's",
        'okay,', 'alright,', 'i need to', 'i should', 'i will',
        'currently it is', 'this is around', 'paragraph ',
        'to ensure', 'to make sure', 'expanding', 'slightly',
        'within the', 'word range', 'falls well',
      ];
      for (final p in thinkingPatterns) {
        if (lower.contains(p)) return false;
      }
      return true;
    }).toList();
    return filtered.join('\n').trim();
  }
}
