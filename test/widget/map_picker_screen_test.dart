import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:audiolens/l10n/app_localizations.dart';
import 'package:audiolens/screens/map_picker_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // MapPickerScreen.initState() calls LocationService.getCurrentLocation()
  // as a best-effort starting point — without this mock, the unregistered
  // channel call hangs for the full 10s default timeout (RemoteConfig
  // default), which the test binding reports as a leaked pending Timer.
  const locationChannel = MethodChannel('audio_guide/location');

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      locationChannel,
      (call) async => call.method == 'requestLocation' ? {'status': 'denied'} : null,
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(locationChannel, null);
  });

  Widget wrap(Widget child) => MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: child,
      );

  testWidgets('locks the map to north-up (#123) — rotate gesture disabled',
      (tester) async {
    await tester.pumpWidget(wrap(const MapPickerScreen()));
    await tester.pump();

    final map = tester.widget<FlutterMap>(find.byType(FlutterMap));
    final flags = map.options.interactionOptions.flags;

    expect(flags & InteractiveFlag.rotate, 0);
    // Panning/pinch-zoom/tap-to-pick must still work — only rotation is locked.
    expect(flags & InteractiveFlag.drag, isNot(0));
    expect(flags & InteractiveFlag.pinchZoom, isNot(0));
  });

  testWidgets('shows a place search field (#123)', (tester) async {
    await tester.pumpWidget(wrap(const MapPickerScreen()));
    await tester.pump();

    expect(find.byType(TextField), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'Tour Eiffel');
    await tester.pump();

    expect(find.text('Tour Eiffel'), findsOneWidget);
    // Clearing it drops the "clear" affordance again.
    expect(find.byIcon(Icons.clear), findsOneWidget);
    await tester.tap(find.byIcon(Icons.clear));
    await tester.pump();
    expect(find.byIcon(Icons.clear), findsNothing);
  });
}
