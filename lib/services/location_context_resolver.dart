import 'dart:io';
import 'exif_location_service.dart';
import 'location_service.dart';
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
  final bool wikipediaUsed;

  /// Combined location + Wikipedia text to feed the AI prompt, or null.
  final String? promptContext;
}

/// Resolves the photo's location (EXIF GPS first, then real-time GPS) and
/// enriches it with nearby Wikipedia articles (T06 — extracted from
/// AudioGuideService.analyzeAndPlay).
class LocationContextResolver {
  Future<LocationContext> resolve(File imageFile) async {
    final exifCoords = await ExifLocationService.readGpsFromImage(imageFile);
    LocationResult locationResult;
    String source;
    if (exifCoords != null) {
      locationResult = await LocationService.fromCoordinates(exifCoords.lat, exifCoords.lon);
      source = 'exif';
    } else {
      locationResult = await LocationService.getCurrentLocation();
      source = locationResult.status == LocationPermissionStatus.granted ? 'realtime' : 'none';
    }

    var latitude = locationResult.info?.latitude;
    var longitude = locationResult.info?.longitude;
    var address = locationResult.info?.contextForPrompt;
    if (locationResult.info == null || locationResult.status != LocationPermissionStatus.granted) {
      latitude = null;
      longitude = null;
      address = null;
      source = 'none';
    }

    String? wikiContext;
    var wikipediaUsed = false;
    if (locationResult.info != null) {
      final wikiResults = await WikipediaService.searchNearby(
        lat: locationResult.info!.latitude,
        lon: locationResult.info!.longitude,
      );
      if (wikiResults.isNotEmpty) {
        wikiContext = WikipediaService.buildContext(wikiResults);
        wikipediaUsed = true;
      }
    }

    final promptContext = [
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
      wikipediaUsed: wikipediaUsed,
      promptContext: promptContext.isNotEmpty ? promptContext : null,
    );
  }
}
