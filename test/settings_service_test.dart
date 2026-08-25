import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:audiolens/services/settings_service.dart';

const _secureChannel =
    MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

/// T68 — only autoGenerateAudio was covered before this (incidentally, via
/// script_only_mode_test.dart); showKofiButton, scriptStyle (T75), the
/// onboarding/API key flow, and resetOnboarding() had no dedicated test.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final secureStore = <String, String>{};

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    secureStore.clear();
    // T123 follow-up: SecureKeyStorage.writeApiKey no longer falls back to
    // plaintext SharedPreferences on failure, so it needs a real (mocked)
    // secure storage channel to succeed in tests.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_secureChannel, (call) async {
      final args = (call.arguments as Map?)?.cast<String, dynamic>();
      switch (call.method) {
        case 'write':
          secureStore[args!['key'] as String] = args['value'] as String;
          return null;
        case 'read':
          return secureStore[args!['key'] as String];
        case 'delete':
          secureStore.remove(args!['key'] as String);
          return null;
        case 'deleteAll':
          secureStore.clear();
          return null;
        case 'readAll':
          return Map<String, String>.from(secureStore);
        case 'containsKey':
          return secureStore.containsKey(args!['key'] as String);
      }
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_secureChannel, null);
  });

  test('defaults before onboarding: not complete, empty key, style immersive', () async {
    final settings = SettingsService();
    await settings.init();

    expect(settings.isOnboardingComplete, isFalse);
    expect(settings.geminiApiKey, isEmpty);
    expect(settings.showKofiButton, isTrue);
    expect(settings.autoGenerateAudio, isTrue);
    expect(settings.scriptStyle, 'immersive');
    expect(settings.themeMode, ThemeMode.system);
  });

  test('completeOnboarding stores the API key and marks onboarding complete',
      () async {
    final settings = SettingsService();
    await settings.init();

    await settings.completeOnboarding(apiKey: 'AIza-test-key');

    expect(settings.isOnboardingComplete, isTrue);
    expect(settings.geminiApiKey, 'AIza-test-key');

    // Persisted, not just in-memory — a fresh instance sees the same state.
    final reloaded = SettingsService();
    await reloaded.init();
    expect(reloaded.isOnboardingComplete, isTrue);
    expect(reloaded.geminiApiKey, 'AIza-test-key');
  });

  test('setShowKofiButton persists across a reload', () async {
    final settings = SettingsService();
    await settings.init();

    await settings.setShowKofiButton(false);
    expect(settings.showKofiButton, isFalse);

    final reloaded = SettingsService();
    await reloaded.init();
    expect(reloaded.showKofiButton, isFalse);
  });

  test('setScriptStyle persists across a reload (T75)', () async {
    final settings = SettingsService();
    await settings.init();

    await settings.setScriptStyle('anecdotal');
    expect(settings.scriptStyle, 'anecdotal');

    final reloaded = SettingsService();
    await reloaded.init();
    expect(reloaded.scriptStyle, 'anecdotal');
  });

  test('resetOnboarding clears onboarding, API key, and restores every default',
      () async {
    final settings = SettingsService();
    await settings.init();
    await settings.completeOnboarding(apiKey: 'AIza-test-key');
    await settings.setShowKofiButton(false);
    await settings.setAutoGenerateAudio(false);
    await settings.setScriptStyle('concise');
    await settings.setAutoPurgeEnabled(true);
    await settings.setAutoPurgeDays(7);
    await settings.setThemeMode(ThemeMode.dark);

    await settings.resetOnboarding();

    expect(settings.isOnboardingComplete, isFalse);
    expect(settings.geminiApiKey, isEmpty);
    expect(settings.showKofiButton, isTrue);
    expect(settings.autoGenerateAudio, isTrue);
    expect(settings.scriptStyle, 'immersive');
    expect(settings.autoPurgeEnabled, isFalse);
    expect(settings.autoPurgeDays, 30);
    expect(settings.themeMode, ThemeMode.system);
  });

  // #145
  test('setThemeMode persists across a reload', () async {
    final settings = SettingsService();
    await settings.init();

    await settings.setThemeMode(ThemeMode.light);
    expect(settings.themeMode, ThemeMode.light);

    final reloaded = SettingsService();
    await reloaded.init();
    expect(reloaded.themeMode, ThemeMode.light);
  });

  test('setThemeMode(ThemeMode.dark) also persists across a reload (#145)',
      () async {
    final settings = SettingsService();
    await settings.init();

    await settings.setThemeMode(ThemeMode.dark);

    final reloaded = SettingsService();
    await reloaded.init();
    expect(reloaded.themeMode, ThemeMode.dark);
  });

  test('auto-purge defaults to disabled, 30 days (T95)', () async {
    final settings = SettingsService();
    await settings.init();

    expect(settings.autoPurgeEnabled, isFalse);
    expect(settings.autoPurgeDays, 30);
  });

  test('setAutoPurgeEnabled/setAutoPurgeDays persist across a reload (T95)',
      () async {
    final settings = SettingsService();
    await settings.init();

    await settings.setAutoPurgeEnabled(true);
    await settings.setAutoPurgeDays(14);
    expect(settings.autoPurgeEnabled, isTrue);
    expect(settings.autoPurgeDays, 14);

    final reloaded = SettingsService();
    await reloaded.init();
    expect(reloaded.autoPurgeEnabled, isTrue);
    expect(reloaded.autoPurgeDays, 14);
  });
}
