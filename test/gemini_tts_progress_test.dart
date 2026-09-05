import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:audiolens/services/gemini_tts_service.dart';
import 'support/fake_dio_adapter.dart';

const _pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');
const _audioPlayerChannel = MethodChannel('audio_guide/audio_player');

String _successBody() => jsonEncode({
      'candidates': [
        {
          'content': {
            'parts': [
              {
                'inlineData': {'data': base64Encode(<int>[1, 2, 3, 4])}
              }
            ]
          }
        }
      ],
    });

/// #329: GeminiTtsService has no real playback-position signal (it plays a
/// pre-rendered WAV via a plain MediaPlayer, no word-boundary callback like
/// native TTS gets) — onProgress is an estimate, ticked by a real
/// Stopwatch/Timer. These tests use short real delays rather than
/// fake_async (not a dependency here) since the tick interval is only
/// 200ms.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmpDir;
  late Completer<dynamic> playWavCompleter;

  setUp(() {
    tmpDir = Directory.systemTemp.createTempSync('gemini_tts_progress_test');
    playWavCompleter = Completer<dynamic>();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_pathProviderChannel, (call) async {
      if (call.method == 'getTemporaryDirectory') return tmpDir.path;
      return null;
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_audioPlayerChannel, (call) async {
      if (call.method == 'playWav') return playWavCompleter.future;
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_pathProviderChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_audioPlayerChannel, null);
    tmpDir.deleteSync(recursive: true);
  });

  GeminiTtsService buildService() => GeminiTtsService(
        apiKey: 'test-key',
        dioClient: fakeDio((_) async => (statusCode: 200, body: _successBody())),
      );

  // 20 words at the 2.5 words/sec heuristic -> ~8s estimated, so a short
  // real wait below lands comfortably mid-playback, never near 1.0.
  String longText() => List.generate(20, (i) => 'mot$i').join(' ');

  test('ticks upward while playing, driven by the estimated speaking rate',
      () async {
    final service = buildService();
    final progressValues = <double>[];
    service.onProgress = progressValues.add;

    await service.speak(longText());
    await Future<void>.delayed(const Duration(milliseconds: 450));

    expect(progressValues, isNotEmpty);
    expect(progressValues.last, greaterThan(0.0));
    expect(progressValues.last, lessThan(1.0));

    playWavCompleter.complete(null);
    await Future<void>.delayed(Duration.zero);
  });

  test('stops changing once playback completes', () async {
    final service = buildService();
    final progressValues = <double>[];
    service.onProgress = progressValues.add;

    await service.speak('mot0 mot1 mot2');
    await Future<void>.delayed(const Duration(milliseconds: 250));
    expect(progressValues, isNotEmpty);

    playWavCompleter.complete(null);
    await Future<void>.delayed(Duration.zero);
    final countAtComplete = progressValues.length;
    await Future<void>.delayed(const Duration(milliseconds: 250));

    expect(progressValues.length, countAtComplete);
  });

  test('pause() freezes the estimate, resume() continues it', () async {
    final service = buildService();
    final progressValues = <double>[];
    service.onProgress = progressValues.add;

    await service.speak(longText());
    await Future<void>.delayed(const Duration(milliseconds: 250));
    await service.pause();
    final afterPause = progressValues.length;
    await Future<void>.delayed(const Duration(milliseconds: 250));
    expect(progressValues.length, afterPause,
        reason: 'no new ticks while paused');

    await service.resume();
    await Future<void>.delayed(const Duration(milliseconds: 250));
    expect(progressValues.length, greaterThan(afterPause));

    playWavCompleter.complete(null);
    await Future<void>.delayed(Duration.zero);
  });

  test('skipForward()/skipBack() immediately adjust the reported progress',
      () async {
    final service = buildService();
    final progressValues = <double>[];
    service.onProgress = progressValues.add;

    await service.speak(longText());
    await Future<void>.delayed(const Duration(milliseconds: 250));
    final before = progressValues.last;

    await service.skipForward();
    expect(progressValues.last, greaterThan(before));

    final afterSkipForward = progressValues.last;
    await service.skipBack();
    expect(progressValues.last, lessThan(afterSkipForward));

    playWavCompleter.complete(null);
    await Future<void>.delayed(Duration.zero);
  });
}
