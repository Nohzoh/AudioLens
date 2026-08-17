import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'secure_key_storage.dart';

class SettingsService extends ChangeNotifier {
  late SharedPreferences _prefs;
  bool _isOnboardingComplete = false;
  String _geminiApiKey = '';
  bool _showKofiButton = true;
  bool _autoGenerateAudio = true;
  String _scriptStyle = 'immersive';

  bool get isOnboardingComplete => _isOnboardingComplete;
  String get geminiApiKey => _geminiApiKey;
  bool get showKofiButton => _showKofiButton;

  /// Whether audio is synthesized automatically after each analysis (T16).
  /// When false, analyzeAndPlay stops after generating the script; audio
  /// can be generated later on demand from the history entry.
  bool get autoGenerateAudio => _autoGenerateAudio;

  /// One of 'immersive' (default), 'academic', 'anecdotal', 'concise' —
  /// passed to the AI prompt (both cloud and on-device) to steer the
  /// script's tone and length (T75/T48).
  String get scriptStyle => _scriptStyle;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    _isOnboardingComplete = _prefs.getBool('onboarding_complete') ?? false;
    _geminiApiKey = await SecureKeyStorage.readApiKey() ?? '';
    _showKofiButton = _prefs.getBool('show_kofi_button') ?? true;
    _autoGenerateAudio = _prefs.getBool('auto_generate_audio') ?? true;
    _scriptStyle = _prefs.getString('script_style') ?? 'immersive';
  }

  Future<void> completeOnboarding({required String apiKey}) async {
    _geminiApiKey = apiKey;
    _isOnboardingComplete = true;
    await SecureKeyStorage.writeApiKey(apiKey);
    await _prefs.setBool('onboarding_complete', true);
    notifyListeners();
  }

  Future<void> resetOnboarding() async {
    await _prefs.clear();
    await SecureKeyStorage.clearApiKey();
    _isOnboardingComplete = false;
    _geminiApiKey = '';
    _showKofiButton = true;
    _autoGenerateAudio = true;
    _scriptStyle = 'immersive';
    notifyListeners();
  }

  Future<void> setShowKofiButton(bool value) async {
    _showKofiButton = value;
    await _prefs.setBool('show_kofi_button', value);
    notifyListeners();
  }

  Future<void> setAutoGenerateAudio(bool value) async {
    _autoGenerateAudio = value;
    await _prefs.setBool('auto_generate_audio', value);
    notifyListeners();
  }

  Future<void> setScriptStyle(String value) async {
    _scriptStyle = value;
    await _prefs.setString('script_style', value);
    notifyListeners();
  }
}
