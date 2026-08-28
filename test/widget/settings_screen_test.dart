import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:audiolens/screens/settings_screen.dart';
import 'package:audiolens/services/audio_guide_service.dart';
import 'package:audiolens/services/feedback_service.dart';
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

  // #278: tapping the locked "Gemini API" card used to do nothing (onTap
  // was null while no key was saved) — the only way to discover the key
  // field existed was to scroll past it by chance. It now scrolls the key
  // section into view and focuses the field instead.
  testWidgets('tapping the locked Gemini API card focuses the API key field',
      (tester) async {
    await tester.pumpWidget(wrapScreen());
    await tester.pumpAndSettle();

    expect(guide.geminiApiKey, anyOf(isNull, isEmpty));
    final apiKeyField = tester.widget<TextField>(find.byType(TextField));
    expect(apiKeyField.focusNode?.hasFocus, isFalse);

    await tester.tap(find.text('Gemini API'));
    await tester.pumpAndSettle();

    final focusedField = tester.widget<TextField>(find.byType(TextField));
    expect(focusedField.focusNode?.hasFocus, isTrue);
  });

  // #283: the "IA locale" card used to show a generic "(non configuré)"
  // suffix regardless of *why* Nano wasn't usable — including when the
  // device simply doesn't support AICore, which isn't something the user
  // configured or can fix. SettingsScreen queries
  // GeminiNanoService.checkDeviceStatus() (over the same platform channel
  // AudioGuideService's real nanoService uses) in initState to show the
  // right reason instead.
  const nanoChannel = MethodChannel('audio_guide/gemini_nano');

  testWidgets('shows a device-support message when Nano is hardware/OS unavailable',
      (tester) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(nanoChannel, (call) async {
      if (call.method == 'checkNanoStatus') return 'unavailable';
      return null;
    });
    addTearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(nanoChannel, null));

    await tester.pumpWidget(wrapScreen());
    await tester.pumpAndSettle();

    expect(find.textContaining("ne prend pas en charge l'IA locale"), findsOneWidget);
  });

  testWidgets('shows a download-pending message when Nano is downloadable but not yet ready',
      (tester) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(nanoChannel, (call) async {
      if (call.method == 'checkNanoStatus') return 'downloadable';
      return null;
    });
    addTearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(nanoChannel, null));

    await tester.pumpWidget(wrapScreen());
    await tester.pumpAndSettle();

    expect(find.textContaining('Modèle IA non téléchargé'), findsOneWidget);
  });

  // #294: the feedback button only exists on a build that actually has
  // TELEGRAM_BOT_TOKEN/TELEGRAM_CHAT_ID baked in (a real CI build) —
  // wrapScreen()'s plain FeedbackService() is always unconfigured here,
  // since a `flutter test` run never passes --dart-define.
  testWidgets('hides the feedback button when FeedbackService is not configured',
      (tester) async {
    await tester.pumpWidget(wrapScreen());
    await tester.pumpAndSettle();

    expect(find.text('Envoyer un feedback'), findsNothing);
  });

  group('feedback dialog (#294)', () {
    Widget wrapConfiguredScreen(http.Client client) => wrapWithProviders(
          SettingsScreen(
            feedbackService:
                FeedbackService(botToken: '123:ABC', chatId: '-100999', client: client),
          ),
          settings: settings,
          guide: guide,
          history: history,
        );

    testWidgets('shows the button, and a successful send closes the dialog '
        'with a confirmation snackbar', (tester) async {
      Map<String, String>? sentFields;
      final client = MockClient((request) async {
        sentFields = request.bodyFields;
        return http.Response('{"ok":true}', 200);
      });

      await tester.pumpWidget(wrapConfiguredScreen(client));
      await tester.pumpAndSettle();

      final button = find.text('Envoyer un feedback');
      await tester.scrollUntilVisible(button, 300, scrollable: find.byType(Scrollable).first);
      expect(button, findsOneWidget);
      await tester.tap(button);
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'Ça plante au lancement');
      await tester.tap(find.widgetWithText(FilledButton, 'Envoyer'));
      // Bounded pumps, not pumpAndSettle — the SnackBar has its own timed
      // dismissal, and settling would run straight past its display
      // window (matches this suite's established caution elsewhere about
      // pumpAndSettle racing timed/async UI).
      await tester.runAsync(() async {
        await Future<void>.delayed(Duration.zero);
      });
      await tester.pump();
      await tester.pump();

      expect(sentFields?['text'], contains('Ça plante au lancement'));
      expect(find.text('Feedback envoyé, merci !'), findsOneWidget);
    });

    testWidgets('shows an inline error and keeps the dialog open on failure',
        (tester) async {
      final client = MockClient((request) async => http.Response('error', 500));

      await tester.pumpWidget(wrapConfiguredScreen(client));
      await tester.pumpAndSettle();

      final button = find.text('Envoyer un feedback');
      await tester.scrollUntilVisible(button, 300, scrollable: find.byType(Scrollable).first);
      await tester.tap(button);
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'Test');
      await tester.tap(find.widgetWithText(FilledButton, 'Envoyer'));
      await tester.runAsync(() async {
        await Future<void>.delayed(Duration.zero);
      });
      await tester.pump();
      await tester.pump();

      expect(find.text("L'envoi a échoué. Réessayez plus tard."), findsOneWidget);
      // Dialog stayed open — the text field is still there to retry from.
      expect(find.byType(TextField), findsOneWidget);
    });
  });

  testWidgets('entering an API key and tapping Save shows the saved snackbar',
      (tester) async {
    await tester.pumpWidget(wrapScreen());
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'AIzaTestKey123');
    // #260: the new "Langue de l'application" section pushed this button
    // below the fold — needs an explicit scroll like the other off-screen
    // finders in this file (ListView only builds children near the
    // viewport, not the whole list).
    final saveButton = find.text('Sauvegarder');
    await tester.scrollUntilVisible(saveButton, 300,
        scrollable: find.byType(Scrollable).first);
    // AudioGuideService.setGeminiApiKey does real SecureKeyStorage I/O —
    // needs tester.runAsync() (see history_screen_test.dart's file doc for
    // why: testWidgets()'s fake-async zone never resolves real async I/O
    // otherwise).
    await tester.runAsync(() async {
      await tester.tap(saveButton);
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
