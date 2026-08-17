import 'package:flutter/material.dart';
import 'services/remote_config_service.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'l10n/app_localizations.dart';
import 'services/settings_service.dart';
import 'services/audio_guide_service.dart';
import 'services/history_service.dart';
import 'screens/onboarding_screen.dart';
import 'screens/home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await RemoteConfigService.load();
  // Both supported locales' formatting data must be initialized up front —
  // DateFormat calls elsewhere (e.g. history_screen.dart) switch locale at
  // format time based on the active Localizations.localeOf(context), not
  // once at startup, so whichever locale wasn't pre-initialized here would
  // throw on first use.
  await initializeDateFormatting('fr_FR', null);
  await initializeDateFormatting('en', null);

  final settings = SettingsService();
  await settings.init();

  final guide = AudioGuideService();
  await guide.init();

  final history = HistoryService();
  await history.init();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: settings),
        ChangeNotifierProvider.value(value: guide),
        ChangeNotifierProvider.value(value: history),
      ],
      child: const AudioGuideApp(),
    ),
  );
}

class AudioGuideApp extends StatelessWidget {
  const AudioGuideApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AudioLens',
      debugShowCheckedModeBanner: false,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      // No custom localeResolutionCallback needed: Flutter's default
      // resolution already matches the device's locale when supported (fr
      // or en) and falls back to supportedLocales.first otherwise — which
      // is English (the generated list is alphabetical: [en, fr]).
      // English as the fallback for unsupported system locales reaches
      // more non-French speakers than defaulting to French would.
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6B4EFF),
          brightness: Brightness.dark,
        ),
        textTheme: GoogleFonts.interTextTheme(ThemeData.dark().textTheme),
        useMaterial3: true,
      ),
      home: Consumer<SettingsService>(
        builder: (context, settings, _) {
          final guide = context.read<AudioGuideService>();
          if (guide.isReady) return const HomeScreen();
          if (settings.isOnboardingComplete) return const HomeScreen();
          return const OnboardingScreen();
        },
      ),
    );
  }
}
