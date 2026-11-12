import 'dart:async';
import 'package:flutter_tts/flutter_tts.dart';
import '../utils/app_logger.dart';
import 'genai_tts_service.dart';
import '../utils/cancel_token.dart';

/// Wraps the device's system TTS engine — the app's sole local/offline TTS
/// engine since T89 replaced Piper (sherpa_onnx) with it, after real-device
/// A/B testing showed the native voice quality was clearly better. Same
/// public shape as the old TtsService (onComplete/onProgress/isPlaying/
/// speak/pause/stop) so TtsOrchestrator only needed a different engine
/// plugged in, not restructuring.
class NativeTtsService {
  final FlutterTts _tts = FlutterTts();
  bool _initialized = false;
  bool _isPlaying = false;
  String? _lastSpokenText;
  Completer<bool>? _pendingSpeak;

  Function()? onComplete;
  Function(double progress)? onProgress;

  bool get isPlaying => _isPlaying;

  /// 'female' or 'male' — set directly (no platform I/O) by
  /// AudioGuideService from the persisted preference; only takes effect
  /// once actually applied (lazily on first use, or immediately via
  /// [applyPreferredVoice] after the user changes it).
  String preferredGender = 'female';

  /// #130: BCP-47 locale (e.g. 'en-US'), set by AudioGuideService right
  /// before each [speak]/[speakAndWaitForResult] call from
  /// `SettingsService.outputLanguage` — unlike [preferredGender], this can
  /// legitimately differ from one narration to the next, so it's re-applied
  /// every time rather than cached at initialization.
  String preferredLanguageLocale = 'fr-FR';

  /// #485: looks up one of Google's on-device generative voices for a
  /// locale and gender — noticeably more natural than the "network" ones
  /// (judged on a Pixel 10) — returning its name, or null when the phone
  /// has none ready. Set by AudioGuideService; left null, the service
  /// behaves as before.
  Future<String?> Function(String locale, String gender)? generativeVoiceFinder;

  /// #485: plays a generative voice. Needed because Android's speech
  /// engine does not list these voices to flutter_tts (seen on a Pixel
  /// 10: « not listed by the engine »); they are only reachable through
  /// ML Kit, which drives the same engine with its own client.
  GenAiTtsService? generativeSpeaker;

  /// Name of the voice used by the last narration, or null when the
  /// engine's default was left in place.
  String? activeVoiceName;

  final Map<String, String> _generativeVoiceCache = {};

  /// Set when the generative voice failed before playing anything: the
  /// usual voice is used for the rest of the session rather than paying
  /// the failed attempt's delay before every narration.
  bool _generativeFailed = false;

  /// Text and progress of the generative narration in progress, for
  /// [resume] (ML Kit has no pause: it is a stop plus a restart).
  bool _generativeActive = false;
  int _generativePlayedMs = 0;
  bool _generativeStopRequested = false;

  /// Speaking rate of the generative voice, measured on a Pixel 10
  /// (1659 characters in 92 s) — used to turn played time into progress.
  static const _generativeCharsPerSecond = 18.0;

  static const femaleVoice = {'name': 'fr-fr-x-frc-network', 'locale': 'fr-FR'};
  static const maleVoice = {'name': 'fr-fr-x-frd-network', 'locale': 'fr-FR'};

  Future<void> _ensureInitialized() async {
    if (_initialized) return;
    // #130: language/voice setup itself lives in _applyPreferredVoiceInternal,
    // which every public entry point (speak/speakAndWaitForResult/
    // applyPreferredVoice) already calls explicitly right after this one —
    // doing it here too would just double the setLanguage call on first use.
    await _tts.setSpeechRate(0.45);
    await _tts.setPitch(1.0);
    // Some voices reported by frenchVoices() turned out to be catalog
    // entries Android hasn't actually downloaded/enabled on the device —
    // speak() used to fail silently for those (T89: confusing while
    // comparing voices). These let speak() report whether audio actually
    // played instead of just firing and forgetting.
    _tts.setCompletionHandler(() {
      _isPlaying = false;
      if (_pendingSpeak?.isCompleted == false) _pendingSpeak!.complete(true);
      onComplete?.call();
    });
    _tts.setErrorHandler((_) {
      _isPlaying = false;
      if (_pendingSpeak?.isCompleted == false) _pendingSpeak!.complete(false);
      // Still notify onComplete so the app's state doesn't stay stuck on
      // "speaking" forever — applyPreferredVoice() already avoids the
      // most common cause (a listed-but-unavailable voice) by checking
      // availability before selecting one, so this should be rare.
      onComplete?.call();
    });
    _tts.setProgressHandler((text, start, end, word) {
      if (text.isEmpty) return;
      onProgress?.call((end / text.length).clamp(0.0, 1.0));
    });
    _initialized = true;
  }

  /// #130: the hand-picked female/male "network" voice IDs are French-only
  /// (`fr-fr-x-frc/frd-network`) — there's no equivalent catalog of
  /// verified-good voice IDs per gender for arbitrary languages across
  /// arbitrary Android TTS engines, and guessing at one would be unreliable
  /// in a way that's worse than just not pretending to support it. So
  /// outside French, this only sets the language and leaves voice/gender
  /// selection to the engine's own default for that locale — narrower than
  /// the French behavior, but honest about what's actually verified to work.
  Future<void> _applyPreferredVoiceInternal() async {
    await _tts.setLanguage(preferredLanguageLocale);
    activeVoiceName = null;
    if (!preferredLanguageLocale.toLowerCase().startsWith('fr')) return;
    final target = preferredGender == 'male' ? maleVoice : femaleVoice;
    final voices = await voicesForLocale('fr');
    final isAvailable = voices
        .any((v) => v['name'] == target['name'] && v['locale'] == target['locale']);
    if (isAvailable) {
      await _tts.setVoice(target);
      activeVoiceName = target['name'];
    }
    // Else: leave the engine's own default French voice in place rather
    // than risk a silent no-op speak() call with an unavailable voice.
  }

  /// The generative voice to use for the current language and gender, or
  /// null (none on this phone, kill switch, a previous failure, or no
  /// speaker wired). Each outcome is logged once, so the in-app logs say
  /// which voice a narration used.
  Future<String?> _generativeVoiceName() async {
    final finder = generativeVoiceFinder;
    if (finder == null || generativeSpeaker == null || _generativeFailed) return null;
    final key = '$preferredLanguageLocale|$preferredGender';
    var name = _generativeVoiceCache[key];
    if (name == null) {
      try {
        name = await finder(preferredLanguageLocale, preferredGender);
      } catch (_) {
        name = null;
      }
      if (name == null) {
        _logOnce('none:$key',
            'Native voice: no generative voice for $preferredLanguageLocale ($preferredGender), usual voice');
        return null;
      }
      // Only a hit is cached: a voice may become available later (its
      // model downloaded), and a miss must be able to turn into a hit.
      _generativeVoiceCache[key] = name;
    }
    return name;
  }

  String? _lastLoggedVoice;

  void _logOnce(String key, String message) {
    if (_lastLoggedVoice == key) return;
    _lastLoggedVoice = key;
    AppLogger.tts(message);
  }

  /// Speaks [text] with the generative [voice] and resolves when playback
  /// ends: true when it reached the end. If it fails before any audio,
  /// the usual voice takes over and speaks [text] instead.
  Future<bool> _speakGenerative(String text, String voice, double speed) async {
    final speaker = generativeSpeaker!;
    _logOnce('gen:$voice', 'Native voice: generative voice $voice');
    if (speed != 1.0) {
      _logOnce('speed:$voice',
          'Native voice: speed setting not applied, the generative voice has no rate control');
    }
    activeVoiceName = voice;
    _lastSpokenText = text;
    _isPlaying = true;
    _generativeActive = true;
    _generativeStopRequested = false;
    _generativePlayedMs = 0;
    final estimatedMs = text.length / _generativeCharsPerSecond * 1000;
    final result = await speaker.speak(
      locale: preferredLanguageLocale,
      voice: voice,
      text: text,
      onPlayedMs: (ms) {
        _generativePlayedMs = ms;
        if (_isPlaying && estimatedMs > 0) {
          onProgress?.call((ms / estimatedMs).clamp(0.0, 0.99));
        }
      },
    );
    _generativeActive = false;
    _generativePlayedMs = result.playedMs;
    if (result.completed) {
      _isPlaying = false;
      onProgress?.call(1.0);
      if (_pendingSpeak?.isCompleted == false) _pendingSpeak!.complete(true);
      onComplete?.call();
      return true;
    }
    if (result.stopped || _generativeStopRequested) {
      // Same as flutter_tts after stop(): no completion callback.
      _isPlaying = false;
      return false;
    }
    if (!result.started) {
      AppLogger.tts('Native voice: generative voice failed (${result.error}), '
          'usual voice for the rest of the session');
      _generativeFailed = true;
      _isPlaying = false;
      await _applyPreferredVoiceInternal();
      await _tts.setSpeechRate(0.45 * speed);
      _isPlaying = true;
      await _tts.speak(text);
      return false;
    }
    // Failed mid-way: like flutter_tts's error handler, end the narration
    // so the app does not stay stuck on "speaking".
    AppLogger.tts('Native voice: generative voice stopped with an error (${result.error})');
    _isPlaying = false;
    if (_pendingSpeak?.isCompleted == false) _pendingSpeak!.complete(false);
    onComplete?.call();
    return false;
  }

  /// Re-applies [preferredGender]'s voice right away — call after the user
  /// changes the preference so the next speak() reflects it immediately,
  /// instead of waiting for a fresh (one-time) initialization cycle.
  Future<void> applyPreferredVoice() async {
    await _ensureInitialized();
    await _applyPreferredVoiceInternal();
  }

  /// All voices the device's TTS engine reports whose locale starts with
  /// [localePrefix] (e.g. 'fr', 'en') — flutter_tts only surfaces
  /// name/locale, not Android's quality/network-required metadata, see
  /// [_applyPreferredVoiceInternal] for how this is used to avoid selecting
  /// an unavailable one. #130: generalized from the original French-only
  /// `frenchVoices()`.
  Future<List<Map<String, String>>> voicesForLocale(String localePrefix) async {
    final voices = await _tts.getVoices;
    if (voices is! List) return [];
    return voices
        .whereType<Map>()
        .map((v) => v.map((k, val) => MapEntry(k.toString(), val.toString())))
        .where((v) => (v['locale'] ?? '').toLowerCase().startsWith(localePrefix.toLowerCase()))
        .toList();
  }

  /// Fire-and-forget, matching TtsService/GeminiTtsService's convention:
  /// kicks off synthesis+playback and returns once it's been queued, not
  /// once it's finished — actual completion is signaled via [onComplete].
  /// [speed] is a multiplier on the app's tuned baseline rate (T15), e.g.
  /// 1.0 = normal, 1.5 = 50% faster. Re-applied on every call rather than
  /// cached, so a mid-session Settings change takes effect immediately
  /// without needing a separate "re-apply" step (unlike [preferredGender],
  /// which needs the pricier voice-availability check in
  /// [_applyPreferredVoiceInternal]).
  Future<void> speak(String text, {CancelToken? cancelToken, double speed = 1.0}) async {
    if (cancelToken?.isCancelled ?? false) return;
    await _ensureInitialized();
    // #485: the generative voice when the phone has one. Not awaited:
    // speak() stays fire-and-forget, completion comes via onComplete.
    final generative = await _generativeVoiceName();
    if (generative != null) {
      unawaited(_speakGenerative(text, generative, speed));
      return;
    }
    // #130: re-applied every call, same reasoning as setSpeechRate above —
    // preferredLanguageLocale can differ from one narration to the next.
    await _applyPreferredVoiceInternal();
    await _tts.setSpeechRate(0.45 * speed);
    _lastSpokenText = text;
    _isPlaying = true;
    await _tts.speak(text);
  }

  /// Speaks [text] and waits for the actual result — used by the Settings
  /// voice-preview button, which wants immediate feedback on whether the
  /// selected voice produced audio, unlike [speak]'s fire-and-forget
  /// production behavior.
  Future<bool> speakAndWaitForResult(String text, {double speed = 1.0}) async {
    await _ensureInitialized();
    final generative = await _generativeVoiceName();
    if (generative != null) {
      return _speakGenerative(text, generative, speed)
          .timeout(const Duration(seconds: 30), onTimeout: () => false);
    }
    await _applyPreferredVoiceInternal();
    await _tts.setSpeechRate(0.45 * speed);
    if (_pendingSpeak?.isCompleted == false) _pendingSpeak!.complete(false);
    final completer = Completer<bool>();
    _pendingSpeak = completer;
    await _tts.speak(text);
    return completer.future.timeout(
      const Duration(seconds: 15),
      onTimeout: () => false,
    );
  }

  Future<void> pause() async {
    if (_generativeActive) {
      // ML Kit has no pause: stop, and let resume() restart from about
      // where playback got to.
      _generativeStopRequested = true;
      await generativeSpeaker?.stopSpeaking();
      _isPlaying = false;
      return;
    }
    await _tts.pause();
    _isPlaying = false;
  }

  /// Android's TextToSpeech has no true pause/resume — flutter_tts fakes
  /// it by remembering how much of the text was already spoken (via the
  /// progress handler) and expects the *same* text to be passed to speak()
  /// again to continue from there, which this wraps.
  Future<void> resume() async {
    final text = _lastSpokenText;
    if (text == null) return;
    final voice = activeVoiceName;
    if (voice != null && _generativeVoiceCache.containsValue(voice)) {
      // #485: restart at the beginning of the sentence playback had reached.
      final rest = generativeResumeText(text, _generativePlayedMs);
      unawaited(_speakGenerative(rest, voice, 1.0).then((_) => _lastSpokenText = text));
      return;
    }
    _isPlaying = true;
    await _tts.speak(text);
  }

  Future<void> stop() async {
    if (_generativeActive) {
      _generativeStopRequested = true;
      await generativeSpeaker?.stopSpeaking();
    }
    await _tts.stop();
    _isPlaying = false;
  }
}

/// #485: the part of [text] left to say after [playedMs] of generative
/// speech, starting at the beginning of the sentence playback had reached
/// (estimated from the measured speaking rate), so a resumed narration
/// repeats a few words rather than cutting into one.
String generativeResumeText(String text, int playedMs) {
  final reached = (playedMs / 1000 * NativeTtsService._generativeCharsPerSecond).floor();
  if (reached <= 0) return text;
  if (reached >= text.length) return text;
  final before = text.substring(0, reached);
  final boundary = before.lastIndexOf(RegExp(r'[.!?…]\s'));
  final start = boundary == -1 ? 0 : boundary + 2;
  return text.substring(start).trimLeft();
}
