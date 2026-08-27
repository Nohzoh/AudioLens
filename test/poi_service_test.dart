import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:audiolens/services/poi_service.dart';

void main() {
  test('returns the closest tagged POI', () async {
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
    final poi = await service.findNearby(lat: 48.8, lon: 2.3);

    expect(poi?.name, 'Bowling de la Matène');
    expect(poi?.category, 'leisure=bowling_alley');
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
    final poi = await service.findNearby(lat: 48.8, lon: 2.3);

    expect(poi?.name, 'Musée local');
    expect(poi?.category, 'tourism=museum');
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
    final poi = await service.findNearby(lat: 48.8, lon: 2.3);

    expect(poi, isNull);
  });

  test('returns null when no elements found', () async {
    final client = MockClient((request) async {
      return http.Response(jsonEncode({'elements': []}), 200);
    });

    final service = PoiService(client: client);
    final poi = await service.findNearby(lat: 48.8, lon: 2.3);

    expect(poi, isNull);
  });

  test('returns null gracefully on HTTP failure', () async {
    final client = MockClient((request) async {
      return http.Response('error', 500);
    });

    final service = PoiService(client: client);
    final poi = await service.findNearby(lat: 48.8, lon: 2.3);

    expect(poi, isNull);
  });

  test('returns null gracefully on network exception', () async {
    final client = MockClient((request) async {
      throw Exception('no network');
    });

    final service = PoiService(client: client);
    final poi = await service.findNearby(lat: 48.8, lon: 2.3);

    expect(poi, isNull);
  });

  // #276
  group('structured metadata', () {
    test('surfaces subtype, inscription, and wikidataId when present', () async {
      final client = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'elements': [
              {
                'type': 'node',
                'lat': 48.8001,
                'lon': 2.3001,
                'tags': {
                  'historic': 'memorial',
                  'memorial': 'stolperstein',
                  'name': 'Umberto Chignoli',
                  'inscription': 'Ici habitait Umberto CHIGNOLI...',
                  'wikidata': 'Q89207218',
                },
              },
            ],
          }),
          200,
        );
      });

      final service = PoiService(client: client);
      final poi = await service.findNearby(lat: 48.8, lon: 2.3);

      expect(poi?.name, 'Umberto Chignoli');
      expect(poi?.category, 'historic=memorial');
      expect(poi?.subtype, 'stolperstein');
      expect(poi?.inscription, 'Ici habitait Umberto CHIGNOLI...');
      expect(poi?.wikidataId, 'Q89207218');
    });

    test('category/subtype/inscription/wikidataId are all null when absent', () async {
      final client = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'elements': [
              {
                'type': 'node',
                'lat': 48.8001,
                'lon': 2.3001,
                'tags': {'amenity': 'restaurant', 'name': 'Chez Paul'},
              },
            ],
          }),
          200,
        );
      });

      final service = PoiService(client: client);
      final poi = await service.findNearby(lat: 48.8, lon: 2.3);

      expect(poi?.name, 'Chez Paul');
      expect(poi?.category, 'amenity=restaurant');
      expect(poi?.subtype, isNull);
      expect(poi?.inscription, isNull);
      expect(poi?.wikidataId, isNull);
    });

    test('category priority follows historic > tourism > amenity > leisure '
        'when an element somehow carries more than one', () async {
      final client = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'elements': [
              {
                'type': 'node',
                'lat': 48.8001,
                'lon': 2.3001,
                'tags': {'amenity': 'restaurant', 'historic': 'ruins', 'name': 'X'},
              },
            ],
          }),
          200,
        );
      });

      final service = PoiService(client: client);
      final poi = await service.findNearby(lat: 48.8, lon: 2.3);

      expect(poi?.category, 'historic=ruins');
    });
  });
}
