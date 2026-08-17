import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:audiolens/services/gemini_api_service.dart';
import 'support/fake_dio_adapter.dart';

/// T75/T48 — the script style option steers the AI prompt's tone/length.
/// These check the actual outgoing request body rather than the parsed
/// result, since the point is what instruction reaches the model.
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
  setUp(() => tmpDir = Directory.systemTemp.createTempSync('script-style'));
  tearDown(() => tmpDir.deleteSync(recursive: true));

  File tempImage() {
    final f = File('${tmpDir.path}/photo.jpg');
    f.writeAsBytesSync([0xFF, 0xD8, 0xFF, 0xD9]);
    return f;
  }

  Future<String> promptSentFor(String? style) async {
    String? capturedBody;
    final service = GeminiApiService(
      apiKey: 'test-key',
      dioClient: fakeDio((options) async {
        capturedBody = options.data as String?;
        return (statusCode: 200, body: _successJson());
      }),
    );
    await service.analyzeImage(tempImage(), style: style);
    return capturedBody!;
  }

  test('no style (default) uses the original immersive wording unchanged', () async {
    final prompt = await promptSentFor(null);
    expect(prompt, contains('narratif et immersif'));
    expect(prompt, contains('Entre 300 et 400 mots'));
  });

  test('style=immersive matches the default wording explicitly', () async {
    final prompt = await promptSentFor('immersive');
    expect(prompt, contains('narratif et immersif'));
  });

  test('style=academic asks for a documentary, factual tone', () async {
    final prompt = await promptSentFor('academic');
    expect(prompt, contains('documentaire et rigoureux'));
    expect(prompt, isNot(contains('narratif et immersif')));
  });

  test('style=anecdotal asks for anecdotes and curiosities', () async {
    final prompt = await promptSentFor('anecdotal');
    expect(prompt, contains('anecdotes, secrets et petites histoires'));
  });

  test('style=concise asks for a shorter script', () async {
    final prompt = await promptSentFor('concise');
    expect(prompt, contains('direct et efficace'));
    expect(prompt, contains('Entre 100 et 150 mots'));
    expect(prompt, isNot(contains('Entre 300 et 400 mots')));
  });
}
