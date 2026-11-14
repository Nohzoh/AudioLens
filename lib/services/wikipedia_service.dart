import 'dart:convert';
import 'dart:math' as math;
import 'package:http/http.dart' as http;
import 'shared_http_client.dart';
import 'network_config.dart';

class WikipediaResult {
  final String title;
  final String extract;
  final String? coordinates;

  /// #547: Wikipedia edition the article comes from.
  final String lang;

  /// #595: where the article is geotagged, when it is.
  final double? latitude;
  final double? longitude;

  const WikipediaResult({
    required this.title,
    required this.extract,
    this.coordinates,
    this.lang = 'fr',
    this.latitude,
    this.longitude,
  });
}

class WikipediaService {
  /// Search Wikipedia articles near GPS coordinates
  ///
  /// #547: [localLanguage] (the language of the country, when it isn't
  /// French) is searched too: abroad, the local edition often has many
  /// more articles about the surroundings. Results of both editions are
  /// merged closest first, [limit] in total.
  static Future<List<WikipediaResult>> searchNearby({
    required double lat,
    required double lon,
    int radius = 200, // meters
    int limit = 3,
    int extractChars = 1500,
    String? localLanguage,
    http.Client? client,
  }) async {
    final http.Client c = client ?? sharedHttpClient;
    final languages = ['fr', if (localLanguage != null && localLanguage != 'fr') localLanguage];
    final found = await Future.wait([
      for (final lang in languages) _geosearch(c, lang, lat, lon, radius, limit),
    ]);
    final hits = [for (final list in found) ...list]
      ..sort((a, b) => a.dist.compareTo(b.dist));
    final kept = hits.take(limit).toList();
    final results = <WikipediaResult>[];
    for (final lang in languages) {
      final ids = [for (final h in kept) if (h.lang == lang) h.pageId];
      try {
        results.addAll(await _fetchExtracts(c, lang, ids, extractChars));
      } catch (_) {}
    }
    // Back in distance order.
    final order = {for (var i = 0; i < kept.length; i++) '${kept[i].lang}:${kept[i].title}': i};
    results.sort((a, b) => (order['${a.lang}:${a.title}'] ?? 99)
        .compareTo(order['${b.lang}:${b.title}'] ?? 99));
    return results;
  }

  static Future<List<({String lang, String pageId, String title, double dist})>> _geosearch(
      http.Client c, String lang, double lat, double lon, int radius, int limit) async {
    try {
      final geoUri = Uri.https('$lang.wikipedia.org', '/w/api.php', {
        'action': 'query',
        'list': 'geosearch',
        'gscoord': '$lat|$lon',
        'gsradius': '$radius',
        'gslimit': '$limit',
        'format': 'json',
        'origin': '*',
      });
      final geoResp = await c
          .get(geoUri, headers: {'User-Agent': NetworkConfig.userAgent})
          .timeout(const Duration(seconds: 6));
      if (geoResp.statusCode != 200) return const [];
      final geoData = jsonDecode(geoResp.body) as Map<String, dynamic>;
      final pages = geoData['query']?['geosearch'] as List? ?? [];
      return [
        for (final p in pages)
          (
            lang: lang,
            pageId: p['pageid'].toString(),
            title: p['title'] as String? ?? '',
            dist: (p['dist'] as num?)?.toDouble() ?? 0,
          ),
      ];
    } catch (_) {
      return const [];
    }
  }

  /// #547: main language of the Wikipedia edition worth adding for a
  /// country (ISO code from reverse geocoding); null when French or
  /// unknown. Multilingual countries get their most-used edition.
  static String? localLanguageFor(String? countryCode) => switch (countryCode?.toLowerCase()) {
        'de' || 'at' || 'ch' || 'li' => 'de',
        'it' || 'sm' || 'va' => 'it',
        'es' => 'es',
        'pt' || 'br' => 'pt',
        'nl' || 'be' => 'nl',
        'gb' || 'ie' || 'us' || 'ca' || 'au' || 'nz' => 'en',
        'jp' => 'ja',
        'pl' => 'pl',
        'cz' => 'cs',
        'se' => 'sv',
        'dk' => 'da',
        'no' => 'no',
        'gr' => 'el',
        _ => null,
      };

  /// Full-text search by name (e.g. a POI name + city), complementing
  /// [searchNearby]'s geosearch — catches articles that exist but aren't
  /// geotagged (T74). Falls back to English Wikipedia if the French search
  /// finds nothing.
  ///
  /// #595: with [nearLat]/[nearLon], an article geotagged farther than
  /// [maxDistanceKm] is dropped — a text search on « Musée du Colombier
  /// Alès » returned the Colombier of Neuchâtel and its château, 400 km
  /// away. Articles without coordinates are kept.
  static Future<List<WikipediaResult>> searchByName({
    required String query,
    int limit = 2,
    int extractChars = 1500,
    double? nearLat,
    double? nearLon,
    double maxDistanceKm = 15,
    http.Client? client,
  }) async {
    if (query.trim().isEmpty) return [];
    final http.Client c = client ?? sharedHttpClient;

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
        final results = [
          for (final r in await _fetchExtracts(c, lang, pageIds, extractChars))
            if (nearLat == null ||
                nearLon == null ||
                r.latitude == null ||
                r.longitude == null ||
                distanceKm(nearLat, nearLon, r.latitude!, r.longitude!) <= maxDistanceKm)
              r,
        ];
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
      '&prop=extracts%7Ccoordinates'
      '&colimit=max'
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
      final coords = page['coordinates'];
      final first = coords is List && coords.isNotEmpty && coords.first is Map ? coords.first as Map : null;
      return WikipediaResult(
        title: page['title'] as String? ?? '',
        extract: cleaned.length > extractChars
            ? '${cleaned.substring(0, extractChars)}...'
            : cleaned,
        lang: lang,
        latitude: (first?['lat'] as num?)?.toDouble(),
        longitude: (first?['lon'] as num?)?.toDouble(),
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
    final pattern = _streetPatterns[r.lang] ?? _streetPatterns['fr']!;
    return pattern.hasMatch(head);
  }

  /// #498/#587: the opening phrase of street and administrative articles,
  /// per Wikipedia edition (#547 brought German, English… articles in).
  static final _streetPatterns = <String, RegExp>{
    'fr': RegExp(
        r'\best une (voie|impasse|circonscription|division administrative|subdivision)\b',
        caseSensitive: false),
    'de': RegExp(
        r'\b(ist|war) (eine|ein) ([A-Za-zäöüß-]*straße|[A-Za-zäöüß-]*gasse|Straße|Gasse|Allee|Platz|Weg|Stadtteil|Stadtbezirk|Ortsteil|Gemarkung|Gemeinde)\b',
        caseSensitive: false),
    'en': RegExp(
        r'\bis an? (street|road|avenue|lane|district|ward|neighbourhood|neighborhood|borough|civil parish|electoral division)\b',
        caseSensitive: false),
    'it': RegExp(r"(^|\s)è una? (via|strada|piazza|quartiere|frazione|circoscrizione)\b",
        caseSensitive: false),
    'es': RegExp(r'\bes una? (calle|avenida|plaza|barrio|distrito)\b', caseSensitive: false),
    'nl': RegExp(r'\bis een (straat|laan|plein|wijk|buurt|stadsdeel)\b', caseSensitive: false),
  };

  /// #498: [results] without street and administrative articles — unless
  /// that would leave nothing, in which case they are kept: some context
  /// is better than none.
  ///
  /// #595: statistical areas (aire urbaine, unité urbaine…) always go;
  /// with [placeIdentified] (a named place was found at the spot), the
  /// article about the whole town goes too — it is long, and a small
  /// model then narrates the town instead of what the photo shows.
  static List<WikipediaResult> withoutStreets(List<WikipediaResult> results,
      {bool placeIdentified = false}) {
    final kept = results
        .where((r) =>
            !isStreetOrAdministrative(r) &&
            !isStatisticalArea(r) &&
            !(placeIdentified && isTownArticle(r)))
        .toList();
    return kept.isEmpty && !placeIdentified ? results : kept;
  }

  static String _head(WikipediaResult r) =>
      r.extract.length > 200 ? r.extract.substring(0, 200) : r.extract;

  /// #595: « L'aire urbaine d'Alès est une aire urbaine française… ».
  static bool isStatisticalArea(WikipediaResult r) => RegExp(
        r"\best une (aire urbaine|unité urbaine|aire d['’]attraction|agglomération|intercommunalité|communauté (de communes|d['’]agglomération|urbaine))\b",
        caseSensitive: false,
      ).hasMatch(_head(r));

  /// #595: « Alès est une commune française… », « … est une localité et
  /// une ancienne commune suisse… ».
  static bool isTownArticle(WikipediaResult r) => RegExp(
        r'\best une (commune|ville|localité|ancienne commune)\b|\b(ist eine (Stadt|Gemeinde|Großstadt))\b|\bis a (city|town|commune|municipality)\b',
        caseSensitive: false,
      ).hasMatch(_head(r));

  /// Great-circle distance, in km.
  static double distanceKm(double lat1, double lon1, double lat2, double lon2) {
    const r = 6371.0;
    final dLat = (lat2 - lat1) * math.pi / 180;
    final dLon = (lon2 - lon1) * math.pi / 180;
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1 * math.pi / 180) *
            math.cos(lat2 * math.pi / 180) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    return 2 * r * math.asin(math.sqrt(a));
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
      // #547: articles from another edition stay in their language; the
      // model writes in the narration language anyway.
      final tag = r.lang == 'fr' ? '' : ' [${r.lang}]';
      buffer.writeln('- ${r.title}$tag : ${r.extract}');
    }
    return buffer.toString();
  }
}
