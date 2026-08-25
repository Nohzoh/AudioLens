import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:audiolens/screens/about_analysis_screen.dart';
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
// #131: only needed by the new "regenerate" tests, which call
// SettingsService.init() — that reads the API key via SecureKeyStorage,
// an unmocked platform channel here otherwise (mirrors
// settings_service_test.dart's own mock). Confirmed the hard way: without
// this, the read() call never resolves and the test hangs until package:
// test's 10-minute timeout, rather than a fast MissingPluginException.
const _secureStorageChannel =
    MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

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

      // #235: rotate moved into the overflow menu.
      await tester.tap(find.byTooltip('Plus d\'actions'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pivoter la photo'));
      await tester.pumpAndSettle();

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

  group('swipe between entries (#126)', () {
    // find.text('La Joconde') isn't unique enough to assert absence with:
    // the underlying HistoryScreen list stays mounted beneath the pushed
    // detail route (never replaced) and shows every entry's title too.
    // Reading the current top-most HistoryDetailScreen's own `entry`
    // avoids that ambiguity entirely.
    HistoryEntry currentDetailEntry(WidgetTester tester) =>
        tester.widget<HistoryDetailScreen>(find.byType(HistoryDetailScreen)).entry;

    testWidgets('a decisive left fling navigates to the next (older) entry', (tester) async {
      // addEntry inserts at index 0 (newest-first) — "Second Entry" ends
      // up newer/first, "La Joconde" older/second, so opening "Second
      // Entry" and swiping left (direction: +1, toward older) should land
      // on "La Joconde".
      await tester.runAsync(() => history.addEntry(
            imagePath: imagePath,
            title: 'La Joconde',
            script: 'Bienvenue.',
          ));
      await tester.runAsync(() => history.addEntry(
            imagePath: imagePath,
            title: 'Second Entry',
            script: 'Autre script.',
          ));

      await tester.pumpWidget(wrapScreen());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Second Entry'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));

      expect(currentDetailEntry(tester).title, 'Second Entry');

      await tester.fling(find.byType(HistoryDetailScreen), const Offset(-400, 0), 1000);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));

      expect(currentDetailEntry(tester).title, 'La Joconde');
    });

    testWidgets('a decisive fling past the last entry is a no-op', (tester) async {
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

      // Only entry in the list — swiping either direction has nowhere to go.
      await tester.fling(find.byType(HistoryDetailScreen), const Offset(-400, 0), 1000);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(currentDetailEntry(tester).title, 'La Joconde');
      expect(tester.takeException(), isNull);
    });
  });

  group('pinch-to-zoom reaches the photo through the gradient overlay (#204)', () {
    Future<void> openDetailInPhotoMode(WidgetTester tester) async {
      await tester.pumpWidget(wrapScreen());
      await tester.pumpAndSettle();
      await tester.tap(find.text('La Joconde'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      // #191's photo-mode toggle — zoomable is only true in this mode.
      await tester.tap(find.byTooltip('Mode photo'));
      await tester.pump();
    }

    testWidgets(
        'a two-finger pinch changes the InteractiveViewer transform, not just called-then-blocked',
        (tester) async {
      await tester.runAsync(() => history.addEntry(
            imagePath: imagePath,
            title: 'La Joconde',
            script: 'Bienvenue.',
          ));

      await openDetailInPhotoMode(tester);
      expect(find.byType(InteractiveViewer), findsOneWidget);

      final transformFinder = find.descendant(
        of: find.byType(InteractiveViewer),
        matching: find.byType(Transform),
      );
      final before = tester.widget<Transform>(transformFinder.first).transform;
      expect(before, Matrix4.identity());

      // A gradient Container sitting on top of BackgroundPhoto in the
      // Stack previously absorbed every touch before it reached
      // InteractiveViewer's own GestureDetector (BoxDecoration.hitTest()
      // defaults to true for its whole rectangular bounds regardless of
      // visual transparency) — this pinch would silently do nothing.
      final center = tester.getCenter(find.byType(InteractiveViewer));
      final gesture1 = await tester.startGesture(center - const Offset(20, 0));
      final gesture2 = await tester.startGesture(center + const Offset(20, 0));
      await tester.pump();
      await gesture1.moveBy(const Offset(-40, 0));
      await gesture2.moveBy(const Offset(40, 0));
      await tester.pump();
      await gesture1.up();
      await gesture2.up();
      await tester.pumpAndSettle();

      final after = tester.widget<Transform>(transformFinder.first).transform;
      expect(after, isNot(Matrix4.identity()));
    });
  });

  // #131 — the sheet's own render/pre-fill behavior only. Actually tapping
  // "Relancer" hands off to _retryAnalysis -> runAnalysisAndNavigate ->
  // AudioGuideService.analyzeAndPlay, which awaits real foreground-service/
  // notification-permission platform channels before it ever reaches the
  // (safely quick) "no AI service configured" early return — confirmed by
  // hitting a genuine hang (not a fast MissingPluginException) driving a
  // tap that far. Same class of thing this file's own doc comment already
  // scopes out for retry/launch flows; left for a pass that adds that
  // channel mocking rather than risking a flaky/hanging CI run here.
  group('regenerate with different settings (#131)', () {
    testWidgets('opens pre-filled from current settings for an entry with no saved style/language',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_secureStorageChannel, (call) async => null);
      addTearDown(() => TestDefaultBinaryMessengerBinding.instance
          .defaultBinaryMessenger
          .setMockMethodCallHandler(_secureStorageChannel, null));
      await settings.init();
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

      // #235: regenerate moved into the overflow menu.
      await tester.tap(find.byTooltip('Plus d\'actions'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Relancer avec d\'autres paramètres'));
      await tester.pumpAndSettle();

      // Default settings: 'immersive' style, 'Français' language.
      final immersiveChip =
          tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Immersif'));
      expect(immersiveChip.selected, isTrue);
      final frenchChip =
          tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Français'));
      expect(frenchChip.selected, isTrue);
    });
  });

  // #235 — only favorite/photo-mode stay always-visible; the rest moved
  // into an overflow menu so the least-recently-added icons (info,
  // delete) aren't scrolled off-screen and undiscoverable anymore.
  group('top bar overflow menu (#235)', () {
    Future<void> openDetail(WidgetTester tester) async {
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
    }

    testWidgets('rotate/regenerate/info/delete are not directly visible',
        (tester) async {
      await openDetail(tester);

      expect(find.byIcon(Icons.rotate_90_degrees_cw_outlined), findsNothing);
      expect(find.byIcon(Icons.tune), findsNothing);
      expect(find.byIcon(Icons.info_outline), findsNothing);
      expect(find.byIcon(Icons.delete_outline), findsNothing);
      // Favorite and photo-mode stay always-visible.
      expect(find.byTooltip('Ajouter aux favoris'), findsOneWidget);
      expect(find.byTooltip('Mode photo'), findsOneWidget);
    });

    testWidgets('opening the overflow menu reveals all 5 labeled actions',
        (tester) async {
      await openDetail(tester);

      await tester.tap(find.byTooltip('Plus d\'actions'));
      await tester.pumpAndSettle();

      expect(find.text('Ajouter à une collection'), findsOneWidget);
      expect(find.text('Pivoter la photo'), findsOneWidget);
      expect(find.text('Relancer avec d\'autres paramètres'), findsOneWidget);
      expect(find.text('À propos de cette analyse'), findsOneWidget);
      expect(find.text('Supprimer'), findsOneWidget);
    });

    testWidgets('tapping Info navigates to AboutAnalysisScreen', (tester) async {
      await openDetail(tester);

      await tester.tap(find.byTooltip('Plus d\'actions'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('À propos de cette analyse'));
      await tester.pumpAndSettle();

      expect(find.byType(AboutAnalysisScreen), findsOneWidget);
    });
  });
}
