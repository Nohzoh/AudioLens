import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:audiolens/l10n/app_localizations.dart';
import 'package:audiolens/screens/voice_lab_screen.dart';
import 'package:audiolens/services/genai_tts_service.dart';

// #485
class _FakeTts extends GenAiTtsService {
  _FakeTts({this.voiceList = const [], this.fail = false, this.crash});

  final String? crash;
  bool crashCleared = false;

  @override
  Future<String?> lastCrash() async => crash;

  @override
  Future<void> clearCrash() async => crashCleared = true;

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

Future<void> _pump(
  WidgetTester tester,
  GenAiTtsService service, {
  List<String> nativeNames = const [],
}) async {
  await tester.pumpWidget(MaterialApp(
    locale: const Locale('fr'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: VoiceLabScreen(service: service, nativeVoiceNames: (_) async => nativeNames),
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

  testWidgets('says whether the app\'s native voice can see the selected voice',
      (tester) async {
    const voices = [
      GenAiVoice(
          name: 'star02', status: 'available', details: 'fr-FR, female', engineName: 'fr-fr-x-gen-a'),
    ];
    await _pump(tester, _FakeTts(voiceList: voices), nativeNames: ['fr-fr-x-gen-a', 'fr-fr-x-vlf']);
    expect(find.textContaining('fr-fr-x-gen-a — visible par la voix native'), findsOneWidget);
  });

  testWidgets('says when the native voice does not list the selected voice',
      (tester) async {
    await _pump(
      tester,
      _FakeTts(voiceList: const [
        GenAiVoice(
            name: 'star02', status: 'available', details: 'fr-FR, female', engineName: 'fr-fr-x-gen-a'),
      ]),
      nativeNames: ['fr-fr-x-vlf'],
    );

    expect(find.textContaining('fr-fr-x-gen-a — absent des 1 voix'), findsOneWidget);
  });

  test('availableVoiceName picks an installed voice of the asked gender', () async {
    final tts = _FakeTts(voiceList: const [
      GenAiVoice(name: 'star01', status: 'downloadable', details: '', gender: 'female'),
      GenAiVoice(name: 'star04', status: 'available', details: '', gender: 'male'),
      GenAiVoice(name: 'star02', status: 'available', details: '', gender: 'female'),
    ]);

    expect(await tts.availableVoiceName('fr-FR', 'female'), 'star02');
    expect(await tts.availableVoiceName('fr-FR', 'male'), 'star04');
    expect(await _FakeTts(fail: true).availableVoiceName('fr-FR', 'female'), isNull);
  });

  test('derives the audio rate from the playback window', () {
    final probe = GenAiTtsProbe.fromMap(const {
      'totalBytes': 96000,
      'startMs': 500,
      'doneMs': 2500,
    });

    expect(probe.bytesPerSecond, 48000);
    expect(GenAiTtsProbe.fromMap(const {'totalBytes': 96000}).bytesPerSecond, isNull);
  });

  // #501
  testWidgets('shows the trace of a probe that crashed the app, and clears it',
      (tester) async {
    final tts = _FakeTts(crash: 'java.lang.NoSuchMethodError: foo\n  at Bar.baz');
    await _pump(tester, tts);

    expect(find.textContaining('a fait planter'), findsOneWidget);
    expect(find.textContaining('NoSuchMethodError'), findsOneWidget);

    await tester.tap(find.text('Effacer'));
    await tester.pumpAndSettle();

    expect(tts.crashCleared, isTrue);
    expect(find.textContaining('NoSuchMethodError'), findsNothing);
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
