import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:audiolens/screens/about_analysis_screen.dart';
import 'package:audiolens/services/audio_guide_service.dart';
import 'package:audiolens/services/history_service.dart';
import 'package:audiolens/services/settings_service.dart';
import '../support/service_fakes.dart';

/// #154 — tapping a single row's value in the analysis details screen
/// copies just that value, distinct from the existing bulk "Copier les
/// infos de debug" button.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const clipboardChannel = SystemChannels.platform;
  final clipboardCalls = <MethodCall>[];

  setUp(() {
    clipboardCalls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(clipboardChannel, (call) async {
      if (call.method == 'Clipboard.setData') clipboardCalls.add(call);
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(clipboardChannel, null);
  });

  final entry = HistoryEntry(
    imagePath: '/nonexistent/photo.jpg',
    title: 'Tour Eiffel',
    script: 'Un monument emblematique de Paris.',
    createdAt: DateTime(2026, 1, 1, 10, 30),
    aiModel: 'gemini-3.5-flash',
  );

  Widget wrapScreen() => wrapWithProviders(
        AboutAnalysisScreen(entry: entry),
        settings: SettingsService(),
        guide: AudioGuideService(nativeTtsService: FakeNativeTts()),
        history: HistoryService(),
      );

  testWidgets('tapping a row value copies just that value to the clipboard',
      (tester) async {
    await tester.pumpWidget(wrapScreen());
    await tester.pumpAndSettle();

    await tester.tap(find.text('gemini-3.5-flash'));
    await tester.pump();

    expect(clipboardCalls, hasLength(1));
    expect(
      (clipboardCalls.single.arguments as Map)['text'],
      'gemini-3.5-flash',
    );
    expect(find.text('« gemini-3.5-flash » copié'), findsOneWidget);
  });

  testWidgets('the bulk "Copier les infos de debug" button still copies everything',
      (tester) async {
    await tester.pumpWidget(wrapScreen());
    await tester.pumpAndSettle();

    await tester.dragUntilVisible(
      find.text('Copier les infos de debug'),
      find.byType(ListView),
      const Offset(0, -300),
    );
    await tester.tap(find.text('Copier les infos de debug'));
    await tester.pumpAndSettle();

    expect(clipboardCalls, hasLength(1));
    final copied = (clipboardCalls.single.arguments as Map)['text'] as String;
    expect(copied, contains('Tour Eiffel'));
    expect(copied, contains('gemini-3.5-flash'));
    expect(find.text('Infos copiées'), findsOneWidget);
  });

  testWidgets('#425: the script style shows its localized label, not the raw key',
      (tester) async {
    await tester.pumpWidget(wrapWithProviders(
      AboutAnalysisScreen(
        entry: HistoryEntry(
          imagePath: '/nonexistent/photo.jpg',
          title: 'Tour Eiffel',
          script: 'Un monument.',
          createdAt: DateTime(2026, 1, 1),
          scriptStyle: 'kids',
        ),
      ),
      settings: SettingsService(),
      guide: AudioGuideService(nativeTtsService: FakeNativeTts()),
      history: HistoryService(),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Pour enfants'), findsOneWidget);
    expect(find.text('kids'), findsNothing);
  });

  group('#422 TTS model row', () {
    Widget screenFor(HistoryEntry e) => wrapWithProviders(
          AboutAnalysisScreen(entry: e),
          settings: SettingsService(),
          guide: AudioGuideService(nativeTtsService: FakeNativeTts()),
          history: HistoryService(),
        );

    // The value shown next to the "Modèle TTS" label (other rows can
    // legitimately show "Inconnu" too).
    String ttsRowValue(WidgetTester tester) {
      final row = find.ancestor(of: find.text('Modèle TTS'), matching: find.byType(Row)).first;
      final texts = tester.widgetList<Text>(find.descendant(of: row, matching: find.byType(Text)));
      return texts.last.data!;
    }

    HistoryEntry entryWith({String? ttsModel, String? audioPath}) => HistoryEntry(
          imagePath: '/nonexistent/photo.jpg',
          title: 'Tour Eiffel',
          script: 'Un monument emblematique de Paris.',
          createdAt: DateTime(2026, 1, 1, 10, 30),
          aiModel: 'gemini-3.5-flash',
          ttsModel: ttsModel,
          audioPath: audioPath,
        );

    testWidgets('no audio generated -> "Aucun (audio non généré)", not "Inconnu"',
        (tester) async {
      await tester.pumpWidget(screenFor(entryWith()));
      await tester.pumpAndSettle();

      expect(ttsRowValue(tester), 'Aucun (audio non généré)');
    });

    testWidgets('audio with a recorded model -> shows the model', (tester) async {
      await tester.pumpWidget(screenFor(
          entryWith(ttsModel: 'gemini-2.5-flash-preview-tts', audioPath: '/nonexistent/a.wav')));
      await tester.pumpAndSettle();

      expect(ttsRowValue(tester), 'gemini-2.5-flash-preview-tts');
    });

    testWidgets('audio without a recorded model (old entry) -> "Inconnu"', (tester) async {
      await tester.pumpWidget(screenFor(entryWith(audioPath: '/nonexistent/a.wav')));
      await tester.pumpAndSettle();

      expect(ttsRowValue(tester), 'Inconnu');
    });

    testWidgets('copied debug text says no audio was generated', (tester) async {
      await tester.pumpWidget(screenFor(entryWith()));
      await tester.pumpAndSettle();

      await tester.dragUntilVisible(
        find.text('Copier les infos de debug'),
        find.byType(ListView),
        const Offset(0, -300),
      );
      await tester.tap(find.text('Copier les infos de debug'));
      await tester.pumpAndSettle();

      final copied = (clipboardCalls.single.arguments as Map)['text'] as String;
      expect(copied, contains('TTS Model: none (no audio generated)'));
    });
  });
}
