import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:audiolens/screens/player_screen.dart';
import 'package:audiolens/services/audio_guide_service.dart';
import 'package:audiolens/services/history_service.dart';
import 'package:audiolens/services/settings_service.dart';
import 'package:audiolens/utils/analysis_runner.dart';
import '../support/service_fakes.dart';

/// #174 — runAnalysisAndNavigate used to push a fresh PlayerScreen
/// unconditionally, before ever checking whether an analysis was already
/// running, so a second attempt always got its own screen dropped
/// straight into AudioGuideService's "already in progress" guard.
class _BusyAudioGuideService extends AudioGuideService {
  _BusyAudioGuideService({required super.nativeTtsService});

  @override
  bool get isBusy => true;
}

const _pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  // databaseFactoryFfi's default worker-isolate model hangs indefinitely
  // under testWidgets()'s test zone (see history_screen_test.dart's same
  // comment) — the no-isolate variant runs SQLite synchronously instead.
  databaseFactory = databaseFactoryFfiNoIsolate;

  late Directory tmpDir;
  late String imagePath;
  late HistoryService history;
  late SettingsService settings;

  setUp(() async {
    tmpDir = await Directory.systemTemp.createTemp('analysis_runner_test');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_pathProviderChannel, (call) async {
      if (call.method == 'getApplicationDocumentsDirectory') return tmpDir.path;
      return null;
    });
    imagePath = join(tmpDir.path, 'photo.jpg');
    File(imagePath).writeAsBytesSync([0xFF, 0xD8, 0xFF, 0xD9]);

    history = HistoryService();
    await history.init(dbPath: join(tmpDir.path, 'history.db'));
    settings = SettingsService();
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_pathProviderChannel, null);
    await tmpDir.delete(recursive: true);
  });

  testWidgets(
      'runAnalysisAndNavigate does not push a second PlayerScreen while one is already busy, '
      'and tells the user instead', (tester) async {
    final guide = _BusyAudioGuideService(nativeTtsService: FakeNativeTts());
    // Real dart:io/sqflite I/O directly inside a testWidgets() body hangs
    // indefinitely under its fake-async zone (confirmed empirically) —
    // tester.runAsync() steps outside that zone for this one call.
    late HistoryEntry pending;
    await tester.runAsync(() async {
      pending = await history.addPendingEntry(imagePath: imagePath);
    });

    late BuildContext capturedContext;
    await tester.pumpWidget(wrapWithProviders(
      Builder(builder: (context) {
        capturedContext = context;
        return Scaffold(
          body: ElevatedButton(
            onPressed: () => runAnalysisAndNavigate(
              context: context,
              imageFile: File(imagePath),
              entryId: pending.id!,
              source: 'captured',
            ),
            child: const Text('go'),
          ),
        );
      }),
      settings: settings,
      guide: guide,
      history: history,
    ));

    await tester.tap(find.text('go'));
    await tester.pump();
    // Bounded pumps rather than pumpAndSettle(): if this regressed and a
    // PlayerScreen genuinely got pushed, its own analysis pipeline could
    // keep scheduling frames indefinitely in this environment.
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(PlayerScreen), findsNothing);
    expect(find.text('Une analyse est déjà en cours.'), findsOneWidget);
    expect(Navigator.of(capturedContext).canPop(), isFalse);
  });
}
