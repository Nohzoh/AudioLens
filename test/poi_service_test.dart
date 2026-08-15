import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:audiolens/services/poi_service.dart';

void main() {
  test('returns the name of the closest tagged POI', () async {
    // Two POIs: one 'far' further away, one 'close' nearer to (48.8, 2.3).
    final client = MockClient((request) async {
      return http.Response(
        jsonEncode({
          'elements': [
            {
              'type': 'node',
              'lat': 48.9,
              'lon': 2.3,
              'tags': {'leisure': 'bowling_alley', 'name': 'Bowling lointain'},
            },
            {
              'type': 'node',
              'lat': 48.8001,
              'lon': 2.3001,
              'tags': {'leisure': 'bowling_alley', 'name': 'Bowling de la Matène'},
            },
          ],
        }),
        200,
      );
    });

    final service = PoiService(client: client);
    final name = await service.findNearbyName(lat: 48.8, lon: 2.3);

    expect(name, 'Bowling de la Matène');
  });

  test('reads name from way "center" when element has no direct lat/lon', () async {
    final client = MockClient((request) async {
      return http.Response(
        jsonEncode({
          'elements': [
            {
              'type': 'way',
              'center': {'lat': 48.8001, 'lon': 2.3001},
              'tags': {'tourism': 'museum', 'name': 'Musée local'},
            },
          ],
        }),
        200,
      );
    });

    final service = PoiService(client: client);
    final name = await service.findNearbyName(lat: 48.8, lon: 2.3);

    expect(name, 'Musée local');
  });

  test('skips elements without a name tag', () async {
    final client = MockClient((request) async {
      return http.Response(
        jsonEncode({
          'elements': [
            {
              'type': 'node',
              'lat': 48.8001,
              'lon': 2.3001,
              'tags': {'amenity': 'bench'}, // no name
            },
          ],
        }),
        200,
      );
    });

    final service = PoiService(client: client);
    final name = await service.findNearbyName(lat: 48.8, lon: 2.3);

    expect(name, isNull);
  });

  test('returns null when no elements found', () async {
    final client = MockClient((request) async {
      return http.Response(jsonEncode({'elements': []}), 200);
    });

    final service = PoiService(client: client);
    final name = await service.findNearbyName(lat: 48.8, lon: 2.3);

    expect(name, isNull);
  });

  test('returns null gracefully on HTTP failure', () async {
    final client = MockClient((request) async {
      return http.Response('error', 500);
    });

    final service = PoiService(client: client);
    final name = await service.findNearbyName(lat: 48.8, lon: 2.3);

    expect(name, isNull);
  });

  test('returns null gracefully on network exception', () async {
    final client = MockClient((request) async {
      throw Exception('no network');
    });

    final service = PoiService(client: client);
    final name = await service.findNearbyName(lat: 48.8, lon: 2.3);

    expect(name, isNull);
  });
}
