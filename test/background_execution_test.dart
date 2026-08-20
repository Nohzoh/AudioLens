import 'dart:convert';
import 'dart:io';
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
