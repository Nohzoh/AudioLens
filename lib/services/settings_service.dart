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
  bool _autoPurgeEnabled = false;
  int _autoPurgeDays = 30;

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

  /// Whether history entries older than [autoPurgeDays] are deleted
  /// automatically on app startup (T95). Off by default — deletion stays
  /// manual (from the history entry itself) unless explicitly opted in.
  bool get autoPurgeEnabled => _autoPurgeEnabled;

  /// How old (in days) a history entry must be before auto-purge deletes
  /// it, when [autoPurgeEnabled] is true.
  int get autoPurgeDays => _autoPurgeDays;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    _isOnboardingComplete = _prefs.getBool('onboarding_complete') ?? false;
    _geminiApiKey = await SecureKeyStorage.readApiKey() ?? '';
    _showKofiButton = _prefs.getBool('show_kofi_button') ?? true;
    _autoGenerateAudio = _prefs.getBool('auto_generate_audio') ?? true;
    _scriptStyle = _prefs.getString('script_style') ?? 'immersive';
    _autoPurgeEnabled = _prefs.getBool('auto_purge_enabled') ?? false;
    _autoPurgeDays = _prefs.getInt('auto_purge_days') ?? 30;
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
    _autoPurgeEnabled = false;
    _autoPurgeDays = 30;
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

  Future<void> setAutoPurgeEnabled(bool value) async {
    _autoPurgeEnabled = value;
    await _prefs.setBool('auto_purge_enabled', value);
    notifyListeners();
  }

  Future<void> setAutoPurgeDays(int value) async {
    _autoPurgeDays = value;
    await _prefs.setInt('auto_purge_days', value);
    notifyListeners();
  }
}
