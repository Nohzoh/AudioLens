import 'dart:io';
import '../utils/app_logger.dart';
import '../utils/cancel_token.dart';
import '../utils/error_sanitizer.dart';
import '../models/guide_error.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart';
import 'ai_service.dart';
import 'gemini_nano_service.dart';
import 'gemini_api_service.dart';
import 'tts_service.dart';
import 'gemini_tts_service.dart';
import 'location_service.dart';
import 'remote_config_service.dart';
import 'secure_key_storage.dart';
import 'guide_preferences_store.dart';
import 'guide_progress_estimator.dart';
import 'location_context_resolver.dart';
import 'tts_orchestrator.dart';

enum GuideState { idle, locating, analyzing, synthesizing, speaking, paused, cancelling, error }
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
    TtsService? ttsService,
    GeminiTtsService? geminiTtsService,
    GeminiApiService? geminiApiService,
    GeminiNanoService? nanoService,
    GuidePreferencesStore? preferencesStore,
    LocationContextResolver? locationResolver,
  })  : _ttsService = ttsService ?? TtsService(),
        _nanoService = nanoService ?? GeminiNanoService(),
        _geminiTtsService = geminiTtsService,
        _geminiApiService = geminiApiService,
        _preferencesStore = preferencesStore ?? GuidePreferencesStore(),
        _locationResolver = locationResolver ?? LocationContextResolver() {
    _ttsOrchestrator = TtsOrchestrator(piper: _ttsService);
  }

  final TtsService _ttsService;
  TtsService get ttsService => _ttsService;
  final GuidePreferencesStore _preferencesStore;
  final LocationContextResolver _locationResolver;
  late final TtsOrchestrator _ttsOrchestrator;
  GuideProgressEstimator _progressEstimator = GuideProgressEstimator();
  GeminiTtsService? _geminiTtsService;
  GeminiTtsService? get geminiTtsService => _geminiTtsService;
  String? _lastAudioPath;
  String? get lastAudioPath => _lastAudioPath;
  String _lastTtsModel = "piper";
  String get lastTtsModel => _lastTtsModel;
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
  bool get ttsWasFallback => _lastTtsModel == 'piper' && _geminiTtsService != null;
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

    _ttsService.onComplete = () {
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

  Future<void> setGeminiApiKey(String key) async {
    _geminiApiKey = key.isEmpty ? null : key;
    _geminiApiService = key.isNotEmpty ? GeminiApiService(apiKey: key) : null;
    _geminiTtsService = key.isNotEmpty ? GeminiTtsService(apiKey: key) : null;
    await SecureKeyStorage.writeApiKey(key);
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
  }

  Future<AudioGuideResult?> analyzeAndPlay(File imageFile) async {
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
      final locationContext = await _locationResolver.resolve(imageFile);
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
        );
      } catch (analysisError) {
        final message = sanitizeError(analysisError.toString());
        if (_activeProvider == AIProvider.geminiApi && _nanoAvailable) {
          AppLogger.error('Cloud analysis failed, trying local fallback: $message');
          _activeProvider = AIProvider.geminiNano;
          _updateProviderName();
          final localService = _currentService;
          if (localService != null) {
            _lastResult = await localService.analyzeImage(
              imageFile,
              locationContext: locationContext.promptContext,
            );
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

      _state = GuideState.synthesizing;
      _currentStep = 2;
      _progressEstimator.stepProgress = -1.0;
      notifyListeners();

      _lastTtsModel = await _ttsOrchestrator.speak(
        _lastResult!.script,
        cancelToken: _cancelToken,
        geminiTts: _geminiTtsService,
      );

      // Cache the generated audio for replay without re-generating
      _lastAudioPath = await _getLastWavPath();

      await _preferencesStore.saveTimings(
        _progressEstimator.gpsDurations,
        _progressEstimator.analyzeDurations,
      );

      _state = GuideState.speaking;
      _progressEstimator.stepProgress = 1.0;
      notifyListeners();

      return _lastResult;
    } catch (e) {
      _progressEstimator.stop();
      _state = GuideState.error;
      _errorMessage = sanitizeError(e.toString());
      notifyListeners();
      return null;
    } finally {
      _analysisInProgress = false;
    }
  }

  Future<void> togglePause() async {
    if (_state == GuideState.speaking) {
      if (_geminiTtsService != null) {
        await _geminiTtsService!.pause();
      } else {
        await _ttsService.pause();
      }
      _state = GuideState.paused;
    } else if (_state == GuideState.paused) {
      const channel = MethodChannel('audio_guide/audio_player');
      await channel.invokeMethod('play');
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
    
    // Try to stop TTS with a timeout to prevent hanging
    try {
      await _ttsService.stop().timeout(const Duration(seconds: 5));
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

  Future<String?> _getLastWavPath() async {
    try {
      final tmpDir = await getTemporaryDirectory();
      final geminiWav = File('${tmpDir.path}/gemini_tts_output.wav');
      if (await geminiWav.exists()) return geminiWav.path;
      final piperWav = File('${tmpDir.path}/tts_output.wav');
      if (await piperWav.exists()) return piperWav.path;
    } catch (_) {}
    return null;
  }

  @override
  void dispose() {
    _progressEstimator.stop();
    _analysisInProgress = false;
    _ttsService.dispose();
    super.dispose();
  }
}
