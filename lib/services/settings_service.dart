import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../constants/output_languages.dart';
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
  ThemeMode _themeMode = ThemeMode.system;
  String _outputLanguage = defaultOutputLanguage;

  bool get isOnboardingComplete => _isOnboardingComplete;
  String get geminiApiKey => _geminiApiKey;
  bool get showKofiButton => _showKofiButton;

  /// #145 — defaults to following the device's own setting, like most
  /// apps do, rather than forcing dark (the app's only option before).
  ThemeMode get themeMode => _themeMode;

  /// Whether audio is synthesized automatically after each analysis (T16).
  /// When false, analyzeAndPlay stops after generating the script; audio
  /// can be generated later on demand from the history entry.
  bool get autoGenerateAudio => _autoGenerateAudio;

  /// One of 'immersive' (default), 'academic', 'anecdotal', 'concise' —
  /// passed to the AI prompt (both cloud and on-device) to steer the
  /// script's tone and length (T75/T48).
  String get scriptStyle => _scriptStyle;

  /// #130 — the narration's language, independent of the app's own
  /// interface language. Defaults to French (the narration's de-facto
  /// language before this setting existed), not the device locale, so
  /// existing installs see no surprise change in narration language on
  /// upgrade. One of [outputLanguageLocales]'s keys.
  String get outputLanguage => _outputLanguage;

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
    _themeMode = ThemeMode.values.byName(_prefs.getString('theme_mode') ?? 'system');
    _outputLanguage = _prefs.getString('output_language') ?? defaultOutputLanguage;
  }

  /// Throws [SecureStorageUnavailableException] if the key can't be
  /// persisted securely — onboarding isn't marked complete in that case,
  /// so the user sees the same screen again rather than an app that
  /// silently forgot its key was ever entered.
  Future<void> completeOnboarding({required String apiKey}) async {
    await SecureKeyStorage.writeApiKey(apiKey);
    _geminiApiKey = apiKey;
    _isOnboardingComplete = true;
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
    _themeMode = ThemeMode.system;
    _outputLanguage = defaultOutputLanguage;
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

  Future<void> setOutputLanguage(String value) async {
    _outputLanguage = value;
    await _prefs.setString('output_language', value);
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

  Future<void> setThemeMode(ThemeMode value) async {
    _themeMode = value;
    await _prefs.setString('theme_mode', value.name);
    notifyListeners();
  }
}
