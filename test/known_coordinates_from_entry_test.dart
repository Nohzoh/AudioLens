import 'package:flutter_test/flutter_test.dart';
import 'package:audiolens/services/history_service.dart';
import 'package:audiolens/utils/analysis_runner.dart';

/// knownCoordinatesFromEntry() is what makes a retry (of a failed analysis
/// or a T78 captured entry) reuse a previously resolved location instead
/// of re-resolving the device's current position — the actual fix behind
/// the "retry after failure used the wrong GPS" bug report.
void main() {
  HistoryEntry entryWith({double? lat, double? lon, String? source}) => HistoryEntry(
        imagePath: '/tmp/x.jpg',
        title: 't',
        script: 's',
        createdAt: DateTime(2026),
        gpsLatitude: lat,
        gpsLongitude: lon,
        gpsSource: source,
      );

  test('returns null when the entry has no saved coordinates', () {
    expect(knownCoordinatesFromEntry(entryWith()), isNull);
  });

  test('returns null when only latitude is present', () {
    expect(knownCoordinatesFromEntry(entryWith(lat: 48.86)), isNull);
  });

  test('returns the saved lat/lon/source when both coordinates are present', () {
    final result =
        knownCoordinatesFromEntry(entryWith(lat: 48.86, lon: 2.33, source: 'map'));

    expect(result, isNotNull);
    expect(result!.lat, 48.86);
    expect(result.lon, 2.33);
    expect(result.source, 'map');
  });

  test('defaults source to "realtime" when coordinates are present but source is not', () {
    final result = knownCoordinatesFromEntry(entryWith(lat: 48.86, lon: 2.33));

    expect(result!.source, 'realtime');
  });
}
