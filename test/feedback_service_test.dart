import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:audiolens/services/feedback_service.dart';

/// #294 — botToken/chatId are always explicitly injected here rather than
/// relying on the --dart-define defaults: a plain `flutter test` run
/// never passes --dart-define, so those defaults are always empty in
/// this environment (real values only exist in a CI build).
void main() {
  test('isConfigured is true only when both botToken and chatId are set', () {
    expect(FeedbackService(botToken: '', chatId: '').isConfigured, isFalse);
    expect(FeedbackService(botToken: 'x', chatId: '').isConfigured, isFalse);
    expect(FeedbackService(botToken: '', chatId: 'y').isConfigured, isFalse);
    expect(FeedbackService(botToken: 'x', chatId: 'y').isConfigured, isTrue);
  });

  test('send() throws without making a request when not configured', () async {
    var called = false;
    final client = MockClient((request) async {
      called = true;
      return http.Response('', 200);
    });
    final service = FeedbackService(botToken: '', chatId: '', client: client);

    await expectLater(
      service.send('hello', appVersion: '1.0', platform: 'android'),
      throwsA(isA<FeedbackSendException>()),
    );
    expect(called, isFalse);
  });

  test('send() posts to the Telegram sendMessage endpoint with chat_id and '
      'a message prefixed with app version/platform', () async {
    Uri? capturedUri;
    Map<String, String>? capturedFields;
    final client = MockClient((request) async {
      capturedUri = request.url;
      capturedFields = request.bodyFields;
      return http.Response('{"ok":true}', 200);
    });
    final service =
        FeedbackService(botToken: '123:ABC', chatId: '-100999', client: client);

    await service.send('Ça plante au lancement', appVersion: '0.10.3', platform: 'android');

    expect(capturedUri.toString(), 'https://api.telegram.org/bot123:ABC/sendMessage');
    expect(capturedFields?['chat_id'], '-100999');
    expect(capturedFields?['text'], contains('Ça plante au lancement'));
    expect(capturedFields?['text'], contains('0.10.3'));
    expect(capturedFields?['text'], contains('android'));
  });

  test('send() throws FeedbackSendException on a non-200 response', () async {
    final client = MockClient((request) async => http.Response('rate limited', 429));
    final service =
        FeedbackService(botToken: '123:ABC', chatId: '-100999', client: client);

    await expectLater(
      service.send('hello', appVersion: '1.0', platform: 'android'),
      throwsA(isA<FeedbackSendException>()),
    );
  });

  test('send() throws FeedbackSendException on a network exception', () async {
    final client = MockClient((request) async => throw Exception('no network'));
    final service =
        FeedbackService(botToken: '123:ABC', chatId: '-100999', client: client);

    await expectLater(
      service.send('hello', appVersion: '1.0', platform: 'android'),
      throwsA(isA<FeedbackSendException>()),
    );
  });

  // #296
  group('chunking a long message at word boundaries', () {
    test('a short message is sent as a single sendMessage call', () async {
      final requests = <Map<String, String>?>[];
      final client = MockClient((request) async {
        requests.add(request.bodyFields);
        return http.Response('{"ok":true}', 200);
      });
      final service =
          FeedbackService(botToken: '123:ABC', chatId: '-100999', client: client);

      await service.send('short message', appVersion: '1.0', platform: 'android');

      expect(requests, hasLength(1));
    });

    test('a long message is split into several sendMessage calls, none '
        'over 1024 chars, none breaking a word in half', () async {
      final words = List.generate(400, (i) => 'mot$i');
      final longMessage = words.join(' ');

      final texts = <String>[];
      final client = MockClient((request) async {
        texts.add(request.bodyFields['text']!);
        return http.Response('{"ok":true}', 200);
      });
      final service =
          FeedbackService(botToken: '123:ABC', chatId: '-100999', client: client);

      await service.send(longMessage, appVersion: '1.0', platform: 'android');

      expect(texts.length, greaterThan(1));
      for (final text in texts) {
        expect(text.length, lessThanOrEqualTo(1024));
      }
      // Reassembling every chunk (minus the version/platform prefix on
      // the first one) must reproduce every original word, in order —
      // proves nothing was dropped or split mid-word.
      const prefix = 'Feedback AudioLens (1.0, android) :\n\n';
      final reassembled =
          '${texts.first.replaceFirst(prefix, '')} ${texts.skip(1).join(' ')}';
      expect(reassembled.split(RegExp(r'\s+')), words);
    });

    test('a single word longer than the chunk budget is hard-cut rather '
        'than exceeding it or hanging', () async {
      final hugeWord = 'x' * 2500;
      final texts = <String>[];
      final client = MockClient((request) async {
        texts.add(request.bodyFields['text']!);
        return http.Response('{"ok":true}', 200);
      });
      final service =
          FeedbackService(botToken: '123:ABC', chatId: '-100999', client: client);

      await service.send(hugeWord, appVersion: '1.0', platform: 'android');

      expect(texts.length, greaterThan(1));
      for (final text in texts) {
        expect(text.length, lessThanOrEqualTo(1024));
      }
      expect(texts.join(''), contains('x' * 100)); // the word survived, just cut up
    });
  });

  group('sending a screenshot', () {
    late Directory tmpDir;
    setUp(() => tmpDir = Directory.systemTemp.createTempSync('feedback-test'));
    tearDown(() => tmpDir.deleteSync(recursive: true));

    File fakeImage() {
      final f = File('${tmpDir.path}/screenshot.png');
      f.writeAsBytesSync(List<int>.filled(20, 0xFF));
      return f;
    }

    test('sends the image via sendPhoto, with the message as caption, for '
        'a short message that fits in one chunk', () async {
      final requests = <http.BaseRequest>[];
      final client = MockClient((request) async {
        requests.add(request);
        return http.Response('{"ok":true}', 200);
      });
      final service =
          FeedbackService(botToken: '123:ABC', chatId: '-100999', client: client);

      await service.send('Ca plante au lancement',
          appVersion: '1.0', platform: 'android', image: fakeImage());

      expect(requests, hasLength(1));
      final request = requests.single as http.Request;
      expect(request.url.toString(), contains('/sendPhoto'));
      expect(request.headers['content-type'], contains('multipart/form-data'));
      final body = latin1.decode(request.bodyBytes);
      expect(body, contains('name="chat_id"'));
      expect(body, contains('-100999'));
      expect(body, contains('name="caption"'));
      expect(body, contains('Ca plante au lancement'));
      expect(body, contains('name="photo"'));
    });

    test('a message too long for one caption sends the photo (first chunk '
        'as caption) then the rest as follow-up sendMessage calls', () async {
      final words = List.generate(400, (i) => 'mot$i');
      final longMessage = words.join(' ');

      final requests = <http.BaseRequest>[];
      final client = MockClient((request) async {
        requests.add(request);
        return http.Response('{"ok":true}', 200);
      });
      final service =
          FeedbackService(botToken: '123:ABC', chatId: '-100999', client: client);

      await service.send(longMessage,
          appVersion: '1.0', platform: 'android', image: fakeImage());

      expect(requests.length, greaterThan(1));
      expect(requests.first.url.toString(), contains('/sendPhoto'));
      for (final r in requests.skip(1)) {
        expect(r.url.toString(), contains('/sendMessage'));
      }
    });

    test('throws FeedbackSendException when the photo upload itself fails',
        () async {
      final client = MockClient((request) async => http.Response('error', 500));
      final service =
          FeedbackService(botToken: '123:ABC', chatId: '-100999', client: client);

      await expectLater(
        service.send('hello', appVersion: '1.0', platform: 'android', image: fakeImage()),
        throwsA(isA<FeedbackSendException>()),
      );
    });
  });
}
