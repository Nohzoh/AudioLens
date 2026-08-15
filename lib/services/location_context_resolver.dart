import 'dart:io';
import 'package:http/http.dart' as http;
import 'exif_location_service.dart';
import 'location_service.dart';
import 'poi_service.dart';
import 'remote_config_service.dart';
import 'wikipedia_service.dart';

/// Result of resolving where a photo was taken and enriching it with
/// nearby Wikipedia context.
class LocationContext {
  const LocationContext({
    required this.source,
    required this.status,
    this.latitude,
    this.longitude,
    this.address,
    this.city,
    this.poiName,
    this.wikipediaUsed = false,
    this.promptContext,
  });

  /// 'exif' | 'realtime' | 'none'
  final String source;
  final LocationPermissionStatus status;
  final double? latitude;
  final double? longitude;
  final String? address;
  final String? city;

  /// Name of the closest tagged point of interest (business, venue,
  /// landmark...), if one was found nearby (T74).
  final String? poiName;
  final bool wikipediaUsed;

  /// Combined location + Wikipedia text to feed the AI prompt, or null.
  final String? promptContext;
}

/// Resolves a location context — either from a photo (EXIF GPS first, then
/// real-time GPS) or from already-known coordinates — and enriches it with
/// a nearby point of interest and Wikipedia articles.
///
/// T06 — extracted from AudioGuideService.analyzeAndPlay.
/// T74 — added POI lookup + name-based Wikipedia search.
/// T78 — split GPS resolution from enrichment (POI/Wikipedia/reverse
/// geocoding) so a deferred capture can supply coordinates already known
/// from capture time, without repeating the GPS step.
class LocationContextResolver {
  LocationContextResolver({PoiService? poiService, http.Client? httpClient})
      : _poiService = poiService ?? PoiService(client: httpClient),
        _httpClient = httpClient;

  final PoiService _poiService;
  final http.Client? _httpClient;

  Future<LocationContext> resolve(File imageFile) async {
    final exifCoords = await ExifLocationService.readGpsFromImage(imageFile);
    LocationResult locationResult;
    String source;
    if (exifCoords != null) {
      locationResult = await LocationService.fromCoordinates(exifCoords.lat, exifCoords.lon, client: _httpClient);
      source = 'exif';
    } else {
      locationResult = await LocationService.getCurrentLocation(client: _httpClient);
      source = locationResult.status == LocationPermissionStatus.granted ? 'realtime' : 'none';
    }
    return _enrich(locationResult, source);
  }

  /// Resolves from coordinates already known (e.g. saved at capture time by
  /// a deferred/offline capture) instead of reading them from a photo.
  /// Reverse geocoding, POI lookup, and Wikipedia enrichment all happen
  /// now, at call time — this is the network-heavy part T78's deferred
  /// capture defers until the user explicitly launches the analysis.
  Future<LocationContext> resolveFromCoordinates({
    required double lat,
    required double lon,
    required String source,
  }) async {
    final locationResult = await LocationService.fromCoordinates(lat, lon, client: _httpClient);
    return _enrich(locationResult, source);
  }

  Future<LocationContext> _enrich(LocationResult locationResult, String source) async {
    var latitude = locationResult.info?.latitude;
    var longitude = locationResult.info?.longitude;
    var address = locationResult.info?.contextForPrompt;
    if (locationResult.info == null || locationResult.status != LocationPermissionStatus.granted) {
      latitude = null;
      longitude = null;
      address = null;
      source = 'none';
    }

    final cfg = RemoteConfigService.current;

    String? poiName;
    String? wikiContext;
    var wikipediaUsed = false;
    if (locationResult.info != null) {
      final lat = locationResult.info!.latitude;
      final lon = locationResult.info!.longitude;

      poiName = await _poiService.findNearbyName(
        lat: lat,
        lon: lon,
        radius: cfg.poiRadiusMeters,
      );

      var wikiResults = await WikipediaService.searchNearby(
        lat: lat,
        lon: lon,
        radius: cfg.wikipediaRadiusMeters,
        limit: cfg.wikipediaMaxResults,
        extractChars: cfg.wikipediaExtractChars,
        client: _httpClient,
      );

      if (poiName != null) {
        final nameQuery = [poiName, locationResult.info!.city].where((s) => s != null && s.isNotEmpty).join(' ');
        final nameResults = await WikipediaService.searchByName(
          query: nameQuery,
          limit: cfg.wikipediaMaxResults,
          extractChars: cfg.wikipediaExtractChars,
          client: _httpClient,
        );
        wikiResults = WikipediaService.merge(wikiResults, nameResults);
      }

      if (wikiResults.isNotEmpty) {
        wikiContext = WikipediaService.buildContext(wikiResults);
        wikipediaUsed = true;
      }
    }

    final promptContext = [
      poiName != null ? 'Lieu identifié à proximité : $poiName' : null,
      locationResult.info?.contextForPrompt,
      wikiContext,
    ].where((s) => s != null && s.isNotEmpty).join('\n\n');

    return LocationContext(
      source: source,
      status: locationResult.status,
      latitude: latitude,
      longitude: longitude,
      address: address,
      city: locationResult.info?.city,
      poiName: poiName,
      wikipediaUsed: wikipediaUsed,
      promptContext: promptContext.isNotEmpty ? promptContext : null,
    );
  }
}
