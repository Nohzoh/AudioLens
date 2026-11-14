import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:audiolens/services/location_context_resolver.dart';
import 'package:audiolens/services/poi_service.dart';

/// #247 — when a POI is found, its name-matched Wikipedia extract must
/// come *before* the generic-proximity one in the final promptContext,
/// not after. Before this fix, WikipediaService.merge() was called as
/// merge(nearbyResults, nameResults) — nearby-by-distance first — which
/// let a broader article (the surrounding town) outrank the specific
/// place actually photographed, then get truncated away entirely by
/// GeminiNanoService's character budget for Nano.
void main() {
  test(
      'name-matched Wikipedia extract appears before the generic-proximity one in promptContext',
      () async {
    final client = MockClient((request) async {
      final uri = request.url;

      if (uri.host == 'nominatim.openstreetmap.org') {
        return http.Response(
          jsonEncode({
            'address': {'city': 'Vincennes', 'country': 'France'},
          }),
          200,
        );
      }

      if (uri.host == 'overpass-api.de') {
        return http.Response(
          jsonEncode({
            'elements': [
              {
                'type': 'node',
                'lat': 48.8476,
                'lon': 2.4383,
                'tags': {
                  'amenity': 'place_of_worship',
                  'name': 'Église Notre-Dame de Vincennes',
                },
              },
            ],
          }),
          200,
        );
      }

      if (uri.host.endsWith('wikipedia.org')) {
        final action = uri.queryParameters['action'];
        if (action == 'query' && uri.queryParameters['list'] == 'geosearch') {
          // Broad, generic-proximity result (not the town's own article, which #595 drops when a place is identified).
          return http.Response(
            jsonEncode({
              'query': {
                'geosearch': [
                  {'pageid': 1, 'title': 'Vincennes'},
                ],
              },
            }),
            200,
          );
        }
        if (action == 'query' && uri.queryParameters['list'] == 'search') {
          // Specific, name-matched result — the actual place photographed.
          return http.Response(
            jsonEncode({
              'query': {
                'search': [
                  {'pageid': 2, 'title': 'Église Notre-Dame de Vincennes'},
                ],
              },
            }),
            200,
          );
        }
        if (action == 'query' && uri.queryParameters.containsKey('pageids')) {
          final pageids = uri.queryParameters['pageids'];
          if (pageids == '1') {
            return http.Response(
              jsonEncode({
                'query': {
                  'pages': {
                    '1': {
                      'title': 'Vincennes',
                      'extract': 'Le bois de Vincennes est un espace vert de Paris.',
                    },
                  },
                },
              }),
              200,
            );
          }
          if (pageids == '2') {
            return http.Response(
              jsonEncode({
                'query': {
                  'pages': {
                    '2': {
                      'title': 'Église Notre-Dame de Vincennes',
                      'extract': 'Église catholique construite au XIXe siècle.',
                    },
                  },
                },
              }),
              200,
            );
          }
        }
      }

      return http.Response('{}', 404);
    });

    final resolver = LocationContextResolver(
      poiService: PoiService(client: client),
      httpClient: client,
    );

    final ctx = await resolver.resolveFromCoordinates(
      lat: 48.8476,
      lon: 2.4383,
      source: 'map',
    );

    expect(ctx.wikipediaUsed, isTrue);
    final promptContext = ctx.promptContext!;
    // Both extracts should be present...
    expect(promptContext, contains('Église catholique construite au XIXe siècle.'));
    expect(promptContext, contains('Le bois de Vincennes est un espace vert de Paris.'));
    // ...but the name-matched (specific) one must come first, so a
    // downstream character budget can't truncate it away in favor of the
    // broader, less relevant one.
    final churchExtractIndex =
        promptContext.indexOf('Église catholique construite au XIXe siècle.');
    final townExtractIndex =
        promptContext.indexOf('Le bois de Vincennes est un espace vert de Paris.');
    expect(churchExtractIndex, lessThan(townExtractIndex));
  });

  // #276
  group('POI metadata enrichment', () {
    http.Client emptyWikiClient(Map<String, dynamic> overpassTags) {
      return MockClient((request) async {
        final uri = request.url;
        if (uri.host == 'nominatim.openstreetmap.org') {
          return http.Response(jsonEncode({'address': {}}), 200);
        }
        if (uri.host == 'overpass-api.de') {
          return http.Response(
            jsonEncode({
              'elements': [
                {'type': 'node', 'lat': 48.85, 'lon': 2.47, 'tags': overpassTags},
              ],
            }),
            200,
          );
        }
        if (uri.host.endsWith('wikipedia.org')) {
          if (uri.queryParameters['list'] == 'geosearch') {
            return http.Response(jsonEncode({'query': {'geosearch': []}}), 200);
          }
          if (uri.queryParameters['list'] == 'search') {
            return http.Response(jsonEncode({'query': {'search': []}}), 200);
          }
        }
        if (uri.host == 'www.wikidata.org') {
          return http.Response(
            jsonEncode({
              'entities': {
                'Q89207218': {
                  'labels': {
                    'fr': {'value': "Stolperstein à la mémoire d'Umberto Chignoli"}
                  },
                  'descriptions': {
                    'fr': {'value': 'stolperstein à Fontenay-sous-Bois, France'}
                  },
                },
              },
            }),
            200,
          );
        }
        return http.Response('{}', 404);
      });
    }

    test('folds subtype and inscription into the POI line in promptContext',
        () async {
      final client = emptyWikiClient({
        'historic': 'memorial',
        'memorial': 'stolperstein',
        'name': 'Umberto Chignoli',
        'inscription': 'Ici habitait Umberto CHIGNOLI...',
      });
      final resolver = LocationContextResolver(
        poiService: PoiService(client: client),
        httpClient: client,
      );

      final ctx = await resolver.resolveFromCoordinates(
        lat: 48.85, lon: 2.47, source: 'map',
      );

      expect(ctx.poi?.subtype, 'stolperstein');
      expect(
        ctx.promptContext,
        contains('Lieu identifié à proximité : Umberto Chignoli (stolperstein). '
            'Inscription : "Ici habitait Umberto CHIGNOLI..."'),
      );
    });

    test('fetches and includes Wikidata info when the POI has a wikidata tag',
        () async {
      final client = emptyWikiClient({
        'historic': 'memorial',
        'name': 'Umberto Chignoli',
        'wikidata': 'Q89207218',
      });
      final resolver = LocationContextResolver(
        poiService: PoiService(client: client),
        httpClient: client,
      );

      final ctx = await resolver.resolveFromCoordinates(
        lat: 48.85, lon: 2.47, source: 'map',
      );

      expect(ctx.wikidataInfo?.label, "Stolperstein à la mémoire d'Umberto Chignoli");
      expect(
        ctx.promptContext,
        contains("Selon Wikidata : Stolperstein à la mémoire d'Umberto Chignoli "
            '(stolperstein à Fontenay-sous-Bois, France)'),
      );
    });

    test('no Wikidata line when the POI has no wikidata tag', () async {
      final client = emptyWikiClient({'amenity': 'restaurant', 'name': 'Chez Paul'});
      final resolver = LocationContextResolver(
        poiService: PoiService(client: client),
        httpClient: client,
      );

      final ctx = await resolver.resolveFromCoordinates(
        lat: 48.85, lon: 2.47, source: 'map',
      );

      expect(ctx.wikidataInfo, isNull);
      expect(ctx.promptContext, isNot(contains('Selon Wikidata')));
    });

    test('wikipediaResults exposes the individual articles found, not just '
        'the merged promptContext string', () async {
      final client = MockClient((request) async {
        final uri = request.url;
        if (uri.host == 'nominatim.openstreetmap.org') {
          return http.Response(jsonEncode({'address': {}}), 200);
        }
        if (uri.host == 'overpass-api.de') {
          return http.Response(jsonEncode({'elements': []}), 200);
        }
        if (uri.host.endsWith('wikipedia.org')) {
          if (uri.queryParameters['list'] == 'geosearch') {
            return http.Response(
              jsonEncode({
                'query': {
                  'geosearch': [
                    {'pageid': 1, 'title': 'Vincennes'},
                  ],
                },
              }),
              200,
            );
          }
          if (uri.queryParameters.containsKey('pageids')) {
            return http.Response(
              jsonEncode({
                'query': {
                  'pages': {
                    '1': {'title': 'Vincennes', 'extract': 'Une commune.'},
                  },
                },
              }),
              200,
            );
          }
        }
        return http.Response('{}', 404);
      });
      final resolver = LocationContextResolver(
        poiService: PoiService(client: client),
        httpClient: client,
      );

      final ctx = await resolver.resolveFromCoordinates(
        lat: 48.85, lon: 2.47, source: 'map',
      );

      expect(ctx.wikipediaResults, hasLength(1));
      expect(ctx.wikipediaResults.first.title, 'Vincennes');
      expect(ctx.wikipediaResults.first.extract, 'Une commune.');
    });
  });

  // #137
  group('enrichment cache', () {
    // Only counts POI/Wikipedia requests — the cache covers POI/Wikidata/
    // Wikipedia enrichment, not the separate reverse-geocoding call, which
    // still fires on every resolveFromCoordinates regardless (T78's own
    // sequencing, unrelated to this cache).
    http.Client countingClient(Map<String, dynamic> overpassTags, List<int> enrichmentRequestCount) {
      return MockClient((request) async {
        final uri = request.url;
        if (uri.host == 'nominatim.openstreetmap.org') {
          return http.Response(jsonEncode({'address': {}}), 200);
        }
        if (uri.host == 'overpass-api.de') {
          enrichmentRequestCount[0]++;
          return http.Response(
            jsonEncode({
              'elements': [
                {'type': 'node', 'lat': 48.85, 'lon': 2.47, 'tags': overpassTags},
              ],
            }),
            200,
          );
        }
        if (uri.host.endsWith('wikipedia.org')) {
          enrichmentRequestCount[0]++;
          if (uri.queryParameters['list'] == 'geosearch') {
            return http.Response(jsonEncode({'query': {'geosearch': []}}), 200);
          }
          if (uri.queryParameters['list'] == 'search') {
            return http.Response(jsonEncode({'query': {'search': []}}), 200);
          }
        }
        return http.Response('{}', 404);
      });
    }

    test('a second resolve for the same coordinates reuses the cached '
        'result instead of re-fetching POI/Wikipedia', () async {
      final enrichmentRequestCount = [0];
      final client =
          countingClient({'amenity': 'restaurant', 'name': 'Chez Paul'}, enrichmentRequestCount);
      final resolver = LocationContextResolver(
        poiService: PoiService(client: client),
        httpClient: client,
      );

      final first = await resolver.resolveFromCoordinates(lat: 48.85, lon: 2.47, source: 'map');
      final countAfterFirst = enrichmentRequestCount[0];
      expect(countAfterFirst, greaterThan(0));

      final second = await resolver.resolveFromCoordinates(lat: 48.85, lon: 2.47, source: 'map');

      expect(enrichmentRequestCount[0], countAfterFirst,
          reason: 'no new POI/Wikipedia calls on the cache hit');
      expect(second.poi?.name, first.poi?.name);
      expect(second.promptContext, first.promptContext);
    });

    test('coordinates far enough apart are not treated as a cache hit',
        () async {
      final enrichmentRequestCount = [0];
      final client =
          countingClient({'amenity': 'restaurant', 'name': 'Chez Paul'}, enrichmentRequestCount);
      final resolver = LocationContextResolver(
        poiService: PoiService(client: client),
        httpClient: client,
      );

      await resolver.resolveFromCoordinates(lat: 48.85, lon: 2.47, source: 'map');
      final countAfterFirst = enrichmentRequestCount[0];

      await resolver.resolveFromCoordinates(lat: 40.71, lon: -74.01, source: 'map');

      expect(enrichmentRequestCount[0], greaterThan(countAfterFirst));
    });
  });

  // #482
  group('place name from reverse geocoding', () {
    final searches = <String>[];

    http.Client client({required bool overpassFindsPoi}) {
      searches.clear();
      return MockClient((request) async {
        final uri = request.url;
        if (uri.host == 'nominatim.openstreetmap.org') {
          return http.Response.bytes(
            utf8.encode(jsonEncode({
              'class': 'amenity',
              'type': 'place_of_worship',
              'name': 'Église Saint-Joseph',
              'address': {
                'amenity': 'Église Saint-Joseph',
                'road': 'Rue Frédéric Mistral',
                'town': 'Alès',
                'country': 'France',
              },
            })),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }
        if (uri.host == 'overpass-api.de') {
          if (!overpassFindsPoi) return http.Response('timeout', 504);
          return http.Response.bytes(
            utf8.encode(jsonEncode({
              'elements': [
                {
                  'type': 'node',
                  'lat': 44.1249,
                  'lon': 4.0805,
                  'tags': {'historic': 'memorial', 'name': 'Monument aux morts'},
                },
              ],
            })),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }
        if (uri.host.endsWith('wikipedia.org')) {
          if (uri.queryParameters['list'] == 'geosearch') {
            return http.Response(jsonEncode({'query': {'geosearch': []}}), 200);
          }
          if (uri.queryParameters['list'] == 'search') {
            searches.add(uri.queryParameters['srsearch'] ?? '');
            return http.Response(jsonEncode({'query': {'search': []}}), 200);
          }
        }
        return http.Response('{}', 404);
      });
    }

    test('names the geocoded place and searches Wikipedia for it when no POI is found',
        () async {
      final c = client(overpassFindsPoi: false);
      final resolver = LocationContextResolver(
        poiService: PoiService(client: c),
        httpClient: c,
      );

      final ctx = await resolver.resolveFromCoordinates(
          lat: 44.1248726, lon: 4.0804628, source: 'realtime');

      expect(ctx.poi, isNull);
      expect(ctx.geocodedPlaceName, 'Église Saint-Joseph');
      expect(
        ctx.promptContext,
        startsWith('Lieu identifié à cet emplacement (OpenStreetMap) : Église Saint-Joseph'),
      );
      expect(searches.toSet(), {'Église Saint-Joseph Alès'});
      // #481
      expect(ctx.trace.placeLine,
          'Église Saint-Joseph (geocode, amenity=place_of_worship)');
      expect(ctx.trace.wikipediaTitles, isEmpty);
    });

    test('a POI from Overpass takes precedence over the geocoded name', () async {
      final c = client(overpassFindsPoi: true);
      final resolver = LocationContextResolver(
        poiService: PoiService(client: c),
        httpClient: c,
      );

      final ctx = await resolver.resolveFromCoordinates(
          lat: 44.1248726, lon: 4.0804628, source: 'realtime');

      expect(ctx.poi?.name, 'Monument aux morts');
      expect(ctx.geocodedPlaceName, isNull);
      expect(ctx.promptContext, isNot(contains('OpenStreetMap')));
      expect(searches.toSet(), {'Monument aux morts Alès'});
      // #481
      expect(ctx.trace.placeName, 'Monument aux morts');
      expect(ctx.trace.placeSource, 'poi');
    });
  });
}
