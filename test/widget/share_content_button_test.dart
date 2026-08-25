import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:share_plus/share_plus.dart';
import 'package:share_plus_platform_interface/share_plus_platform_interface.dart';
import 'package:audiolens/l10n/app_localizations.dart';
import 'package:audiolens/widgets/share_content_button.dart';

/// #125 — [SharePlus.instance] is a lazily-constructed singleton that only
/// captures [SharePlatform.instance] at its *first* access process-wide, so
/// a fresh fake assigned per-test wouldn't actually take effect past the
/// first test in this file to trigger a share (confirmed the hard way: it
/// silently stuck to whichever test happened to touch `SharePlus.instance`
/// first). [SharePlus.custom] sidesteps the singleton entirely — paired
/// with [ShareContentButton.sharePlus]'s injection seam, each test gets its
/// own isolated instance instead.
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
    tmpDir = Directory.systemTemp.createTempSync('share-content-button');
  });

  tearDown(() => tmpDir.deleteSync(recursive: true));

  Widget wrap(Widget child) => MaterialApp(
        locale: const Locale('fr'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: child),
      );

  testWidgets('renders a Share chip', (tester) async {
    await tester.pumpWidget(wrap(ShareContentButton(
      title: 'La Joconde',
      script: 'Bienvenue devant ce chef-d\'oeuvre.',
      sharePlus: sharePlus,
    )));

    expect(find.text('Partager'), findsOneWidget);
  });

  testWidgets('shares the script text when no audio file exists', (tester) async {
    await tester.pumpWidget(wrap(ShareContentButton(
      title: 'La Joconde',
      script: 'Bienvenue devant ce chef-d\'oeuvre.',
      sharePlus: sharePlus,
    )));

    await tester.tap(find.text('Partager'));
    await tester.pumpAndSettle();

    expect(fakePlatform.lastParams?.text, 'Bienvenue devant ce chef-d\'oeuvre.');
    expect(fakePlatform.lastParams?.subject, 'La Joconde');
    expect(fakePlatform.lastParams?.files, isNull);
  });

  testWidgets('shares the script text when audioPath is set but the file does not exist',
      (tester) async {
    await tester.pumpWidget(wrap(ShareContentButton(
      title: 'La Joconde',
      script: 'Bienvenue devant ce chef-d\'oeuvre.',
      audioPath: '${tmpDir.path}/missing.wav',
      sharePlus: sharePlus,
    )));

    await tester.tap(find.text('Partager'));
    await tester.pumpAndSettle();

    expect(fakePlatform.lastParams?.text, 'Bienvenue devant ce chef-d\'oeuvre.');
    expect(fakePlatform.lastParams?.files, isNull);
  });

  testWidgets('shares the audio file when it exists, preferring it over the text',
      (tester) async {
    final audioFile = File('${tmpDir.path}/audio.wav')..writeAsBytesSync([0, 1, 2, 3]);

    await tester.pumpWidget(wrap(ShareContentButton(
      title: 'La Joconde',
      script: 'Bienvenue devant ce chef-d\'oeuvre.',
      audioPath: audioFile.path,
      sharePlus: sharePlus,
    )));

    await tester.tap(find.text('Partager'));
    await tester.pumpAndSettle();

    expect(fakePlatform.lastParams?.files, hasLength(1));
    expect(fakePlatform.lastParams?.files!.first.path, audioFile.path);
    expect(fakePlatform.lastParams?.text, 'La Joconde');
  });
}
