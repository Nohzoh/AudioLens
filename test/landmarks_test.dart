import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:audiolens/services/location_context_resolver.dart';
import 'package:audiolens/services/poi_service.dart';

// #498: the Duo towers case — tram platform, towers several hundred m away.
void main() {
  test('keeps tall named structures, closest first, one per name', () async {
    String? query;
    final client = MockClient((request) async {
      query = request.bodyFields['data'];
      return http.Response(
        jsonEncode({
          'elements': [
            {'type': 'way', 'center': {'lat': 48.8270, 'lon': 2.3790}, 'tags': {'name': 'Tour Duo 1', 'height': '180', 'building': 'yes'}},
            {'type': 'way', 'center': {'lat': 48.8269, 'lon': 2.3791}, 'tags': {'name': 'Tour Duo 1', 'height': '180 m', 'building:part': 'yes'}},
            {'type': 'way', 'center': {'lat': 48.8300, 'lon': 2.3800}, 'tags': {'name': 'Tour M6B2', 'building:levels': '50'}},
            {'type': 'way', 'center': {'lat': 48.8245, 'lon': 2.3776}, 'tags': {'name': 'Petit immeuble', 'height': '21'}},
            {'type': 'node', 'lat': 48.8250, 'lon': 2.3780, 'tags': {'height': '120'}},
          ],
        }),
        200,
      );
    });

    final landmarks =
        await PoiService(client: client).findLandmarks(lat: 48.8242535, lon: 2.377508);

    expect(query, contains('around:1500,48.8242535,2.377508'));
    expect(landmarks.map((l) => l.name), ['Tour Duo 1', 'Tour M6B2']);
    expect(landmarks.first.heightMeters, 180);
    expect(landmarks.first.distanceMeters, inInclusiveRange(250, 350));
  });

  test('a failure gives no landmark', () async {
    final client = MockClient((_) async => http.Response('busy', 504));
    expect(await PoiService(client: client).findLandmarks(lat: 48.8, lon: 2.3), isEmpty);
  });

  test('tag rules', () {
    expect(PoiService.landmarkFromTags({'name': 'Phare', 'man_made': 'tower', 'height': '35'}),
        isNotNull);
    expect(PoiService.landmarkFromTags({'name': 'Château d’eau', 'height': '35'}), isNull);
    expect(PoiService.landmarkFromTags({'name': 'Tour', 'height': '200 ft'}), isNull);
    expect(PoiService.landmarkFromTags({'name': 'Tour', 'height': '75,5'})?.heightMeters, 76);
  });

  test('prompt line frames them as candidates and skips the named POI', () {
    const duo = Landmark(name: 'Tour Duo 1', heightMeters: 180, distanceMeters: 310);
    const m6 = Landmark(name: 'Tour M6B2', levels: 50, distanceMeters: 680);
    expect(
      landmarksContext([duo, m6]),
      'Grands édifices visibles de loin depuis cet endroit (peut-être sur la photo, '
      'peut-être pas) : Tour Duo 1 (180 m de haut, à 310 m) ; Tour M6B2 (50 étages, à 680 m).',
    );
    expect(landmarksContext([duo], exclude: 'tour duo 1'), isNull);
    expect(landmarksContext(const []), isNull);
  });

  test('the trace keeps the landmarks, old traces read as none', () {
    const trace = LocationTrace(placeName: 'Gare', landmarks: ['Tour Duo 1 (310 m)']);
    final back = LocationTrace.decode(trace.encode())!;
    expect(back.landmarks, ['Tour Duo 1 (310 m)']);
    expect(back.withUserHint('tours').landmarks, ['Tour Duo 1 (310 m)']);
    expect(LocationTrace.decode('{"place":"Gare"}')!.landmarks, isEmpty);
    expect(const LocationTrace(landmarks: ['x']).isEmpty, isFalse);
  });
}
