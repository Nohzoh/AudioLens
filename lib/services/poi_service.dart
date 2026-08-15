import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;
import 'network_config.dart';

/// Looks up the name of a nearby point of interest (POI) via the
/// OpenStreetMap Overpass API (T74).
///
/// Reverse geocoding (Nominatim, used by [LocationService]) resolves an
/// address, but doesn't reliably surface the name of a specific business or
/// venue (e.g. a bowling alley) at that address. Overpass lets us query
/// directly for tagged POIs (leisure/tourism/historic/amenity) instead.
class PoiService {
  static const _overpassUrl = 'https://overpass-api.de/api/interpreter';

  /// [client] allows injecting a mock HTTP client in tests.
  const PoiService({http.Client? client}) : _client = client;

  final http.Client? _client;

  /// Returns the name of the closest named POI within [radius] meters of
  /// (lat, lon), or null if none found / on any failure.
  Future<String?> findNearbyName({
    required double lat,
    required double lon,
    int radius = 75,
  }) async {
    final query = '[out:json][timeout:5];'
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
          .timeout(const Duration(seconds: 6));

      if (response.statusCode != 200) return null;

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final elements = data['elements'] as List? ?? [];

      String? closestName;
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
          closestName = name;
        }
      }

      return closestName;
    } catch (_) {
      return null;
    }
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
