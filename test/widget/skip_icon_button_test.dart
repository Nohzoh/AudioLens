import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:audiolens/l10n/app_localizations.dart';
import 'package:audiolens/widgets/skip_icon_button.dart';

/// #147 — shared between player_screen.dart and history_screen.dart, so
/// its icon/tooltip/callback wiring is covered once here instead of via
/// each screen's own (heavier) widget tests.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget wrap(Widget child) => MaterialApp(
        locale: const Locale('fr'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: child),
      );

  testWidgets('forward: false renders replay_10 with the skip-back tooltip',
      (tester) async {
    var tapped = false;
    await tester.pumpWidget(wrap(SkipIconButton(
      forward: false,
      onPressed: () => tapped = true,
    )));

    expect(find.byIcon(Icons.replay_10), findsOneWidget);
    expect(find.byIcon(Icons.forward_10), findsNothing);
    expect(find.byTooltip('Reculer de 10 secondes'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.replay_10));
    expect(tapped, isTrue);
  });

  testWidgets('forward: true renders forward_10 with the skip-forward tooltip',
      (tester) async {
    var tapped = false;
    await tester.pumpWidget(wrap(SkipIconButton(
      forward: true,
      onPressed: () => tapped = true,
    )));

    expect(find.byIcon(Icons.forward_10), findsOneWidget);
    expect(find.byIcon(Icons.replay_10), findsNothing);
    expect(find.byTooltip('Avancer de 10 secondes'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.forward_10));
    expect(tapped, isTrue);
  });
}
