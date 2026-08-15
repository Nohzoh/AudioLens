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
      final jsonStart = text.indexOf('{');
      final jsonEnd = text.lastIndexOf('}');
      if (jsonStart != -1 && jsonEnd != -1) {
        final parsed = jsonDecode(text.substring(jsonStart, jsonEnd + 1)) as Map<String, dynamic>;
        title = (parsed['title'] as String? ?? '').trim();
        script = _cleanMarkdown((parsed['script'] as String? ?? text).trim());
        if (title.isEmpty) throw const FormatException('empty title');
      } else {
        throw const FormatException('no JSON');
      }
    } catch (_) {
      final cleaned = _cleanMarkdown(text);
      final first = cleaned.split(RegExp(r'[.!?]')).first.trim();
      title = first.length > 60 ? '${first.substring(0, 60)}...' : first;
      script = cleaned;
    }

    return AudioGuideResult(title: title, script: script);
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
