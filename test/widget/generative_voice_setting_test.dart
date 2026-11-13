import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:audiolens/l10n/app_localizations.dart';
import 'package:audiolens/services/audio_guide_service.dart';
import 'package:audiolens/services/genai_tts_service.dart';
import 'package:audiolens/services/settings_service.dart';
import 'package:audiolens/widgets/generative_voice_setting.dart';
import '../support/service_fakes.dart';

// #552
void main() {
  late SettingsService settings;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    setUpSecureStorageMock();
    settings = SettingsService();
    await settings.init();
  });

  Future<void> pump(WidgetTester tester, GenerativeVoiceSetting widget) => tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: settings),
            ChangeNotifierProvider.value(value: AudioGuideService(nativeTtsService: FakeNativeTts())),
          ],
          child: MaterialApp(
            locale: const Locale('fr'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(body: SingleChildScrollView(child: widget)),
          ),
        ),
      );

  testWidgets('downloadable voices can be downloaded from Settings', (tester) async {
    var installed = false;
    final downloads = <String>[];
    await pump(
      tester,
      GenerativeVoiceSetting(
        loadVoices: (locale) async => [
          const GenAiVoice(name: 'fr-fr-x-star02', status: 'available', details: '', gender: 'female'),
          GenAiVoice(
              name: 'fr-fr-x-star04',
              status: installed ? 'available' : 'downloadable',
              details: '',
              gender: 'male'),
        ],
        downloadVoice: (locale, name) async {
          downloads.add('$locale|$name');
          installed = true;
          return true;
        },
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('star02 · féminine'), findsOneWidget);
    expect(find.byTooltip('Télécharger cette voix'), findsOneWidget);

    await tester.tap(find.byTooltip('Télécharger cette voix'));
    await tester.pumpAndSettle();

    expect(downloads, ['fr-FR|fr-fr-x-star04']);
    expect(find.byTooltip('Télécharger cette voix'), findsNothing);
    expect(find.text('star04 · masculine'), findsOneWidget, reason: 'now a choice');
  });

  testWidgets('nothing is shown on a phone without generative voices', (tester) async {
    await pump(tester, GenerativeVoiceSetting(loadVoices: (_) async => const []));
    await tester.pumpAndSettle();
    expect(find.text('Voix de synthèse du téléphone'), findsNothing);
  });
}
