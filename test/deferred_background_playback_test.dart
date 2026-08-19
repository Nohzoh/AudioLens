import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:audiolens/services/audio_guide_service.dart';
import 'package:audiolens/services/audio_ready_notifier.dart';
import 'package:audiolens/services/gemini_api_service.dart';
import 'package:audiolens/services/gemini_tts_service.dart';
import 'package:audiolens/services/native_tts_service.dart';
import 'package:audiolens/utils/cancel_token.dart';
import 'support/fake_dio_adapter.dart';

class _FakeNativeTts extends NativeTtsService {
  bool speakCalled = false;

  @override
  Future<void> speak(String text, {CancelToken? cancelToken, double speed = 1.0}) async {
    speakCalled = true;
    onComplete?.call();
  }
}

class _FakeGeminiTts extends GeminiTtsService {
  _FakeGeminiTts({this.failSynthesis = false}) : super(apiKey: 'test-key');

  final bool failSynthesis;
  bool speakCalled = false;
  bool synthesizeToFileCalled = false;

  @override
  Future<void> speak(String text, {CancelToken? cancelToken, double speed = 1.0}) async {
    speakCalled = true;
  }

  // Overridden so the background pre-synthesis path (T85 follow-up) never
  // makes a real network call in tests — the base implementation isn't
  // stubbed here since only speak() was previously exercised in this file.
  @override
  Future<void> synthesizeToFile(String text, String outputPath, {CancelToken? cancelToken}) async {
    synthesizeToFileCalled = true;
    if (failSynthesis) throw Exception('Gemini TTS 429');
    await File(outputPath).writeAsBytes([0, 1, 2, 3]);
  }
}

/// Spies on notifyReady() calls without touching the real
/// flutter_local_notifications plugin (unavailable in the test
/// environment, same rationale as background_execution_test.dart).
class _SpyAudioReadyNotifier extends AudioReadyNotifier {
  String? lastPayload;
  int readyCalls = 0;

  @override
  Future<void> notifyReady({String? payload}) async {
    readyCalls++;
    lastPayload = payload;
  }
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

GeminiApiService _successApi() => GeminiApiService(
      apiKey: 'test-key',
      dioClient: fakeDio((_) async => (statusCode: 200, body: _successJson())),
    );

const _pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmpDir;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    tmpDir = Directory.systemTemp.createTempSync('deferred-background-playback');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_pathProviderChannel, (call) async {
      if (call.method == 'getTemporaryDirectory') return tmpDir.path;
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_pathProviderChannel, null);
    tmpDir.deleteSync(recursive: true);
  });

  File tempImage() {
    final f = File('${tmpDir.path}/photo.jpg');
    f.writeAsBytesSync([0xFF, 0xD8, 0xFF, 0xD9]);
    return f;
  }

  group('analyzeAndPlay auto-play deferred while backgrounded', () {
    test(
        'backgrounded with Gemini TTS: pre-synthesizes (not played), '
        'notifyReady carries entryId', () async {
      TestWidgetsFlutterBinding.instance
          .handleAppLifecycleStateChanged(AppLifecycleState.paused);

      final native = _FakeNativeTts();
      final geminiTts = _FakeGeminiTts();
      final notifier = _SpyAudioReadyNotifier();
      final service = AudioGuideService(
        nativeTtsService: native,
        geminiTtsService: geminiTts,
        geminiApiService: _successApi(),
        audioReadyNotifier: notifier,
      );
      await service.setActiveProvider(AIProvider.geminiApi);

      final result = await service.analyzeAndPlay(tempImage(), entryId: 42);

      expect(result, isNotNull);
      expect(service.state, GuideState.scriptReady);
      // Pre-synthesized and cached so a notification tap can play it
      // instantly, but never actually played while backgrounded.
      expect(geminiTts.synthesizeToFileCalled, isTrue);
      expect(service.lastAudioPath, isNotNull);
      expect(service.lastTtsModel, 'gemini-tts');
      expect(native.speakCalled, isFalse);
      expect(geminiTts.speakCalled, isFalse);
      expect(notifier.readyCalls, 1);
      expect(notifier.lastPayload, '42');
    });

    test('backgrounded, pre-synthesis fails: falls back to script-only, no crash', () async {
      TestWidgetsFlutterBinding.instance
          .handleAppLifecycleStateChanged(AppLifecycleState.paused);

      final native = _FakeNativeTts();
      final geminiTts = _FakeGeminiTts(failSynthesis: true);
      final notifier = _SpyAudioReadyNotifier();
      final service = AudioGuideService(
        nativeTtsService: native,
        geminiTtsService: geminiTts,
        geminiApiService: _successApi(),
        audioReadyNotifier: notifier,
      );
      await service.setActiveProvider(AIProvider.geminiApi);

      final result = await service.analyzeAndPlay(tempImage(), entryId: 5);

      expect(result, isNotNull);
      expect(service.state, GuideState.scriptReady);
      expect(service.lastAudioPath, isNull);
      expect(notifier.lastPayload, '5');
    });

    test('backgrounded without Gemini TTS configured: script-only as before', () async {
      TestWidgetsFlutterBinding.instance
          .handleAppLifecycleStateChanged(AppLifecycleState.paused);

      final native = _FakeNativeTts();
      final notifier = _SpyAudioReadyNotifier();
      final service = AudioGuideService(
        nativeTtsService: native,
        geminiApiService: _successApi(),
        audioReadyNotifier: notifier,
      );
      await service.setActiveProvider(AIProvider.geminiApi);

      final result = await service.analyzeAndPlay(tempImage(), entryId: 6);

      expect(result, isNotNull);
      expect(service.state, GuideState.scriptReady);
      expect(service.lastAudioPath, isNull);
      expect(native.speakCalled, isFalse);
      expect(notifier.lastPayload, '6');
    });

    test('resumed: auto-play unaffected (regression guard)', () async {
      TestWidgetsFlutterBinding.instance
          .handleAppLifecycleStateChanged(AppLifecycleState.resumed);

      final native = _FakeNativeTts();
      final geminiTts = _FakeGeminiTts();
      final notifier = _SpyAudioReadyNotifier();
      final service = AudioGuideService(
        nativeTtsService: native,
        geminiTtsService: geminiTts,
        geminiApiService: _successApi(),
        audioReadyNotifier: notifier,
      );
      await service.setActiveProvider(AIProvider.geminiApi);

      final result = await service.analyzeAndPlay(tempImage(), entryId: 7);

      expect(result, isNotNull);
      expect(service.state, GuideState.speaking);
      expect(geminiTts.speakCalled, isTrue);
      expect(notifier.readyCalls, 1);
      expect(notifier.lastPayload, isNull);
    });

    test('backgrounded + generateAudio:false (T16): scriptReady with no payload', () async {
      TestWidgetsFlutterBinding.instance
          .handleAppLifecycleStateChanged(AppLifecycleState.paused);

      final native = _FakeNativeTts();
      final geminiTts = _FakeGeminiTts();
      final notifier = _SpyAudioReadyNotifier();
      final service = AudioGuideService(
        nativeTtsService: native,
        geminiTtsService: geminiTts,
        geminiApiService: _successApi(),
        audioReadyNotifier: notifier,
      );
      await service.setActiveProvider(AIProvider.geminiApi);

      final result =
          await service.analyzeAndPlay(tempImage(), generateAudio: false, entryId: 99);

      expect(result, isNotNull);
      expect(service.state, GuideState.scriptReady);
      expect(notifier.lastPayload, isNull);
    });
  });
}
