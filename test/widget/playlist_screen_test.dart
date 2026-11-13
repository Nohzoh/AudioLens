import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:audiolens/l10n/app_localizations.dart';
import 'package:audiolens/screens/playlist_screen.dart';
import 'package:audiolens/services/history_service.dart';

// #550
class _FakePlayer extends PlaylistPlayer {
  final played = <String>[];
  Completer<void>? current;
  int stops = 0;

  @override
  Future<void> play(String path) {
    played.add(path);
    current = Completer<void>();
    return current!.future;
  }

  void finish() => current?.complete();

  @override
  Future<void> stop() async {
    stops++;
    if (current?.isCompleted == false) current!.complete();
  }

  @override
  Future<void> pause() async {}
  @override
  Future<void> resume() async {}
}

HistoryEntry _entry(int i) => HistoryEntry(
      id: i,
      imagePath: '/nope/$i.jpg',
      title: 'Œuvre $i',
      script: 'Texte $i.',
      createdAt: DateTime(2026, 11, 13, 10, i),
      audioPath: '/audio/$i.wav',
    );

void main() {
  Future<_FakePlayer> pump(WidgetTester tester) async {
    final player = _FakePlayer();
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('fr'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: PlaylistScreen(
          title: 'Louvre', entries: [_entry(1), _entry(2), _entry(3)], player: player),
    ));
    await tester.pump();
    await tester.pump();
    return player;
  }

  testWidgets('plays the entries one after the other', (tester) async {
    final player = await pump(tester);
    expect(player.played, ['/audio/1.wav']);
    expect(find.text('1 sur 3'), findsOneWidget);

    player.finish();
    await tester.pump();
    await tester.pump();
    expect(player.played.last, '/audio/2.wav');
    expect(find.text('2 sur 3'), findsOneWidget);
  });

  testWidgets('next skips ahead without playing twice', (tester) async {
    final player = await pump(tester);
    await tester.tap(find.byTooltip('Suivante'));
    await tester.pump();
    await tester.pump();
    expect(player.played, ['/audio/1.wav', '/audio/2.wav'],
        reason: 'the stopped first entry must not advance the list again');

    player.finish();
    await tester.pump();
    await tester.pump();
    expect(player.played.last, '/audio/3.wav');
    player.finish();
    await tester.pump();
    await tester.pump();
    expect(find.byTooltip('Réécouter depuis le début'), findsOneWidget);
  });
}
