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
          // Broad, generic-proximity result — the town itself.
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
                      'extract': 'Vincennes est une commune du Val-de-Marne.',
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
    expect(promptContext, contains('Vincennes est une commune du Val-de-Marne.'));
    // ...but the name-matched (specific) one must come first, so a
    // downstream character budget can't truncate it away in favor of the
    // broader, less relevant one.
    final churchExtractIndex =
        promptContext.indexOf('Église catholique construite au XIXe siècle.');
    final townExtractIndex =
        promptContext.indexOf('Vincennes est une commune du Val-de-Marne.');
    expect(churchExtractIndex, lessThan(townExtractIndex));
  });
}
