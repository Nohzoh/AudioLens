import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:audiolens/services/audio_guide_service.dart';
import 'package:audiolens/services/gemini_api_service.dart';
import 'package:audiolens/services/gemini_tts_service.dart';
import 'package:audiolens/services/native_tts_service.dart';
import 'package:audiolens/utils/cancel_token.dart';
import 'support/fake_dio_adapter.dart';

/// T15 — the playback speed setting must actually reach whichever TTS
/// engine plays the script, not just live as inert state.
class _FakeNativeTts extends NativeTtsService {
  double? lastSpeed;

  @override
  Future<void> speak(String text, {CancelToken? cancelToken, double speed = 1.0}) async {
    lastSpeed = speed;
    onComplete?.call();
  }
}

class _FakeGeminiTts extends GeminiTtsService {
  _FakeGeminiTts() : super(apiKey: 'test-key');

  double? lastSpeed;

  @override
  Future<void> speak(String text, {CancelToken? cancelToken, double speed = 1.0}) async {
    lastSpeed = speed;
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('setPlaybackSpeed persists and updates the getter', () async {
    final service = AudioGuideService();
    expect(service.playbackSpeed, 1.0);

    await service.setPlaybackSpeed(1.5);
    expect(service.playbackSpeed, 1.5);
  });

  test('the configured speed reaches Gemini TTS during playback', () async {
    final tmpDir = Directory.systemTemp.createTempSync('playback-speed');
    addTearDown(() => tmpDir.deleteSync(recursive: true));
    final imageFile = File('${tmpDir.path}/photo.jpg')
      ..writeAsBytesSync([0xFF, 0xD8, 0xFF, 0xD9]);

    final geminiTts = _FakeGeminiTts();
    final service = AudioGuideService(
      nativeTtsService: _FakeNativeTts(),
      geminiTtsService: geminiTts,
      geminiApiService: GeminiApiService(
        apiKey: 'test-key',
        dioClient: fakeDio((_) async => (statusCode: 200, body: _successJson())),
      ),
    );
    await service.setActiveProvider(AIProvider.geminiApi);
    await service.setPlaybackSpeed(1.25);

    await service.analyzeAndPlay(imageFile);

    expect(geminiTts.lastSpeed, 1.25);
  });

  test('the configured speed reaches native TTS when Gemini TTS is not configured', () async {
    final tmpDir = Directory.systemTemp.createTempSync('playback-speed-native');
    addTearDown(() => tmpDir.deleteSync(recursive: true));
    final imageFile = File('${tmpDir.path}/photo.jpg')
      ..writeAsBytesSync([0xFF, 0xD8, 0xFF, 0xD9]);

    final nativeTts = _FakeNativeTts();
    final service = AudioGuideService(
      nativeTtsService: nativeTts,
      geminiApiService: GeminiApiService(
        apiKey: 'test-key',
        dioClient: fakeDio((_) async => (statusCode: 200, body: _successJson())),
      ),
    );
    await service.setActiveProvider(AIProvider.geminiApi);
    await service.setPlaybackSpeed(0.75);

    await service.analyzeAndPlay(imageFile);

    expect(nativeTts.lastSpeed, 0.75);
  });
}
