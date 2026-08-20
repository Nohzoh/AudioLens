import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfiNoIsolate;

  late Directory tmpDir;
  late SettingsService settings;
  late AudioGuideService guide;
  late HistoryService history;

  setUp(() async {
    tmpDir = await Directory.systemTemp.createTemp('home_screen_test');
    SharedPreferences.setMockInitialValues({});
    setUpSecureStorageMock();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_pathProviderChannel, (call) async {
      if (call.method == 'getApplicationDocumentsDirectory') return tmpDir.path;
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
}
