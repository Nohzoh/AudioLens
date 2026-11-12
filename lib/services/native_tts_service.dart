import 'dart:async';
import 'package:flutter_tts/flutter_tts.dart';
import '../utils/app_logger.dart';
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
  /// locale and gender, returning the name Android's speech engine knows
  /// it by, or null when the phone has none ready. Set by
  /// AudioGuideService; left null, the service behaves as before.
  ///
  /// These voices are ordinary voices of the same engine this service
  /// already drives — noticeably more natural than the "network" ones
  /// (judged on a Pixel 10) — so using one is just a different voice
  /// name, in any language that has one.
  Future<String?> Function(String locale, String gender)? generativeVoiceFinder;

  /// Name of the voice selected by the last voice application, or null
  /// when the engine's default was left in place.
  String? activeVoiceName;

  final Map<String, String> _generativeVoiceCache = {};

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
    // #485: a generative voice, when the phone has one for this language
    // and gender, takes precedence over everything below.
    final generative = await _generativeVoice();
    if (generative != null) {
      await _tts.setVoice(generative);
      activeVoiceName = generative['name'];
      return;
    }
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

  /// The generative voice to use for the current language and gender, as
  /// a flutter_tts voice map, or null. Only a voice the engine itself
  /// lists is returned: a name it doesn't know would make speak() fail
  /// silently (same safeguard as the French "network" voices).
  Future<Map<String, String>?> _generativeVoice() async {
    final finder = generativeVoiceFinder;
    if (finder == null) return null;
    final key = '$preferredLanguageLocale|$preferredGender';
    var name = _generativeVoiceCache[key];
    if (name == null) {
      try {
        name = await finder(preferredLanguageLocale, preferredGender);
      } catch (_) {
        name = null;
      }
      if (name == null) return null;
      // Only a hit is cached: a voice may become available later (its
      // model downloaded), and a miss must be able to turn into a hit.
      _generativeVoiceCache[key] = name;
    }
    final prefix = preferredLanguageLocale.split(RegExp('[-_]')).first;
    final voices = await voicesForLocale(prefix);
    for (final voice in voices) {
      if (voice['name'] == name) {
        if (_lastLoggedVoice != name) {
          AppLogger.tts('Native voice: generative voice $name');
          _lastLoggedVoice = name;
        }
        return {'name': name, 'locale': voice['locale'] ?? preferredLanguageLocale};
      }
    }
    if (_lastLoggedVoice != '!$name') {
      AppLogger.tts('Native voice: generative voice $name not listed by the engine, keeping the usual voice');
      _lastLoggedVoice = '!$name';
    }
    return null;
  }

  String? _lastLoggedVoice;

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
    _isPlaying = true;
    await _tts.speak(text);
  }

  Future<void> stop() async {
    await _tts.stop();
    _isPlaying = false;
  }
}
