import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:audiolens/services/audio_guide_service.dart';
import 'package:audiolens/services/history_service.dart';
import 'package:audiolens/services/settings_service.dart';
import 'package:audiolens/widgets/home_suggestions.dart';
import '../support/service_fakes.dart';

// #556/#551
const _pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfiNoIsolate;

  late Directory tmpDir;
  late SettingsService settings;
  late HistoryService history;
  late String image;

  setUp(() async {
    tmpDir = await Directory.systemTemp.createTemp('home_suggestions_test');
    SharedPreferences.setMockInitialValues({});
    setUpSecureStorageMock();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_pathProviderChannel, (call) async => tmpDir.path);
    settings = SettingsService();
    await settings.init();
    history = HistoryService();
    await history.init(dbPath: '${tmpDir.path}/history.db');
    image = '${tmpDir.path}/p.jpg';
    File(image).writeAsBytesSync([0xFF, 0xD8, 0xFF, 0xD9]);
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_pathProviderChannel, null);
    await tmpDir.delete(recursive: true);
  });

  Future<void> pump(WidgetTester tester, {bool? wifi}) async {
    await tester.runAsync(() => tester.pumpWidget(wrapWithProviders(
          Scaffold(body: HomeSuggestions(unmetered: () async => wifi)),
          settings: settings,
          guide: AudioGuideService(nativeTtsService: FakeNativeTts()),
          history: history,
        )));
    await tester.pump();
  }

  testWidgets('photos set aside and the last guide are offered', (tester) async {
    await tester.runAsync(() async {
      final done = await history.addPendingEntry(imagePath: image);
      await history.completeEntry(entryId: done.id!, title: 'Les tours Duo', script: 'Texte.');
      await history.addCapturedEntry(imagePath: image, gpsLatitude: 48.8, gpsLongitude: 2.3);
      await history.addCapturedEntry(imagePath: image);
    });
    await pump(tester, wifi: true);

    expect(find.text('2 photos à analyser'), findsOneWidget);
    expect(find.text('Vous êtes en Wi-Fi : bon moment pour les analyser.'), findsOneWidget);
    expect(find.text('Tout analyser'), findsOneWidget);
    expect(find.text('Réécouter le dernier guide'), findsOneWidget);
    expect(find.text('Les tours Duo'), findsOneWidget);
  });

  testWidgets('no pending card without photos set aside', (tester) async {
    await tester.runAsync(() async {
      final done = await history.addPendingEntry(imagePath: image);
      await history.completeEntry(entryId: done.id!, title: 'T', script: 'S.');
    });
    await pump(tester, wifi: false);
    expect(find.text('Tout analyser'), findsNothing);
    expect(find.text('Réécouter le dernier guide'), findsOneWidget);
  });
}
