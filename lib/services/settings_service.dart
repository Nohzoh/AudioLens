import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsService extends ChangeNotifier {
  late SharedPreferences _prefs;
  bool _isOnboardingComplete = false;
  String _geminiApiKey = '';
  bool _showKofiButton = true;

  bool get isOnboardingComplete => _isOnboardingComplete;
  String get geminiApiKey => _geminiApiKey;
  bool get showKofiButton => _showKofiButton;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    _isOnboardingComplete = _prefs.getBool('onboarding_complete') ?? false;
    _geminiApiKey = _prefs.getString('gemini_api_key') ?? '';
    _showKofiButton = _prefs.getBool('show_kofi_button') ?? true;
  }

  Future<void> completeOnboarding({required String apiKey}) async {
    _geminiApiKey = apiKey;
    _isOnboardingComplete = true;
    await _prefs.setString('gemini_api_key', apiKey);
    await _prefs.setBool('onboarding_complete', true);
    notifyListeners();
  }

  Future<void> resetOnboarding() async {
    await _prefs.clear();
    _isOnboardingComplete = false;
    _geminiApiKey = '';
    _showKofiButton = true;
    notifyListeners();
  }

  Future<void> setShowKofiButton(bool value) async {
    _showKofiButton = value;
    await _prefs.setBool('show_kofi_button', value);
    notifyListeners();
  }
}
