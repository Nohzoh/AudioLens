import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:audiolens/services/wikipedia_service.dart';

// #547: Heidelberg — the German edition has the closer articles.
void main() {
  test('country → Wikipedia edition', () {
    expect(WikipediaService.localLanguageFor('DE'), 'de');
    expect(WikipediaService.localLanguageFor('ch'), 'de');
    expect(WikipediaService.localLanguageFor('fr'), isNull);
    expect(WikipediaService.localLanguageFor(null), isNull);
  });

  test('both editions are searched and merged closest first', () async {
    final hosts = <String>[];
    final client = MockClient((request) async {
      final lang = request.url.host.split('.').first;
      hosts.add('$lang:${request.url.queryParameters['list'] ?? 'extracts'}');
      if (request.url.queryParameters['list'] == 'geosearch') {
        final pages = lang == 'de'
            ? [
                {'pageid': 11, 'title': 'Philosophenweg', 'dist': 20.0},
                {'pageid': 12, 'title': 'Alte Brücke', 'dist': 700.0},
              ]
            : [
                {'pageid': 21, 'title': 'Heidelberg', 'dist': 400.0},
              ];
        return http.Response(jsonEncode({'query': {'geosearch': pages}}), 200);
      }
      final ids = request.url.queryParameters['pageids']!.split('|');
      final titles = {'11': 'Philosophenweg', '12': 'Alte Brücke', '21': 'Heidelberg'};
      return http.Response(
          jsonEncode({
            'query': {
              'pages': {
                for (final id in ids) id: {'title': titles[id], 'extract': 'Texte $id.'}
              }
            }
          }),
          200);
    });

    final results = await WikipediaService.searchNearby(
        lat: 49.416, lon: 8.7098, limit: 2, localLanguage: 'de', client: client);

    expect(results.map((r) => '${r.lang}:${r.title}'), ['de:Philosophenweg', 'fr:Heidelberg']);
    expect(hosts.where((h) => h.endsWith('geosearch')).toSet(), {'fr:geosearch', 'de:geosearch'});
    expect(WikipediaService.buildContext(results), contains('- Philosophenweg [de] : Texte 11.'));
  });
}
