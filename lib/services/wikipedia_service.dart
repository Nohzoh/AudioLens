import 'dart:convert';
import 'package:http/http.dart' as http;
import 'network_config.dart';

class WikipediaResult {
  final String title;
  final String extract;
  final String? coordinates;

  const WikipediaResult({
    required this.title,
    required this.extract,
    this.coordinates,
  });
}

class WikipediaService {
  /// Search Wikipedia articles near GPS coordinates
  static Future<List<WikipediaResult>> searchNearby({
    required double lat,
    required double lon,
    int radius = 200, // meters
    int limit = 3,
    int extractChars = 1500,
    http.Client? client,
  }) async {
    try {
      // GeoSearch: find articles near coordinates
      final geoUri = Uri.parse(
        'https://fr.wikipedia.org/w/api.php'
        '?action=query'
        '&list=geosearch'
        '&gscoord=$lat|$lon'
        '&gsradius=$radius'
        '&gslimit=$limit'
        '&format=json'
        '&origin=*'
      );

      final http.Client c = client ?? http.Client();
      final geoResp = await c.get(geoUri,
        headers: {'User-Agent': NetworkConfig.userAgent})
          .timeout(const Duration(seconds: 6));

      if (geoResp.statusCode != 200) return [];

      final geoData = jsonDecode(geoResp.body) as Map<String, dynamic>;
      final pages = geoData['query']?['geosearch'] as List? ?? [];

      if (pages.isEmpty) return [];

      final pageIds = pages.map((p) => p['pageid'].toString()).toList();
      return await _fetchExtracts(c, 'fr', pageIds, extractChars);
    } catch (_) {
      return [];
    }
  }

  /// Full-text search by name (e.g. a POI name + city), complementing
  /// [searchNearby]'s geosearch — catches articles that exist but aren't
  /// geotagged (T74). Falls back to English Wikipedia if the French search
  /// finds nothing.
  static Future<List<WikipediaResult>> searchByName({
    required String query,
    int limit = 2,
    int extractChars = 1500,
    http.Client? client,
  }) async {
    if (query.trim().isEmpty) return [];
    final http.Client c = client ?? http.Client();

    for (final lang in ['fr', 'en']) {
      try {
        final searchUri = Uri.parse(
          'https://$lang.wikipedia.org/w/api.php'
          '?action=query'
          '&list=search'
          '&srsearch=${Uri.encodeQueryComponent(query)}'
          '&srlimit=$limit'
          '&format=json'
          '&origin=*'
        );

        final searchResp = await c.get(searchUri,
          headers: {'User-Agent': NetworkConfig.userAgent})
            .timeout(const Duration(seconds: 6));
        if (searchResp.statusCode != 200) continue;

        final searchData = jsonDecode(searchResp.body) as Map<String, dynamic>;
        final hits = searchData['query']?['search'] as List? ?? [];
        if (hits.isEmpty) continue;

        final pageIds = hits.map((h) => h['pageid'].toString()).toList();
        final results = await _fetchExtracts(c, lang, pageIds, extractChars);
        if (results.isNotEmpty) return results;
      } catch (_) {
        continue;
      }
    }
    return [];
  }

  static Future<List<WikipediaResult>> _fetchExtracts(
    http.Client client,
    String lang,
    List<String> pageIds,
    int extractChars,
  ) async {
    if (pageIds.isEmpty) return [];

    final extractUri = Uri.parse(
      'https://$lang.wikipedia.org/w/api.php'
      '?action=query'
      // #542: page ids are numbers; anything else is dropped.
      '&pageids=${pageIds.where((id) => RegExp(r'^[0-9]+$').hasMatch(id)).join('|')}'
      '&prop=extracts'
      '&exintro=true'
      '&explaintext=true'
      '&exsectionformat=plain'
      '&exchars=$extractChars'
      '&format=json'
      '&origin=*'
    );

    final extractResp = await client.get(extractUri,
      headers: {'User-Agent': NetworkConfig.userAgent})
        .timeout(const Duration(seconds: 6));

    if (extractResp.statusCode != 200) return [];

    final extractData = jsonDecode(extractResp.body) as Map<String, dynamic>;
    final queryPages = extractData['query']?['pages'] as Map? ?? {};

    return queryPages.values.map((page) {
      final extract = (page['extract'] as String? ?? '').trim();
      final cleaned = extract
          .replaceAll(RegExp(r'\n+'), ' ')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      return WikipediaResult(
        title: page['title'] as String? ?? '',
        extract: cleaned.length > extractChars
            ? '${cleaned.substring(0, extractChars)}...'
            : cleaned,
      );
    }).where((r) => r.extract.isNotEmpty).toList();
  }

  /// Merge two result lists, dropping duplicate titles from [additional].
  static List<WikipediaResult> merge(
    List<WikipediaResult> base,
    List<WikipediaResult> additional,
  ) {
    final seenTitles = base.map((r) => r.title).toSet();
    return [
      ...base,
      ...additional.where((r) => seenTitles.add(r.title)),
    ];
  }

  /// #498: an article about a street or an administrative division —
  /// rarely what a photo shows, and the kind a small model latches onto
  /// when the real subject is further away (field case: Paris 13e, three
  /// street articles while the photo showed the Duo towers). French
  /// Wikipedia opens such articles with a stable phrase.
  static bool isStreetOrAdministrative(WikipediaResult r) {
    final head = r.extract.length > 200 ? r.extract.substring(0, 200) : r.extract;
    return RegExp(
      r'\best une (voie|impasse|circonscription|division administrative|subdivision)\b',
      caseSensitive: false,
    ).hasMatch(head);
  }

  /// #498: [results] without street and administrative articles — unless
  /// that would leave nothing, in which case they are kept: some context
  /// is better than none.
  static List<WikipediaResult> withoutStreets(List<WikipediaResult> results) {
    final kept = results.where((r) => !isStreetOrAdministrative(r)).toList();
    return kept.isEmpty ? results : kept;
  }

  /// Build context string for AI prompt
  static String buildContext(List<WikipediaResult> results) {
    if (results.isEmpty) return '';

    final buffer = StringBuffer();
    // #498: framed as places around, not as facts about the subject — both
    // Nano models built a whole script on nearby articles that had
    // nothing to do with the photo.
    buffer.writeln(
        "Lieux proches d'après Wikipedia (la photo peut montrer l'un d'eux, ou tout autre chose : "
        "ne t'en sers que s'ils correspondent à ce que montre l'image) :");
    for (final r in results) {
      buffer.writeln('- ${r.title} : ${r.extract}');
    }
    return buffer.toString();
  }
}
