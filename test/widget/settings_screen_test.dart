import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:audiolens/screens/settings_screen.dart';
import 'package:audiolens/services/audio_guide_service.dart';
import 'package:audiolens/services/history_service.dart';
import 'package:audiolens/services/settings_service.dart';
import '../support/service_fakes.dart';

/// T105 — first widget-level coverage for SettingsScreen. Deliberately
/// skips tapping "View source code" / "Get a free key" (external
/// url_launcher calls) — out of scope for this pass, avoids adding a
/// url_launcher_platform_interface fake for marginal value.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfiNoIsolate;

  late Directory tmpDir;
  late SettingsService settings;
  late AudioGuideService guide;
  late HistoryService history;

  setUp(() async {
    tmpDir = await Directory.systemTemp.createTemp('settings_screen_test');
    SharedPreferences.setMockInitialValues({});
    setUpSecureStorageMock();
    PackageInfo.setMockInitialValues(
      appName: 'AudioLens',
      packageName: 'io.nohzoh.audiolens',
      version: '0.1.5',
      buildNumber: '42',
      buildSignature: '',
    );

    settings = SettingsService();
    await settings.init();
    guide = AudioGuideService(nativeTtsService: FakeNativeTts());
    history = HistoryService();
    await history.init(dbPath: '${tmpDir.path}/history.db');
  });

  tearDown(() async {
    tearDownSecureStorageMock();
    await tmpDir.delete(recursive: true);
  });

  Widget wrapScreen() => wrapWithProviders(
        const SettingsScreen(),
        settings: settings,
        guide: guide,
        history: history,
      );

  testWidgets('renders both provider cards, local AI active-by-default and Gemini API locked',
      (tester) async {
    await tester.pumpWidget(wrapScreen());
    await tester.pumpAndSettle();

    // #253: "IA locale", not the "Gemini Nano" brand name.
    expect(find.text('IA locale'), findsOneWidget);
    expect(find.text('Gemini API'), findsOneWidget);
    // AudioGuideService defaults activeProvider to geminiNano even though
    // nanoAvailable is false for a fresh instance — that's existing app
    // behavior, not something this test changes. Gemini API has no key,
    // so it's the one shown locked.
    expect(find.byIcon(Icons.check_circle), findsOneWidget);
    expect(find.byIcon(Icons.lock_outline), findsOneWidget);
  });

  testWidgets('entering an API key and tapping Save shows the saved snackbar',
      (tester) async {
    await tester.pumpWidget(wrapScreen());
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'AIzaTestKey123');
    // AudioGuideService.setGeminiApiKey does real SecureKeyStorage I/O —
    // needs tester.runAsync() (see history_screen_test.dart's file doc for
    // why: testWidgets()'s fake-async zone never resolves real async I/O
    // otherwise).
    await tester.runAsync(() async {
      await tester.tap(find.text('Sauvegarder'));
    });
    await tester.pumpAndSettle();

    expect(find.text('Paramètres sauvegardés'), findsOneWidget);
  });

  testWidgets('toggling auto-generate-audio updates SettingsService', (tester) async {
    expect(settings.autoGenerateAudio, isTrue);

    await tester.pumpWidget(wrapScreen());
    await tester.pumpAndSettle();

    // Well below the fold in this long settings list — the plain
    // ListView doesn't mount offscreen children, so the tap target
    // isn't in the tree until scrolled into view.
    final toggle = find.widgetWithText(SwitchListTile, 'Générer l\'audio automatiquement');
    await tester.scrollUntilVisible(toggle, 300, scrollable: find.byType(Scrollable).first);
    await tester.ensureVisible(toggle);
    await tester.pumpAndSettle();
    await tester.tap(toggle);
    await tester.pumpAndSettle();

    expect(settings.autoGenerateAudio, isFalse);
  });

  testWidgets('toggling auto-purge updates SettingsService and reveals the day chips',
      (tester) async {
    expect(settings.autoPurgeEnabled, isFalse);

    await tester.pumpWidget(wrapScreen());
    await tester.pumpAndSettle();

    final toggle = find.widgetWithText(SwitchListTile, 'Purger automatiquement l\'historique');
    await tester.scrollUntilVisible(toggle, 300, scrollable: find.byType(Scrollable).first);
    await tester.ensureVisible(toggle);
    await tester.pumpAndSettle();
    expect(find.text('30 jours'), findsNothing);

    await tester.tap(toggle);
    await tester.pumpAndSettle();

    expect(settings.autoPurgeEnabled, isTrue);
    expect(find.text('30 jours'), findsOneWidget);
  });

  testWidgets('the version label renders from the mocked PackageInfo', (tester) async {
    await tester.pumpWidget(wrapScreen());
    await tester.pumpAndSettle();

    // #145 pushed this section further down the list — same offscreen-child
    // issue as the toggles above.
    final versionLabel = find.text('Version : 0.1.5 (42)');
    await tester.scrollUntilVisible(versionLabel, 300, scrollable: find.byType(Scrollable).first);

    expect(versionLabel, findsOneWidget);
  });
}
