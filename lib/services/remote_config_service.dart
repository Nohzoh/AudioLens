import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/app_logger.dart';
import '../utils/script_validation.dart';

class RemoteConfig {
  // Gemini API
  final String geminiModel;
  final List<String> geminiModelFallbacks;
  final String geminiApiUrl;
  final int geminiMaxTokens;
  final double geminiTemperature;

  // Gemini Nano
  final int geminiNanoMaxTokens;
  final int geminiNanoCascadeSegments;

  /// #170: previously not settable at all — inference ran at whatever
  /// ML Kit GenAI's own unstated default was. 0.7 matches [geminiTemperature]
  /// so both pipelines aim for the same tone by default.
  final double geminiNanoTemperature;

  // Wikipedia
  final int wikipediaRadiusMeters;
  final int wikipediaMaxResults;
  final int wikipediaExtractChars;

  // POI (point of interest) lookup — T74
  final int poiRadiusMeters;

  /// #248: the free public Overpass instance enforces its own concurrent
  /// request "slot" limit — live testing against `/api/status` confirmed
  /// "Rate limit: 2", with queued requests taking 10+ seconds or
  /// returning 504 under load, well past the previous flat 6s client
  /// timeout. Requests paced a second or so apart were 100% reliable in
  /// the same testing, so a longer timeout plus [poiMaxAttempts] (a
  /// short-delay retry) recovers most of these transient failures
  /// without needing a second, less-trustworthy mirror — several
  /// alternatives were tried and rejected: some mirrors errored outright,
  /// and one (overpass.osm.ch) responded fast but with a stale/empty
  /// database, which is worse than a timeout since it would silently
  /// report "no POI found" for a real one.
  final int poiTimeoutSeconds;

  /// Total attempts (including the first), not additional retries — 2
  /// means "try once, retry once more on failure".
  final int poiMaxAttempts;

  // TTS
  final double ttsSpeed;
  final int ttsSid;
  final int ttsNumThreads;

  // Location
  final int locationTimeoutSeconds;

  // Image
  final int imageMaxWidth;
  final int imageQuality;

  // App
  final int timingHistorySize;
  final int progressSimulationIntervalMs;
  final String geminiTtsModel;
  final String geminiTtsVoice;
  final int geminiThinkingBudget;

  /// Character ceiling for a generated script before it reaches history
  /// and TTS (T117) — see utils/script_validation.dart.
  final int scriptMaxChars;

  const RemoteConfig({
    this.geminiModel = 'gemini-3.5-flash',
    this.geminiModelFallbacks = const ['gemini-2.5-flash-preview-05-20', 'gemini-1.5-flash'],
    this.geminiApiUrl = 'https://generativelanguage.googleapis.com/v1',
    this.geminiMaxTokens = 1024,
    this.geminiTemperature = 0.7,
    this.geminiNanoMaxTokens = 256,
    this.geminiNanoCascadeSegments = 3,
    this.geminiNanoTemperature = 0.7,
    this.wikipediaRadiusMeters = 500,
    this.wikipediaMaxResults = 3,
    this.wikipediaExtractChars = 1500,
    this.poiRadiusMeters = 75,
    this.poiTimeoutSeconds = 10,
    this.poiMaxAttempts = 2,
    this.ttsSpeed = 1.2,
    this.ttsSid = 0,
    this.ttsNumThreads = 2,
    this.locationTimeoutSeconds = 10,
    this.imageMaxWidth = 1280,
    this.imageQuality = 85,
    this.timingHistorySize = 5,
    this.progressSimulationIntervalMs = 150,
    this.geminiTtsModel = 'gemini-2.5-flash-preview-tts',
    this.geminiTtsVoice = 'Aoede',
    this.geminiThinkingBudget = 512,
    this.scriptMaxChars = kDefaultScriptMaxChars,
  });

  factory RemoteConfig.fromJson(Map<String, dynamic> json) {
    return RemoteConfig(
      geminiModel: json['gemini_model'] as String? ?? 'gemini-3.5-flash',
      geminiModelFallbacks: (json['gemini_model_fallbacks'] as List<dynamic>?)?.cast<String>() ?? const ['gemini-2.5-flash-preview-05-20', 'gemini-1.5-flash'],
      geminiApiUrl: json['gemini_api_url'] as String?
          ?? 'https://generativelanguage.googleapis.com/v1',
      geminiMaxTokens: json['gemini_max_tokens'] as int? ?? 1024,
      geminiTemperature: (json['gemini_temperature'] as num?)?.toDouble() ?? 0.7,
      geminiNanoMaxTokens: json['gemini_nano_max_tokens'] as int? ?? 256,
      geminiNanoCascadeSegments: json['gemini_nano_cascade_segments'] as int? ?? 3,
      geminiNanoTemperature: (json['gemini_nano_temperature'] as num?)?.toDouble() ?? 0.7,
      wikipediaRadiusMeters: json['wikipedia_radius_meters'] as int? ?? 500,
      wikipediaMaxResults: json['wikipedia_max_results'] as int? ?? 3,
      wikipediaExtractChars: json['wikipedia_extract_chars'] as int? ?? 1500,
      poiRadiusMeters: json['poi_radius_meters'] as int? ?? 75,
      poiTimeoutSeconds: json['poi_timeout_seconds'] as int? ?? 10,
      poiMaxAttempts: json['poi_max_attempts'] as int? ?? 2,
      ttsSpeed: (json['tts_speed'] as num?)?.toDouble() ?? 1.2,
      ttsSid: json['tts_sid'] as int? ?? 0,
      ttsNumThreads: json['tts_num_threads'] as int? ?? 2,
      locationTimeoutSeconds: json['location_timeout_seconds'] as int? ?? 10,
      imageMaxWidth: json['image_max_width'] as int? ?? 1280,
      imageQuality: json['image_quality'] as int? ?? 85,
      timingHistorySize: json['timing_history_size'] as int? ?? 5,
      progressSimulationIntervalMs:
          json['progress_simulation_interval_ms'] as int? ?? 150,
      geminiTtsModel: json['gemini_tts_model'] as String? ?? 'gemini-2.5-flash-preview-tts',
      geminiTtsVoice: json['gemini_tts_voice'] as String? ?? 'Aoede',
      geminiThinkingBudget: json['gemini_thinking_budget'] as int? ?? 512,
      scriptMaxChars: json['script_max_chars'] as int? ?? kDefaultScriptMaxChars,
    );
  }

  Map<String, dynamic> toJson() => {
    'gemini_model': geminiModel,
    'gemini_model_fallbacks': geminiModelFallbacks,
    'gemini_api_url': geminiApiUrl,
    'gemini_max_tokens': geminiMaxTokens,
    'gemini_temperature': geminiTemperature,
    'gemini_nano_max_tokens': geminiNanoMaxTokens,
    'gemini_nano_cascade_segments': geminiNanoCascadeSegments,
    'gemini_nano_temperature': geminiNanoTemperature,
    'wikipedia_radius_meters': wikipediaRadiusMeters,
    'wikipedia_max_results': wikipediaMaxResults,
    'wikipedia_extract_chars': wikipediaExtractChars,
    'poi_radius_meters': poiRadiusMeters,
    'poi_timeout_seconds': poiTimeoutSeconds,
    'poi_max_attempts': poiMaxAttempts,
    'tts_speed': ttsSpeed,
    'tts_sid': ttsSid,
    'tts_num_threads': ttsNumThreads,
    'location_timeout_seconds': locationTimeoutSeconds,
    'image_max_width': imageMaxWidth,
    'image_quality': imageQuality,
    'timing_history_size': timingHistorySize,
    'progress_simulation_interval_ms': progressSimulationIntervalMs,
    'gemini_tts_model': geminiTtsModel,
    'gemini_tts_voice': geminiTtsVoice,
    'gemini_thinking_budget': geminiThinkingBudget,
    'script_max_chars': scriptMaxChars,
  };
}

class RemoteConfigService {
  static const _configUrl =
      'https://raw.githubusercontent.com/Nohzoh/AudioLens/main/config.json';
  static const _cacheKey = 'remote_config_cache';
  static const _cacheSigKey = 'remote_config_cache_sig';
  static const _cacheLoadedAtKey = 'remote_config_cache_loaded_at';

  /// Hosts the Gemini API URL is allowed to point to. The remote config is
  /// fetched unauthenticated (T81) — without this allowlist, a compromised
  /// config.json could redirect the user's API key to an attacker's server.
  static const allowedApiHosts = {'generativelanguage.googleapis.com'};

  /// Whether [url] is safe to use as the Gemini API base URL.
  static bool isAllowedApiUrl(String url) {
    final host = Uri.tryParse(url)?.host;
    return host != null && allowedApiHosts.contains(host);
  }

  // Public half of the Ed25519 keypair used to sign config.json — the
  // private half never touches CI or GitHub secrets, it's only ever used
  // locally (scripts/sign_config.dart) before committing config.json and
  // config.json.sig together. A compromised CI/repo write access alone
  // can edit config.json's *content*, but can't produce a valid signature
  // for it — the app rejects anything that doesn't verify.
  static const _publicKeyB64 = 'PRUKkHzANB7y05yMvxk8XAM01o3e2YDTLCKy1JJm5Ys=';
  static const _signatureUrl =
      'https://raw.githubusercontent.com/Nohzoh/AudioLens/main/config.json.sig';

  static RemoteConfig _current = const RemoteConfig();
  static DateTime? _loadedAt;
  static bool _loadedFromRemote = false;
  static DateTime? get loadedAt => _loadedAt;
  static bool get loadedFromRemote => _loadedFromRemote;
  static RemoteConfig get current => _current;

  /// Verifies [bodyBytes] against [signatureB64] using the embedded public
  /// key. Exposed statically so it can be unit-tested without a network
  /// round-trip.
  static Future<bool> verifySignature(
      List<int> bodyBytes, String signatureB64) async {
    try {
      final algorithm = Ed25519();
      final publicKey = SimplePublicKey(base64Decode(_publicKeyB64),
          type: KeyPairType.ed25519);
      final signature =
          Signature(base64Decode(signatureB64.trim()), publicKey: publicKey);
      return await algorithm.verify(bodyBytes, signature: signature);
    } catch (_) {
      return false;
    }
  }

  /// Applies a verified config body: parses it, enforces the API-URL
  /// allowlist, and sets [_current]/[_loadedAt]/[_loadedFromRemote].
  /// Shared by the live-fetch and cache-fallback paths below so they
  /// can't drift on how a config body is turned into [_current] (in
  /// particular the allowlist check, which is a real security control —
  /// see [isAllowedApiUrl]'s own doc).
  static void _applyVerifiedConfig(String body, DateTime loadedAt) {
    final json = jsonDecode(body) as Map<String, dynamic>;
    final apiUrl = json['gemini_api_url'] as String?;
    if (apiUrl != null && !isAllowedApiUrl(apiUrl)) {
      AppLogger.error(
          'Remote config: gemini_api_url "$apiUrl" rejected (not in allowlist), using default');
      json.remove('gemini_api_url');
    }
    _current = RemoteConfig.fromJson(json);
    _loadedAt = loadedAt;
    _loadedFromRemote = true;
  }

  /// #135: falls back to the last successfully-verified config instead of
  /// silently reverting to hardcoded defaults — a user offline right after
  /// an intentional remote config change still gets it, rather than the
  /// cache being pure write-only dead weight. Re-verifies the cached
  /// signature rather than trusting SharedPreferences' contents as-is —
  /// same trust model as a live fetch, no separate carve-out for cached
  /// data. Returns true if a cached config was applied.
  static Future<bool> _tryLoadFromCache(SharedPreferences prefs) async {
    final body = prefs.getString(_cacheKey);
    final sig = prefs.getString(_cacheSigKey);
    final loadedAtIso = prefs.getString(_cacheLoadedAtKey);
    if (body == null || sig == null || loadedAtIso == null) return false;

    final verified = await verifySignature(utf8.encode(body), sig);
    if (!verified) return false;

    try {
      _applyVerifiedConfig(body, DateTime.parse(loadedAtIso));
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Load config: always try remote, fall back to the last verified
  /// cached config if the network fails, and only then to hardcoded
  /// defaults. A config (live or cached) is only ever applied if its
  /// signature verifies — otherwise this behaves exactly like a network
  /// failure, never silently falling back to an unsigned/tampered body.
  /// [client] allows injecting a mock HTTP client in tests.
  static Future<void> load({http.Client? client}) async {
    final prefs = await SharedPreferences.getInstance();
    final c = client ?? http.Client();

    // Always try remote first (fast, tiny files)
    try {
      final configResponse = await c.get(Uri.parse(_configUrl))
          .timeout(const Duration(seconds: 5));
      final sigResponse = await c.get(Uri.parse(_signatureUrl))
          .timeout(const Duration(seconds: 5));
      if (configResponse.statusCode == 200 && sigResponse.statusCode == 200) {
        final verified = await verifySignature(
            configResponse.bodyBytes, sigResponse.body);
        if (verified) {
          final now = DateTime.now();
          _applyVerifiedConfig(configResponse.body, now);
          await prefs.setString(_cacheKey, configResponse.body);
          await prefs.setString(_cacheSigKey, sigResponse.body);
          await prefs.setString(_cacheLoadedAtKey, now.toIso8601String());
          return;
        }
        AppLogger.error(
            'Remote config: signature verification failed, falling back to cache/defaults');
      }
    } catch (_) {}

    // Network failed (or signature invalid) — try the last verified
    // cached config before giving up to hardcoded defaults.
    if (await _tryLoadFromCache(prefs)) return;
  }

  /// Force refresh (e.g. from Settings)
  static Future<void> forceRefresh({http.Client? client}) => load(client: client);
}
