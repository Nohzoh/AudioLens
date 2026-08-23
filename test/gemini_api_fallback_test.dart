import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:audiolens/services/gemini_api_service.dart';
import 'package:audiolens/services/remote_config_service.dart';
import 'support/fake_dio_adapter.dart';

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

String _errorJson() => jsonEncode({
  'error': {'message': 'rate limit exceeded'},
});

/// A well-formed 200 body whose candidate carries [text] — used to build
/// the various "succeeded but unusable" shapes below.
String _textPayload(String text) => jsonEncode({
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

/// What thinking-budget exhaustion looks like: a valid 200, empty text.
String _emptyTextJson() => _textPayload('');

String _modelFromPath(String path) =>
    RegExp(r'/models/([^:]+):').firstMatch(path)?.group(1) ?? '?';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final cfg = RemoteConfigService.current;
  final primary = cfg.geminiModel;
  final fallbacks =
      cfg.geminiModelFallbacks.where((m) => m != primary).toList();
  final fb1 = fallbacks.first;

  late Directory tmpDir;
  setUp(() {
    tmpDir = Directory.systemTemp.createTempSync('gemini-api-fallback');
  });
  tearDown(() {
    tmpDir.deleteSync(recursive: true);
  });

  File tempImage() {
    final f = File('${tmpDir.path}/photo.jpg');
    f.writeAsBytesSync([0xFF, 0xD8, 0xFF, 0xD9]);
    return f;
  }

  test('primary 429 -> falls back to next model', () async {
    final requested = <String>[];
    final service = GeminiApiService(
      apiKey: 'test-key',
      dioClient: fakeDio((options) async {
        final model = _modelFromPath(options.uri.path);
        requested.add(model);
        if (model == primary) {
          return (statusCode: 429, body: _errorJson());
        }
        return (statusCode: 200, body: _successJson());
      }),
    );

    final result = await service.analyzeImage(tempImage());

    expect(requested, [primary, fb1]);
    expect(service.lastUsedModel, fb1);
    expect(result.title, 'La Joconde');
    expect(service.lastAttempts, hasLength(2));
    expect(service.lastAttempts.first, startsWith('✗ $primary'));
    expect(service.lastAttempts.last, startsWith('✓ $fb1'));
  });

  test('primary 404 -> falls back to next model', () async {
    final requested = <String>[];
    final service = GeminiApiService(
      apiKey: 'test-key',
      dioClient: fakeDio((options) async {
        final model = _modelFromPath(options.uri.path);
        requested.add(model);
        if (model == primary) {
          return (statusCode: 404, body: _errorJson());
        }
        return (statusCode: 200, body: _successJson());
      }),
    );

    final result = await service.analyzeImage(tempImage());

    expect(requested, [primary, fb1]);
    expect(service.lastUsedModel, fb1);
    expect(result.title, 'La Joconde');
  });

  test('primary 503 -> falls back to next model', () async {
    final requested = <String>[];
    final service = GeminiApiService(
      apiKey: 'test-key',
      dioClient: fakeDio((options) async {
        final model = _modelFromPath(options.uri.path);
        requested.add(model);
        if (model == primary) {
          return (statusCode: 503, body: _errorJson());
        }
        return (statusCode: 200, body: _successJson());
      }),
    );

    final result = await service.analyzeImage(tempImage());

    expect(requested, [primary, fb1]);
    expect(service.lastUsedModel, fb1);
    expect(result.title, 'La Joconde');
  });

  test('network error on primary -> next model attempted', () async {
    final requested = <String>[];
    final service = GeminiApiService(
      apiKey: 'test-key',
      dioClient: fakeDio((options) async {
        final model = _modelFromPath(options.uri.path);
        requested.add(model);
        if (model == primary) {
          throw const SocketException('network down');
        }
        return (statusCode: 200, body: _successJson());
      }),
    );

    final result = await service.analyzeImage(tempImage());

    expect(requested, [primary, fb1]);
    expect(service.lastUsedModel, fb1);
    expect(result.title, 'La Joconde');
  });

  test('primary succeeds -> no fallback attempted', () async {
    final requested = <String>[];
    final service = GeminiApiService(
      apiKey: 'test-key',
      dioClient: fakeDio((options) async {
        requested.add(_modelFromPath(options.uri.path));
        return (statusCode: 200, body: _successJson());
      }),
    );

    final result = await service.analyzeImage(tempImage());

    expect(requested, [primary]);
    expect(service.lastUsedModel, primary);
    expect(service.lastAttempts, ['✓ $primary']);
    expect(result.title, 'La Joconde');
  });

  test('all models fail -> throws with full trace', () async {
    final requested = <String>[];
    final service = GeminiApiService(
      apiKey: 'test-key',
      dioClient: fakeDio((options) async {
        requested.add(_modelFromPath(options.uri.path));
        return (statusCode: 429, body: _errorJson());
      }),
    );

    await expectLater(
      service.analyzeImage(tempImage()),
      throwsA(isA<Exception>().having(
        (e) => e.toString(),
        'message',
        contains('tous les modèles ont échoué'),
      )),
    );

    expect(requested, hasLength(fallbacks.length + 1));
    expect(service.lastAttempts, hasLength(fallbacks.length + 1));
    expect(service.lastUsedModel, isNull);
  });

  // A 200 with no usable text is what a thinking-budget exhaustion looks
  // like from the client's side: the request succeeded, the model just had
  // no tokens left to answer with. Before this was handled, the loop broke
  // on the 200 and then threw, never reaching a fallback model.
  test('primary returns 200 with empty text -> falls back to next model', () async {
    final requested = <String>[];
    final service = GeminiApiService(
      apiKey: 'test-key',
      dioClient: fakeDio((options) async {
        final model = _modelFromPath(options.uri.path);
        requested.add(model);
        if (model == primary) {
          return (statusCode: 200, body: _emptyTextJson());
        }
        return (statusCode: 200, body: _successJson());
      }),
    );

    final result = await service.analyzeImage(tempImage());

    expect(requested, [primary, fb1]);
    expect(service.lastUsedModel, fb1);
    expect(result.title, 'La Joconde');
    expect(service.lastAttempts.first, startsWith('✗ $primary (200'));
    expect(service.lastAttempts.last, startsWith('✓ $fb1'));
  });

  test('primary returns 200 with no candidates at all -> falls back', () async {
    final requested = <String>[];
    final service = GeminiApiService(
      apiKey: 'test-key',
      dioClient: fakeDio((options) async {
        final model = _modelFromPath(options.uri.path);
        requested.add(model);
        if (model == primary) {
          return (statusCode: 200, body: jsonEncode({'candidates': []}));
        }
        return (statusCode: 200, body: _successJson());
      }),
    );

    final result = await service.analyzeImage(tempImage());

    expect(requested, [primary, fb1]);
    expect(service.lastUsedModel, fb1);
    expect(result.title, 'La Joconde');
  });

  test('primary returns unrecoverable JSON debris -> falls back', () async {
    final requested = <String>[];
    final service = GeminiApiService(
      apiKey: 'test-key',
      dioClient: fakeDio((options) async {
        final model = _modelFromPath(options.uri.path);
        requested.add(model);
        if (model == primary) {
          // JSON-shaped but neither field recoverable — must not be shown
          // verbatim (T90), and must not end the loop either.
          return (statusCode: 200, body: _textPayload('{"title": , "script": }'));
        }
        return (statusCode: 200, body: _successJson());
      }),
    );

    final result = await service.analyzeImage(tempImage());

    expect(requested, [primary, fb1]);
    expect(service.lastUsedModel, fb1);
    expect(result.title, 'La Joconde');
  });

  test('every model returns an empty 200 -> throws with full trace', () async {
    final requested = <String>[];
    final service = GeminiApiService(
      apiKey: 'test-key',
      dioClient: fakeDio((options) async {
        requested.add(_modelFromPath(options.uri.path));
        return (statusCode: 200, body: _emptyTextJson());
      }),
    );

    await expectLater(
      service.analyzeImage(tempImage()),
      throwsA(isA<Exception>().having(
        (e) => e.toString(),
        'message',
        contains('tous les modèles ont échoué'),
      )),
    );

    expect(requested, hasLength(fallbacks.length + 1));
    expect(service.lastUsedModel, isNull);
  });

  // Guards the plain-text branch: a model ignoring the JSON instruction
  // entirely still produces usable content, so it must NOT be treated as
  // an unusable response and skipped over.
  test('plain-text (non-JSON) 200 is accepted, not treated as a failure', () async {
    final requested = <String>[];
    final service = GeminiApiService(
      apiKey: 'test-key',
      dioClient: fakeDio((options) async {
        requested.add(_modelFromPath(options.uri.path));
        return (
          statusCode: 200,
          body: _textPayload('Bienvenue devant ce chef-d\'oeuvre. Il fut peint en 1503.'),
        );
      }),
    );

    final result = await service.analyzeImage(tempImage());

    expect(requested, [primary]);
    expect(service.lastUsedModel, primary);
    expect(result.script, contains('chef-d\'oeuvre'));
  });

  test('HTTP 500 -> rethrows immediately, stops the fallback loop', () async {
    final requested = <String>[];
    final service = GeminiApiService(
      apiKey: 'test-key',
      dioClient: fakeDio((options) async {
        requested.add(_modelFromPath(options.uri.path));
        return (statusCode: 500, body: 'internal error');
      }),
    );

    await expectLater(
      service.analyzeImage(tempImage()),
      throwsA(isA<Exception>().having(
        (e) => e.toString(),
        'message',
        contains('Gemini API erreur 500'),
      )),
    );

    expect(requested, hasLength(1));
  });
}
