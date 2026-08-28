import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;
import 'network_config.dart';

/// Everything usable pulled from the closest tagged OSM element, not just
/// its name (#276) — a plain `name` tag alone throws away structured
/// context (memorial/monument subtype, the exact engraved/written text,
/// a Wikidata link) that OSM often already carries for exactly the kind
/// of small, undocumented object a generic AI description struggles
/// with (a memorial plaque, a wayside cross, a public artwork...).
class PoiInfo {
  final String name;

  /// The primary OSM key this element matched on (`historic`, `tourism`,
  /// `amenity`, `leisure`) and its value, e.g. `historic=memorial` — a
  /// coarse category, present whenever the element has one of those tags
  /// at all (it always does, by construction of the Overpass query below).
  final String? category;

  /// The specific subtype when OSM carries one alongside [category] —
  /// e.g. `memorial=stolperstein`, `historic=wayside_cross`. Distinct
  /// from [category] because some of these live on their own key
  /// (`memorial`, `artwork_type`) rather than as the matched tag's value.
  final String? subtype;

  /// Verbatim engraved/written text (OSM's `inscription` tag), when
  /// present — plaques, memorials, gravestones. Not something a vision
  /// model needs to be told rather than read off the photo itself, but
  /// useful as ground truth to compare a description against, or to
  /// supply when the text is only partially legible in the image.
  final String? inscription;

  /// Wikidata QID (OSM's `wikidata` tag), when present — lets
  /// [WikidataService] fetch a label/description for POIs that have no
  /// Wikipedia article at all (common for small/local memorials) but do
  /// have a structured Wikidata entry, filling a real gap
  /// [WikipediaService] alone can't.
  final String? wikidataId;

  const PoiInfo({
    required this.name,
    this.category,
    this.subtype,
    this.inscription,
    this.wikidataId,
  });
}

/// Looks up the closest point of interest (POI) via the OpenStreetMap
/// Overpass API (T74), and now (#276) as much of its structured metadata
/// as OSM carries, not just its name.
///
/// Reverse geocoding (Nominatim, used by [LocationService]) resolves an
/// address, but doesn't reliably surface the name of a specific business or
/// venue (e.g. a bowling alley) at that address. Overpass lets us query
/// directly for tagged POIs (leisure/tourism/historic/amenity) instead.
class PoiService {
  static const _overpassUrl = 'https://overpass-api.de/api/interpreter';

  /// #248: delay between retry attempts. Live testing against the public
  /// instance's `/api/status` (self-reported "Rate limit: 2" concurrent
  /// slots) showed requests spaced roughly a second or more apart were
  /// 100% reliable, while a rapid burst reproduced 10+ second stalls and
  /// outright 504s — this waits comfortably past that.
  static const _retryDelay = Duration(seconds: 2);

  /// The tag keys queried, in priority order for [PoiInfo.category] when
  /// an element happens to carry more than one (rare, but Overpass's
  /// query OR's them together rather than picking one).
  static const _categoryKeys = ['historic', 'tourism', 'amenity', 'leisure'];

  /// [client] allows injecting a mock HTTP client in tests.
  const PoiService({http.Client? client}) : _client = client;

  final http.Client? _client;

  /// Returns the closest named POI within [radius] meters of (lat, lon),
  /// or null if none found / if every attempt failed.
  ///
  /// #248: the free public Overpass instance enforces its own concurrent
  /// request "slot" limit and can queue or 504 under load — confirmed by
  /// direct testing against the exact coordinates from a real user
  /// report, which reproduced repeated 10-12s stalls and a 504 well past
  /// the previous flat 6s timeout, alongside runs that succeeded in
  /// under a second. [maxAttempts] (default from
  /// [RemoteConfigService.poiMaxAttempts]) retries after [_retryDelay] on
  /// any failed attempt — a non-200 response or a thrown exception (a
  /// client-side timeout included) — but never on a successful response
  /// that simply parsed to zero elements, since that's a legitimate "no
  /// POI nearby" answer, not a failure to retry.
  Future<PoiInfo?> findNearby({
    required double lat,
    required double lon,
    int radius = 75,
    int timeoutSeconds = 10,
    int maxAttempts = 2,
  }) async {
    final serverTimeout = (timeoutSeconds - 2).clamp(1, timeoutSeconds);
    final query = '[out:json][timeout:$serverTimeout];'
        '('
        'node(around:$radius,$lat,$lon)[leisure];'
        'node(around:$radius,$lat,$lon)[tourism];'
        'node(around:$radius,$lat,$lon)[historic];'
        'node(around:$radius,$lat,$lon)[amenity];'
        'way(around:$radius,$lat,$lon)[leisure];'
        'way(around:$radius,$lat,$lon)[tourism];'
        'way(around:$radius,$lat,$lon)[historic];'
        'way(around:$radius,$lat,$lon)[amenity];'
        ');'
        'out center tags;';

    List<dynamic>? elements;
    for (var attempt = 1; attempt <= maxAttempts && elements == null; attempt++) {
      elements = await _fetchElements(query, Duration(seconds: timeoutSeconds));
      if (elements == null && attempt < maxAttempts) {
        await Future.delayed(_retryDelay);
      }
    }
    if (elements == null) return null;

    PoiInfo? closest;
    double closestDistance = double.infinity;

    for (final el in elements) {
      final map = el as Map<String, dynamic>;
      final tags = map['tags'] as Map<String, dynamic>?;
      final name = tags?['name'] as String?;
      if (name == null || name.isEmpty) continue;

      final elLat = (map['lat'] as num?)?.toDouble() ??
          (map['center']?['lat'] as num?)?.toDouble();
      final elLon = (map['lon'] as num?)?.toDouble() ??
          (map['center']?['lon'] as num?)?.toDouble();
      if (elLat == null || elLon == null) continue;

      final distance = _distanceMeters(lat, lon, elLat, elLon);
      if (distance < closestDistance) {
        closestDistance = distance;
        closest = _toPoiInfo(name, tags!);
      }
    }

    return closest;
  }

  /// One HTTP attempt. Returns the raw `elements` list on a 200 (possibly
  /// empty — a real answer), or null on any failure (non-200, thrown
  /// exception, timeout) for [findNearby] to decide whether to retry.
  Future<List<dynamic>?> _fetchElements(String query, Duration timeout) async {
    try {
      final client = _client ?? http.Client();
      final response = await client
          .post(
            Uri.parse(_overpassUrl),
            headers: {
              'User-Agent': NetworkConfig.userAgent,
              'Content-Type': 'application/x-www-form-urlencoded',
            },
            body: {'data': query},
          )
          .timeout(timeout);

      if (response.statusCode != 200) return null;

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return data['elements'] as List? ?? [];
    } catch (_) {
      return null;
    }
  }

  static PoiInfo _toPoiInfo(String name, Map<String, dynamic> tags) {
    String? category;
    for (final key in _categoryKeys) {
      final value = tags[key] as String?;
      if (value != null && value.isNotEmpty) {
        category = '$key=$value';
        break;
      }
    }
    // `memorial`/`artwork_type` carry the specific subtype for their
    // respective `historic=memorial`/`tourism=artwork` category — only
    // meaningful alongside that category, not a general-purpose tag.
    final subtype = (tags['memorial'] as String?) ?? (tags['artwork_type'] as String?);

    return PoiInfo(
      name: name,
      category: category,
      subtype: subtype,
      inscription: tags['inscription'] as String?,
      wikidataId: tags['wikidata'] as String?,
    );
  }

  static double _distanceMeters(
      double lat1, double lon1, double lat2, double lon2) {
    const earthRadiusMeters = 6371000.0;
    final dLat = _degToRad(lat2 - lat1);
    final dLon = _degToRad(lon2 - lon1);
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_degToRad(lat1)) *
            cos(_degToRad(lat2)) *
            sin(dLon / 2) *
            sin(dLon / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return earthRadiusMeters * c;
  }

  static double _degToRad(double deg) => deg * (pi / 180);
}
