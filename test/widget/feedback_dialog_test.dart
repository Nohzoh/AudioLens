import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image/image.dart' as img;
import 'package:audiolens/l10n/app_localizations.dart';
import 'package:audiolens/services/feedback_service.dart';
import 'package:audiolens/services/history_service.dart';
import 'package:audiolens/widgets/feedback_dialog.dart';

/// #426 — the feedback dialog opened from an analysis screen, with that
/// analysis pre-attached. The Settings entry point keeps its own tests in
/// settings_screen_test.dart.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmpDir;
  late List<http.BaseRequest> requests;
  late FeedbackService feedback;

  setUp(() {
    tmpDir = Directory.systemTemp.createTempSync('feedback-dialog');
    requests = [];
    feedback = FeedbackService(
      botToken: '123:ABC',
      chatId: '-100999',
      client: MockClient((request) async {
        requests.add(request);
        return http.Response('{"ok":true}', 200);
      }),
    );
  });

  tearDown(() => tmpDir.deleteSync(recursive: true));

  HistoryEntry entryWithPhoto() {
    final photo = img.Image(width: 4, height: 4);
    final path = '${tmpDir.path}/photo.jpg';
    File(path).writeAsBytesSync(img.encodeJpg(photo));
    return HistoryEntry(
      id: 1,
      imagePath: path,
      title: 'La Joconde',
      script: 'Bienvenue devant ce chef-d\'oeuvre.',
      createdAt: DateTime(2026, 1, 1),
    );
  }

  Widget wrap(Widget dialog) => MaterialApp(
        locale: const Locale('fr'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: dialog),
      );

  Future<void> tapSend(WidgetTester tester) async {
    await tester.runAsync(() async {
      await tester.tap(find.widgetWithText(FilledButton, 'Envoyer'));
      for (var i = 0; i < 50 && requests.isEmpty; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
    await tester.pump();
  }

  testWidgets('opens with the analysis attached and the comment marked optional',
      (tester) async {
    await tester.pumpWidget(wrap(FeedbackDialog(
      feedback: feedback,
      appVersion: '1.0.0 (1)',
      history: HistoryService(),
      initialEntry: entryWithPhoto(),
    )));

    expect(find.text("Changer l'analyse"), findsOneWidget);
    expect(find.text('Un commentaire ? (facultatif)'), findsOneWidget);
  });

  testWidgets('sends with no comment when an analysis is attached', (tester) async {
    await tester.pumpWidget(wrap(FeedbackDialog(
      feedback: feedback,
      appVersion: '1.0.0 (1)',
      history: HistoryService(),
      initialEntry: entryWithPhoto(),
    )));

    await tapSend(tester);

    expect(requests, hasLength(1));
    expect(requests.single.url.toString(), contains('/sendPhoto'));
  });

  testWidgets('still requires a comment when no analysis is attached', (tester) async {
    await tester.pumpWidget(wrap(FeedbackDialog(
      feedback: feedback,
      appVersion: '1.0.0 (1)',
      history: HistoryService(),
    )));

    expect(find.text('Décrivez le problème ou votre suggestion...'), findsOneWidget);
    await tapSend(tester);

    expect(requests, isEmpty);
  });
}
