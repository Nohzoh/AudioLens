import 'package:shared_preferences/shared_preferences.dart';

/// Snapshot of the GPS/analysis duration history used to estimate
/// remaining pipeline time.
class TimingSnapshot {
  const TimingSnapshot({required this.gpsDurations, required this.analyzeDurations});

  final List<double> gpsDurations;
  final List<double> analyzeDurations;
}

/// Persistence for pipeline preferences (active AI provider, timing
/// history) via SharedPreferences (T06 — extracted from
/// AudioGuideService so it doesn't talk to SharedPreferences directly).
///
/// The Gemini API key is handled separately by SecureKeyStorage.
class GuidePreferencesStore {
  static const _activeProviderKey = 'active_provider';
  static const _timingGpsKey = 'timing_gps';
  static const _timingAnalyzeKey = 'timing_analyze';
  static const _ttsVoiceGenderKey = 'tts_voice_gender';

  /// 'female' or 'male' — which native TTS voice to prefer (T89).
  Future<String> loadTtsVoiceGender() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_ttsVoiceGenderKey) ?? 'female';
  }

  Future<void> saveTtsVoiceGender(String gender) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_ttsVoiceGenderKey, gender);
  }

  Future<String?> loadActiveProviderName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_activeProviderKey);
  }

  Future<void> saveActiveProviderName(String name) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_activeProviderKey, name);
  }

  Future<TimingSnapshot> loadTimings() async {
    final prefs = await SharedPreferences.getInstance();
    return TimingSnapshot(
      gpsDurations: (prefs.getStringList(_timingGpsKey) ?? []).map(double.parse).toList(),
      analyzeDurations: (prefs.getStringList(_timingAnalyzeKey) ?? []).map(double.parse).toList(),
    );
  }

  Future<void> saveTimings(List<double> gpsDurations, List<double> analyzeDurations) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_timingGpsKey, gpsDurations.map((d) => d.toString()).toList());
    await prefs.setStringList(_timingAnalyzeKey, analyzeDurations.map((d) => d.toString()).toList());
  }
}
