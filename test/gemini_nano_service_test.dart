import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:audiolens/services/gemini_nano_service.dart';

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
