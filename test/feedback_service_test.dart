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
}
