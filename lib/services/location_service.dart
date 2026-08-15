import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'network_config.dart';

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

  /// [client] allows injecting a mock HTTP client in tests.
  static Future<LocationResult> getCurrentLocation({http.Client? client}) async {
    try {
      final result = await _channel.invokeMethod<Map>('requestLocation');
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
  /// Null if permission isn't granted or no fix is available.
  static Future<({double lat, double lon})?> getCurrentRawCoordinates() async {
    try {
      final result = await _channel.invokeMethod<Map>('requestLocation');
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
