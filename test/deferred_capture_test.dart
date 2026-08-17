import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:audiolens/services/audio_guide_service.dart';
import 'package:audiolens/services/gemini_api_service.dart';
import 'package:audiolens/services/gemini_tts_service.dart';
import 'package:audiolens/services/location_context_resolver.dart';
import 'package:audiolens/services/location_service.dart';
import 'package:audiolens/services/native_tts_service.dart';
import 'package:audiolens/utils/cancel_token.dart';
import 'support/fake_dio_adapter.dart';

class _FakeNativeTts extends NativeTtsService {
  @override
  Future<void> speak(String text, {CancelToken? cancelToken, double speed = 1.0}) async {
    onComplete?.call();
  }
}

class _FakeGeminiTts extends GeminiTtsService {
  _FakeGeminiTts() : super(apiKey: 'test-key');

  @override
  Future<void> speak(String text, {CancelToken? cancelToken, double speed = 1.0}) async {}
}

String _successJson() => jsonEncode({
      'candidates': [
        {
          'content': {
            'parts': [
              {
                'text':
                    '{"title": "La Joconde", "script": "Bienvenue devant ce chef-d\'oeuvre."}',
              },
            ],
          },
        },
      ],
    });

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LocationContextResolver.resolveFromCoordinates — T78', () {
    test('reverse-geocodes the given coordinates and preserves the given source', () async {
      final client = MockClient((request) async {
        if (request.url.host == 'nominatim.openstreetmap.org') {
          return http.Response(
            jsonEncode({
              'address': {'city': 'Paris', 'road': 'Rue de Rivoli', 'country': 'France'},
            }),
            200,
          );
        }
        if (request.url.host == 'overpass-api.de') {
          return http.Response(jsonEncode({'elements': []}), 200);
        }
        // Wikipedia geosearch/search — no results.
        if (request.url.queryParameters['list'] == 'geosearch' ||
            request.url.queryParameters['list'] == 'search') {
          return http.Response(jsonEncode({'query': {}}), 200);
        }
        return http.Response('{}', 200);
      });

      final resolver = LocationContextResolver(httpClient: client);
      final result = await resolver.resolveFromCoordinates(
        lat: 48.8566,
        lon: 2.3522,
        source: 'realtime',
      );

      expect(result.source, 'realtime');
      expect(result.status, LocationPermissionStatus.granted);
      expect(result.latitude, 48.8566);
      expect(result.longitude, 2.3522);
      expect(result.city, 'Paris');
    });
  });

  group('AudioGuideService.analyzeAndPlay(knownCoordinates:) — T78', () {
    late Directory tmpDir;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      tmpDir = Directory.systemTemp.createTempSync('deferred-capture');
    });

    tearDown(() {
      tmpDir.deleteSync(recursive: true);
    });

    test('uses the passed coordinates instead of re-reading EXIF/GPS', () async {
      // No GPS EXIF in this file, and no platform channel bound in tests —
      // if the service ignored knownCoordinates and fell through to the
      // normal resolve() path, lastGpsSource would end up 'none'.
      final imageFile = File('${tmpDir.path}/photo.jpg')
        ..writeAsBytesSync([0xFF, 0xD8, 0xFF, 0xD9]);

      final client = MockClient((request) async {
        if (request.url.host == 'nominatim.openstreetmap.org') {
          return http.Response(jsonEncode({'address': {'city': 'Lyon'}}), 200);
        }
        return http.Response(jsonEncode({'elements': [], 'query': {}}), 200);
      });

      final service = AudioGuideService(
        nativeTtsService: _FakeNativeTts(),
        geminiTtsService: _FakeGeminiTts(),
        geminiApiService: GeminiApiService(
          apiKey: 'test-key',
          dioClient: fakeDio((_) async => (statusCode: 200, body: _successJson())),
        ),
        locationResolver: LocationContextResolver(httpClient: client),
      );
      await service.setActiveProvider(AIProvider.geminiApi);

      final result = await service.analyzeAndPlay(
        imageFile,
        knownCoordinates: (lat: 45.75, lon: 4.85, source: 'realtime'),
      );

      expect(result, isNotNull);
      expect(service.lastGpsSource, 'realtime');
      expect(service.lastGpsLatitude, 45.75);
      expect(service.lastGpsLongitude, 4.85);
      expect(service.lastGpsAddress, contains('Lyon'));
    });
  });

  group('LocationService.getCurrentRawCoordinates', () {
    test('returns null gracefully with no platform channel bound', () async {
      final result = await LocationService.getCurrentRawCoordinates();
      expect(result, isNull);
    });
  });
}
