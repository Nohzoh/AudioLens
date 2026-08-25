import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:audiolens/services/gemini_api_service.dart';
import 'support/fake_dio_adapter.dart';

/// #130 — the output language option steers the AI prompt's language,
/// independent of the app's own interface language. These check the actual
/// outgoing request body rather than the parsed result, since the point is
/// what instruction reaches the model — same technique as script_style_test.dart.
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

  late Directory tmpDir;
  setUp(() => tmpDir = Directory.systemTemp.createTempSync('output-language'));
  tearDown(() => tmpDir.deleteSync(recursive: true));

  File tempImage() {
    final f = File('${tmpDir.path}/photo.jpg');
    f.writeAsBytesSync([0xFF, 0xD8, 0xFF, 0xD9]);
    return f;
  }

  Future<String> promptSentFor(String? language) async {
    String? capturedBody;
    final service = GeminiApiService(
      apiKey: 'test-key',
      dioClient: fakeDio((options) async {
        capturedBody = options.data as String?;
        return (statusCode: 200, body: _successJson());
      }),
    );
    await service.analyzeImage(tempImage(), language: language);
    return capturedBody!;
  }

  test('no language given omits the directive entirely (existing behavior unchanged)',
      () async {
    final prompt = await promptSentFor(null);
    expect(prompt, isNot(contains('exclusivement en')));
  });

  test('language=English adds an explicit language directive', () async {
    final prompt = await promptSentFor('English');
    expect(prompt, contains('exclusivement en English'));
  });

  test('language=Español adds an explicit language directive', () async {
    final prompt = await promptSentFor('Español');
    expect(prompt, contains('exclusivement en Español'));
  });
}
