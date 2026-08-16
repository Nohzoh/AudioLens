import 'dart:convert';
import 'dart:io';
import '../utils/app_logger.dart';
import 'package:http/http.dart' as http;
import 'ai_service.dart';
import 'remote_config_service.dart';

class GeminiApiService implements AIService {
  String? _lastUsedModel;
  String? get lastUsedModel => _lastUsedModel;
  List<String> _lastAttempts = [];
  List<String> get lastAttempts => _lastAttempts;
  final String apiKey;
  final http.Client? _client;

  /// [client] allows injecting a mock HTTP client in tests (fallback logic).
  GeminiApiService({required this.apiKey, http.Client? client}) : _client = client;

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
  }) async {
    final cfg = RemoteConfigService.current;
    final imageBytes = await imageFile.readAsBytes();
    final base64Image = base64Encode(imageBytes);

    final contextPart = locationContext != null && locationContext.isNotEmpty
        ? '\n\nContexte et informations factuelles disponibles :\n$locationContext'
        : '';

    final prompt = 'Tu es un guide audio de musee, passionne et erudit. '
        'Redige deux choses en JSON valide uniquement, sans markdown : '
        '{"title": "titre court et evocateur (5-8 mots max)", "script": "le texte du guide"} '
        'Le titre doit nommer precisement l\'oeuvre ou le lieu si reconnu, sinon evoquer ce qu\'on voit. '
        'Le script : narratif et immersif, tu t\'adresses au visiteur avec "vous". '
        'Varie toujours l\'accroche d\'ouverture : ne commence jamais par "Arrêtez-vous", '
        '"Regardez", "Devant vous", "Contemplez" ou toute formule repetitive. '
        'Sois inventif : commence par un fait surprenant, une question, une anecdote, '
        'une sensation, une date marquante, ou plonge directement dans l\'histoire. '
        'Construis : accroche originale, details fascinants, contexte historique, '
        'anecdote marquante, conclusion emotionnelle. '
        'Si tu reconnais l\'oeuvre, nomme-la avec des faits reels. '
        'Si le contexte fourni mentionne un lieu identifie, une adresse ou une enseigne, '
        'utilise-le en priorite pour identifier precisement l\'endroit reel plutot que de '
        'rester generique, et cherche les faits marquants qui s\'y rattachent (tournages, '
        'evenements historiques, personnalites) plutot que de decrire seulement ce qui est visible. '
        '$contextPart '
        'Entre 300 et 400 mots pour le script, sans mise en forme ni asterisque. '
        'Ne montre jamais ton raisonnement interne. '
        'Ne commente pas le nombre de mots. '
        'Ecris uniquement le JSON final, rien d\'autre.';

    // Try primary model then fallbacks on 429
    final modelsToTry = [
      cfg.geminiModel,
      ...cfg.geminiModelFallbacks.where((m) => m != cfg.geminiModel),
    ];

    http.Response? response;
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
        ).timeout(const Duration(seconds: 30));

        if (resp.statusCode == 200) {
          response = resp;
          _lastUsedModel = model;
          attempts.add('✓ $model');
          AppLogger.ai('Model succeeded: $model');
          break;
        } else if (resp.statusCode == 429 || resp.statusCode == 404 || resp.statusCode == 503) {
          final err = _tryDecode(resp);
          final msg = err?['error']?['message'] as String? ?? 'HTTP ${resp.statusCode}';
          final short = msg.length > 80 ? msg.substring(0, 80) : msg;
          attempts.add('✗ $model (${resp.statusCode}): $short');
          AppLogger.ai('Model failed: $model (${resp.statusCode}): $short');
          continue;
        } else {
          final err = _tryDecode(resp);
          final msg = (err?['error']?['message'] as String?) ?? resp.body;
          attempts.add('✗ $model (${resp.statusCode}): $msg');
          throw Exception(
            'Gemini API erreur ${resp.statusCode} sur $model:\n$msg',
          );
        }
      } catch (e) {
        if (e is Exception && e.toString().contains('Gemini API erreur')) rethrow;
        attempts.add('✗ $model (timeout/réseau): $e');
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
      title = (parsed['title'] as String? ?? '').trim();
      script = _cleanMarkdown((parsed['script'] as String? ?? text).trim());
      if (title.isEmpty) throw const FormatException('empty title');
    } catch (_) {
      // Full JSON parsing failed — often because the model left an
      // unescaped quote inside "script" (not a brace-matching problem,
      // so _extractJsonObject's string-aware scan doesn't help here).
      // The "title" field alone is short (5-8 words per the prompt) and
      // rarely contains a stray quote, so it's usually still recoverable
      // by regex even when the full object isn't valid JSON.
      final titleMatch = RegExp(r'"title"\s*:\s*"((?:[^"\\]|\\.)*)"').firstMatch(text);
      final scriptMatch = RegExp(r'"script"\s*:\s*"((?:[^"\\]|\\.)*)"').firstMatch(text);
      final regexTitle = titleMatch != null ? _unescapeJsonString(titleMatch.group(1)!) : null;

      if (regexTitle != null && regexTitle.trim().isNotEmpty) {
        title = regexTitle.trim();
        script = scriptMatch != null
            ? _cleanMarkdown((_unescapeJsonString(scriptMatch.group(1)!) ?? text).trim())
            : _cleanMarkdown(text);
      } else {
        final cleaned = _cleanMarkdown(text);
        final first = cleaned.split(RegExp(r'[.!?]')).first.trim();
        // Last-resort guard: if even this heuristic lands on something
        // that still looks like unparsed JSON, never show that to the
        // user (T90) — fall back to a generic title instead.
        final looksLikeJson = first.startsWith('{') || first.contains('"title"');
        title = looksLikeJson
            ? 'Votre guide audio'
            : (first.length > 60 ? '${first.substring(0, 60)}...' : first);
        script = cleaned;
      }
    }

    return AudioGuideResult(title: title, script: script);
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

  Future<http.Response> _post(
    Uri uri, {
    required Map<String, String> headers,
    required String body,
  }) {
    final client = _client;
    if (client != null) {
      return client
          .post(uri, headers: headers, body: body)
          .timeout(const Duration(seconds: 30));
    }
    return http.post(uri, headers: headers, body: body)
        .timeout(const Duration(seconds: 30));
  }

  /// Safely decodes an error body: API error pages are not always JSON.
  static Map<String, dynamic>? _tryDecode(http.Response resp) {
    try {
      final decoded = jsonDecode(resp.body);
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
