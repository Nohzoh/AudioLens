import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:audiolens/services/gemini_api_service.dart';
import 'package:audiolens/services/gemini_nano_service.dart';
import 'package:audiolens/services/guide_question_service.dart';
import 'package:audiolens/utils/cancel_token.dart';

// #424
class _FakeApi extends GeminiApiService {
  _FakeApi({this.fail = false}) : super(apiKey: 'k');
  final bool fail;
  final prompts = <String>[];

  @override
  Future<String> answerQuestion(String prompt, {CancelToken? cancelToken}) async {
    prompts.add(prompt);
    if (fail) throw Exception('HTTP 429');
    return '**Jean Nouvel** a conçu les tours.';
  }
}

class _FakeNano extends GeminiNanoService {
  final prompts = <String>[];

  @override
  Future<void> initialize() async {}

  @override
  Future<String> rawPrompt({
    required String prompt,
    File? imageFile,
    int? maxOutputTokens,
    double? temperature,
    NanoModelVariant? variant,
  }) async {
    prompts.add(prompt);
    return 'Réponse locale.';
  }
}

void main() {
  group('buildGuideQuestionPrompt', () {
    test('holds the guide, the context, earlier exchanges and the question', () {
      final prompt = buildGuideQuestionPrompt(
        title: 'Les tours Duo',
        script: 'Les tours Duo dominent le boulevard.',
        context: 'Lieu identifié : Tours Duo',
        language: 'English',
        previous: const [GuideExchange('Quelle hauteur ?', '180 mètres.')],
        question: 'Qui les a construites ?',
      );

      expect(prompt, contains('« Les tours Duo »'));
      expect(prompt, contains('Les tours Duo dominent le boulevard.'));
      expect(prompt, contains('Lieu identifié : Tours Duo'));
      expect(prompt, contains('- Question : Quelle hauteur ?'));
      expect(prompt, contains('Question du visiteur : Qui les a construites ?'));
      expect(prompt, contains('exclusivement en English'));
      expect(prompt, contains("Si la réponse n'y figure pas, dis-le simplement, sans inventer."));
    });

    test('works without context, defaults to French and can cap the context', () {
      final bare = buildGuideQuestionPrompt(title: 't', script: 's', question: 'q');
      expect(bare, isNot(contains('Informations disponibles')));
      expect(bare, contains('exclusivement en Français'));

      final capped = buildGuideQuestionPrompt(
          title: 't', script: 's', context: 'x' * 100, question: 'q', maxContextChars: 10);
      expect(capped, contains('${'x' * 10}…'));
      expect(capped, isNot(contains('x' * 11)));
    });
  });

  group('GuideQuestionService', () {
    test('uses the cloud model when there is one, and cleans its formatting', () async {
      final api = _FakeApi();
      final nano = _FakeNano();
      final service = GuideQuestionService(api: api, nano: nano, nanoAvailable: true);

      final answer = await service.ask(title: 't', script: 's', question: 'q');

      expect(answer, 'Jean Nouvel a conçu les tours.');
      expect(api.prompts, hasLength(1));
      expect(nano.prompts, isEmpty);
    });

    test('falls back to the on-device model, with a shorter prompt', () async {
      final nano = _FakeNano();
      final service =
          GuideQuestionService(api: _FakeApi(fail: true), nano: nano, nanoAvailable: true);

      final answer = await service.ask(
        title: 't',
        script: 's',
        context: 'c' * 5000,
        previous: const [GuideExchange('q1', 'a1'), GuideExchange('q2', 'a2')],
        question: 'q3',
      );

      expect(answer, 'Réponse locale.');
      final prompt = nano.prompts.single;
      expect(prompt, isNot(contains('q1')), reason: 'only the last exchange is sent');
      expect(prompt, contains('- Question : q2'));
      expect(prompt, isNot(contains('c' * 2501)));
    });

    test('reports the cloud failure when there is no on-device model', () async {
      final service = GuideQuestionService(api: _FakeApi(fail: true));

      await expectLater(
          service.ask(title: 't', script: 's', question: 'q'), throwsException);
    });

    test('is unavailable without any model', () async {
      final service = GuideQuestionService(nano: _FakeNano(), nanoAvailable: false);

      expect(service.isAvailable, isFalse);
      await expectLater(service.ask(title: 't', script: 's', question: 'q'),
          throwsA(isA<GuideQuestionUnavailableException>()));
    });
  });
}
