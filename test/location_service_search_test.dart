import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:audiolens/services/location_service.dart';

void main() {
  group('LocationService.searchPlace (#123)', () {
    test('returns parsed predictions from a Nominatim search response', () async {
      final client = MockClient((request) async {
        expect(request.url.queryParameters['q'], 'Tour Eiffel');
        return http.Response(
          jsonEncode([
            {'display_name': 'Tour Eiffel, Paris, France', 'lat': '48.8584', 'lon': '2.2945'},
            {'display_name': 'Eiffel Tower, Paris, France', 'lat': '48.8583', 'lon': '2.2944'},
          ]),
          200,
        );
      });

      final results = await LocationService.searchPlace('Tour Eiffel', client: client);

      expect(results, hasLength(2));
      expect(results.first.displayName, 'Tour Eiffel, Paris, France');
      expect(results.first.lat, 48.8584);
      expect(results.first.lon, 2.2945);
    });

    test('skips entries with unparseable coordinates', () async {
      final client = MockClient((request) async {
        return http.Response(
          jsonEncode([
            {'display_name': 'Broken', 'lat': 'not-a-number', 'lon': '2.2945'},
            {'display_name': 'Valid', 'lat': '48.8584', 'lon': '2.2945'},
          ]),
          200,
        );
      });

      final results = await LocationService.searchPlace('query', client: client);

      expect(results, hasLength(1));
      expect(results.first.displayName, 'Valid');
    });

    test('returns empty list for a blank query without making a request', () async {
      final client = MockClient((request) async {
        fail('should not make a network request for a blank query');
      });

      final results = await LocationService.searchPlace('   ', client: client);

      expect(results, isEmpty);
    });

    test('returns empty list gracefully on HTTP failure', () async {
      final client = MockClient((request) async {
        return http.Response('error', 500);
      });

      final results = await LocationService.searchPlace('query', client: client);

      expect(results, isEmpty);
    });

    test('returns empty list gracefully on network exception', () async {
      final client = MockClient((request) async {
        throw Exception('no network');
      });

      final results = await LocationService.searchPlace('query', client: client);

      expect(results, isEmpty);
    });
  });
}
