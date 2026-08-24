import 'dart:async';
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
import 'package:audiolens/widgets/background_photo.dart';
import '../support/service_fakes.dart';

/// T105 — first widget-level coverage for HistoryScreen: the empty state
/// and each AnalysisStatus's distinct rendering (this is the exact
/// interactive surface T105 flagged as unprotected). Tap-driven retry/
/// launch-analysis flows (which run the full analysis pipeline) are left
/// for a later pass — those need network/location channel mocking beyond
/// this pass's scope; here we verify the "tap to retry"/"tap to analyze"
/// treatment renders correctly instead.
const _pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');
const _audioPlayerChannel = MethodChannel('audio_guide/audio_player');
// FakeNativeTts only overrides speak() — stop() (called from
// HistoryDetailScreen.dispose(), #148) falls through to the real
// NativeTtsService/flutter_tts implementation, which needs this mocked
// or it throws MissingPluginException during the widget's teardown.
const _flutterTtsChannel = MethodChannel('flutter_tts');

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
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_flutterTtsChannel, (call) async => 1);
    // Default no-op handler — HistoryDetailScreen.dispose() always calls
    // 'stop' on this channel regardless of whether anything was playing,
    // so any test that opens the detail screen needs it mocked or its
    // teardown throws MissingPluginException (which then bleeds into
    // whichever test happens to run next). Tests that actually exercise
    // playback override this locally with their own handler.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_audioPlayerChannel, (call) async => null);
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
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_flutterTtsChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_audioPlayerChannel, null);
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

  // #149 — the Save/Copy/Report row used to be a plain Row, which could
  // overflow on a narrow screen with the (longer) French labels this
  // test suite renders in. Wrap (not a width assumption) is what's
  // actually being verified here: any RenderFlex overflow throws during
  // layout and surfaces via tester.takeException().
  testWidgets('the Save/Copy/Report row does not overflow on a narrow screen', (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1.0;

    await tester.runAsync(() => history.addEntry(
          imagePath: imagePath,
          title: 'La Joconde',
          script: 'Bienvenue.',
        ));

    await tester.pumpWidget(wrapScreen());
    await tester.pumpAndSettle();
    await tester.tap(find.text('La Joconde'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(HistoryDetailScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
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

  // #148 — skip controls reached parity with player_screen.dart, but only
  // for the seekable cached-WAV path. Native TTS speaks live with no
  // seekable position, so the buttons must stay hidden there rather than
  // appear and silently do nothing (same reasoning as
  // AudioGuideService.canSkip on the player screen).
  group('skip controls', () {
    /// Opens the detail screen for the only entry in history.
    Future<void> openDetail(WidgetTester tester) async {
      await tester.pumpWidget(wrapScreen());
      await tester.pumpAndSettle();
      await tester.tap(find.text('La Joconde'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }

    testWidgets('are hidden before playback starts', (tester) async {
      await tester.runAsync(() async {
        final e = await history.addEntry(
          imagePath: imagePath,
          title: 'La Joconde',
          script: 'Bienvenue.',
        );
        final wav = join(tmpDir.path, 'cached.wav');
        File(wav).writeAsBytesSync(List.filled(64, 0));
        await history.saveAudioPath(e.id!, wav, ttsModel: 'gemini-tts');
      });

      await openDetail(tester);

      expect(find.byIcon(Icons.replay_10), findsNothing);
      expect(find.byIcon(Icons.forward_10), findsNothing);
    });

    testWidgets('appear while cached audio is playing', (tester) async {
      await tester.runAsync(() async {
        final e = await history.addEntry(
          imagePath: imagePath,
          title: 'La Joconde',
          script: 'Bienvenue.',
        );
        final wav = join(tmpDir.path, 'cached.wav');
        File(wav).writeAsBytesSync(List.filled(64, 0));
        await history.saveAudioPath(e.id!, wav, ttsModel: 'gemini-tts');
      });

      // playWav must not complete: its completion is what flips
      // _isPlaying back to false, which would hide the buttons again
      // before we can assert on them. Other calls (seek/stop) return
      // normally.
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_audioPlayerChannel, (call) {
        calls.add(call);
        if (call.method == 'playWav') return Completer<void>().future;
        return Future<dynamic>.value(null);
      });
      addTearDown(() => TestDefaultBinaryMessengerBinding
          .instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_audioPlayerChannel, null));

      await openDetail(tester);
      await tester.tap(find.text('Écouter le commentaire'));
      await tester.pump();

      expect(find.byIcon(Icons.replay_10), findsOneWidget);
      expect(find.byIcon(Icons.forward_10), findsOneWidget);

      await tester.tap(find.byIcon(Icons.forward_10));
      await tester.pump();
      expect(
        calls.map((c) => c.method),
        contains('seekForward'),
      );
    });

    // hasAudio alone gates cached playback — deliberately not
    // `hasAudio && ttsModel == 'gemini-tts'`: a legacy 'piper' cached file
    // plays through the same MediaPlayer and seeks just as well.
    testWidgets('appear for a legacy piper cached file too', (tester) async {
      await tester.runAsync(() async {
        final e = await history.addEntry(
          imagePath: imagePath,
          title: 'La Joconde',
          script: 'Bienvenue.',
        );
        final wav = join(tmpDir.path, 'legacy.wav');
        File(wav).writeAsBytesSync(List.filled(64, 0));
        await history.saveAudioPath(e.id!, wav, ttsModel: 'piper');
      });

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_audioPlayerChannel, (call) {
        if (call.method == 'playWav') return Completer<void>().future;
        return Future<dynamic>.value(null);
      });
      addTearDown(() => TestDefaultBinaryMessengerBinding
          .instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_audioPlayerChannel, null));

      await openDetail(tester);
      await tester.tap(find.text('Écouter le commentaire'));
      await tester.pump();

      expect(find.byIcon(Icons.replay_10), findsOneWidget);
    });

    testWidgets('stay hidden for a native-TTS entry, which has no seekable position',
        (tester) async {
      await tester.runAsync(() async {
        final e = await history.addEntry(
          imagePath: imagePath,
          title: 'La Joconde',
          script: 'Bienvenue.',
        );
        // Native fallback: a ttsModel is recorded but no audio file exists.
        await history.saveTtsModel(e.id!, 'native-tts', ttsFallback: true);
      });

      await openDetail(tester);
      await tester.tap(find.text('Écouter le commentaire'));
      await tester.pump();

      expect(find.byIcon(Icons.replay_10), findsNothing);
      expect(find.byIcon(Icons.forward_10), findsNothing);
    });
  });

  // #190 — _liveEntry(context) reads HistoryService via context.read, so
  // this screen never rebuilt on its own when rotateEntry()/toggleFavorite()
  // notified a change; the new state only became visible once some
  // unrelated setState (e.g. toggling photo mode) happened to force a
  // rebuild that re-read it fresh.
  group('rotate/favorite update the detail screen immediately (#190)', () {
    Future<void> openDetail(WidgetTester tester) async {
      await tester.pumpWidget(wrapScreen());
      await tester.pumpAndSettle();
      await tester.tap(find.text('La Joconde'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }

    testWidgets('tapping rotate updates BackgroundPhoto without leaving the screen',
        (tester) async {
      await tester.runAsync(() => history.addEntry(
            imagePath: imagePath,
            title: 'La Joconde',
            script: 'Bienvenue.',
          ));

      await openDetail(tester);
      expect(
        tester.widget<BackgroundPhoto>(find.byType(BackgroundPhoto)).rotationQuarters,
        0,
      );

      await tester.tap(find.byTooltip('Pivoter la photo'));
      await tester.pump();

      expect(
        tester.widget<BackgroundPhoto>(find.byType(BackgroundPhoto)).rotationQuarters,
        1,
      );
    });

    testWidgets('tapping favorite updates the star icon without leaving the screen',
        (tester) async {
      await tester.runAsync(() => history.addEntry(
            imagePath: imagePath,
            title: 'La Joconde',
            script: 'Bienvenue.',
          ));

      // Scoped by tooltip, not find.byIcon(Icons.star): the underlying
      // HistoryScreen list stays mounted under the pushed detail route
      // and has its own unrelated, always-present Icons.star (the
      // "Favorites" filter chip's avatar), which byIcon would also match.
      await openDetail(tester);
      expect(find.byTooltip('Ajouter aux favoris'), findsOneWidget);
      expect(find.byTooltip('Retirer des favoris'), findsNothing);

      await tester.tap(find.byTooltip('Ajouter aux favoris'));
      await tester.pump();

      expect(find.byTooltip('Retirer des favoris'), findsOneWidget);
      expect(find.byTooltip('Ajouter aux favoris'), findsNothing);
    });
  });
}
