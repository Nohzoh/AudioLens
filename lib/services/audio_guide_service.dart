import 'dart:io';
import '../utils/app_logger.dart';
import '../utils/cancel_token.dart';
import '../utils/error_sanitizer.dart';
import '../models/guide_error.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/widgets.dart';
import 'ai_service.dart';
import 'analysis_foreground_service.dart';
import 'audio_ready_notifier.dart';
import 'gemini_nano_service.dart';
import 'gemini_api_service.dart';
import 'native_tts_service.dart';
import 'gemini_tts_service.dart';
import 'location_service.dart';
import 'remote_config_service.dart';
import 'secure_key_storage.dart';
import 'guide_preferences_store.dart';
import 'guide_progress_estimator.dart';
import 'location_context_resolver.dart';
import 'tts_orchestrator.dart';

enum GuideState { idle, locating, analyzing, synthesizing, speaking, paused, cancelling, error, scriptReady }
enum AIProvider { geminiNano, geminiApi }

class PipelineProgress {
  final GuideState state;
  final double stepProgress;
  final int currentStep;
  final double? estimatedSecondsRemaining;

  const PipelineProgress({
    required this.state,
    this.stepProgress = 0.0,
    this.currentStep = 0,
    this.estimatedSecondsRemaining,
  });
}

class AudioGuideService extends ChangeNotifier {
  AudioGuideService({
    NativeTtsService? nativeTtsService,
    GeminiTtsService? geminiTtsService,
    GeminiApiService? geminiApiService,
    GeminiNanoService? nanoService,
    GuidePreferencesStore? preferencesStore,
    LocationContextResolver? locationResolver,
    AnalysisForegroundService? foregroundService,
    AudioReadyNotifier? audioReadyNotifier,
  })  : _nativeTtsService = nativeTtsService ?? NativeTtsService(),
        _nanoService = nanoService ?? GeminiNanoService(),
        _geminiTtsService = geminiTtsService,
        _geminiApiService = geminiApiService,
        _preferencesStore = preferencesStore ?? GuidePreferencesStore(),
        _locationResolver = locationResolver ?? LocationContextResolver(),
        _foregroundService = foregroundService ?? AnalysisForegroundService(),
        _audioReadyNotifier = audioReadyNotifier ?? AudioReadyNotifier() {
    _ttsOrchestrator = TtsOrchestrator(nativeTts: _nativeTtsService);
  }

  final AnalysisForegroundService _foregroundService;
  final AudioReadyNotifier _audioReadyNotifier;

  final NativeTtsService _nativeTtsService;
  NativeTtsService get nativeTtsService => _nativeTtsService;
  final GuidePreferencesStore _preferencesStore;
  final LocationContextResolver _locationResolver;
  late final TtsOrchestrator _ttsOrchestrator;
  GuideProgressEstimator _progressEstimator = GuideProgressEstimator();
  GeminiTtsService? _geminiTtsService;
  GeminiTtsService? get geminiTtsService => _geminiTtsService;
  String? _lastAudioPath;
  String? get lastAudioPath => _lastAudioPath;
  String _lastTtsModel = "native-tts";
  String get lastTtsModel => _lastTtsModel;
  String _ttsVoiceGender = 'female';
  String get ttsVoiceGender => _ttsVoiceGender;
  double _playbackSpeed = 1.0;
  double get playbackSpeed => _playbackSpeed;
  String? _lastAiModel;
  String? get lastAiModel => _lastAiModel;
  String? _lastGpsSource;
  String? get lastGpsSource => _lastGpsSource;
  bool _lastWikipediaUsed = false;
  bool get lastWikipediaUsed => _lastWikipediaUsed;
  int? _lastAnalysisDurationMs;
  int? get lastAnalysisDurationMs => _lastAnalysisDurationMs;
  double? _lastGpsLatitude;
  double? get lastGpsLatitude => _lastGpsLatitude;
  double? _lastGpsLongitude;
  double? get lastGpsLongitude => _lastGpsLongitude;
  String? _lastGpsAddress;
  String? get lastGpsAddress => _lastGpsAddress;
  // Fallback info
  bool get aiModelWasFallback {
    final svc = _currentService;
    if (svc is GeminiApiService) {
      final used = svc.lastUsedModel;
      final cfg = RemoteConfigService.current;
      return used != null && used != cfg.geminiModel;
    }
    return false;
  }
  String? get actualAiModel {
    final svc = _currentService;
    if (svc is GeminiApiService) return svc.lastUsedModel;
    return _lastAiModel;
  }
  bool get ttsWasFallback => _lastTtsModel == 'native-tts' && _geminiTtsService != null;
  bool get ttsFallbackWasRateLimit => _ttsOrchestrator.wasRateLimited;
  final GeminiNanoService _nanoService;

  GuideState _state = GuideState.idle;
  AudioGuideResult? _lastResult;
  String? _errorMessage;
  String _providerName = '';
  File? _lastImageFile;
  LocationPermissionStatus _lastLocationStatus = LocationPermissionStatus.granted;
  
  // Cancellation support
  final CancelToken _cancelToken = CancelToken();
  CancelToken get cancelToken => _cancelToken;

  // Provider management
  AIProvider _activeProvider = AIProvider.geminiNano;
  bool _nanoAvailable = false;
  String? _geminiApiKey;

  AIProvider get activeProvider => _activeProvider;
  bool get nanoAvailable => _nanoAvailable;
  String? get geminiApiKey => _geminiApiKey;
  GeminiApiService? _geminiApiService; // cached instance

  int _currentStep = 0;
  bool _analysisInProgress = false;

  GuideState get state => _state;
  AudioGuideResult? get lastResult => _lastResult;
  String? get errorMessage => _errorMessage;
  String get providerName => _providerName;
  File? get lastImageFile => _lastImageFile;
  bool get isReady => true;
  LocationPermissionStatus get lastLocationStatus => _lastLocationStatus;

  PipelineProgress get progress => PipelineProgress(
    state: _state,
    stepProgress: _progressEstimator.stepProgress,
    currentStep: _currentStep,
    estimatedSecondsRemaining: _estimateRemaining(),
  );

  double? _estimateRemaining() {
    if (_state == GuideState.locating) return _progressEstimator.estimateWhileLocating;
    if (_state == GuideState.analyzing) return _progressEstimator.estimateWhileAnalyzing;
    return null;
  }

  Future<void> init() async {
    await _loadPreferences();

    _nanoAvailable = await _nanoService.isAvailable();
    if (_nanoAvailable) {
      try {
        await _nanoService.initialize();
      } catch (e) {
        debugPrint('Gemini Nano init failed: $e');
        _nanoAvailable = false;
      }
    }

    // Determine active provider
    if (_activeProvider == AIProvider.geminiNano && !_nanoAvailable) {
      if (_geminiApiKey?.isNotEmpty == true) {
        _activeProvider = AIProvider.geminiApi;
      }
    }

    _updateProviderName();

    _nativeTtsService.onComplete = () {
      _state = GuideState.idle;
      _progressEstimator.stepProgress = 0.0;
      notifyListeners();
    };

    notifyListeners();
  }

  void _updateProviderName() {
    switch (_activeProvider) {
      case AIProvider.geminiNano:
        _providerName = 'Gemini Nano';
      case AIProvider.geminiApi:
        _providerName = 'Gemini API';
    }
  }

  AIService? get _currentService {
    switch (_activeProvider) {
      case AIProvider.geminiNano:
        return _nanoAvailable ? _nanoService : null;
      case AIProvider.geminiApi:
        return _geminiApiService;
    }
  }

  Future<void> setActiveProvider(AIProvider provider) async {
    _activeProvider = provider;
    _updateProviderName();
    await _preferencesStore.saveActiveProviderName(provider.name);
    notifyListeners();
  }

  /// Throws [SecureStorageUnavailableException] if the key can't be
  /// persisted securely — nothing is changed in-memory in that case
  /// either, so the app's active provider/key state always matches what's
  /// actually on disk.
  Future<void> setGeminiApiKey(String key) async {
    await SecureKeyStorage.writeApiKey(key);
    _geminiApiKey = key.isEmpty ? null : key;
    _geminiApiService = key.isNotEmpty ? GeminiApiService(apiKey: key) : null;
    _geminiTtsService = key.isNotEmpty ? GeminiTtsService(apiKey: key) : null;
    // Auto-switch to Gemini API if key provided
    if (key.isNotEmpty) {
      await setActiveProvider(AIProvider.geminiApi);
    } else if (_nanoAvailable) {
      await setActiveProvider(AIProvider.geminiNano);
    }
    notifyListeners();
  }

  Future<void> _loadPreferences() async {
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
    final timings = await _preferencesStore.loadTimings();
    _progressEstimator = GuideProgressEstimator(
      gpsDurations: timings.gpsDurations,
      analyzeDurations: timings.analyzeDurations,
    );
    // Plain field assignment (no platform I/O) — the voice itself is
    // applied lazily on first real use of the native engine, matching
    // its existing lazy-initialization pattern.
    _ttsVoiceGender = await _preferencesStore.loadTtsVoiceGender();
    _nativeTtsService.preferredGender = _ttsVoiceGender;
    _playbackSpeed = await _preferencesStore.loadPlaybackSpeed();
  }

  /// Changes the preferred native TTS voice's gender ('female' or 'male',
  /// T89) and re-applies it immediately so a subsequent preview/speak
  /// reflects the change without waiting for a fresh app start.
  Future<void> setTtsVoiceGender(String gender) async {
    _ttsVoiceGender = gender;
    _nativeTtsService.preferredGender = gender;
    await _preferencesStore.saveTtsVoiceGender(gender);
    await _nativeTtsService.applyPreferredVoice();
    notifyListeners();
  }

  /// Changes the narration playback speed multiplier (T15, 1.0 = normal).
  /// Applies to both TTS engines; no live re-apply needed since it's
  /// threaded through as a parameter at the next play, not cached engine
  /// state (see [NativeTtsService.speak]/[GeminiTtsService.speak]).
  Future<void> setPlaybackSpeed(double speed) async {
    _playbackSpeed = speed;
    await _preferencesStore.savePlaybackSpeed(speed);
    notifyListeners();
  }

  /// Analyzes [imageFile] and, unless [generateAudio] is false (T16),
  /// synthesizes and plays the resulting script. When [generateAudio] is
  /// false, the pipeline stops after analysis with state
  /// [GuideState.scriptReady] — audio can be generated later via
  /// [generateAudioForScript].
  ///
  /// [knownCoordinates] resolves location from already-known coordinates
  /// (T78 — a deferred capture's saved GPS fix) instead of re-reading GPS
  /// from [imageFile]; use this to launch the analysis for a captured
  /// entry using the location it was captured at, not the device's
  /// current location.
  Future<AudioGuideResult?> analyzeAndPlay(
    File imageFile, {
    bool generateAudio = true,
    ({double lat, double lon, String source})? knownCoordinates,
    String? style,
    int? entryId,
  }) async {
    if (_analysisInProgress || _state == GuideState.cancelling) {
      _errorMessage = 'Une analyse est déjà en cours.';
      _state = GuideState.error;
      notifyListeners();
      return null;
    }

    final service = _currentService;
    if (service == null) {
      _state = GuideState.error;
      _errorMessage = 'Aucun service IA disponible. Configurez une clé API dans les paramètres.';
      notifyListeners();
      return null;
    }

    _analysisInProgress = true;
    _cancelToken.reset(); // Reset cancellation for new analysis
    await _foregroundService.start();
    await _audioReadyNotifier.requestPermissionIfNeeded();

    try {
      _lastResult = null;
      _state = GuideState.locating;
      _currentStep = 0;
      _progressEstimator.stepProgress = 0.0;
      _lastImageFile = imageFile;
      _errorMessage = null;
      notifyListeners();

      // Check for cancellation before starting
      if (_cancelToken.isCancelled) {
        _state = GuideState.idle;
        _analysisInProgress = false;
        notifyListeners();
        return null;
      }

      final gpsStart = DateTime.now();
      final locationContext = knownCoordinates != null
          ? await _locationResolver.resolveFromCoordinates(
              lat: knownCoordinates.lat,
              lon: knownCoordinates.lon,
              source: knownCoordinates.source,
            )
          : await _locationResolver.resolve(imageFile);
      _lastGpsSource = locationContext.source;
      _lastGpsLatitude = locationContext.latitude;
      _lastGpsLongitude = locationContext.longitude;
      _lastGpsAddress = locationContext.address;
      _lastLocationStatus = locationContext.status;
      _lastWikipediaUsed = locationContext.wikipediaUsed;
      _progressEstimator.recordGpsDuration(
          DateTime.now().difference(gpsStart).inMilliseconds / 1000.0);

      // Check cancellation before AI analysis
      if (_cancelToken.isCancelled) {
        _state = GuideState.idle;
        _analysisInProgress = false;
        notifyListeners();
        return null;
      }

      _state = GuideState.analyzing;
      _currentStep = 1;
      _progressEstimator.stepProgress = 0.0;
      notifyListeners();

      _progressEstimator.simulate(
        expectedDuration: _progressEstimator.averageAnalyzeDuration,
        onTick: notifyListeners,
      );

      _lastAiModel = _providerName; // will be refined after analysis
      final analyzeStart = DateTime.now();
      try {
        _lastResult = await service.analyzeImage(
          imageFile,
          locationContext: locationContext.promptContext,
          cancelToken: _cancelToken,
          style: style,
        );
      } catch (analysisError) {
        // A cancellation must abort outright, not trigger the local-model
        // fallback below (T70) — the user asked to stop, not to keep
        // burning time on a slower on-device retry.
        if (analysisError is CancelledException) rethrow;
        // Gemini Nano inference is an OS-enforced foreground-only
        // operation (unlike the cloud API) — if the app was backgrounded
        // mid-analysis, the native call fails outright and there's no
        // retry that fixes it here. No auto-fallback to the cloud API
        // either: the user chose on-device processing, often for privacy
        // (see PRIVACY.md), so silently sending their photo to Gemini API
        // instead would be a real overstep — just report it clearly.
        if (analysisError is GeminiNanoBackgroundRestrictedException) {
          throw const GuideError(
            GuideErrorKind.ai,
            'L\'analyse hors-ligne (Gemini Nano) nécessite que l\'application '
            'reste au premier plan. Réessayez en gardant AudioLens ouvert, ou '
            'configurez une clé Gemini API dans les réglages pour permettre '
            'l\'analyse en arrière-plan.',
          );
        }
        final message = sanitizeError(analysisError.toString());
        if (_activeProvider == AIProvider.geminiApi && _nanoAvailable) {
          AppLogger.error('Cloud analysis failed, trying local fallback: $message');
          _activeProvider = AIProvider.geminiNano;
          _updateProviderName();
          final localService = _currentService;
          if (localService != null) {
            try {
              _lastResult = await localService.analyzeImage(
                imageFile,
                locationContext: locationContext.promptContext,
                style: style,
              );
            } on GeminiNanoBackgroundRestrictedException {
              throw const GuideError(
                GuideErrorKind.ai,
                'L\'analyse a échoué et le repli hors-ligne (Gemini Nano) '
                'nécessite que l\'application reste au premier plan. '
                'Réessayez en gardant AudioLens ouvert.',
              );
            }
          } else {
            throw GuideError(GuideErrorKind.ai, 'Analyse IA impossible. $message');
          }
        } else {
          throw GuideError(GuideErrorKind.ai, 'Analyse IA impossible. $message');
        }
      }
      final analysisDuration = DateTime.now().difference(analyzeStart).inMilliseconds;
      _lastAnalysisDurationMs = analysisDuration;
      _progressEstimator.recordAnalyzeDuration(analysisDuration / 1000.0);
      _progressEstimator.stop();

      if (locationContext.city != null && _lastResult != null) {
        _lastResult = AudioGuideResult(
          title: _lastResult!.title,
          script: _lastResult!.script,
          locationName: locationContext.city,
        );
      }

      // Check cancellation before TTS synthesis
      if (_cancelToken.isCancelled) {
        _state = GuideState.idle;
        _analysisInProgress = false;
        notifyListeners();
        return null;
      }

      // Skip auto-play if the app was backgrounded while analysis ran — the
      // user may be doing something else by the time it finishes, so
      // starting audio unprompted would be disruptive. The script is kept
      // ready instead, and the "ready" notification below carries the
      // entry ID so tapping it starts playback deliberately. `null`
      // lifecycleState (never set — the case in every test that doesn't
      // simulate backgrounding) is treated as foreground, not backgrounded.
      final lifecycle = WidgetsBinding.instance.lifecycleState;
      final isBackgrounded = lifecycle != null && lifecycle != AppLifecycleState.resumed;
      var deferredForBackground = false;

      if (generateAudio && isBackgrounded) {
        deferredForBackground = true;
        await _synthesizeOnlyForBackground(_lastResult!.script);
      } else if (generateAudio) {
        await _synthesizeAndPlay(_lastResult!.script);
      } else {
        _lastAudioPath = null;
        _state = GuideState.scriptReady;
        _progressEstimator.stepProgress = 1.0;
        notifyListeners();
      }

      await _preferencesStore.saveTimings(
        _progressEstimator.gpsDurations,
        _progressEstimator.analyzeDurations,
      );

      await _audioReadyNotifier.notifyReady(
        payload: deferredForBackground ? entryId?.toString() : null,
      );
      return _lastResult;
    } catch (e) {
      _progressEstimator.stop();
      // A real cancellation (T70) lands here too now that cloud calls can
      // actually be aborted mid-flight — treat it like the cooperative
      // isCancelled checks above (back to idle), not a failure. The user
      // asked to stop, so unlike a genuine error (below), this isn't worth
      // a "failed" notification (T85).
      if (e is CancelledException) {
        _state = GuideState.idle;
        _analysisInProgress = false;
        notifyListeners();
        return null;
      }
      _state = GuideState.error;
      _errorMessage = sanitizeError(e.toString());
      notifyListeners();
      await _audioReadyNotifier.notifyFailed();
      return null;
    } finally {
      _analysisInProgress = false;
      await _foregroundService.stop();
    }
  }

  /// Synthesizes [script] (cloud TTS with native TTS fallback) and plays
  /// it, driving the synthesizing -> speaking state transition.
  Future<void> _synthesizeAndPlay(String script) async {
    _state = GuideState.synthesizing;
    _currentStep = 2;
    _progressEstimator.stepProgress = -1.0;
    notifyListeners();

    // T76's speakChunked() is parked for now (2026-08-16): splitting a
    // script into several Gemini TTS calls reliably hits rate limiting on
    // real accounts, and the fallback-to-native-mid-script it causes is a
    // worse experience than the plain wait speak() gives every user. Back
    // to one call for the whole script until chunking is revisited.
    // speakChunked() and its tests are untouched, ready to swap back in.
    _lastTtsModel = await _ttsOrchestrator.speak(
      script,
      cancelToken: _cancelToken,
      geminiTts: _geminiTtsService,
      speed: _playbackSpeed,
    );

    // Cache the generated audio for replay without re-generating
    _lastAudioPath = await _getLastWavPath();

    _state = GuideState.speaking;
    _progressEstimator.stepProgress = 1.0;
    notifyListeners();
  }

  /// Synthesizes [script] via Gemini TTS without playing it — used instead
  /// of [_synthesizeAndPlay] when the app is backgrounded at completion
  /// time, so the notification's tap can start playback instantly from the
  /// cached file rather than re-synthesizing from scratch. Only Gemini TTS
  /// is worth pre-generating this way: the native engine synthesizes and
  /// speaks in one live step with no separate "render to file" mode, and
  /// its replay is instant/free anyway (see [_getLastWavPath]'s doc), so
  /// there's nothing to pre-generate for it — the script is simply left
  /// ready, and native TTS will speak it live whenever the user does ask.
  /// Best-effort: a synthesis failure (rate limit, network) just leaves the
  /// script audio-less, same as if Gemini TTS wasn't configured at all.
  Future<void> _synthesizeOnlyForBackground(String script) async {
    _state = GuideState.synthesizing;
    _progressEstimator.stepProgress = -1.0;
    notifyListeners();

    if (_geminiTtsService != null) {
      try {
        final path = await _getGeminiWavPath();
        await _geminiTtsService!.synthesizeToFile(script, path, cancelToken: _cancelToken);
        _lastAudioPath = path;
        _lastTtsModel = 'gemini-tts';
      } catch (e) {
        if (e is CancelledException) rethrow;
        AppLogger.error('Background pre-synthesis failed, deferring to on-demand: '
            '${sanitizeError(e.toString())}');
        _lastAudioPath = null;
      }
    } else {
      _lastAudioPath = null;
    }

    _state = GuideState.scriptReady;
    _progressEstimator.stepProgress = 1.0;
    notifyListeners();
  }

  /// Generates and plays audio for an already-analyzed script (T16) —
  /// e.g. an entry created with [analyzeAndPlay]'s `generateAudio: false`,
  /// or any other script-only history entry. Skips GPS/Wikipedia/AI
  /// entirely; only runs the TTS step.
  Future<AudioGuideResult?> generateAudioForScript({
    required String title,
    required String script,
    String? locationName,
  }) async {
    if (_analysisInProgress || _state == GuideState.cancelling) {
      _errorMessage = 'Une opération est déjà en cours.';
      _state = GuideState.error;
      notifyListeners();
      return null;
    }

    _analysisInProgress = true;
    _cancelToken.reset();
    await _foregroundService.start();
    await _audioReadyNotifier.requestPermissionIfNeeded();

    try {
      _lastResult = AudioGuideResult(title: title, script: script, locationName: locationName);
      _errorMessage = null;
      notifyListeners();

      await _synthesizeAndPlay(script);

      await _audioReadyNotifier.notifyReady();
      return _lastResult;
    } catch (e) {
      if (e is CancelledException) {
        _state = GuideState.idle;
        notifyListeners();
        return null;
      }
      _state = GuideState.error;
      _errorMessage = sanitizeError(e.toString());
      notifyListeners();
      await _audioReadyNotifier.notifyFailed();
      return null;
    } finally {
      _analysisInProgress = false;
      await _foregroundService.stop();
    }
  }

  Future<void> togglePause() async {
    // Which engine is actually playing must be checked via lastTtsModel,
    // not just "is Gemini TTS configured" (_geminiTtsService != null) — a
    // configured Gemini TTS can still have fallen back to the native
    // engine for this particular playback (rate limit, network error).
    final geminiIsPlaying = _lastTtsModel == 'gemini-tts' && _geminiTtsService != null;
    if (_state == GuideState.speaking) {
      if (geminiIsPlaying) {
        await _geminiTtsService!.pause();
      } else {
        await _nativeTtsService.pause();
      }
      _state = GuideState.paused;
    } else if (_state == GuideState.paused) {
      if (geminiIsPlaying) {
        const channel = MethodChannel('audio_guide/audio_player');
        await channel.invokeMethod('play');
      } else {
        await _nativeTtsService.resume();
      }
      _state = GuideState.speaking;
    }
    notifyListeners();
  }

  Future<void> cancelCurrentAction() async {
    _progressEstimator.stop();
    _errorMessage = null;
    _analysisInProgress = false;
    
    // Cancel all ongoing operations
    _cancelToken.cancel();
    
    _state = GuideState.cancelling;
    notifyListeners();
    
    // Try to stop TTS with a timeout to prevent hanging. Native TTS
    // manages its own playback internally (not the shared
    // audio_guide/audio_player channel Gemini TTS's WAV playback uses),
    // so both need stopping regardless of which one actually played.
    try {
      await Future.wait([
        _nativeTtsService.stop(),
        if (_geminiTtsService != null) _geminiTtsService!.stop(),
      ]).timeout(const Duration(seconds: 5));
    } catch (_) {
      // Timeout reached, TTS is still running in background but we can proceed
    }
    
    // Reset the token for next operation
    _cancelToken.reset();
    
    _state = GuideState.idle;
    notifyListeners();
  }

  Future<void> stop() async {
    await cancelCurrentAction();
  }

  /// Returns the last Gemini-TTS-generated WAV file for caching, if any.
  /// The native engine (T89) plays directly via the device's own TTS
  /// pipeline and doesn't produce a file to cache — its entries are just
  /// re-synthesized on replay, which is fine since it's instant and free,
  /// unlike Gemini TTS's quota-limited cloud calls.
  Future<String?> _getLastWavPath() async {
    try {
      final geminiWav = File(await _getGeminiWavPath());
      if (await geminiWav.exists()) return geminiWav.path;
    } catch (_) {}
    return null;
  }

  /// The conventional path Gemini TTS synthesis writes to, shared by
  /// [_synthesizeAndPlay] (via [GeminiTtsService.speak]/[_getLastWavPath])
  /// and [_synthesizeOnlyForBackground] (via
  /// [GeminiTtsService.synthesizeToFile]) so both land on the same file.
  Future<String> _getGeminiWavPath() async {
    final tmpDir = await getTemporaryDirectory();
    return '${tmpDir.path}/gemini_tts_output.wav';
  }

  @override
  void dispose() {
    _progressEstimator.stop();
    _analysisInProgress = false;
    super.dispose();
  }
}
