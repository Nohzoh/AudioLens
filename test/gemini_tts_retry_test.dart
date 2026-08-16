import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:audiolens/services/gemini_tts_service.dart';

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
    final client = MockClient((request) async {
      callCount++;
      if (callCount == 1) return http.Response('rate limited', 429);
      return http.Response(_successBody(), 200);
    });
    final service = GeminiTtsService(apiKey: 'test-key', client: client);
    final outputPath = '${Directory.systemTemp.path}/gemini_tts_retry_test_ok.wav';

    await service.synthesizeToFile('Some text', outputPath);

    expect(callCount, 2);
    expect(File(outputPath).existsSync(), isTrue);
  });

  test('a second consecutive 429 gives up (only one retry)', () async {
    var callCount = 0;
    final client = MockClient((request) async {
      callCount++;
      return http.Response('rate limited', 429);
    });
    final service = GeminiTtsService(apiKey: 'test-key', client: client);

    await expectLater(
      service.synthesizeToFile('Some text', '${Directory.systemTemp.path}/x.wav'),
      throwsException,
    );
    expect(callCount, 2);
  });

  test('a success on the first try does not trigger any retry', () async {
    var callCount = 0;
    final client = MockClient((request) async {
      callCount++;
      return http.Response(_successBody(), 200);
    });
    final service = GeminiTtsService(apiKey: 'test-key', client: client);

    await service.synthesizeToFile('Some text', '${Directory.systemTemp.path}/y.wav');

    expect(callCount, 1);
  });

  test('a non-429 error is not retried', () async {
    var callCount = 0;
    final client = MockClient((request) async {
      callCount++;
      return http.Response('server error', 500);
    });
    final service = GeminiTtsService(apiKey: 'test-key', client: client);

    await expectLater(
      service.synthesizeToFile('Some text', '${Directory.systemTemp.path}/z.wav'),
      throwsException,
    );
    expect(callCount, 1);
  });
}
