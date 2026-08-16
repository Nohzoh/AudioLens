import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:audiolens/services/gemini_api_service.dart';

/// T90 — the title/script JSON parsing had "holes in the net" beyond what
/// the original indexOf/lastIndexOf brace matching handled: markdown
/// fences, braces inside the script text, and unescaped quotes inside the
/// script text all could (and did, per real user reports) end up showing
/// raw JSON as the analysis title.
String _responseWithText(String text) => jsonEncode({
      'candidates': [
        {
          'content': {
            'parts': [
              {'text': text},
            ],
          },
        },
      ],
    });

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmpDir;
  setUp(() {
    tmpDir = Directory.systemTemp.createTempSync('gemini-title-parsing');
  });
  tearDown(() {
    tmpDir.deleteSync(recursive: true);
  });

  File tempImage() {
    final f = File('${tmpDir.path}/photo.jpg');
    f.writeAsBytesSync([0xFF, 0xD8, 0xFF, 0xD9]);
    return f;
  }

  Future<GeminiApiService> serviceReturning(String text) async {
    return GeminiApiService(
      apiKey: 'test-key',
      client: MockClient((request) async => http.Response(_responseWithText(text), 200)),
    );
  }

  test('plain JSON, no fence — baseline still works', () async {
    final service = await serviceReturning(
        '{"title": "La Joconde", "script": "Bienvenue devant ce chef-d\'oeuvre."}');

    final result = await service.analyzeImage(tempImage());

    expect(result.title, 'La Joconde');
    expect(result.script, "Bienvenue devant ce chef-d'oeuvre.");
  });

  test('JSON wrapped in a ```json markdown fence is still parsed cleanly', () async {
    final service = await serviceReturning(
        '```json\n{"title": "La Tour Eiffel", "script": "Un symbole de Paris."}\n```');

    final result = await service.analyzeImage(tempImage());

    expect(result.title, 'La Tour Eiffel');
    expect(result.script, 'Un symbole de Paris.');
  });

  test('a literal brace inside the script text no longer breaks the boundary match', () async {
    // The old lastIndexOf('}') would have matched this inner brace
    // instead of the object's real closing brace.
    final service = await serviceReturning(
        '{"title": "Architecture gothique", '
        '"script": "Remarquez les motifs en accolade {comme celui-ci} sur la facade."}');

    final result = await service.analyzeImage(tempImage());

    expect(result.title, 'Architecture gothique');
    expect(result.script, contains('accolade {comme celui-ci}'));
  });

  test('an unescaped quote inside script breaks full JSON parsing, but the '
      'title is still recovered via the regex fallback', () async {
    final service = await serviceReturning(
        '{"title": "Le mot "liberte"", "script": "Une histoire sur ce mot."}');

    final result = await service.analyzeImage(tempImage());

    expect(result.title, isNot(contains('{')));
    expect(result.title, isNot(contains('"title"')));
  });

  test('non-JSON plain text still falls through to the sentence heuristic', () async {
    final service = await serviceReturning(
        'La Statue de la Liberte. Un cadeau de la France aux Etats-Unis, inaugure en 1886.');

    final result = await service.analyzeImage(tempImage());

    expect(result.title, 'La Statue de la Liberte');
    expect(result.script, contains('inaugure en 1886'));
  });

  test('never shows raw JSON as the title: throws instead when every '
      'parsing layer fails on JSON-shaped text', () async {
    // Malformed beyond what the title-regex can recover (no closing
    // quote for the title value at all) — must not surface the JSON
    // debris verbatim as the title. There's no usable script either, so
    // this must fail loudly (existing retry flow) rather than silently
    // showing broken JSON as if it were real content.
    final service = await serviceReturning('{"title": incomplete garbage here');

    await expectLater(service.analyzeImage(tempImage()), throwsException);
  });

  test('never shows raw JSON as the script: title recovers via regex but '
      'script does not -> throws instead of leaking the JSON wrapper', () async {
    // Regression case for the gap this test file's first version missed:
    // title alone was guarded against showing raw JSON, but a missing
    // "script" match used to fall back to the full raw `text` (still
    // JSON-shaped) as the script.
    final service = await serviceReturning(
        '{"title": "La Tour Eiffel", "script": no closing quote for this one');

    await expectLater(service.analyzeImage(tempImage()), throwsException);
  });

  test('a valid JSON object missing the script field entirely also throws '
      'instead of using the raw text (still containing the title key) as script', () async {
    final service = await serviceReturning('{"title": "La Tour Eiffel"}');

    await expectLater(service.analyzeImage(tempImage()), throwsException);
  });
}
