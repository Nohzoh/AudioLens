import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:audiolens/l10n/app_localizations.dart';
import 'package:audiolens/services/feedback_service.dart';
import 'package:audiolens/services/history_service.dart';
import 'package:audiolens/widgets/script_rating_bar.dart';

/// Records ratings instead of writing to a database — persistence itself
/// is covered in history_service_migration_test.dart.
class _RecordingHistory extends HistoryService {
  final ratings = <int>[];

  @override
  Future<void> setRating(int entryId, int rating) async => ratings.add(rating);
}

/// #421 — rating a script, and the 1-star feedback offer.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    PackageInfo.setMockInitialValues(
      appName: 'AudioLens',
      packageName: 'io.nohzoh.audiolens',
      version: '0.1.5',
      buildNumber: '42',
      buildSignature: '',
    );
  });

  final configuredFeedback = FeedbackService(
    botToken: '123:ABC',
    chatId: '-100999',
    client: MockClient((_) async => http.Response('{"ok":true}', 200)),
  );

  HistoryEntry entry({int? rating}) => HistoryEntry(
        id: 1,
        imagePath: '/nonexistent/photo.jpg',
        title: 'La Joconde',
        script: 'Bienvenue devant ce chef-d\'oeuvre.',
        createdAt: DateTime(2026, 1, 1),
        rating: rating,
      );

  Widget wrap(HistoryService history, Widget child) => ChangeNotifierProvider.value(
        value: history,
        child: MaterialApp(
          locale: const Locale('fr'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: child),
        ),
      );

  testWidgets('shows the saved rating as filled stars', (tester) async {
    await tester.pumpWidget(wrap(_RecordingHistory(), ScriptRatingBar(entry: entry(rating: 3))));

    expect(find.byIcon(Icons.star_rounded), findsNWidgets(3));
    expect(find.byIcon(Icons.star_outline_rounded), findsNWidgets(2));
  });

  testWidgets('tapping a star saves that rating, with no prompt above 1', (tester) async {
    final history = _RecordingHistory();
    await tester.pumpWidget(wrap(
        history, ScriptRatingBar(entry: entry(), feedbackService: configuredFeedback)));

    await tester.tap(find.byKey(const ValueKey('rating-star-4')));
    await tester.pumpAndSettle();

    expect(history.ratings, [4]);
    expect(find.text('Pas satisfait de ce script ?'), findsNothing);
  });

  testWidgets('1 star on a configured build offers feedback, and accepting opens '
      'the dialog with the analysis attached', (tester) async {
    final history = _RecordingHistory();
    await tester.pumpWidget(wrap(
        history, ScriptRatingBar(entry: entry(), feedbackService: configuredFeedback)));

    await tester.tap(find.byKey(const ValueKey('rating-star-1')));
    await tester.pumpAndSettle();

    expect(history.ratings, [1]);
    expect(find.text('Pas satisfait de ce script ?'), findsOneWidget);

    await tester.tap(find.text("Envoyer l'analyse"));
    await tester.pumpAndSettle();

    expect(find.text('Envoyer un feedback'), findsOneWidget);
    expect(find.text("Changer l'analyse"), findsOneWidget);
  });

  testWidgets('declining the 1-star offer keeps the rating', (tester) async {
    final history = _RecordingHistory();
    await tester.pumpWidget(wrap(
        history, ScriptRatingBar(entry: entry(), feedbackService: configuredFeedback)));

    await tester.tap(find.byKey(const ValueKey('rating-star-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Non merci'));
    await tester.pumpAndSettle();

    expect(history.ratings, [1]);
    expect(find.text('Envoyer un feedback'), findsNothing);
  });

  testWidgets('1 star on a build without feedback configured just saves', (tester) async {
    final history = _RecordingHistory();
    await tester.pumpWidget(
        wrap(history, ScriptRatingBar(entry: entry(), feedbackService: FeedbackService())));

    await tester.tap(find.byKey(const ValueKey('rating-star-1')));
    await tester.pumpAndSettle();

    expect(history.ratings, [1]);
    expect(find.text('Pas satisfait de ce script ?'), findsNothing);
  });
}
