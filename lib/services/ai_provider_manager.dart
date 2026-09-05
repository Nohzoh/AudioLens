import 'package:flutter/foundation.dart';
import 'ai_service.dart';
import 'gemini_api_service.dart';
import 'gemini_nano_service.dart';
import 'gemini_tts_service.dart';
import 'guide_preferences_store.dart';
import 'secure_key_storage.dart';

enum AIProvider { geminiNano, geminiApi }

/// Owns the app's choice of AI backend (on-device Gemini Nano vs. cloud
/// Gemini API) and the credentials/service instances that choice depends
/// on — extracted from `AudioGuideService` (#136) as the one piece of its
/// original "does everything" complaint not already behind its own
/// collaborator class (`LocationContextResolver`, `TtsOrchestrator`,
/// `GuideProgressEstimator`, `GuidePreferencesStore`, `AudioReadyNotifier`,
/// `AnalysisForegroundService` already existed at the time this was
/// extracted).
///
/// `AudioGuideService` still owns the actual analyze/synthesize/play
/// pipeline — this class only answers "which AI service should be used
/// right now, and is Nano actually available".
class AiProviderManager {
  AiProviderManager({
    required GuidePreferencesStore preferencesStore,
    GeminiNanoService? nanoService,
    GeminiApiService? geminiApiService,
    GeminiTtsService? geminiTtsService,
  })  : _preferencesStore = preferencesStore,
        nanoService = nanoService ?? GeminiNanoService(),
        _geminiApiService = geminiApiService,
        _geminiTtsService = geminiTtsService;

  final GuidePreferencesStore _preferencesStore;

  /// Public (not private to this class) — `AudioGuideService`'s
  /// cloud-to-local fallback path calls this directly regardless of
  /// [activeProvider], to retry on-device after a cloud failure without
  /// permanently switching the user's chosen provider (T132).
  final GeminiNanoService nanoService;

  AIProvider _activeProvider = AIProvider.geminiNano;
  AIProvider get activeProvider => _activeProvider;

  bool _nanoAvailable = false;
  bool get nanoAvailable => _nanoAvailable;

  String? _geminiApiKey;
  String? get geminiApiKey => _geminiApiKey;

  String _providerName = '';
  String get providerName => _providerName;

  GeminiApiService? _geminiApiService;
  GeminiApiService? get geminiApiService => _geminiApiService;

  GeminiTtsService? _geminiTtsService;
  GeminiTtsService? get geminiTtsService => _geminiTtsService;

  /// #253: the TTS engine to actually speak with, following the active
  /// *AI* provider rather than "is a Gemini TTS instance configured at
  /// all" — before this, picking Nano for analysis (specifically to keep
  /// everything on-device) still silently spoke through the cloud
  /// whenever an API key happened to be configured too, e.g. from a
  /// prior session or a since-abandoned attempt at the cloud provider.
  /// [geminiTtsService] itself stays available separately — the
  /// "Improve the voice" retry action in HistoryDetailScreen deliberately
  /// reaches for cloud TTS on demand regardless of the active provider,
  /// an explicit one-off upgrade the user asked for, not the default
  /// playback path this getter governs.
  GeminiTtsService? get geminiTtsForCurrentProvider =>
      _activeProvider == AIProvider.geminiApi ? _geminiTtsService : null;

  /// The AI service to use for the next analysis, or null if none is
  /// available right now (e.g. Nano selected but not actually available
  /// on this device, and no API key configured either).
  AIService? get currentService {
    switch (_activeProvider) {
      case AIProvider.geminiNano:
        return _nanoAvailable ? nanoService : null;
      case AIProvider.geminiApi:
        return _geminiApiService;
    }
  }

  /// Re-resolves on-device Nano availability. Extracted out of [init] so
  /// it can also be called again later (#325) — [init] only ever runs
  /// once at startup, so a device where AICore/Nano finishes downloading
  /// mid-session stayed stuck on whatever [nanoAvailable] read at launch,
  /// even though Settings' own on-demand device-status check (a purely
  /// cosmetic display string, unrelated to this field) would have shown
  /// the user it just became available. Deliberately doesn't touch
  /// [activeProvider] — becoming available shouldn't silently switch the
  /// user onto it, only unlock picking it.
  Future<void> refreshNanoAvailability() async {
    _nanoAvailable = await nanoService.isAvailable();
    if (_nanoAvailable) {
      try {
        await nanoService.initialize();
      } catch (e) {
        debugPrint('Gemini Nano init failed: $e');
        _nanoAvailable = false;
      }
    }
  }

  void _updateProviderName() {
    switch (_activeProvider) {
      case AIProvider.geminiNano:
        _providerName = 'Gemini Nano';
      case AIProvider.geminiApi:
        _providerName = 'Gemini API';
    }
  }

  /// Loads the persisted API key and active-provider choice, and resolves
  /// on-device Nano availability. Must be awaited before [currentService]
  /// reflects reality — until then, [activeProvider] defaults to
  /// [AIProvider.geminiNano] with [nanoAvailable] false.
  Future<void> init() async {
    _geminiApiKey = await SecureKeyStorage.readApiKey();
    if (_geminiApiKey?.isNotEmpty == true) {
      _geminiApiService = GeminiApiService(apiKey: _geminiApiKey!);
      _geminiTtsService = GeminiTtsService(apiKey: _geminiApiKey!);
    }
    final providerName = await _preferencesStore.loadActiveProviderName();
    if (providerName != null) {
      _activeProvider = AIProvider.values.firstWhere(
        (p) => p.name == providerName,
        orElse: () => AIProvider.geminiNano,
      );
    }

    await refreshNanoAvailability();

    // Nano was the chosen provider but isn't actually available on this
    // device — fall back to the cloud API if a key is configured, rather
    // than leaving currentService permanently null.
    if (_activeProvider == AIProvider.geminiNano && !_nanoAvailable) {
      if (_geminiApiKey?.isNotEmpty == true) {
        _activeProvider = AIProvider.geminiApi;
      }
    }

    _updateProviderName();
  }

  Future<void> setActiveProvider(AIProvider provider) async {
    _activeProvider = provider;
    _updateProviderName();
    await _preferencesStore.saveActiveProviderName(provider.name);
  }

  /// Throws [SecureStorageUnavailableException] if the key can't be
  /// persisted securely — nothing changes in-memory in that case either,
  /// so the active provider/key state always matches what's actually on
  /// disk.
  Future<void> setGeminiApiKey(String key) async {
    await SecureKeyStorage.writeApiKey(key);
    _geminiApiKey = key.isEmpty ? null : key;
    _geminiApiService = key.isNotEmpty ? GeminiApiService(apiKey: key) : null;
    _geminiTtsService = key.isNotEmpty ? GeminiTtsService(apiKey: key) : null;
    // Auto-switch to Gemini API if a key was just provided.
    if (key.isNotEmpty) {
      await setActiveProvider(AIProvider.geminiApi);
    } else if (_nanoAvailable) {
      await setActiveProvider(AIProvider.geminiNano);
    }
  }
}
