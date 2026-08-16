import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:audiolens/services/audio_guide_service.dart';
import 'package:audiolens/services/gemini_api_service.dart';
import 'package:audiolens/services/gemini_tts_service.dart';
import 'package:audiolens/services/settings_service.dart';
import 'package:audiolens/services/native_tts_service.dart';
import 'package:audiolens/utils/cancel_token.dart';

class _FakeNativeTts extends NativeTtsService {
  bool speakCalled = false;

  @override
  Future<void> speak(String text, {CancelToken? cancelToken}) async {
    speakCalled = true;
    onComplete?.call();
  }
}

class _FakeGeminiTts extends GeminiTtsService {
  _FakeGeminiTts({this.fail = false}) : super(apiKey: 'test-key');

  final bool fail;
  bool speakCalled = false;

  @override
  Future<void> speak(String text, {CancelToken? cancelToken}) async {
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
      client: MockClient((_) async => http.Response(_successJson(), 200)),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmpDir;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    tmpDir = Directory.systemTemp.createTempSync('script-only-mode');
  });

  tearDown(() {
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

      final result = await service.generateAudioForScript(
        title: 'Titre',
        script: 'Script.',
      );

      expect(result, isNotNull);
      expect(service.lastTtsModel, 'native-tts');
      expect(service.ttsWasFallback, isTrue);
      expect(native.speakCalled, isTrue);
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
