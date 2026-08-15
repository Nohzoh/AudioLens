import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'secure_key_storage.dart';

class SettingsService extends ChangeNotifier {
  late SharedPreferences _prefs;
  bool _isOnboardingComplete = false;
  String _geminiApiKey = '';
  bool _showKofiButton = true;
  bool _autoGenerateAudio = true;

  bool get isOnboardingComplete => _isOnboardingComplete;
  String get geminiApiKey => _geminiApiKey;
  bool get showKofiButton => _showKofiButton;

  /// Whether audio is synthesized automatically after each analysis (T16).
  /// When false, analyzeAndPlay stops after generating the script; audio
  /// can be generated later on demand from the history entry.
  bool get autoGenerateAudio => _autoGenerateAudio;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    _isOnboardingComplete = _prefs.getBool('onboarding_complete') ?? false;
    _geminiApiKey = await SecureKeyStorage.readApiKey() ?? '';
    _showKofiButton = _prefs.getBool('show_kofi_button') ?? true;
    _autoGenerateAudio = _prefs.getBool('auto_generate_audio') ?? true;
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
}
