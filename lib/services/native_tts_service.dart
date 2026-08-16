import 'dart:async';
import 'package:flutter_tts/flutter_tts.dart';

/// Thin wrapper around the device's system TTS engine (T89), used to let
/// the user A/B-listen it against Piper (`tts_service.dart`) before
/// deciding whether it's good enough to replace or complement it. Not
/// wired into the main synthesis pipeline (TtsOrchestrator) yet.
class NativeTtsService {
  final FlutterTts _tts = FlutterTts();
  bool _initialized = false;
  Completer<bool>? _pendingSpeak;

  Future<void> _ensureInitialized() async {
    if (_initialized) return;
    await _tts.setLanguage('fr-FR');
    await _tts.setSpeechRate(0.45);
    await _tts.setPitch(1.0);
    // Some voices reported by frenchVoices() turned out to be catalog
    // entries Android hasn't actually downloaded/enabled on the device —
    // speak() used to fail silently for those (T89: confusing while
    // comparing voices). These let speak() report whether audio actually
    // played instead of just firing and forgetting.
    _tts.setCompletionHandler(() {
      if (_pendingSpeak?.isCompleted == false) _pendingSpeak!.complete(true);
    });
    _tts.setErrorHandler((_) {
      if (_pendingSpeak?.isCompleted == false) _pendingSpeak!.complete(false);
    });
    _initialized = true;
  }

  /// Whether the device's system TTS engine has a French voice installed
  /// — not guaranteed on every device/configuration, unlike the bundled
  /// Piper model.
  Future<bool> isFrenchAvailable() async {
    final result = await _tts.isLanguageAvailable('fr-FR');
    return result == true || result == 1;
  }

  /// All French voices the device's TTS engine offers, as {name, locale}
  /// maps (flutter_tts doesn't surface Android's quality/network-required
  /// metadata, so the app can't auto-pick "the best one" — this is meant
  /// to be listed for the user to try, since a monotone default voice
  /// (T89: reported as sounding like an SNCF-style announcement) can
  /// often be swapped for a much more natural one on the same device).
  Future<List<Map<String, String>>> frenchVoices() async {
    final voices = await _tts.getVoices;
    if (voices is! List) return [];
    return voices
        .whereType<Map>()
        .map((v) => v.map((k, val) => MapEntry(k.toString(), val.toString())))
        .where((v) => (v['locale'] ?? '').toLowerCase().startsWith('fr'))
        .toList();
  }

  Future<void> setVoice(String name, String locale) async {
    await _ensureInitialized();
    await _tts.setVoice({'name': name, 'locale': locale});
  }

  /// Speaks [text], returning whether audio actually played. A voice
  /// that's listed but not really available on the device (see
  /// [frenchVoices]) tends to just do nothing rather than throw, which
  /// this surfaces instead of silently swallowing.
  Future<bool> speak(String text) async {
    await _ensureInitialized();
    if (_pendingSpeak?.isCompleted == false) _pendingSpeak!.complete(false);
    final completer = Completer<bool>();
    _pendingSpeak = completer;
    await _tts.speak(text);
    return completer.future.timeout(
      const Duration(seconds: 15),
      onTimeout: () => false,
    );
  }

  Future<void> stop() async {
    await _tts.stop();
  }
}
