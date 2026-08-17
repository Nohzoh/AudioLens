import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:audiolens/services/analysis_foreground_service.dart';
import 'package:audiolens/services/audio_guide_service.dart';
import 'package:audiolens/services/audio_ready_notifier.dart';
import 'package:audiolens/services/gemini_api_service.dart';
import 'package:audiolens/services/gemini_tts_service.dart';
import 'package:audiolens/services/native_tts_service.dart';
import 'package:audiolens/utils/cancel_token.dart';
import 'support/fake_dio_adapter.dart';

/// T85 — these wrappers talk to native code (a foreground service,
/// flutter_local_notifications) that doesn't exist in the Flutter test
/// environment. They must swallow that absence silently rather than throw
/// — both as correct production behavior for platforms without this
/// concept (iOS), and because ~100 other tests construct AudioGuideService
/// without mocking these channels at all.
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

  test('AudioGuideService with real (channel-less) foreground/notifier wrappers '
      'still completes a full analysis', () async {
    SharedPreferences.setMockInitialValues({});
    final tmpDir = Directory.systemTemp.createTempSync('t85-background');
    addTearDown(() => tmpDir.deleteSync(recursive: true));
    final imageFile = File('${tmpDir.path}/photo.jpg')
      ..writeAsBytesSync([0xFF, 0xD8, 0xFF, 0xD9]);

    final service = AudioGuideService(
      nativeTtsService: _FakeNativeTts(),
      geminiTtsService: _FakeGeminiTts(),
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
