import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:audiolens/screens/history_screen.dart';
import 'package:audiolens/services/audio_guide_service.dart';
import 'package:audiolens/services/history_service.dart';
import 'package:audiolens/services/settings_service.dart';
import '../support/service_fakes.dart';

/// T105 — first widget-level coverage for HistoryScreen: the empty state
/// and each AnalysisStatus's distinct rendering (this is the exact
/// interactive surface T105 flagged as unprotected). Tap-driven retry/
/// launch-analysis flows (which run the full analysis pipeline) are left
/// for a later pass — those need network/location channel mocking beyond
/// this pass's scope; here we verify the "tap to retry"/"tap to analyze"
/// treatment renders correctly instead.
const _pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  // databaseFactoryFfi's default worker-isolate model hangs indefinitely
  // under testWidgets()'s test zone (confirmed empirically — works fine
  // in plain test() files like history_service_crud_test.dart, but any
  // DB call here never returns). The no-isolate variant runs SQLite
  // synchronously on the same isolate instead — still real SQLite via
  // FFI, just without the isolate hop that testWidgets' zone breaks.
  databaseFactory = databaseFactoryFfiNoIsolate;

  late Directory tmpDir;
  late String dbPath;
  late String imagePath;
  late HistoryService history;
  late SettingsService settings;
  late AudioGuideService guide;

  setUp(() async {
    tmpDir = await Directory.systemTemp.createTemp('history_screen_test');
    dbPath = join(tmpDir.path, 'history.db');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_pathProviderChannel, (call) async {
      if (call.method == 'getApplicationDocumentsDirectory') return tmpDir.path;
      return null;
    });
    imagePath = join(tmpDir.path, 'photo.jpg');
    // A real (if tiny) decodable JPEG — Image.file() in HistoryDetailScreen
    // actually decodes this, unlike the plain SOI/EOI-marker placeholder
    // bytes used by non-widget CRUD tests.
    final placeholder = img.Image(width: 2, height: 2);
    img.fill(placeholder, color: img.ColorRgb8(120, 60, 200));
    File(imagePath).writeAsBytesSync(img.encodeJpg(placeholder));

    history = HistoryService();
    await history.init(dbPath: dbPath);
    settings = SettingsService();
    guide = AudioGuideService(nativeTtsService: FakeNativeTts());
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_pathProviderChannel, null);
    await tmpDir.delete(recursive: true);
  });

  Widget wrapScreen() => wrapWithProviders(
        const HistoryScreen(),
        settings: settings,
        guide: guide,
        history: history,
      );

  testWidgets('empty state shows the empty title/subtitle', (tester) async {
    await tester.pumpWidget(wrapScreen());
    await tester.pumpAndSettle();

    expect(find.text('Aucune visite enregistrée'), findsOneWidget);
    expect(find.text('Prenez une photo pour commencer'), findsOneWidget);
  });

  testWidgets('a complete entry renders its title and navigates to the detail screen on tap',
      (tester) async {
    // Real dart:io file I/O (HistoryService's image copy) never completes
    // if awaited directly inside a testWidgets() callback — its default
    // binding runs in a fake-async zone that only advances via pump().
    // tester.runAsync() steps outside that zone for real async work.
    await tester.runAsync(() => history.addEntry(
          imagePath: imagePath,
          title: 'La Joconde',
          script: 'Bienvenue.',
        ));

    await tester.pumpWidget(wrapScreen());
    await tester.pumpAndSettle();

    expect(find.text('La Joconde'), findsOneWidget);

    await tester.tap(find.text('La Joconde'));
    // Deliberately bounded pumps rather than pumpAndSettle(): the detail
    // screen's tree isn't relevant here (out of scope, see file doc), and
    // fully settling can hang if anything in it schedules an animation
    // that never completes on its own (e.g. an indeterminate spinner).
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(HistoryDetailScreen), findsOneWidget);
  });

  testWidgets('a failed entry shows the "tap to retry" treatment', (tester) async {
    await tester.runAsync(() async {
      final pending = await history.addPendingEntry(imagePath: imagePath);
      await history.failEntry(pending.id!);
    });

    await tester.pumpWidget(wrapScreen());
    await tester.pumpAndSettle();

    expect(find.text('Échec — appuyer pour réessayer'), findsOneWidget);
    expect(find.byIcon(Icons.refresh), findsOneWidget);
  });

  testWidgets('a captured entry shows the "tap to analyze" treatment', (tester) async {
    await tester.runAsync(() => history.addCapturedEntry(
          imagePath: imagePath,
          gpsLatitude: 48.86,
          gpsLongitude: 2.33,
          gpsSource: 'exif',
        ));

    await tester.pumpWidget(wrapScreen());
    await tester.pumpAndSettle();

    expect(find.text('Capturé — appuyer pour analyser'), findsOneWidget);
    expect(find.byIcon(Icons.cloud_off_outlined), findsOneWidget);
  });
}
