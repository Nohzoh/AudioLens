import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:audiolens/services/analysis_foreground_service.dart';
import 'package:audiolens/services/audio_guide_service.dart';
import 'package:audiolens/services/audio_ready_notifier.dart';
import 'package:audiolens/services/gemini_api_service.dart';
import 'support/fake_dio_adapter.dart';
import 'support/service_fakes.dart';

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

  test('AnalysisForegroundService.start()/stop() never throw without a platform mock',
      () async {
    final service = AnalysisForegroundService();
    await service.start();
    await service.stop();
  });

  test('AudioReadyNotifier.notifyReady()/notifyFailed() never throw without a platform mock',
      () async {
    final notifier = AudioReadyNotifier();
    await notifier.requestPermissionIfNeeded();
    await notifier.notifyReady();
    await notifier.notifyFailed();
  });

  // #324
  group('AudioReadyNotifier.consumeColdStartPayload()', () {
    const channel = MethodChannel('dexterous.com/flutter/local_notifications');

    // flutter_local_notifications routes getNotificationAppLaunchDetails()
    // through a platform-specific implementation resolved from
    // defaultTargetPlatform, which defaults to the host OS (macOS/Linux
    // here) under `flutter test`, not Android — the mocked channel calls
    // below would otherwise never be reached at all. registerWith() sets
    // FlutterLocalNotificationsPlatform.instance, without which
    // resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
    // resolves to null regardless of the platform override (see the
    // package's own test suite for this exact pairing).
    setUp(() {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      AndroidFlutterLocalNotificationsPlugin.registerWith();
    });
    tearDown(() => debugDefaultTargetPlatformOverride = null);

    test('returns null without a platform mock (best-effort, never throws)',
        () async {
      final notifier = AudioReadyNotifier();
      expect(await notifier.consumeColdStartPayload(), isNull);
    });

    test('returns the deferred entry ID when a "ready" notification tap '
        'cold-started the app', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'initialize') return true;
        if (call.method == 'getNotificationAppLaunchDetails') {
          return {
            'notificationLaunchedApp': true,
            'notificationResponse': {
              'notificationId': 4203,
              'notificationResponseType': 0,
              'payload': '42',
            },
          };
        }
        return null;
      });
      addTearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null));

      final notifier = AudioReadyNotifier();
      expect(await notifier.consumeColdStartPayload(), 42);
    });

    test('returns null on a normal (non-notification) launch', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'initialize') return true;
        if (call.method == 'getNotificationAppLaunchDetails') {
          return {'notificationLaunchedApp': false};
        }
        return null;
      });
      addTearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null));

      final notifier = AudioReadyNotifier();
      expect(await notifier.consumeColdStartPayload(), isNull);
    });

    test('returns null for the script-only case, which carries no payload',
        () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'initialize') return true;
        if (call.method == 'getNotificationAppLaunchDetails') {
          return {
            'notificationLaunchedApp': true,
            'notificationResponse': {
              'notificationId': 4203,
              'notificationResponseType': 0,
              'payload': null,
            },
          };
        }
        return null;
      });
      addTearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null));

      final notifier = AudioReadyNotifier();
      expect(await notifier.consumeColdStartPayload(), isNull);
    });
  });

  test('AudioGuideService with real (channel-less) foreground/notifier wrappers '
      'still completes a full analysis', () async {
    SharedPreferences.setMockInitialValues({});
    final tmpDir = Directory.systemTemp.createTempSync('t85-background');
    addTearDown(() => tmpDir.deleteSync(recursive: true));
    final imageFile = File('${tmpDir.path}/photo.jpg')
      ..writeAsBytesSync([0xFF, 0xD8, 0xFF, 0xD9]);

    final service = AudioGuideService(
      nativeTtsService: FakeNativeTts(),
      geminiTtsService: FakeGeminiTts(),
      geminiApiService: GeminiApiService(
        apiKey: 'test-key',
        dioClient: fakeDio((_) async => (statusCode: 200, body: _successJson())),
      ),
      // foregroundService/audioReadyNotifier deliberately left as defaults
      // (real instances) — the point of this test.
    );
    await service.setActiveProvider(AIProvider.geminiApi);

    final result = await service.analyzeAndPlay(imageFile);

    expect(result, isNotNull);
    expect(result!.title, 'La Joconde');
    expect(service.state, GuideState.speaking);
  });
}
