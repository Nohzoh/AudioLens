import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:audiolens/services/location_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('audio_guide/location');

  void mockRequestLocation(Future<Object?> Function() handler) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'requestLocation') return handler();
      return null;
    });
  }

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('getCurrentLocation times out instead of hanging forever (T07)', () async {
    // Simulates a native side that never resolves — GPS stuck with no fix,
    // as observed with no timeout at all before this fix.
    mockRequestLocation(() => Completer<Object?>().future);

    final result = await LocationService.getCurrentLocation(
      timeout: const Duration(milliseconds: 50),
    );

    expect(result.status, LocationPermissionStatus.denied);
  });

  test('getCurrentRawCoordinates times out instead of hanging forever (T07)', () async {
    mockRequestLocation(() => Completer<Object?>().future);

    final result = await LocationService.getCurrentRawCoordinates(
      timeout: const Duration(milliseconds: 50),
    );

    expect(result, isNull);
  });

  test('getCurrentLocation still resolves normally within the timeout', () async {
    mockRequestLocation(() async => {
      'status': 'granted',
      'latitude': 48.8566,
      'longitude': 2.3522,
    });
    final client = MockClient((_) async => http.Response('{}', 200));

    final result = await LocationService.getCurrentLocation(
      timeout: const Duration(seconds: 1),
      client: client,
    );

    expect(result.status, LocationPermissionStatus.granted);
    expect(result.info?.latitude, 48.8566);
  });
}
