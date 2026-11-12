import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:audiolens/l10n/app_localizations.dart';
import 'package:audiolens/services/guide_question_service.dart';
import 'package:audiolens/services/history_service.dart';
import 'package:audiolens/utils/cancel_token.dart';
import 'package:audiolens/widgets/guide_question_sheet.dart';

// #424
class _FakeQuestions extends GuideQuestionService {
  _FakeQuestions({this.fail = false}) : super();
  final bool fail;
  final asked = <({String question, String? context, int previous})>[];

  @override
  bool get isAvailable => true;

  @override
  Future<String> ask({
    required String title,
    required String script,
    String? context,
    String? language,
    List<GuideExchange> previous = const [],
    required String question,
    CancelToken? cancelToken,
  }) async {
    asked.add((question: question, context: context, previous: previous.length));
    if (fail) throw Exception('offline');
    return 'Réponse à « $question ».';
  }
}

HistoryEntry _entry({String? promptContext}) => HistoryEntry(
      id: 1,
      imagePath: '/tmp/x.jpg',
      title: 'Les tours Duo',
      script: 'Les tours Duo dominent le boulevard.',
      createdAt: DateTime(2026, 11, 12),
      status: AnalysisStatus.complete,
      promptContext: promptContext,
      gpsAddress: 'Boulevard du Général Jean Simon',
    );

Future<void> _pump(WidgetTester tester, HistoryEntry entry, GuideQuestionService service,
        {AnswerReader? reader}) =>
    tester.pumpWidget(MaterialApp(
      locale: const Locale('fr'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: GuideQuestionSheet(
            entry: entry, language: 'Français', service: service, reader: reader),
      ),
    ));

Future<void> _ask(WidgetTester tester, String question) async {
  await tester.enterText(find.byType(TextField), question);
  await tester.tap(find.byIcon(Icons.send));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('asks with the stored context and keeps the conversation', (tester) async {
    final questions = _FakeQuestions();
    await _pump(tester, _entry(promptContext: 'Lieu identifié : Tours Duo'), questions);

    await _ask(tester, 'Qui les a construites ?');
    await _ask(tester, 'Quelle hauteur ?');

    expect(find.text('Réponse à « Qui les a construites ? ».'), findsOneWidget);
    expect(find.text('Réponse à « Quelle hauteur ? ».'), findsOneWidget);
    expect(questions.asked.map((a) => a.context), everyElement('Lieu identifié : Tours Duo'));
    expect(questions.asked.map((a) => a.previous), [0, 1]);
  });

  testWidgets('falls back to the address for an entry without stored context',
      (tester) async {
    final questions = _FakeQuestions();
    await _pump(tester, _entry(), questions);

    await _ask(tester, 'Où suis-je ?');

    expect(questions.asked.single.context, 'Adresse : Boulevard du Général Jean Simon');
  });

  testWidgets('a failure is shown and the question is given back', (tester) async {
    await _pump(tester, _entry(), _FakeQuestions(fail: true));

    await _ask(tester, 'Qui les a construites ?');

    expect(find.textContaining("La réponse n'a pas pu être obtenue"), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Qui les a construites ?'), findsOneWidget);
  });

  testWidgets('stops after the maximum number of questions', (tester) async {
    await _pump(tester, _entry(), _FakeQuestions());

    for (var i = 0; i < maxGuideQuestions; i++) {
      await _ask(tester, 'Question $i');
    }

    expect(find.textContaining('Nombre maximum de questions atteint'), findsOneWidget);
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.enabled, isFalse);
  });

  testWidgets('an answer can be listened to, and stopped (#524)', (tester) async {
    final spoken = <String>[];
    var stops = 0;
    final playing = <Completer<bool>>[];
    final AnswerReader reader = (
      speak: (text) {
        spoken.add(text);
        final c = Completer<bool>();
        playing.add(c);
        return c.future;
      },
      stop: () async {
        stops++;
        for (final c in playing) {
          if (!c.isCompleted) c.complete(true);
        }
      },
    );
    await _pump(tester, _entry(), _FakeQuestions(), reader: reader);
    await _ask(tester, 'Qui les a construites ?');

    await tester.tap(find.byTooltip('Écouter la réponse'));
    await tester.pump();
    expect(spoken, ['Réponse à « Qui les a construites ? ».']);
    expect(find.byTooltip('Arrêter la lecture'), findsOneWidget);

    await tester.tap(find.byTooltip('Arrêter la lecture'));
    await tester.pumpAndSettle();
    expect(stops, 1);
    expect(spoken, hasLength(1));
    expect(find.byTooltip('Écouter la réponse'), findsOneWidget);
  });

  testWidgets('no listen button without a voice (#524)', (tester) async {
    await _pump(tester, _entry(), _FakeQuestions());
    await _ask(tester, 'Qui les a construites ?');
    expect(find.byTooltip('Écouter la réponse'), findsNothing);
  });
}
