import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:audiolens/services/location_context_resolver.dart';
import 'package:audiolens/services/wikipedia_service.dart';
import 'package:audiolens/utils/script_cleanup.dart';

// #595: the Musée du Colombier case (Alès, 2026-11-14).
void main() {
  WikipediaResult article(String title, String extract) =>
      WikipediaResult(title: title, extract: extract);

  final ales = article('Alès', 'Alès (prononcé /a.lɛs/) est une commune française située dans le Gard.');
  final aire = article("Aire urbaine d'Alès", "L'aire urbaine d’Alès est une aire urbaine française.");
  final unite = article("Unité urbaine d'Alès", "L'unité urbaine d'Alès est une unité urbaine française.");
  final siege = article("Siège d'Alès", "Le siège d'Alès est la dernière opération militaire de Louis XIII.");
  final musee = article('Musée du Colombier', 'Le musée du Colombier est un musée d’Alès.');

  test('statistical areas always go, the town article when a place is identified', () {
    expect(WikipediaService.withoutStreets([ales, aire, unite, siege]).map((r) => r.title),
        ['Alès', "Siège d'Alès"]);
    expect(
        WikipediaService.withoutStreets([ales, aire, unite, siege], placeIdentified: true)
            .map((r) => r.title),
        ["Siège d'Alès"]);
    // Nothing left is fine when the place itself is known…
    expect(WikipediaService.withoutStreets([ales, aire], placeIdentified: true), isEmpty);
    // …but not otherwise.
    expect(WikipediaService.withoutStreets([aire]), [aire]);
  });

  test('a name search drops namesakes far from the photo', () async {
    final client = MockClient((request) async {
      if (request.url.queryParameters['list'] == 'search') {
        return http.Response(
            jsonEncode({
              'query': {
                'search': [
                  {'pageid': 1},
                  {'pageid': 2},
                  {'pageid': 3},
                ]
              }
            }),
            200);
      }
      return http.Response.bytes(
          utf8.encode(jsonEncode({
            'query': {
              'pages': {
                '1': {
                  'title': 'Colombier (Neuchâtel)',
                  'extract': 'Colombier est une localité suisse.',
                  'coordinates': [
                    {'lat': 46.966, 'lon': 6.866}
                  ],
                },
                '2': {
                  'title': 'Musée du Colombier',
                  'extract': 'Le musée du Colombier est un musée d’Alès.',
                  'coordinates': [
                    {'lat': 44.1284, 'lon': 4.0803}
                  ],
                },
                '3': {'title': 'Luis Alvarez (peintre)', 'extract': 'Peintre né en 1929.'},
              }
            }
          })),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'});
    });

    final results = await WikipediaService.searchByName(
        query: 'Musée du Colombier Alès', limit: 3, nearLat: 44.128379, nearLon: 4.080314, client: client);

    expect(results.map((r) => r.title), ['Musée du Colombier', 'Luis Alvarez (peintre)']);
  });

  test('museum hint and title matching', () {
    expect(exhibitHint('tourism=museum'), contains("n'en invente pas"));
    expect(exhibitHint('amenity=place_of_worship'), isNull);
    expect(exhibitHint(null), isNull);
    expect(titleMatchesPlace(musee.title, 'Musée du Colombier'), isTrue);
    expect(titleMatchesPlace('Alès', 'Musée du Colombier'), isFalse);
    expect(titleMatchesPlace("Siège d'Alès", 'Musée du Colombier'), isFalse);
  });

  test('parasite phrases are removed before the text is read', () {
    expect(
        cleanMarkdown('Une belle représentation. Absolument. Cette esthétique rappelle le symbolisme.'),
        'Une belle représentation. Cette esthétique rappelle le symbolisme.');
    expect(
        cleanMarkdown("L'éclairage met en valeur la peinture. Voici une suite possible, en adoptant "
            "le ton d'un guide audio culturel :\n\n\"Ces nuances chaudes et cette lumière douce "
            'évoquent une période où l\'art et la spiritualité étaient intimement liés.\" Fin.'),
        "L'éclairage met en valeur la peinture. Ces nuances chaudes et cette lumière douce "
        "évoquent une période où l'art et la spiritualité étaient intimement liés. Fin.");
    // A short quoted phrase and an ordinary « absolument » stay.
    expect(cleanMarkdown('On l\'appelle "la capitale des Cévennes". Elle est absolument unique.'),
        'On l\'appelle "la capitale des Cévennes". Elle est absolument unique.');
  });
}
