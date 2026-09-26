import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:audiolens/screens/analyses_map_screen.dart';
import 'package:audiolens/screens/history_screen.dart';
import 'package:audiolens/services/audio_guide_service.dart';
import 'package:audiolens/services/history_service.dart';
import 'package:audiolens/services/settings_service.dart';
import '../support/service_fakes.dart';

/// #423 — map of analyses: which entries get a marker, the empty state,
/// the history filter carried over, and marker tap -> detail. Bounded
/// pump() around the map, never pumpAndSettle() on it: tile network calls
/// aren't mocked (same as mini_map_test.dart).
const _pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');
const _audioPlayerChannel = MethodChannel('audio_guide/audio_player');
const _flutterTtsChannel = MethodChannel('flutter_tts');

HistoryEntry _entry(int id,
        {double? lat,
        double? lon,
        AnalysisStatus status = AnalysisStatus.complete}) =>
    HistoryEntry(
      id: id,
      imagePath: '/nope.jpg',
      title: 'Entry $id',
      script: '',
      createdAt: DateTime(2026, 9, 1),
      status: status,
      gpsLatitude: lat,
      gpsLongitude: lon,
    );

void main() {
  group('groupAnalysesForMap', () {
    test('skips entries without coordinates and non-complete ones', () {
      final groups = groupAnalysesForMap([
        _entry(1, lat: 48.86, lon: 2.33),
        _entry(2),
        _entry(3, lat: 48.86),
        _entry(4, lat: 41.9, lon: 12.49, status: AnalysisStatus.captured),
        _entry(5, lat: 41.9, lon: 12.49, status: AnalysisStatus.failed),
        _entry(6, lat: 41.9, lon: 12.49, status: AnalysisStatus.pending),
      ]);
      expect(groups, hasLength(1));
      expect(groups.single.entries.single.id, 1);
      expect(groups.single.point.latitude, 48.86);
    });

    test('groups analyses a few meters apart, keeps distinct places apart', () {
      final groups = groupAnalysesForMap([
        _entry(1, lat: 48.86061, lon: 2.33761),
        _entry(2, lat: 48.86063, lon: 2.33758),
        _entry(3, lat: 41.9029, lon: 12.4534),
      ]);
      expect(groups, hasLength(2));
      expect(groups.first.entries.map((e) => e.id), [1, 2]);
      expect(groups.last.entries.map((e) => e.id), [3]);
    });
  });

  group('AnalysesMapScreen', () {
    TestWidgetsFlutterBinding.ensureInitialized();
    sqfliteFfiInit();
    // Same no-isolate factory as history_screen_test.dart, for the same
    // testWidgets-zone reason.
    databaseFactory = databaseFactoryFfiNoIsolate;

    late Directory tmpDir;
    late String imagePath;
    late HistoryService history;
    late SettingsService settings;
    late AudioGuideService guide;

    setUp(() async {
      tmpDir = await Directory.systemTemp.createTemp('analyses_map_test');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
              // Every directory, not just documents: flutter_map's tile
              // cache asks for the cache directory and throws on null.
              _pathProviderChannel,
              (call) async => tmpDir.path);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_flutterTtsChannel, (call) async => 1);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_audioPlayerChannel, (call) async => null);
      imagePath = join(tmpDir.path, 'photo.jpg');
      final placeholder = img.Image(width: 2, height: 2);
      File(imagePath).writeAsBytesSync(img.encodeJpg(placeholder));

      history = HistoryService();
      await history.init(dbPath: join(tmpDir.path, 'history.db'));
      settings = SettingsService();
      guide = AudioGuideService(nativeTtsService: FakeNativeTts());
    });

    tearDown(() async {
      for (final channel in [
        _pathProviderChannel,
        _flutterTtsChannel,
        _audioPlayerChannel
      ]) {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
      }
      await tmpDir.delete(recursive: true);
    });

    Future<HistoryEntry> addAnalysis(String title,
        {double? lat, double? lon}) async {
      final pending = await history.addPendingEntry(imagePath: imagePath);
      await history.completeEntry(
        entryId: pending.id!,
        title: title,
        script: 'Bienvenue.',
        gpsLatitude: lat,
        gpsLongitude: lon,
      );
      return history.entries.firstWhere((e) => e.id == pending.id);
    }

    Widget wrap(Widget child) => wrapWithProviders(child,
        settings: settings, guide: guide, history: history);

    testWidgets('shows the empty state when no analysis has a location',
        (tester) async {
      await tester.runAsync(() => addAnalysis('Sans GPS'));

      await tester.pumpWidget(wrap(const AnalysesMapScreen()));
      await tester.pump();

      expect(find.byType(FlutterMap), findsNothing);
      expect(find.textContaining("n'a encore de position"), findsOneWidget);
    });

    testWidgets('fits every marker when there are several places',
        (tester) async {
      await tester.runAsync(() async {
        await addAnalysis('Louvre', lat: 48.8606, lon: 2.3376);
        await addAnalysis('Colisée', lat: 41.8902, lon: 12.4922);
      });

      await tester.pumpWidget(wrap(const AnalysesMapScreen()));
      await tester.pump();

      final map = tester.widget<FlutterMap>(find.byType(FlutterMap));
      final fit = map.options.initialCameraFit;
      expect(fit, isA<FitBounds>());
      final bounds = (fit as FitBounds).bounds;
      expect(bounds.south, closeTo(41.8902, 1e-9));
      expect(bounds.north, closeTo(48.8606, 1e-9));
      expect(tester.takeException(), isNull);
    });

    testWidgets('applies the collection filter it was opened with',
        (tester) async {
      late int collectionId;
      await tester.runAsync(() async {
        final louvre = await addAnalysis('Louvre', lat: 48.8606, lon: 2.3376);
        await addAnalysis('Colisée', lat: 41.8902, lon: 12.4922);
        final paris = await history.createCollection('Paris');
        collectionId = paris.id!;
        await history.setEntryInCollection(louvre.id!, collectionId, true);
      });

      await tester
          .pumpWidget(wrap(AnalysesMapScreen(collectionId: collectionId)));
      await tester.pump();

      expect(find.text('Paris'), findsOneWidget); // app bar title
      final map = tester.widget<FlutterMap>(find.byType(FlutterMap));
      expect(map.options.initialCameraFit, isNull);
      expect(map.options.initialCenter.latitude, 48.8606);
    });

    testWidgets('tapping a marker previews it, then opens the detail',
        (tester) async {
      await tester
          .runAsync(() => addAnalysis('La Joconde', lat: 48.8606, lon: 2.3376));

      await tester.pumpWidget(wrap(const AnalysesMapScreen()));
      await tester.pump();

      await tester.tap(find.byIcon(Icons.location_pin));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('La Joconde'), findsOneWidget);

      await tester.tap(find.text('La Joconde'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(HistoryDetailScreen), findsOneWidget);
    });

    testWidgets('the history app bar opens the map', (tester) async {
      await tester
          .runAsync(() => addAnalysis('La Joconde', lat: 48.8606, lon: 2.3376));

      await tester.pumpWidget(wrap(const HistoryScreen()));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Carte des analyses'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(AnalysesMapScreen), findsOneWidget);
    });
  });
}
