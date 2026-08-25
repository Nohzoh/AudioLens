import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:audiolens/services/gemini_nano_service.dart';
import 'package:audiolens/services/remote_config_service.dart';
import 'package:audiolens/utils/cancel_token.dart';

/// T68 — GeminiNanoService had zero real coverage before this: the one
/// test that touches it (_FakeNano in fallback_orchestration_test.dart)
/// overrides analyzeImage() entirely, so the real MethodChannel plumbing,
/// lazy init, arg-building, and title extraction never actually ran.
const _channel = MethodChannel('audio_guide/gemini_nano');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<MethodCall> calls;
  late Future<dynamic> Function(MethodCall call) handler;

  setUp(() {
    calls = [];
    handler = (call) async {
      calls.add(call);
      switch (call.method) {
        case 'isAvailable':
          return true;
        case 'initialize':
          return true;
        case 'describeImage':
          return 'Une description generee.';
        default:
          return null;
      }
    };
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) => handler(call));
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
  });

  late Directory tmpDir;
  setUp(() => tmpDir = Directory.systemTemp.createTempSync('gemini-nano-test'));
  tearDown(() => tmpDir.deleteSync(recursive: true));

  File tempImage() {
    final f = File('${tmpDir.path}/photo.jpg');
    f.writeAsBytesSync([0xFF, 0xD8, 0xFF, 0xD9]);
    return f;
  }

  test('isAvailable returns the platform result', () async {
    final service = GeminiNanoService();
    expect(await service.isAvailable(), isTrue);
  });

  test('isAvailable swallows a platform failure and returns false', () async {
    handler = (call) async => throw PlatformException(code: 'NOT_SUPPORTED');
    final service = GeminiNanoService();

    expect(await service.isAvailable(), isFalse);
  });

  test('initialize() only invokes the platform once across repeated calls', () async {
    final service = GeminiNanoService();

    await service.initialize();
    await service.initialize();

    expect(calls.where((c) => c.method == 'initialize'), hasLength(1));
  });

  test('analyzeImage() lazily initializes if not already done', () async {
    final service = GeminiNanoService();

    await service.analyzeImage(tempImage());

    expect(calls.first.method, 'initialize');
    expect(calls.any((c) => c.method == 'describeImage'), isTrue);
  });

  test('analyzeImage() sends imagePath, and only includes locationContext/style '
      'when provided', () async {
    final service = GeminiNanoService();

    await service.analyzeImage(tempImage());

    final call = calls.firstWhere((c) => c.method == 'describeImage');
    final args = call.arguments as Map;
    expect(args['imagePath'], isNotNull);
    expect(args.containsKey('locationContext'), isFalse);
    expect(args.containsKey('style'), isFalse);
    expect(args.containsKey('language'), isFalse);
  });

  test('analyzeImage() includes locationContext and style when given', () async {
    final service = GeminiNanoService();

    await service.analyzeImage(
      tempImage(),
      locationContext: 'Musee du Louvre',
      style: 'academic',
    );

    final call = calls.firstWhere((c) => c.method == 'describeImage');
    final args = call.arguments as Map;
    expect(args['locationContext'], 'Musee du Louvre');
    expect(args['style'], 'academic');
  });

  // #130
  test('analyzeImage() includes language when given', () async {
    final service = GeminiNanoService();

    await service.analyzeImage(tempImage(), language: 'English');

    final call = calls.firstWhere((c) => c.method == 'describeImage');
    final args = call.arguments as Map;
    expect(args['language'], 'English');
  });

  // #170 — maxOutputTokens/temperature were hardcoded in GeminiNanoPlugin.kt;
  // now sourced from RemoteConfigService like the cloud pipeline's own
  // geminiMaxTokens/geminiTemperature.
  test('analyzeImage() sends maxOutputTokens and temperature from RemoteConfigService',
      () async {
    final service = GeminiNanoService();

    await service.analyzeImage(tempImage());

    final call = calls.firstWhere((c) => c.method == 'describeImage');
    final args = call.arguments as Map;
    expect(args['maxOutputTokens'], RemoteConfigService.current.geminiNanoMaxTokens);
    expect(args['temperature'], RemoteConfigService.current.geminiNanoTemperature);
  });

  // #172 — segment 1's prompt now asks for a bracketed title on its own
  // line; this parses it out and keeps it out of the spoken script.
  test('analyzeImage() extracts a bracketed title and strips it from the script',
      () async {
    handler = (call) async {
      calls.add(call);
      if (call.method == 'describeImage') {
        return '[Le Colisee de Rome]\nUn amphitheatre antique impressionnant.';
      }
      return true;
    };
    final service = GeminiNanoService();

    final result = await service.analyzeImage(tempImage());

    expect(result.title, 'Le Colisee de Rome');
    expect(result.script, 'Un amphitheatre antique impressionnant.');
    expect(result.script, isNot(contains('[')));
  });

  test('analyzeImage() falls back to the first-sentence heuristic when the '
      'model does not follow the bracket-title format', () async {
    handler = (call) async {
      calls.add(call);
      if (call.method == 'describeImage') {
        return 'Ceci est la Tour Eiffel sans crochets. Suite du texte.';
      }
      return true;
    };
    final service = GeminiNanoService();

    final result = await service.analyzeImage(tempImage());

    expect(result.title, 'Ceci est la Tour Eiffel sans crochets');
    expect(result.script, 'Ceci est la Tour Eiffel sans crochets. Suite du texte.');
  });

  test('analyzeImage() extracts the title from the first sentence', () async {
    handler = (call) async {
      calls.add(call);
      if (call.method == 'describeImage') {
        return 'Ceci est la Tour Eiffel. Elle a ete construite en 1889.';
      }
      return true;
    };
    final service = GeminiNanoService();

    final result = await service.analyzeImage(tempImage());

    expect(result.title, 'Ceci est la Tour Eiffel');
    expect(result.script, 'Ceci est la Tour Eiffel. Elle a ete construite en 1889.');
  });

  test('analyzeImage() truncates a long first sentence to 50 chars', () async {
    const longSentence =
        'Une phrase extremement longue qui depasse largement la limite de cinquante caracteres autorises.';
    handler = (call) async {
      calls.add(call);
      if (call.method == 'describeImage') return longSentence;
      return true;
    };
    final service = GeminiNanoService();

    final result = await service.analyzeImage(tempImage());

    expect(result.title, endsWith('...'));
    expect(result.title.length, 53); // 50 chars + '...'
  });

  test('analyzeImage() wraps a PlatformException in a plain Exception', () async {
    handler = (call) async {
      calls.add(call);
      if (call.method == 'describeImage') {
        throw PlatformException(code: 'INFERENCE_ERROR', message: 'model not ready');
      }
      return true;
    };
    final service = GeminiNanoService();

    await expectLater(
      service.analyzeImage(tempImage()),
      throwsA(isA<Exception>().having(
        (e) => e.toString(),
        'message',
        contains('model not ready'),
      )),
    );
  });

  test(
      'analyzeImage() maps the AICore "background usage blocked" message to '
      'GeminiNanoBackgroundRestrictedException', () async {
    handler = (call) async {
      calls.add(call);
      if (call.method == 'describeImage') {
        throw PlatformException(
          code: 'INFERENCE_ERROR',
          message: '[ErrorCode 30] Background usage is blocked. '
              'Please use the API when your app is in the foreground instead.',
        );
      }
      return true;
    };
    final service = GeminiNanoService();

    await expectLater(
      service.analyzeImage(tempImage()),
      throwsA(isA<GeminiNanoBackgroundRestrictedException>()),
    );
  });

  // #171 — the cloud pipeline's location_context can run up to ~4500
  // chars; injecting that verbatim into a Nano segment budgeted for only
  // 256 output tokens risks the context alone dominating what little
  // attention the model has to spare.
  test('analyzeImage() truncates a long locationContext before sending it', () async {
    final service = GeminiNanoService();
    final longContext = 'a' * 1000;

    await service.analyzeImage(tempImage(), locationContext: longContext);

    final call = calls.firstWhere((c) => c.method == 'describeImage');
    final sent = (call.arguments as Map)['locationContext'] as String;
    expect(sent.length, lessThan(longContext.length));
    expect(sent.length, lessThanOrEqualTo(400));
  });

  test('analyzeImage() does not truncate a short locationContext', () async {
    final service = GeminiNanoService();

    await service.analyzeImage(tempImage(), locationContext: 'Musee du Louvre');

    final call = calls.firstWhere((c) => c.method == 'describeImage');
    expect((call.arguments as Map)['locationContext'], 'Musee du Louvre');
  });

  // #168 — Nano's raw output went straight to history/TTS with none of
  // the markdown/thinking-leakage cleanup the cloud pipeline applies.
  test('analyzeImage() strips markdown and thinking-leakage lines from the result',
      () async {
    handler = (call) async {
      calls.add(call);
      if (call.method == 'describeImage') {
        return '**La Tour Eiffel** est un monument.\n'
            'let me reconsider the word count here.\n'
            'Elle domine Paris depuis 1889.';
      }
      return true;
    };
    final service = GeminiNanoService();

    final result = await service.analyzeImage(tempImage());

    expect(result.script, isNot(contains('**')));
    expect(result.script, isNot(contains('let me')));
    expect(result.script, contains('La Tour Eiffel'));
    expect(result.script, contains('domine Paris'));
  });

  // #169 — cancelToken was accepted but never consulted; cancellation
  // silently did nothing on this pipeline.
  test('analyzeImage() throws CancelledException immediately if already cancelled, '
      'without calling describeImage', () async {
    final service = GeminiNanoService();
    final token = CancelToken()..cancel();

    await expectLater(
      service.analyzeImage(tempImage(), cancelToken: token),
      throwsA(isA<CancelledException>()),
    );
    expect(calls.any((c) => c.method == 'describeImage'), isFalse);
  });

  test('analyzeImage() throws CancelledException as soon as the token is cancelled '
      'mid-call, without waiting for the native call to finish', () async {
    final describeStarted = Completer<void>();
    final describeResult = Completer<String>();
    handler = (call) async {
      calls.add(call);
      if (call.method == 'describeImage') {
        describeStarted.complete();
        return describeResult.future;
      }
      return true;
    };
    final service = GeminiNanoService();
    final token = CancelToken();

    final analysis = service.analyzeImage(tempImage(), cancelToken: token);
    await describeStarted.future;
    token.cancel();

    await expectLater(analysis, throwsA(isA<CancelledException>()));

    // The native call itself is left to finish on its own — completing
    // it now must not throw into an already-completed Future.
    describeResult.complete('ignored, arrived after cancellation');
  });

  test('dispose() resets init state so a later analyzeImage() re-initializes',
      () async {
    final service = GeminiNanoService();
    await service.initialize();
    expect(calls.where((c) => c.method == 'initialize'), hasLength(1));

    service.dispose();
    await service.analyzeImage(tempImage());

    expect(calls.where((c) => c.method == 'initialize'), hasLength(2));
  });
}
