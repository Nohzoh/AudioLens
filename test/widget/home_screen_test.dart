import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:audiolens/screens/home_screen.dart';
import 'package:audiolens/services/audio_guide_service.dart';
import 'package:audiolens/services/history_service.dart';
import 'package:audiolens/services/settings_service.dart';
import '../support/service_fakes.dart';

/// T105 — smoke-level coverage only for HomeScreen: it's by far the
/// heaviest screen (camera/location/share-intent/T128 update banner),
/// so full interaction coverage is left for a later pass (would need
/// image_picker/geolocator channel mocking beyond this pass's budget).
/// This guards the one thing that matters most for a screen this size:
/// it renders without throwing, with its main CTA visible.
const _pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');
const _audioPlayerChannel = MethodChannel('audio_guide/audio_player');
// HomeScreen.initState() subscribes to both of these (share-intent/quick-
// capture warm-start streams) unconditionally — without a stream handler,
// cancelling the subscription at teardown throws MissingPluginException,
// which (being async) surfaces during whichever test runs next rather
// than the one that actually triggered it.
const _shareIntentStreamChannel = EventChannel('audio_guide/share_intent_stream');
const _quickCaptureStreamChannel = EventChannel('audio_guide/quick_capture_stream');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfiNoIsolate;

  // Registered once for the whole file, not per-test: these are trivial,
  // stateless no-op handlers, and re-registering them in every setUp/
  // tearDown left a window where a previous test's still-in-flight
  // EventChannel listen/cancel (both async) could fire while no handler
  // was registered, throwing MissingPluginException that got attributed
  // to whichever test happened to be running at that moment.
  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockStreamHandler(_shareIntentStreamChannel,
            MockStreamHandler.inline(onListen: (_, __) {}, onCancel: (_) {}));
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockStreamHandler(_quickCaptureStreamChannel,
            MockStreamHandler.inline(onListen: (_, __) {}, onCancel: (_) {}));
  });

  late Directory tmpDir;
  late SettingsService settings;
  late AudioGuideService guide;
  late HistoryService history;
  late List<MethodCall> audioPlayerCalls;
  late Completer<dynamic> playWavCompleter;

  setUp(() async {
    tmpDir = await Directory.systemTemp.createTemp('home_screen_test');
    audioPlayerCalls = [];
    playWavCompleter = Completer<dynamic>();
    SharedPreferences.setMockInitialValues({});
    setUpSecureStorageMock();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_pathProviderChannel, (call) async {
      if (call.method == 'getApplicationDocumentsDirectory') return tmpDir.path;
      return null;
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_audioPlayerChannel, (call) async {
      audioPlayerCalls.add(call);
      // playWav's real native call only resolves once playback actually
      // finishes (or is stopped) — resolving it immediately here would
      // race HomeScreen's own "played to completion" reset against the
      // test's "now playing" assertions. Never completes on its own;
      // tests that care can resolve it via _completePlayWav().
      if (call.method == 'playWav') return playWavCompleter.future;
      return null;
    });

    settings = SettingsService();
    await settings.init();
    guide = AudioGuideService(nativeTtsService: FakeNativeTts());
    history = HistoryService();
    await history.init(dbPath: '${tmpDir.path}/history.db');
  });

  tearDown(() async {
    tearDownSecureStorageMock();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_pathProviderChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_audioPlayerChannel, null);
    await tmpDir.delete(recursive: true);
  });

  testWidgets('renders without throwing and shows the "take a photo" CTA',
      (tester) async {
    await tester.runAsync(() => tester.pumpWidget(wrapWithProviders(
          const HomeScreen(),
          settings: settings,
          guide: guide,
          history: history,
        )));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Prendre une photo'), findsOneWidget);
  });

  // #127 — a "Recently visited" tile with cached audio gets a small
  // play/pause control so its narration can be replayed/paused without
  // opening the detail screen.
  group('play/pause on a "Recently visited" tile with cached audio (#127)', () {
    Future<void> pumpWithCachedAudioEntry(WidgetTester tester) async {
      // Default test surface (800x600) is too short once the grid has a
      // real entry: home_screen.dart's "empty state" hint below the grid
      // is unconditional (not gated on history.entries.isEmpty), and on
      // a viewport this cramped that combination overflows — pre-existing,
      // unrelated to #127, and out of scope here; a taller surface avoids
      // tripping it so this test can focus on play/pause.
      addTearDown(() => tester.view.resetPhysicalSize());
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;

      final placeholder = img.Image(width: 4, height: 4);
      img.fill(placeholder, color: img.ColorRgb8(80, 40, 160));
      final imagePath = '${tmpDir.path}/source.jpg';
      File(imagePath).writeAsBytesSync(img.encodeJpg(placeholder));
      final audioSourcePath = '${tmpDir.path}/source.wav';
      File(audioSourcePath).writeAsBytesSync([0, 1, 2, 3]);

      final entry = await tester.runAsync(() => history.addEntry(
            imagePath: imagePath,
            title: 'Tour Eiffel',
            script: 'Un monument emblematique.',
          ));
      await tester.runAsync(
        () => history.saveAudioPath(entry!.id!, audioSourcePath),
      );

      await tester.runAsync(() => tester.pumpWidget(wrapWithProviders(
            const HomeScreen(),
            settings: settings,
            guide: guide,
            history: history,
          )));
      await tester.pumpAndSettle();
    }

    testWidgets('shows a play icon, and tapping it starts cached playback',
        (tester) async {
      await pumpWithCachedAudioEntry(tester);

      expect(find.byIcon(Icons.play_arrow), findsOneWidget);

      await tester.tap(find.byIcon(Icons.play_arrow));
      await tester.pump();

      expect(audioPlayerCalls.map((c) => c.method), contains('playWav'));
      expect(find.byIcon(Icons.pause), findsOneWidget);
    });

    testWidgets('tapping again while playing pauses instead of restarting',
        (tester) async {
      await pumpWithCachedAudioEntry(tester);

      await tester.tap(find.byIcon(Icons.play_arrow));
      await tester.pump();
      audioPlayerCalls.clear();

      await tester.tap(find.byIcon(Icons.pause));
      await tester.pump();

      expect(audioPlayerCalls.map((c) => c.method), ['pause']);
      expect(find.byIcon(Icons.play_arrow), findsOneWidget);
    });

    testWidgets('tapping the play icon does not navigate to the detail screen',
        (tester) async {
      await pumpWithCachedAudioEntry(tester);

      await tester.tap(find.byIcon(Icons.play_arrow));
      await tester.pump();

      expect(find.text('Prendre une photo'), findsOneWidget);
    });
  });
}
