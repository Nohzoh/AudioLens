import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:audiolens/services/ai_service.dart';
import 'package:audiolens/services/audio_guide_service.dart';
import 'package:audiolens/services/gemini_api_service.dart';
import 'package:audiolens/services/gemini_nano_service.dart';
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
  _FakeGeminiTts({required this.fail}) : super(apiKey: 'test-key');

  final bool fail;
  bool speakCalled = false;

  @override
  Future<void> speak(String text, {CancelToken? cancelToken, double speed = 1.0}) async {
    speakCalled = true;
    if (fail) {
      throw Exception('Gemini TTS 429');
    }
  }
}

class _FakeNano extends GeminiNanoService {
  _FakeNano({required this.available});

  final bool available;
  bool analyzeCalled = false;

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<void> initialize() async {}

  @override
  Future<AudioGuideResult> analyzeImage(
    File imageFile, {
    String? locationContext,
    CancelToken? cancelToken,
    String? style,
  }) async {
    analyzeCalled = true;
    return const AudioGuideResult(
      title: 'Nano',
      script: 'Script local de secours.',
    );
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

GeminiApiService _failingApi() => GeminiApiService(
      apiKey: 'test-key',
      dioClient: fakeDio(
        (_) async => (statusCode: 429, body: jsonEncode({'error': {'message': 'quota'}})),
      ),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmpDir;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    tmpDir = Directory.systemTemp.createTempSync('fallback-orchestration');
  });

  tearDown(() {
    tmpDir.deleteSync(recursive: true);
  });

  File tempImage() {
    final f = File('${tmpDir.path}/photo.jpg');
    f.writeAsBytesSync([0xFF, 0xD8, 0xFF, 0xD9]);
    return f;
  }

  test('Gemini TTS failure -> falls back to native TTS and flags ttsWasFallback', () async {
    final native = _FakeNativeTts();
    final geminiTts = _FakeGeminiTts(fail: true);
    final service = AudioGuideService(
      nativeTtsService: native,
      geminiTtsService: geminiTts,
      geminiApiService: _successApi(),
    );
    await service.setActiveProvider(AIProvider.geminiApi);

    final result = await service.analyzeAndPlay(tempImage());

    expect(result, isNotNull);
    expect(geminiTts.speakCalled, isTrue);
    expect(native.speakCalled, isTrue);
    expect(service.lastTtsModel, 'native-tts');
    expect(service.ttsWasFallback, isTrue);
    expect(service.state, GuideState.speaking);
  });

  test('Gemini TTS success -> no fallback, ttsWasFallback false', () async {
    final native = _FakeNativeTts();
    final geminiTts = _FakeGeminiTts(fail: false);
    final service = AudioGuideService(
      nativeTtsService: native,
      geminiTtsService: geminiTts,
      geminiApiService: _successApi(),
    );
    await service.setActiveProvider(AIProvider.geminiApi);

    await service.analyzeAndPlay(tempImage());

    expect(geminiTts.speakCalled, isTrue);
    expect(native.speakCalled, isFalse);
    expect(service.lastTtsModel, 'gemini-tts');
    expect(service.ttsWasFallback, isFalse);
  });

  test('Cloud AI failure -> falls back to local Gemini Nano', () async {
    final nano = _FakeNano(available: true);
    final service = AudioGuideService(
      geminiTtsService: _FakeGeminiTts(fail: false),
      geminiApiService: _failingApi(),
      nanoService: nano,
    );
    await service.init();
    await service.setActiveProvider(AIProvider.geminiApi);

    final result = await service.analyzeAndPlay(tempImage());

    expect(result, isNotNull);
    expect(nano.analyzeCalled, isTrue);
    expect(service.activeProvider, AIProvider.geminiNano);
    expect(result!.script, 'Script local de secours.');
  });

  test('GPS refused -> analysis still completes with gpsSource none', () async {
    final service = AudioGuideService(
      geminiTtsService: _FakeGeminiTts(fail: false),
      geminiApiService: _successApi(),
    );
    await service.setActiveProvider(AIProvider.geminiApi);

    final result = await service.analyzeAndPlay(tempImage());

    expect(result, isNotNull);
    expect(service.lastGpsSource, 'none');
    expect(service.lastGpsLatitude, isNull);
    expect(service.lastGpsLongitude, isNull);
    expect(service.state, GuideState.speaking);
  });

  test('No AI service available -> clear error, no crash', () async {
    final service = AudioGuideService(
      geminiTtsService: _FakeGeminiTts(fail: false),
    );
    await service.setActiveProvider(AIProvider.geminiApi);

    final result = await service.analyzeAndPlay(tempImage());

    expect(result, isNull);
    expect(service.state, GuideState.error);
    expect(service.errorMessage, contains('Aucun service IA'));
  });
}
