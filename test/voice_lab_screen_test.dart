import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:audiolens/l10n/app_localizations.dart';
import 'package:audiolens/screens/voice_lab_screen.dart';
import 'package:audiolens/services/genai_tts_service.dart';

// #485
class _FakeTts extends GenAiTtsService {
  _FakeTts({this.voiceList = const [], this.fail = false});

  final List<GenAiVoice> voiceList;
  final bool fail;
  String? probedVoice;

  @override
  Future<List<GenAiVoice>> voices(String locale) async {
    if (fail) throw PlatformException(code: 'VOICES_ERROR', message: 'not supported here');
    return voiceList;
  }

  @override
  Future<GenAiTtsProbe> probe({
    required String locale,
    required String voice,
    required String text,
  }) async {
    probedVoice = voice;
    return GenAiTtsProbe.fromMap({
      'voice': voice,
      'textLength': text.length,
      'events': ['12 ms status: STARTED', '840 ms first audio chunk'],
      'chunkCount': 3,
      'chunkSizes': [4800, 4800, 1200],
      'totalBytes': 10800,
      'firstChunkMs': 840,
      'firstBytesHex': '52 49 46 46',
      'totalMs': 2100,
      'audioFile': null,
      'error': null,
    });
  }

  @override
  Future<void> stop() async {}
}

Future<void> _pump(WidgetTester tester, GenAiTtsService service) async {
  await tester.pumpWidget(MaterialApp(
    locale: const Locale('fr'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: VoiceLabScreen(service: service),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('lists the voices with their status and shows the probe report',
      (tester) async {
    final tts = _FakeTts(voiceList: const [
      GenAiVoice(name: 'star02', status: 'available', details: 'female, fr-FR'),
      GenAiVoice(name: 'star04', status: 'downloadable', details: 'male, fr-FR'),
    ]);
    await _pump(tester, tts);

    expect(find.text('star02 · available'), findsOneWidget);
    expect(find.text('star04 · downloadable'), findsOneWidget);
    // The selected voice is installed: no download button.
    expect(find.text('Télécharger cette voix'), findsNothing);

    await tester.ensureVisible(find.text('Prononcer'));
    await tester.tap(find.text('Prononcer'));
    await tester.pumpAndSettle();

    expect(tts.probedVoice, 'star02');
    expect(find.textContaining('First audio chunk: 840 ms'), findsOneWidget);
    expect(find.textContaining('Chunks: 3, 10800 bytes'), findsOneWidget);
  });

  testWidgets('offers the download for a voice whose model is not installed',
      (tester) async {
    await _pump(
        tester,
        _FakeTts(voiceList: const [
          GenAiVoice(name: 'star04', status: 'downloadable', details: ''),
        ]));

    expect(find.text('Télécharger cette voix'), findsOneWidget);
  });

  testWidgets('says so when the device offers no voice', (tester) async {
    await _pump(tester, _FakeTts());

    expect(find.text('Aucune voix proposée pour cette langue sur cet appareil.'),
        findsOneWidget);
    expect(find.text('Prononcer'), findsNothing);
  });

  testWidgets('shows the platform error when listing voices fails', (tester) async {
    await _pump(tester, _FakeTts(fail: true));

    expect(find.text('not supported here'), findsOneWidget);
  });
}
