import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:audiolens/l10n/app_localizations.dart';
import 'package:audiolens/widgets/guide_action_row.dart';

/// #147 — shared between player_screen.dart and history_screen.dart. The
/// screen-specific wording (save/copy labels, snackbar text) is passed in
/// by each caller, so this only needs to verify the row renders and the
/// copy action actually copies — Save/Share/Report already have their own
/// dedicated tests for the widgets they delegate to.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget wrap(Widget child) => MaterialApp(
        locale: const Locale('fr'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: child),
      );

  testWidgets('renders all 4 actions with the caller-supplied labels',
      (tester) async {
    await tester.pumpWidget(wrap(GuideActionRow(
      imagePath: '/nonexistent/photo.jpg',
      rotationQuarters: 0,
      script: 'Bienvenue devant ce chef-d\'oeuvre.',
      title: 'La Joconde',
      reportDate: DateTime(2026, 1, 1),
      saveLabel: 'Sauvegarder',
      savedSnackbarText: 'Photo sauvegardée',
      copyLabel: 'Copier',
      copiedSnackbarText: 'Texte copié',
    )));

    expect(find.text('Sauvegarder'), findsOneWidget);
    expect(find.text('Copier'), findsOneWidget);
    expect(find.text('Partager'), findsOneWidget);
    expect(find.text('Signaler'), findsOneWidget);
  });

  testWidgets('tapping Copy copies the script and shows the caller-supplied snackbar',
      (tester) async {
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') calls.add(call);
      return null;
    });
    addTearDown(() => TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));

    await tester.pumpWidget(wrap(GuideActionRow(
      imagePath: '/nonexistent/photo.jpg',
      rotationQuarters: 0,
      script: 'Bienvenue devant ce chef-d\'oeuvre.',
      title: 'La Joconde',
      reportDate: DateTime(2026, 1, 1),
      saveLabel: 'Sauvegarder',
      savedSnackbarText: 'Photo sauvegardée',
      copyLabel: 'Copier',
      copiedSnackbarText: 'Texte copié',
    )));

    await tester.tap(find.text('Copier'));
    await tester.pump();

    expect(calls, hasLength(1));
    expect((calls.single.arguments as Map)['text'],
        'Bienvenue devant ce chef-d\'oeuvre.');
    expect(find.text('Texte copié'), findsOneWidget);
  });
}
