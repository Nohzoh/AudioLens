import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:audiolens/screens/onboarding_screen.dart';
import 'package:audiolens/services/audio_guide_service.dart';
import 'package:audiolens/services/gemini_nano_service.dart';
import 'package:audiolens/services/history_service.dart';
import 'package:audiolens/services/settings_service.dart';
import '../support/service_fakes.dart';

class _FakeNano extends GeminiNanoService {
  _FakeNano({required this.available});
  final bool available;

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<void> initialize() async {}
}

/// #298 — the carousel replacing the old single "enter your API key"
/// gate. Deliberately doesn't exercise real page-swipe gestures (the
/// "Suivant"/"Passer" buttons drive the same PageController, simpler and
/// just as representative of the actual navigation path a user takes).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfiNoIsolate;

  late Directory tmpDir;
  late SettingsService settings;
  late HistoryService history;

  setUp(() async {
    tmpDir = await Directory.systemTemp.createTemp('onboarding_screen_test');
    SharedPreferences.setMockInitialValues({});
    setUpSecureStorageMock();
    settings = SettingsService();
    await settings.init();
    history = HistoryService();
    await history.init(dbPath: '${tmpDir.path}/history.db');
  });

  tearDown(() async {
    tearDownSecureStorageMock();
    await tmpDir.delete(recursive: true);
  });

  Future<AudioGuideService> buildGuide({required bool nanoAvailable}) async {
    final guide = AudioGuideService(
      nativeTtsService: FakeNativeTts(),
      nanoService: _FakeNano(available: nanoAvailable),
    );
    await guide.init();
    return guide;
  }

  Widget wrapScreen(AudioGuideService guide) => wrapWithProviders(
        const OnboardingScreen(),
        settings: settings,
        guide: guide,
        history: history,
      );

  testWidgets('starts on the intro page', (tester) async {
    final guide = await buildGuide(nanoAvailable: false);
    await tester.pumpWidget(wrapScreen(guide));
    await tester.pumpAndSettle();

    expect(find.text('AudioLens'), findsOneWidget);
  });

  testWidgets('Suivant advances through every page to the final one, '
      'where it becomes the finish button', (tester) async {
    final guide = await buildGuide(nanoAvailable: false);
    await tester.pumpWidget(wrapScreen(guide));
    await tester.pumpAndSettle();

    // Page 1 -> 2
    await tester.tap(find.text('Suivant'));
    await tester.pumpAndSettle();
    expect(find.text('Comment ça marche ?'), findsOneWidget);

    // Page 2 -> 3
    await tester.tap(find.text('Suivant'));
    await tester.pumpAndSettle();
    expect(find.text('Deux modes d\'IA'), findsOneWidget);

    // Page 3 -> 4 (final)
    await tester.tap(find.text('Suivant'));
    await tester.pumpAndSettle();
    expect(find.text('Clé API Gemini'), findsOneWidget);
    expect(find.text('C\'est parti !'), findsOneWidget);
  });

  testWidgets('page 3 shows the device-unavailable status when Nano is not '
      'available', (tester) async {
    final guide = await buildGuide(nanoAvailable: false);
    await tester.pumpWidget(wrapScreen(guide));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Suivant'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Suivant'));
    await tester.pumpAndSettle();

    expect(find.textContaining("ne prend pas en charge l'IA locale"), findsOneWidget);
  });

  testWidgets('page 3 shows the positive device-available status when Nano '
      'is available', (tester) async {
    final guide = await buildGuide(nanoAvailable: true);
    await tester.pumpWidget(wrapScreen(guide));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Suivant'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Suivant'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Disponible sur votre appareil'), findsOneWidget);
  });

  testWidgets('finishing without a key when Nano is unavailable shows an '
      'error and does not complete onboarding', (tester) async {
    final guide = await buildGuide(nanoAvailable: false);
    await tester.pumpWidget(wrapScreen(guide));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Suivant'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Suivant'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Suivant'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('C\'est parti !'));
    await tester.pumpAndSettle();

    expect(settings.isOnboardingComplete, isFalse);
    expect(find.text('Entrez votre clé API'), findsOneWidget);
  });

  testWidgets('finishing without a key when Nano is available completes '
      'onboarding with no API key stored', (tester) async {
    final guide = await buildGuide(nanoAvailable: true);
    await tester.pumpWidget(wrapScreen(guide));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Suivant'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Suivant'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Suivant'));
    await tester.pumpAndSettle();

    await tester.runAsync(() async {
      await tester.tap(find.text('C\'est parti !'));
    });
    await tester.pump();
    await tester.pump();

    expect(settings.isOnboardingComplete, isTrue);
    expect(settings.geminiApiKey, isEmpty);
  });

  testWidgets('entering a key and finishing stores it and completes '
      'onboarding', (tester) async {
    final guide = await buildGuide(nanoAvailable: false);
    await tester.pumpWidget(wrapScreen(guide));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Suivant'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Suivant'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Suivant'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'AIza-test-key');
    await tester.runAsync(() async {
      await tester.tap(find.text('C\'est parti !'));
    });
    await tester.pump();
    await tester.pump();

    expect(settings.isOnboardingComplete, isTrue);
    expect(settings.geminiApiKey, 'AIza-test-key');
  });
}
