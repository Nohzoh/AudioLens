import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'services/remote_config_service.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'l10n/app_localizations.dart';
import 'services/settings_service.dart';
import 'services/audio_guide_service.dart';
import 'services/audio_ready_notifier.dart';
import 'services/history_service.dart';
import 'utils/app_logger.dart';
import 'screens/onboarding_screen.dart';
import 'screens/home_screen.dart';
import 'screens/history_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  AppLogger.nav('App starting');
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

  final navigatorKey = GlobalKey<NavigatorState>();
  final audioReadyNotifier = AudioReadyNotifier();

  final guide = AudioGuideService(audioReadyNotifier: audioReadyNotifier);
  await guide.init();

  final history = HistoryService();
  await history.init();

  // T120: any entry still "pending" at this point is guaranteed orphaned
  // (no analysis can be in flight this early in the process) — flip it to
  // "failed" so it surfaces with the existing tap-to-retry UI instead of
  // showing a perpetual, indistinguishable-from-active spinner forever.
  final orphanedCount = await history.failOrphanedPendingEntries();
  if (orphanedCount > 0) {
    AppLogger.info(
        'T120: $orphanedCount orphaned pending entr${orphanedCount == 1 ? "y" : "ies"} marked failed on startup');
  }

  // T95: opt-in only (off by default) — deletes history entries older
  // than the configured threshold once per app startup. A startup delay
  // proportional to old-entry count is an acceptable tradeoff for not
  // needing any background scheduling infrastructure.
  if (settings.autoPurgeEnabled) {
    await history.purgeEntriesOlderThan(settings.autoPurgeDays);
  }

  // Tapping a "ready" notification for an entry whose playback was
  // deferred (app backgrounded when analysis finished) opens it and starts
  // playback immediately, reusing HistoryDetailScreen's own
  // generate-then-play logic (_toggleAudio) instead of duplicating it.
  audioReadyNotifier.onPlayRequested = (entryId) {
    HistoryEntry? entry;
    try {
      entry = history.entries.firstWhere((e) => e.id == entryId);
    } catch (_) {
      entry = null;
    }
    if (entry == null) return;
    navigatorKey.currentState?.push(MaterialPageRoute(
      builder: (_) => HistoryDetailScreen(entry: entry!, autoPlay: true),
    ));
  };

  AppLogger.nav('Routing to initial screen: '
      '${guide.isReady || settings.isOnboardingComplete ? "HomeScreen" : "OnboardingScreen"} '
      '(guide.isReady=${guide.isReady}, isOnboardingComplete=${settings.isOnboardingComplete})');

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: settings),
        ChangeNotifierProvider.value(value: guide),
        ChangeNotifierProvider.value(value: history),
      ],
      child: AudioGuideApp(navigatorKey: navigatorKey),
    ),
  );
}

class AudioGuideApp extends StatelessWidget {
  final GlobalKey<NavigatorState> navigatorKey;
  const AudioGuideApp({super.key, required this.navigatorKey});

  @override
  Widget build(BuildContext context) {
    // #145: wraps the whole MaterialApp (not just `home:`, as before) so
    // `themeMode:` actually reacts when the user changes the Appearance
    // setting — a Consumer scoped only to `home:` never touches themeMode
    // again after the first build.
    return Consumer<SettingsService>(
      builder: (context, settings, _) {
        final guide = context.read<AudioGuideService>();
        return MaterialApp(
          navigatorKey: navigatorKey,
          title: 'AudioLens',
          debugShowCheckedModeBanner: false,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          // null falls through to Flutter's default resolution, which
          // already matches the device's locale when supported (fr or en)
          // and falls back to supportedLocales.first otherwise — which is
          // English (the generated list is alphabetical: [en, fr]). English
          // as the fallback for unsupported system locales reaches more
          // non-French speakers than defaulting to French would. A non-null
          // settings.appLocale (in-app override, independent of the
          // device/per-app system language setting) takes precedence over
          // both.
          locale: settings.appLocale != null
              ? Locale(settings.appLocale!)
              : null,
          // #145: same seed color for both — only brightness differs.
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFF6B4EFF),
              brightness: Brightness.light,
            ),
            textTheme: GoogleFonts.interTextTheme(ThemeData.light().textTheme),
            useMaterial3: true,
            // #217 follow-up: an AppBar computes its *own* status bar style
            // (via its own AnnotatedRegion, closer to the leaves than the
            // builder's below) and otherwise ignores it entirely — this was
            // still leaving screens with an AppBar (Settings, History,
            // Logs, About analysis, map picker) on the wrong style even
            // after the builder-level fix, confirmed by the user on-device.
            appBarTheme: const AppBarTheme(
              systemOverlayStyle: SystemUiOverlayStyle.dark,
            ),
          ),
          darkTheme: ThemeData(
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFF6B4EFF),
              brightness: Brightness.dark,
            ),
            textTheme: GoogleFonts.interTextTheme(ThemeData.dark().textTheme),
            useMaterial3: true,
            appBarTheme: const AppBarTheme(
              systemOverlayStyle: SystemUiOverlayStyle.light,
            ),
          ),
          themeMode: settings.themeMode,
          // #217: without this, the status bar icons stayed in whatever
          // style they defaulted to before the light theme (#145) existed
          // — unreadable light/white icons on the light theme's pale
          // background. `builder` runs inside the `Theme` MaterialApp
          // itself resolves from theme/darkTheme/themeMode above, so
          // Theme.of(context).brightness here is the theme actually on
          // screen (already accounts for ThemeMode.system following the
          // platform), not something recomputed separately. Covers every
          // screen that does NOT have its own AppBar (e.g. HomeScreen's
          // custom header) — screens that do are covered by
          // appBarTheme.systemOverlayStyle above instead, since an AppBar
          // takes precedence over this outer region for its own area.
          builder: (context, child) => AnnotatedRegion<SystemUiOverlayStyle>(
            value: Theme.of(context).brightness == Brightness.dark
                ? SystemUiOverlayStyle.light
                : SystemUiOverlayStyle.dark,
            child: child!,
          ),
          home: guide.isReady || settings.isOnboardingComplete
              ? const HomeScreen()
              : const OnboardingScreen(),
        );
      },
    );
  }
}
