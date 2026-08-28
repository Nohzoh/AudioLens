import 'dart:ui' show PlatformDispatcher;
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
  bool _outputLanguageFollowsApp = false;
  String? _appLocale;
  String? _lastSeenVersion;

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

  /// Whether [outputLanguage] tracks [appLocale] (English/French,
  /// whichever the app's interface is actually showing) instead of being
  /// picked independently. Off by default, matching [outputLanguage]'s own
  /// existing default-to-French-independent-of-locale behavior.
  bool get outputLanguageFollowsApp => _outputLanguageFollowsApp;

  /// The app's own interface language, independent of [outputLanguage] —
  /// null means "follow the device's system language" (the default, and
  /// Flutter's own resolution already does the right thing for that case).
  /// One of [AppLocalizations.supportedLocales]'s language codes when set,
  /// letting testers switch the UI language without touching Android's
  /// system or per-app language settings.
  String? get appLocale => _appLocale;

  /// Whether history entries older than [autoPurgeDays] are deleted
  /// automatically on app startup (T95). Off by default — deletion stays
  /// manual (from the history entry itself) unless explicitly opted in.
  bool get autoPurgeEnabled => _autoPurgeEnabled;

  /// How old (in days) a history entry must be before auto-purge deletes
  /// it, when [autoPurgeEnabled] is true.
  int get autoPurgeDays => _autoPurgeDays;

  /// #299 — the app version (`pubspec.yaml`'s X.Y.Z, not the build
  /// number) this device last showed a "what's new" dialog for, or
  /// recorded as already-seen at the end of onboarding. Null only for an
  /// install that's never gotten past `init()` once — HomeScreen (the
  /// only place this is read) is unreachable before onboarding
  /// completes, so in practice this is always set by the time anything
  /// checks it.
  String? get lastSeenVersion => _lastSeenVersion;

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
    _outputLanguageFollowsApp = _prefs.getBool('output_language_follows_app') ?? false;
    _appLocale = _prefs.getString('app_locale');
    _lastSeenVersion = _prefs.getString('last_seen_version');
    // Re-resolve in case the app's language changed (system locale, or a
    // prior in-app override) since the last launch while this was on.
    if (_outputLanguageFollowsApp) {
      _outputLanguage = _resolveAppLanguageDisplayName();
    }
  }

  /// English or Français — whichever [appLocale] resolves to, following
  /// the same fallback main.dart's own locale resolution uses (only 'fr'
  /// maps to French; every other/unset system locale falls back to
  /// English, since those are the only two supported interface languages).
  String _resolveAppLanguageDisplayName() {
    final code = _appLocale ?? PlatformDispatcher.instance.locale.languageCode;
    return code == 'fr' ? 'Français' : 'English';
  }

  /// #298: [apiKey] is now optional — the onboarding carousel only
  /// requires one on a device where local AI (Nano) isn't available;
  /// that requirement is enforced by the carousel's own final page, not
  /// here. Throws [SecureStorageUnavailableException] if a given key
  /// can't be persisted securely — onboarding isn't marked complete in
  /// that case, so the user sees the same screen again rather than an
  /// app that silently forgot its key was ever entered.
  Future<void> completeOnboarding({String? apiKey}) async {
    if (apiKey != null && apiKey.isNotEmpty) {
      await SecureKeyStorage.writeApiKey(apiKey);
      _geminiApiKey = apiKey;
    }
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
    _outputLanguageFollowsApp = false;
    _appLocale = null;
    _lastSeenVersion = null;
    notifyListeners();
  }

  /// #299 — called once HomeScreen has either shown the "what's new"
  /// dialog for [version] or decided not to (a brand-new install that
  /// just finished onboarding shouldn't also see what's-new for the
  /// version it installed with). Not tied to [completeOnboarding]
  /// itself: that runs before `PackageInfo` is necessarily available to
  /// the onboarding flow, and mixing the two concerns would make
  /// onboarding responsible for what's-new bookkeeping it has no other
  /// reason to know about.
  Future<void> recordSeenVersion(String version) async {
    _lastSeenVersion = version;
    await _prefs.setString('last_seen_version', version);
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

  /// Picking a language explicitly always turns off [outputLanguageFollowsApp]
  /// — an explicit choice here is a deliberate override.
  Future<void> setOutputLanguage(String value) async {
    _outputLanguage = value;
    _outputLanguageFollowsApp = false;
    await _prefs.setString('output_language', value);
    await _prefs.setBool('output_language_follows_app', false);
    notifyListeners();
  }

  Future<void> setOutputLanguageFollowsApp(bool value) async {
    _outputLanguageFollowsApp = value;
    await _prefs.setBool('output_language_follows_app', value);
    if (value) {
      _outputLanguage = _resolveAppLanguageDisplayName();
      await _prefs.setString('output_language', _outputLanguage);
    }
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

  /// [value] null resets to following the device's system language.
  Future<void> setAppLocale(String? value) async {
    _appLocale = value;
    if (value == null) {
      await _prefs.remove('app_locale');
    } else {
      await _prefs.setString('app_locale', value);
    }
    // Keep outputLanguage in sync if it's set to track the app's language.
    if (_outputLanguageFollowsApp) {
      _outputLanguage = _resolveAppLanguageDisplayName();
      await _prefs.setString('output_language', _outputLanguage);
    }
    notifyListeners();
  }
}
