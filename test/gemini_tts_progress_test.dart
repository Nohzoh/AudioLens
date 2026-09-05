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

/// #329 follow-up: GeminiTtsService.onProgress now polls
/// AudioPlayerPlugin.kt's real MediaPlayer position ("getPosition") rather
/// than estimating from a words-per-second speaking rate, which live use
/// showed drifted visibly from actual audio over a whole script. These
/// tests drive that native call via a mutable [mockPosition]/[mockDuration]
/// pair instead of real timing, since correctness here is "reports
/// whatever the native side says", not any particular wall-clock rate.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmpDir;
  late Completer<dynamic> playWavCompleter;
  late int mockPosition;
  late int mockDuration;

  setUp(() {
    tmpDir = Directory.systemTemp.createTempSync('gemini_tts_progress_test');
    playWavCompleter = Completer<dynamic>();
    mockPosition = 0;
    mockDuration = 10000;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_pathProviderChannel, (call) async {
      if (call.method == 'getTemporaryDirectory') return tmpDir.path;
      return null;
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_audioPlayerChannel, (call) async {
      switch (call.method) {
        case 'playWav':
          return playWavCompleter.future;
        case 'getPosition':
          return {'position': mockPosition, 'duration': mockDuration};
        case 'seekForward':
          mockPosition += (call.arguments as Map)['deltaMs'] as int;
          return null;
        case 'seekBack':
          mockPosition -= (call.arguments as Map)['deltaMs'] as int;
          return null;
      }
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

  test('reports progress from the real native position via polling',
      () async {
    final service = buildService();
    final progressValues = <double>[];
    service.onProgress = progressValues.add;

    await service.speak('some text');
    mockPosition = 5000;
    await Future<void>.delayed(const Duration(milliseconds: 250));

    expect(progressValues, isNotEmpty);
    expect(progressValues.last, closeTo(0.5, 0.01));

    playWavCompleter.complete(null);
    await Future<void>.delayed(Duration.zero);
  });

  test('stops polling once playback completes', () async {
    final service = buildService();
    final progressValues = <double>[];
    service.onProgress = progressValues.add;

    await service.speak('some text');
    mockPosition = 3000;
    await Future<void>.delayed(const Duration(milliseconds: 250));
    expect(progressValues, isNotEmpty);

    playWavCompleter.complete(null);
    await Future<void>.delayed(Duration.zero);
    final countAtComplete = progressValues.length;
    mockPosition = 9000; // shouldn't matter once polling has stopped
    await Future<void>.delayed(const Duration(milliseconds: 250));

    expect(progressValues.length, countAtComplete);
  });

  test('pause() needs no special handling — the real position simply '
      "doesn't advance while paused", () async {
    final service = buildService();
    final progressValues = <double>[];
    service.onProgress = progressValues.add;

    await service.speak('some text');
    mockPosition = 2000;
    await Future<void>.delayed(const Duration(milliseconds: 250));
    await service.pause();
    await Future<void>.delayed(const Duration(milliseconds: 250));
    expect(progressValues.last, closeTo(0.2, 0.01));

    await service.resume();
    mockPosition = 6000;
    await Future<void>.delayed(const Duration(milliseconds: 250));
    expect(progressValues.last, closeTo(0.6, 0.01));

    playWavCompleter.complete(null);
    await Future<void>.delayed(Duration.zero);
  });

  test('skipForward()/skipBack() move the real native position, picked up '
      'by the next poll', () async {
    final service = buildService();
    final progressValues = <double>[];
    service.onProgress = progressValues.add;

    await service.speak('some text');
    mockPosition = 3000;
    await Future<void>.delayed(const Duration(milliseconds: 250));
    final before = progressValues.last;

    await service.skipForward();
    await Future<void>.delayed(const Duration(milliseconds: 250));
    expect(progressValues.last, greaterThan(before));

    final afterForward = progressValues.last;
    await service.skipBack();
    await Future<void>.delayed(const Duration(milliseconds: 250));
    expect(progressValues.last, lessThan(afterForward));

    playWavCompleter.complete(null);
    await Future<void>.delayed(Duration.zero);
  });
}
