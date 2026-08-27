import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:audiolens/services/audio_guide_service.dart';
import 'package:audiolens/services/gemini_api_service.dart';
import 'package:audiolens/services/gemini_tts_service.dart';
import 'package:audiolens/services/settings_service.dart';
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
  _FakeGeminiTts({this.fail = false}) : super(apiKey: 'test-key');

  final bool fail;
  bool speakCalled = false;

  @override
  Future<void> speak(String text, {CancelToken? cancelToken, double speed = 1.0}) async {
    speakCalled = true;
    if (fail) throw Exception('Gemini TTS 429');
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
    tmpDir = Directory.systemTemp.createTempSync('script-only-mode');
    // #288: routes AudioGuideService's own getTemporaryDirectory() calls
    // (the shared gemini_tts_output.wav path) into this test's isolated
    // tmpDir, so a test can plant a file there to simulate a stale
    // leftover from an earlier Gemini TTS call.
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

  group('analyzeAndPlay(generateAudio: false) — T16', () {
    test('stops after analysis: scriptReady, no audio, TTS never called', () async {
      final native = _FakeNativeTts();
      final geminiTts = _FakeGeminiTts();
      final service = AudioGuideService(
        nativeTtsService: native,
        geminiTtsService: geminiTts,
        geminiApiService: _successApi(),
      );
      await service.setActiveProvider(AIProvider.geminiApi);

      final result = await service.analyzeAndPlay(tempImage(), generateAudio: false);

      expect(result, isNotNull);
      expect(result!.title, 'La Joconde');
      expect(service.state, GuideState.scriptReady);
      expect(service.lastAudioPath, isNull);
      expect(native.speakCalled, isFalse);
      expect(geminiTts.speakCalled, isFalse);
    });

    test('default (generateAudio: true) still synthesizes as before', () async {
      final native = _FakeNativeTts();
      final geminiTts = _FakeGeminiTts();
      final service = AudioGuideService(
        nativeTtsService: native,
        geminiTtsService: geminiTts,
        geminiApiService: _successApi(),
      );
      await service.setActiveProvider(AIProvider.geminiApi);

      final result = await service.analyzeAndPlay(tempImage());

      expect(result, isNotNull);
      expect(service.state, GuideState.speaking);
      expect(geminiTts.speakCalled, isTrue);
    });
  });

  group('generateAudioForScript — T16', () {
    test('synthesizes and plays a given script without re-running GPS/AI', () async {
      final native = _FakeNativeTts();
      final geminiTts = _FakeGeminiTts();
      final service = AudioGuideService(nativeTtsService: native, geminiTtsService: geminiTts);
      // #253: TTS now follows the active AI provider, not just "is a
      // Gemini TTS instance configured" — this test wants the Gemini
      // path, so it has to actually select it.
      await service.setActiveProvider(AIProvider.geminiApi);

      final result = await service.generateAudioForScript(
        title: 'Titre existant',
        script: 'Script déjà en base.',
        locationName: 'Paris',
      );

      expect(result, isNotNull);
      expect(result!.title, 'Titre existant');
      expect(result.script, 'Script déjà en base.');
      expect(service.state, GuideState.speaking);
      expect(geminiTts.speakCalled, isTrue);
      expect(native.speakCalled, isFalse);
    });

    test('falls back to native TTS if Gemini TTS fails', () async {
      final native = _FakeNativeTts();
      final geminiTts = _FakeGeminiTts(fail: true);
      final service = AudioGuideService(nativeTtsService: native, geminiTtsService: geminiTts);
      // #253: without this, geminiTts would never even be attempted
      // (Nano is the default active provider), which would make this
      // test pass for the wrong reason — the fallback path it's meant
      // to exercise would never actually run.
      await service.setActiveProvider(AIProvider.geminiApi);

      final result = await service.generateAudioForScript(
        title: 'Titre',
        script: 'Script.',
      );

      expect(result, isNotNull);
      expect(geminiTts.speakCalled, isTrue);
      expect(service.lastTtsModel, 'native-tts');
      expect(service.ttsWasFallback, isTrue);
      expect(native.speakCalled, isTrue);
    });

    // #288
    test('does not reuse a stale gemini_tts_output.wav left over from an '
        'earlier cloud generation when this synthesis actually used native TTS',
        () async {
      final staleFile = File('${tmpDir.path}/gemini_tts_output.wav');
      await staleFile.writeAsBytes([1, 2, 3]);

      final native = _FakeNativeTts();
      final geminiTts = _FakeGeminiTts();
      final service = AudioGuideService(nativeTtsService: native, geminiTtsService: geminiTts);
      // Active provider defaults to geminiNano — TTS follows it (#253),
      // so this synthesis speaks via native TTS even though geminiTts is
      // configured, exactly like a user who switched to local AI after
      // an earlier cloud-generated entry left this file behind.

      final result = await service.generateAudioForScript(
        title: 'Titre en IA locale',
        script: 'Script.',
      );

      expect(result, isNotNull);
      expect(service.lastTtsModel, 'native-tts');
      expect(native.speakCalled, isTrue);
      expect(geminiTts.speakCalled, isFalse);
      expect(service.lastAudioPath, isNull,
          reason: 'must not pick up the stale file from an earlier Gemini TTS call');
    });

    test('returns null and sets error state when already busy', () async {
      final service = AudioGuideService(
        nativeTtsService: _FakeNativeTts(),
        geminiTtsService: _FakeGeminiTts(),
        geminiApiService: _successApi(),
      );
      await service.setActiveProvider(AIProvider.geminiApi);

      // Kick off a real analysis but don't await it yet.
      final pending = service.analyzeAndPlay(tempImage());

      final result = await service.generateAudioForScript(title: 't', script: 's');

      expect(result, isNull);
      expect(service.state, GuideState.error);

      await pending;
    });
  });

  group('SettingsService.autoGenerateAudio — T16', () {
    test('defaults to true', () async {
      final settings = SettingsService();
      await settings.init();
      expect(settings.autoGenerateAudio, isTrue);
    });

    test('persists false across reload', () async {
      final settings = SettingsService();
      await settings.init();
      await settings.setAutoGenerateAudio(false);
      expect(settings.autoGenerateAudio, isFalse);

      final reloaded = SettingsService();
      await reloaded.init();
      expect(reloaded.autoGenerateAudio, isFalse);
    });
  });
}
