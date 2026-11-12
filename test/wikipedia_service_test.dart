import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:audiolens/services/wikipedia_service.dart';

http.Response _searchResponse(List<Map<String, dynamic>> hits) => http.Response(
      jsonEncode({
        'query': {'search': hits},
      }),
      200,
    );

http.Response _extractResponse(Map<String, Map<String, dynamic>> pages) => http.Response(
      jsonEncode({
        'query': {'pages': pages},
      }),
      200,
    );

void main() {
  group('searchByName (T74)', () {
    test('returns French results when the French search finds hits', () async {
      final client = MockClient((request) async {
        final isFrench = request.url.host == 'fr.wikipedia.org';
        final isSearch = request.url.queryParameters['list'] == 'search';

        if (isFrench && isSearch) {
          return _searchResponse([
            {'pageid': 1, 'title': 'Bowling de la Matène'},
          ]);
        }
        if (isFrench) {
          return _extractResponse({
            '1': {'title': 'Bowling de la Matène', 'extract': 'Un bowling connu pour...'},
          });
        }
        fail('should not call English Wikipedia when French search succeeds');
      });

      final results = await WikipediaService.searchByName(
        query: 'Bowling de la Matène Paris',
        client: client,
      );

      expect(results, hasLength(1));
      expect(results.first.title, 'Bowling de la Matène');
    });

    test('falls back to English when French search finds nothing', () async {
      final client = MockClient((request) async {
        final isSearch = request.url.queryParameters['list'] == 'search';
        final isEnglish = request.url.host == 'en.wikipedia.org';

        if (isSearch && !isEnglish) {
          return _searchResponse([]); // French: no hits
        }
        if (isSearch && isEnglish) {
          return _searchResponse([
            {'pageid': 2, 'title': 'Tontons Flingueurs Bowling'},
          ]);
        }
        // extract call, must be English at this point
        expect(isEnglish, isTrue);
        return _extractResponse({
          '2': {'title': 'Tontons Flingueurs Bowling', 'extract': 'Known for the film shoot...'},
        });
      });

      final results = await WikipediaService.searchByName(
        query: 'Bowling de la Matène',
        client: client,
      );

      expect(results, hasLength(1));
      expect(results.first.title, 'Tontons Flingueurs Bowling');
    });

    test('returns empty when both languages find nothing', () async {
      final client = MockClient((request) async {
        return _searchResponse([]);
      });

      final results = await WikipediaService.searchByName(query: 'Lieu inconnu', client: client);

      expect(results, isEmpty);
    });

    test('returns empty for a blank query without making a request', () async {
      final client = MockClient((request) async {
        fail('should not make any HTTP request for a blank query');
      });

      final results = await WikipediaService.searchByName(query: '   ', client: client);

      expect(results, isEmpty);
    });
  });

  group('merge', () {
    test('appends only titles not already present in base', () {
      const base = [WikipediaResult(title: 'A', extract: 'a')];
      const additional = [
        WikipediaResult(title: 'A', extract: 'duplicate, dropped'),
        WikipediaResult(title: 'B', extract: 'b'),
      ];

      final merged = WikipediaService.merge(base, additional);

      expect(merged.map((r) => r.title), ['A', 'B']);
    });
  });

  // #498 — extracts as returned for the Paris 13e field case and others.
  group('streets and administrative divisions', () {
    const square = WikipediaResult(
        title: 'Square du Limousin',
        extract: 'Le square du Limousin est une voie du 13e arrondissement de Paris, en France.');
    const avenue = WikipediaResult(
        title: 'Avenue de la Porte-de-Vitry',
        extract: "L'avenue de la Porte-de-Vitry est une voie du quartier de la Gare du 13e "
            'arrondissement de Paris, en France.');
    const porte = WikipediaResult(
        title: 'Porte de Vitry',
        extract: 'La porte de Vitry est une porte de Paris, en France située dans le quartier '
            'de la Gare au sud du 13e arrondissement.');
    const canton = WikipediaResult(
        title: 'Canton de Vincennes',
        extract: 'Le canton de Vincennes est une circonscription électorale française située '
            'dans le département du Val-de-Marne.');
    const church = WikipediaResult(
        title: 'Église Notre-Dame de Vincennes',
        extract: "L'église Notre-Dame est une église catholique située rue Raymond du Temple "
            'à Vincennes, en France.');
    const place = WikipediaResult(
        title: 'Place de la Concorde',
        extract: 'La place de la Concorde est une place de Paris, la plus grande de la capitale.');

    test('are recognized from the opening of the extract', () {
      expect(WikipediaService.isStreetOrAdministrative(square), isTrue);
      expect(WikipediaService.isStreetOrAdministrative(avenue), isTrue);
      expect(WikipediaService.isStreetOrAdministrative(canton), isTrue);
      // A church in a street, a city gate, a square that is a place: kept.
      expect(WikipediaService.isStreetOrAdministrative(church), isFalse);
      expect(WikipediaService.isStreetOrAdministrative(porte), isFalse);
      expect(WikipediaService.isStreetOrAdministrative(place), isFalse);
    });

    test('are dropped when other articles remain', () {
      expect(WikipediaService.withoutStreets([porte, avenue, square]).map((r) => r.title),
          ['Porte de Vitry']);
      expect(WikipediaService.withoutStreets([canton, church]).map((r) => r.title),
          ['Église Notre-Dame de Vincennes']);
    });

    test('are kept when they are all there is', () {
      expect(WikipediaService.withoutStreets([avenue, square]), [avenue, square]);
    });

    test('the context presents the articles as places around, not the subject', () {
      final context = WikipediaService.buildContext([porte]);

      expect(context, startsWith("Lieux proches d'après Wikipedia"));
      expect(context, contains("ne t'en sers que s'ils correspondent à ce que montre l'image"));
      expect(context, contains('- Porte de Vitry : '));
    });
  });
}
