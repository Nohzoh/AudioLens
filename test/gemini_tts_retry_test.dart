import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:audiolens/services/gemini_tts_service.dart';
import 'support/fake_dio_adapter.dart';

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

void main() {
  test('a single 429 is retried once and succeeds, instead of failing the chunk', () async {
    var callCount = 0;
    final dioClient = fakeDio((options) async {
      callCount++;
      if (callCount == 1) return (statusCode: 429, body: 'rate limited');
      return (statusCode: 200, body: _successBody());
    });
    final service = GeminiTtsService(apiKey: 'test-key', dioClient: dioClient);
    final outputPath = '${Directory.systemTemp.path}/gemini_tts_retry_test_ok.wav';

    await service.synthesizeToFile('Some text', outputPath);

    expect(callCount, 2);
    expect(File(outputPath).existsSync(), isTrue);
  });

  test('a second consecutive 429 gives up (only one retry) and throws a '
      'rate-limit-specific exception', () async {
    var callCount = 0;
    final dioClient = fakeDio((options) async {
      callCount++;
      return (statusCode: 429, body: 'rate limited');
    });
    final service = GeminiTtsService(apiKey: 'test-key', dioClient: dioClient);

    await expectLater(
      service.synthesizeToFile('Some text', '${Directory.systemTemp.path}/x.wav'),
      throwsA(isA<GeminiTtsRateLimitException>()),
    );
    expect(callCount, 2);
  });

  test('a success on the first try does not trigger any retry', () async {
    var callCount = 0;
    final dioClient = fakeDio((options) async {
      callCount++;
      return (statusCode: 200, body: _successBody());
    });
    final service = GeminiTtsService(apiKey: 'test-key', dioClient: dioClient);

    await service.synthesizeToFile('Some text', '${Directory.systemTemp.path}/y.wav');

    expect(callCount, 1);
  });

  test('a non-429 error is not retried and is not the rate-limit exception', () async {
    var callCount = 0;
    final dioClient = fakeDio((options) async {
      callCount++;
      return (statusCode: 500, body: 'server error');
    });
    final service = GeminiTtsService(apiKey: 'test-key', dioClient: dioClient);

    await expectLater(
      service.synthesizeToFile('Some text', '${Directory.systemTemp.path}/z.wav'),
      throwsA(isNot(isA<GeminiTtsRateLimitException>())),
    );
    expect(callCount, 1);
  });
}
