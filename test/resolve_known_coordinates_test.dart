import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:audiolens/l10n/app_localizations.dart';
import 'package:audiolens/screens/map_picker_screen.dart';
import 'package:audiolens/services/history_service.dart';
import 'package:audiolens/utils/analysis_runner.dart';

// MapPickerScreen.initState best-effort-centers the map on the device's
// current position via LocationService.getCurrentLocation(), which wraps
// its channel call in a real Future.timeout() — left unmocked, that
// leaves a real pending Timer scheduled well past the test's own
// lifecycle ("A Timer is still pending even after the widget tree was
// disposed"). Mocking the channel to resolve immediately avoids it.
const _locationChannel = MethodChannel('audio_guide/location');

/// resolveKnownCoordinatesForRelaunch() extends knownCoordinatesFromEntry()
/// (tested in known_coordinates_from_entry_test.dart) with a map-picker
/// fallback for retry/deferred-capture relaunches that have no saved GPS —
/// instead of silently falling through to the device's current real-time
/// position, which could be a different place entirely if time has passed.
HistoryEntry _entryWith({double? lat, double? lon, String? source}) => HistoryEntry(
      imagePath: '/tmp/x.jpg',
      title: 't',
      script: 's',
      createdAt: DateTime(2026),
      gpsLatitude: lat,
      gpsLongitude: lon,
      gpsSource: source,
    );

Widget _harness(Future<void> Function(BuildContext context) onPressed) {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Builder(
      builder: (context) => ElevatedButton(
        onPressed: () => onPressed(context),
        child: const Text('go'),
      ),
    ),
  );
}

void main() {
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_locationChannel, (call) async {
      if (call.method == 'requestLocation') return {'status': 'denied'};
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_locationChannel, null);
  });

  testWidgets('returns the saved coordinates directly, without opening the map picker',
      (tester) async {
    ({double lat, double lon, String source})? result;
    await tester.pumpWidget(_harness((context) async {
      result = await resolveKnownCoordinatesForRelaunch(
          context, _entryWith(lat: 48.86, lon: 2.33, source: 'exif'));
    }));

    await tester.tap(find.text('go'));
    await tester.pump();

    expect(find.byType(MapPickerScreen), findsNothing);
    expect(result, isNotNull);
    expect(result!.lat, 48.86);
    expect(result!.lon, 2.33);
    expect(result!.source, 'exif');
  });

  testWidgets('opens the map picker when no coordinates are saved, and returns the picked point',
      (tester) async {
    ({double lat, double lon, String source})? result;
    await tester.pumpWidget(_harness((context) async {
      result = await resolveKnownCoordinatesForRelaunch(context, _entryWith());
    }));

    await tester.tap(find.text('go'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(MapPickerScreen), findsOneWidget);

    tester.state<NavigatorState>(find.byType(Navigator).first).pop(const LatLng(45.0, 5.0));
    await tester.pump();

    expect(result, isNotNull);
    expect(result!.lat, 45.0);
    expect(result!.lon, 5.0);
    expect(result!.source, 'map');
  });

  testWidgets('returns null when no coordinates are saved and the user backs out of the map picker',
      (tester) async {
    ({double lat, double lon, String source})? result;
    var completed = false;
    await tester.pumpWidget(_harness((context) async {
      result = await resolveKnownCoordinatesForRelaunch(context, _entryWith());
      completed = true;
    }));

    await tester.tap(find.text('go'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(MapPickerScreen), findsOneWidget);

    tester.state<NavigatorState>(find.byType(Navigator).first).pop();
    await tester.pump();

    expect(completed, isTrue);
    expect(result, isNull);
  });
}
