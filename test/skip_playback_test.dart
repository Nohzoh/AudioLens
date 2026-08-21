import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:audiolens/services/audio_guide_service.dart';
import 'package:audiolens/services/gemini_api_service.dart';
import 'package:audiolens/services/gemini_tts_service.dart';
import 'support/fake_dio_adapter.dart';
import 'support/service_fakes.dart';

/// T118/T21 — skip ±10s only makes sense for the Gemini/cached-WAV
/// engine (native TTS's live synthesis has no seekable position). These
/// tests cover the gating logic (AudioGuideService.canSkip) and, on the
/// Gemini path, that the right native channel call is made with the
/// right arguments. The channel implementation itself (real seek
/// behavior, MediaSession, lock-screen controls) needs a real device —
/// see CHANGELOG.md's verification notes for this task.
const _audioPlayerChannel = MethodChannel('audio_guide/audio_player');

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

  final invokedCalls = <MethodCall>[];

  setUp(() {
    invokedCalls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_audioPlayerChannel, (call) async {
      invokedCalls.add(call);
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_audioPlayerChannel, null);
  });

  test('a fresh (idle) AudioGuideService cannot skip and does nothing when asked to',
      () async {
    final service = AudioGuideService(nativeTtsService: FakeNativeTts());

    expect(service.canSkip, isFalse);
    await service.skipForward();
    await service.skipBack();

    expect(invokedCalls, isEmpty);
  });

  test('canSkip is true once Gemini TTS is actually speaking, and skip calls the right channel method',
      () async {
    SharedPreferences.setMockInitialValues({});
    final tmpDir = Directory.systemTemp.createTempSync('t118-skip');
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
    );
    await service.setActiveProvider(AIProvider.geminiApi);

    final result = await service.analyzeAndPlay(imageFile);

    expect(result, isNotNull);
    expect(service.state, GuideState.speaking);
    expect(service.canSkip, isTrue);

    await service.skipForward();
    await service.skipBack();

    expect(invokedCalls.map((c) => c.method), ['seekForward', 'seekBack']);
    expect(invokedCalls[0].arguments, {'deltaMs': 10000});
    expect(invokedCalls[1].arguments, {'deltaMs': 10000});
  });

  test('GeminiTtsService.skipForward/skipBack call the expected channel method directly',
      () async {
    final tts = GeminiTtsService(apiKey: 'test-key');

    await tts.skipForward();
    await tts.skipBack();

    expect(invokedCalls.map((c) => c.method), ['seekForward', 'seekBack']);
  });
}
