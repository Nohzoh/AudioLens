import 'package:flutter_tts/flutter_tts.dart';

/// Thin wrapper around the device's system TTS engine (T89), used to let
/// the user A/B-listen it against Piper (`tts_service.dart`) before
/// deciding whether it's good enough to replace or complement it. Not
/// wired into the main synthesis pipeline (TtsOrchestrator) yet.
class NativeTtsService {
  final FlutterTts _tts = FlutterTts();
  bool _initialized = false;

  Future<void> _ensureInitialized() async {
    if (_initialized) return;
    await _tts.setLanguage('fr-FR');
    await _tts.setSpeechRate(0.45);
    await _tts.setPitch(1.0);
    _initialized = true;
  }

  /// Whether the device's system TTS engine has a French voice installed
  /// — not guaranteed on every device/configuration, unlike the bundled
  /// Piper model.
  Future<bool> isFrenchAvailable() async {
    final result = await _tts.isLanguageAvailable('fr-FR');
    return result == true || result == 1;
  }

  Future<void> speak(String text) async {
    await _ensureInitialized();
    await _tts.speak(text);
  }

  Future<void> stop() async {
    await _tts.stop();
  }
}
