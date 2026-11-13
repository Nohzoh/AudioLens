import 'dart:async';
import 'dart:io';
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

  /// #517: receives the WAV recording of a generative narration that
  /// played to the end, with the text it says — so the history can keep
  /// it like a Gemini TTS file (replay without waiting, ±10 s seek,
  /// offline). The temporary file is deleted once this returns.
  Future<void> Function(String text, String wavPath)? onGenerativeRecording;

  /// Folder for the temporary recordings; injectable for tests.
  Future<String> Function() recordingDirectory =
      () async => Directory.systemTemp.path;

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

  /// #545: speaking rate of the generative voice, calibrated after each
  /// complete narration (it varies with the voice and the text).
  double _charsPerSecond = _generativeCharsPerSecond;

  /// #545: the whole narration, and where the segment being spoken starts
  /// in it — after a resume, ML Kit speaks only the rest.
  String? _generativeFullText;
  int _generativeBase = 0;

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
      // #546: after a jump, [text] is the rest of the narration.
      final full = _nativeFullLength;
      if (full != null && full > 0) {
        onProgress?.call(((_nativeBase + end) / full).clamp(0.0, 1.0));
        return;
      }
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

  /// #522: forgets the generative voice found so far (and a previous
  /// failure), so the next narration looks again — after the user picks
  /// another voice, or turns the generative voice back on.
  void resetGenerativeVoice() {
    _generativeVoiceCache.clear();
    _generativeFailed = false;
    _lastLoggedVoice = null;
  }

  Future<void> _handOverRecording(String text, String path) async {
    try {
      await onGenerativeRecording?.call(text, path);
    } catch (_) {
      // The narration was heard; only keeping it failed.
    } finally {
      try {
        await File(path).delete();
      } catch (_) {
        // Already gone.
      }
    }
  }

  void _logOnce(String key, String message) {
    if (_lastLoggedVoice == key) return;
    _lastLoggedVoice = key;
    AppLogger.tts(message);
  }

  /// Speaks [text] with the generative [voice] and resolves when playback
  /// ends: true when it reached the end. If it fails before any audio,
  /// the usual voice takes over and speaks [text] instead.
  Future<bool> _speakGenerative(String text, String voice, double speed,
      {int base = 0, String? fullText}) async {
    final speaker = generativeSpeaker!;
    _logOnce('gen:$voice', 'Native voice: generative voice $voice');
    if (speed != 1.0) {
      _logOnce('speed:$voice',
          'Native voice: speed setting not applied, the generative voice has no rate control');
    }
    activeVoiceName = voice;
    final full = fullText ?? text;
    _lastSpokenText = full;
    _generativeFullText = full;
    _generativeBase = base;
    _isPlaying = true;
    _generativeActive = true;
    _generativeStopRequested = false;
    _generativePlayedMs = 0;
    final cps = _charsPerSecond;
    String? recordPath;
    if (onGenerativeRecording != null) {
      try {
        recordPath = '${await recordingDirectory()}/genai_tts_'
            '${DateTime.now().microsecondsSinceEpoch}.wav';
      } catch (_) {
        recordPath = null;
      }
    }
    final result = await speaker.speak(
      locale: preferredLanguageLocale,
      voice: voice,
      text: text,
      recordPath: recordPath,
      onPlayedMs: (ms) {
        _generativePlayedMs = ms;
        if (_isPlaying && full.isNotEmpty) {
          // Progress through the whole narration, not just this segment.
          onProgress?.call(((base + ms / 1000 * cps) / full.length).clamp(0.0, 0.99));
        }
      },
    );
    _generativeActive = false;
    _generativePlayedMs = result.playedMs;
    if (result.completed && text.length >= 300 && result.playedMs > 5000) {
      // #545: learn the real rate from a long enough complete segment.
      final measured = text.length / (result.playedMs / 1000);
      if (measured > 5 && measured < 60) _charsPerSecond = (_charsPerSecond + measured) / 2;
    }
    if (result.completed) {
      _isPlaying = false;
      onProgress?.call(1.0);
      if (_pendingSpeak?.isCompleted == false) _pendingSpeak!.complete(true);
      onComplete?.call();
      final recorded = result.recordedPath;
      if (recorded != null) unawaited(_handOverRecording(text, recorded));
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
    _nativeFullText = text;
    _nativeBase = 0;
    _nativeFullLength = null;
    _isPlaying = true;
    await _tts.speak(text);
  }

  /// #546: the narration being spoken with the usual voice, and where the
  /// part handed to the engine starts in it after a jump.
  String? _nativeFullText;
  int _nativeBase = 0;
  int? _nativeFullLength;

  /// #546: jumps to [fraction] of the narration being spoken — snapped
  /// to the start of that sentence — with whichever phone voice is
  /// speaking it. No-op when nothing is being narrated.
  Future<void> speakFromFraction(double fraction, {double speed = 1.0}) async {
    final voice = activeVoiceName;
    final generative = voice != null && _generativeVoiceCache.containsValue(voice);
    final full = generative ? (_generativeFullText ?? _lastSpokenText) : (_nativeFullText ?? _lastSpokenText);
    if (full == null || full.isEmpty) return;
    await speakFrom(sentenceStartAt(full, (fraction * full.length).round()), speed: speed);
  }

  /// #546: jumps to [offset] of the narration being spoken.
  Future<void> speakFrom(int offset, {double speed = 1.0}) async {
    final voice = activeVoiceName;
    final generative = voice != null && _generativeVoiceCache.containsValue(voice);
    final full = generative ? (_generativeFullText ?? _lastSpokenText) : (_nativeFullText ?? _lastSpokenText);
    if (full == null || full.isEmpty) return;
    final start = offset.clamp(0, full.length - 1);
    if (generative) {
      if (_generativeActive) {
        _generativeStopRequested = true;
        await generativeSpeaker?.stopSpeaking();
        // Let the stopped segment wind down before the next one starts.
        for (var i = 0; i < 40 && _generativeActive; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
      }
      unawaited(_speakGenerative(full.substring(start), voice, speed, base: start, fullText: full));
      return;
    }
    await _tts.stop();
    await _tts.setSpeechRate(0.45 * speed);
    final rest = full.substring(start);
    _lastSpokenText = rest;
    _nativeFullText = full;
    _nativeBase = start;
    _nativeFullLength = full.length;
    _isPlaying = true;
    await _tts.speak(rest);
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
      // #485/#545: restart at the beginning of the sentence playback had
      // reached, counted in the whole narration (a second pause after a
      // resume must not go back to an earlier sentence).
      final full = _generativeFullText ?? text;
      final base = _generativeBase.clamp(0, full.length);
      final segment = full.substring(base);
      final newBase =
          base + generativeResumeOffset(segment, _generativePlayedMs, charsPerSecond: _charsPerSecond);
      unawaited(_speakGenerative(full.substring(newBase).trimLeft(), voice, 1.0,
          base: newBase, fullText: full));
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
String generativeResumeText(String text, int playedMs) =>
    text.substring(generativeResumeOffset(text, playedMs)).trimLeft();

/// #545: where in [text] a resumed narration restarts — the start of the
/// sentence reached after [playedMs] at [charsPerSecond]; 0 when nothing
/// was played, or when the estimate runs past the end (better to repeat
/// than to skip).
int generativeResumeOffset(String text, int playedMs,
    {double charsPerSecond = NativeTtsService._generativeCharsPerSecond}) {
  final reached = (playedMs / 1000 * charsPerSecond).floor();
  if (reached <= 0 || reached >= text.length) return 0;
  final before = text.substring(0, reached);
  final boundary = before.lastIndexOf(RegExp(r'[.!?…]\s'));
  return boundary == -1 ? 0 : boundary + 2;
}

/// #546: the start of the sentence containing [offset] in [text].
int sentenceStartAt(String text, int offset) {
  if (text.isEmpty) return 0;
  final at = offset.clamp(0, text.length - 1);
  final boundary = text.substring(0, at + 1).lastIndexOf(RegExp(r'[.!?…]\s'));
  if (boundary == -1) return 0;
  var start = boundary + 1;
  while (start < text.length && text[start].trim().isEmpty) {
    start++;
  }
  return start > at ? at : start;
}

