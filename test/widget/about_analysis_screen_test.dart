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
}
