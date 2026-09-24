import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:share_plus_platform_interface/share_plus_platform_interface.dart';
import 'package:audiolens/l10n/app_localizations.dart';
import 'package:audiolens/services/feedback_service.dart';
import 'package:audiolens/services/history_service.dart';
import 'package:audiolens/widgets/guide_action_row.dart';

/// #427 — the analysis actions (shared by player_screen.dart and
/// history_screen.dart, #147) are one "Actions" chip opening a sheet of
/// explicit actions; #426 adds "Send as feedback" to that sheet.
///
/// [SharePlus.custom] sidesteps the [SharePlus.instance] singleton, which
/// only captures the platform at its first access process-wide (#125).
class _FakeSharePlatform extends SharePlatform {
  ShareParams? lastParams;

  @override
  Future<ShareResult> share(ShareParams params) async {
    lastParams = params;
    return const ShareResult('ok', ShareResultStatus.success);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeSharePlatform fakePlatform;
  late SharePlus sharePlus;
  late Directory tmpDir;

  setUp(() {
    fakePlatform = _FakeSharePlatform();
    sharePlus = SharePlus.custom(fakePlatform);
    tmpDir = Directory.systemTemp.createTempSync('guide-action-row');
    PackageInfo.setMockInitialValues(
      appName: 'AudioLens',
      packageName: 'io.nohzoh.audiolens',
      version: '0.1.5',
      buildNumber: '42',
      buildSignature: '',
    );
  });

  tearDown(() => tmpDir.deleteSync(recursive: true));

  final configuredFeedback = FeedbackService(
    botToken: '123:ABC',
    chatId: '-100999',
    client: MockClient((_) async => http.Response('{"ok":true}', 200)),
  );

  HistoryEntry entry({AnalysisStatus status = AnalysisStatus.complete}) => HistoryEntry(
        id: 1,
        imagePath: '/nonexistent/photo.jpg',
        title: 'La Joconde',
        script: 'Bienvenue devant ce chef-d\'oeuvre.',
        createdAt: DateTime(2026, 1, 1),
        status: status,
      );

  Widget wrap(Widget child) => ChangeNotifierProvider.value(
        value: HistoryService(),
        child: MaterialApp(
          locale: const Locale('fr'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: child),
        ),
      );

  GuideActionRow row({
    String? audioPath,
    HistoryEntry? feedbackEntry,
    FeedbackService? feedbackService,
  }) =>
      GuideActionRow(
        imagePath: '/nonexistent/photo.jpg',
        rotationQuarters: 0,
        script: 'Bienvenue devant ce chef-d\'oeuvre.',
        title: 'La Joconde',
        reportDate: DateTime(2026, 1, 1),
        audioPath: audioPath,
        feedbackEntry: feedbackEntry,
        feedbackService: feedbackService ?? FeedbackService(),
        sharePlus: sharePlus,
      );

  Future<void> openSheet(WidgetTester tester) async {
    await tester.tap(find.text('Actions'));
    await tester.pumpAndSettle();
  }

  testWidgets('shows a single Actions chip, not the old row of 4', (tester) async {
    await tester.pumpWidget(wrap(row()));

    expect(find.text('Actions'), findsOneWidget);
    expect(find.text('Sauvegarder'), findsNothing);
    expect(find.text('Copier'), findsNothing);
  });

  testWidgets('the sheet lists explicit actions; no audio share without a file, '
      'no feedback on an unconfigured build', (tester) async {
    await tester.pumpWidget(wrap(row(
      audioPath: '${tmpDir.path}/missing.wav',
      feedbackEntry: entry(),
    )));
    await openSheet(tester);

    expect(find.text('Enregistrer la photo dans la galerie'), findsOneWidget);
    expect(find.text('Partager le texte'), findsOneWidget);
    expect(find.text('Signaler un contenu inapproprié'), findsOneWidget);
    expect(find.text("Partager l'audio"), findsNothing);
    expect(find.text('Envoyer en feedback'), findsNothing);
  });

  testWidgets('"Partager le texte" shares the script', (tester) async {
    await tester.pumpWidget(wrap(row()));
    await openSheet(tester);

    await tester.tap(find.text('Partager le texte'));
    await tester.pumpAndSettle();

    expect(fakePlatform.lastParams?.text, 'Bienvenue devant ce chef-d\'oeuvre.');
    expect(fakePlatform.lastParams?.subject, 'La Joconde');
    expect(fakePlatform.lastParams?.files, isNull);
  });

  testWidgets('"Partager l\'audio" shows when the file exists and shares it', (tester) async {
    final audioFile = File('${tmpDir.path}/audio.wav')..writeAsBytesSync([0, 1, 2, 3]);

    await tester.pumpWidget(wrap(row(audioPath: audioFile.path)));
    await openSheet(tester);

    await tester.tap(find.text("Partager l'audio"));
    await tester.pumpAndSettle();

    expect(fakePlatform.lastParams?.files, hasLength(1));
    expect(fakePlatform.lastParams?.files!.first.path, audioFile.path);
  });

  testWidgets('a failed gallery save shows an error instead of failing silently',
      (tester) async {
    // No gal plugin under test: Gal.putImage throws MissingPluginException.
    await tester.pumpWidget(wrap(row()));
    await openSheet(tester);

    // runAsync: the save path goes through a real platform call, which
    // never completes under the test's fake async zone.
    await tester.tap(find.text('Enregistrer la photo dans la galerie'));
    await tester.pumpAndSettle();
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pumpAndSettle();

    expect(find.text("Impossible d'enregistrer la photo dans la galerie"), findsOneWidget);
  });

  group('#426 send as feedback', () {
    testWidgets('offered for a complete analysis on a configured build', (tester) async {
      await tester.pumpWidget(wrap(row(
        feedbackEntry: entry(),
        feedbackService: configuredFeedback,
      )));
      await openSheet(tester);

      expect(find.text('Envoyer en feedback'), findsOneWidget);
    });

    testWidgets('not offered for an unfinished analysis', (tester) async {
      await tester.pumpWidget(wrap(row(
        feedbackEntry: entry(status: AnalysisStatus.pending),
        feedbackService: configuredFeedback,
      )));
      await openSheet(tester);

      expect(find.text('Envoyer en feedback'), findsNothing);
    });

    testWidgets('not offered without a history entry', (tester) async {
      await tester.pumpWidget(wrap(row(feedbackService: configuredFeedback)));
      await openSheet(tester);

      expect(find.text('Envoyer en feedback'), findsNothing);
    });

    testWidgets('opens the feedback dialog with the analysis already attached',
        (tester) async {
      await tester.pumpWidget(wrap(row(
        feedbackEntry: entry(),
        feedbackService: configuredFeedback,
      )));
      await openSheet(tester);

      await tester.tap(find.text('Envoyer en feedback'));
      await tester.pumpAndSettle();

      expect(find.text('Envoyer un feedback'), findsOneWidget);
      expect(find.text("Changer l'analyse"), findsOneWidget);
      expect(find.text('Un commentaire ? (facultatif)'), findsOneWidget);
    });
  });
}
