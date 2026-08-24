import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'network_config.dart';
import 'remote_config_service.dart';

const _channel = MethodChannel('audio_guide/location');

enum LocationPermissionStatus { granted, denied, deniedForever, serviceDisabled }

class LocationInfo {
  final double latitude;
  final double longitude;
  final String? city;
  final String? road;
  final String? neighbourhood;
  final String? country;

  const LocationInfo({
    required this.latitude,
    required this.longitude,
    this.city,
    this.road,
    this.neighbourhood,
    this.country,
  });

  String get contextForPrompt {
    final parts = <String>[];
    if (road != null) parts.add(road!);
    if (neighbourhood != null) parts.add(neighbourhood!);
    if (city != null) parts.add(city!);
    if (country != null) parts.add(country!);
    final loc = parts.isNotEmpty ? parts.join(', ') : '';
    return 'Localisation GPS : $latitude, $longitude'
        '${loc.isNotEmpty ? ' ($loc)' : ''}';
  }
}

class LocationResult {
  final LocationInfo? info;
  final LocationPermissionStatus status;
  const LocationResult({this.info, required this.status});
}

/// A single forward-geocoding match, as returned by [LocationService.searchPlace]
/// (#123 — jumping the map picker to a searched place by name).
class GeocodePrediction {
  final String displayName;
  final double lat;
  final double lon;

  /// The extent of the matched place, straight from Nominatim's own
  /// `boundingbox` (#201) — tiny for a precise address, large for a
  /// city/region. Null if Nominatim didn't return one or it was
  /// malformed; callers should fall back to a fixed zoom level in that
  /// case rather than fail outright.
  final double? south;
  final double? north;
  final double? west;
  final double? east;

  const GeocodePrediction({
    required this.displayName,
    required this.lat,
    required this.lon,
    this.south,
    this.north,
    this.west,
    this.east,
  });

  bool get hasBoundingBox =>
      south != null && north != null && west != null && east != null;
}

class LocationService {
  static Future<LocationPermissionStatus> checkPermission() async {
    try {
      final status = await _channel.invokeMethod<String>('checkPermission');
      return _mapStatus(status ?? 'denied');
    } catch (_) {
      return LocationPermissionStatus.denied;
    }
  }

  /// Build LocationResult from known coordinates (e.g. from EXIF).
  /// [client] allows injecting a mock HTTP client in tests.
  static Future<LocationResult> fromCoordinates(double lat, double lon, {http.Client? client}) async {
    final geo = await _reverseGeocode(lat, lon, client: client);
    return LocationResult(
      status: LocationPermissionStatus.granted,
      info: LocationInfo(
        latitude: lat,
        longitude: lon,
        city: _extractCity(geo?['address']),
        road: geo?['address']?['road'] as String?,
        neighbourhood: geo?['address']?['neighbourhood'] as String?
            ?? geo?['address']?['suburb'] as String?,
        country: geo?['address']?['country'] as String?,
      ),
    );
  }

  /// [client] allows injecting a mock HTTP client in tests. [timeout]
  /// defaults to [RemoteConfig.locationTimeoutSeconds] and can be
  /// overridden in tests to avoid waiting on the real default.
  static Future<LocationResult> getCurrentLocation({
    http.Client? client,
    Duration? timeout,
  }) async {
    try {
      final result = await _channel.invokeMethod<Map>('requestLocation').timeout(
        timeout ?? Duration(seconds: RemoteConfigService.current.locationTimeoutSeconds),
      );
      final map = Map<String, dynamic>.from(result ?? {});
      final status = map['status'] as String? ?? 'error';

      if (status == 'deniedForever') {
        return const LocationResult(status: LocationPermissionStatus.deniedForever);
      }
      if (status == 'denied') {
        return const LocationResult(status: LocationPermissionStatus.denied);
      }
      if (status != 'granted') {
        return const LocationResult(status: LocationPermissionStatus.denied);
      }

      final lat = (map['latitude'] as num?)?.toDouble();
      final lon = (map['longitude'] as num?)?.toDouble();

      if (lat == null || lon == null) {
        return const LocationResult(status: LocationPermissionStatus.granted);
      }

      // Reverse geocode via Nominatim
      final geo = await _reverseGeocode(lat, lon, client: client);
      return LocationResult(
        status: LocationPermissionStatus.granted,
        info: LocationInfo(
          latitude: lat,
          longitude: lon,
          city: _extractCity(geo?['address']),
          road: geo?['address']?['road'] as String?,
          neighbourhood: geo?['address']?['neighbourhood'] as String?
              ?? geo?['address']?['suburb'] as String?,
          country: geo?['address']?['country'] as String?,
        ),
      );
    } catch (_) {
      return const LocationResult(status: LocationPermissionStatus.denied);
    }
  }

  /// Returns the current raw GPS fix without reverse geocoding — no
  /// network call (T78, for capturing a location entirely offline).
  /// Null if permission isn't granted or no fix is available. [timeout]
  /// defaults to [RemoteConfig.locationTimeoutSeconds] and can be
  /// overridden in tests to avoid waiting on the real default.
  static Future<({double lat, double lon})?> getCurrentRawCoordinates({
    Duration? timeout,
  }) async {
    try {
      final result = await _channel.invokeMethod<Map>('requestLocation').timeout(
        timeout ?? Duration(seconds: RemoteConfigService.current.locationTimeoutSeconds),
      );
      final map = Map<String, dynamic>.from(result ?? {});
      if ((map['status'] as String? ?? 'error') != 'granted') return null;

      final lat = (map['latitude'] as num?)?.toDouble();
      final lon = (map['longitude'] as num?)?.toDouble();
      if (lat == null || lon == null) return null;

      return (lat: lat, lon: lon);
    } catch (_) {
      return null;
    }
  }

  /// Forward-geocodes [query] (a place name/address) via Nominatim, for the
  /// map picker's search field (#123). Returns at most 5 matches, closest
  /// first is not guaranteed — Nominatim's own relevance ranking is used
  /// as-is. Empty on a blank query, no results, or any failure.
  /// [client] allows injecting a mock HTTP client in tests.
  static Future<List<GeocodePrediction>> searchPlace(
    String query, {
    http.Client? client,
  }) async {
    if (query.trim().isEmpty) return [];
    try {
      final uri = Uri.parse(
        'https://nominatim.openstreetmap.org/search'
        '?q=${Uri.encodeQueryComponent(query)}&format=json&limit=5&accept-language=fr',
      );
      final c = client ?? http.Client();
      final response = await c.get(
        uri,
        headers: {'User-Agent': NetworkConfig.userAgent},
      ).timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) return [];

      final data = jsonDecode(response.body) as List;
      return data
          .map((e) {
            final map = e as Map<String, dynamic>;
            final lat = double.tryParse(map['lat'] as String? ?? '');
            final lon = double.tryParse(map['lon'] as String? ?? '');
            if (lat == null || lon == null) return null;

            // Nominatim's own order: [south, north, west, east], all as
            // strings — malformed/missing entries just leave the
            // bounding box null rather than failing the whole result.
            final bbox = (map['boundingbox'] as List<dynamic>?)
                ?.map((v) => double.tryParse(v as String))
                .toList();
            final hasValidBbox = bbox != null &&
                bbox.length == 4 &&
                bbox.every((v) => v != null);

            return GeocodePrediction(
              displayName: map['display_name'] as String? ?? '',
              lat: lat,
              lon: lon,
              south: hasValidBbox ? bbox[0] : null,
              north: hasValidBbox ? bbox[1] : null,
              west: hasValidBbox ? bbox[2] : null,
              east: hasValidBbox ? bbox[3] : null,
            );
          })
          .whereType<GeocodePrediction>()
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> openSettings() async {
    await _channel.invokeMethod('openSettings');
  }

  static LocationPermissionStatus _mapStatus(String s) {
    switch (s) {
      case 'granted': return LocationPermissionStatus.granted;
      case 'deniedForever': return LocationPermissionStatus.deniedForever;
      default: return LocationPermissionStatus.denied;
    }
  }

  static Future<Map<String, dynamic>?> _reverseGeocode(double lat, double lon, {http.Client? client}) async {
    try {
      final uri = Uri.parse(
        'https://nominatim.openstreetmap.org/reverse'
        '?lat=$lat&lon=$lon&format=json&addressdetails=1&accept-language=fr',
      );
      final c = client ?? http.Client();
      final response = await c.get(
        uri,
        headers: {'User-Agent': NetworkConfig.userAgent},
      ).timeout(const Duration(seconds: 8));
      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
    } catch (_) {}
    return null;
  }

  static String? _extractCity(Map<String, dynamic>? address) {
    if (address == null) return null;
    return address['city'] as String?
        ?? address['town'] as String?
        ?? address['village'] as String?
        ?? address['municipality'] as String?;
  }
}
