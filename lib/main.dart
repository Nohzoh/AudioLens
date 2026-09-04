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

  // #324: a tap that cold-starts the app (process was killed while
  // backgrounded, the deferred analysis finished, notification posted)
  // never reaches onPlayRequested above — that only fires for a tap
  // received while the plugin's already running. Deferred to a
  // post-frame callback so the Navigator (built by runApp() below) exists
  // by the time onPlayRequested tries to push onto it.
  final coldStartEntryId = await audioReadyNotifier.consumeColdStartPayload();
  if (coldStartEntryId != null) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      audioReadyNotifier.onPlayRequested?.call(coldStartEntryId);
    });
  }

  // #312: guide.isReady used to be enough on its own to skip onboarding —
  // meant for an existing install where AI was already configured before
  // onboarding existed. But it's equally true on a brand-new install on a
  // device that happens to support on-device Nano out of the box, which
  // then skipped the carousel entirely (never explaining the app, never
  // stamping lastSeenVersion) and went straight to HomeScreen, where the
  // whats-new dialog fired incorrectly for what was actually a first
  // launch. isOnboardingComplete alone is the only signal that actually
  // means "this device has been through onboarding" — always route there
  // when it's false; the carousel has its own "Passer" button for anyone
  // who doesn't need it.
  AppLogger.nav('Routing to initial screen: '
      '${settings.isOnboardingComplete ? "HomeScreen" : "OnboardingScreen"} '
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
          locale:
              settings.appLocale != null ? Locale(settings.appLocale!) : null,
          // #145: same seed color for both — only brightness differs.
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFF6B4EFF),
              brightness: Brightness.light,
            ),
            textTheme: GoogleFonts.interTextTheme(ThemeData.light().textTheme),
            useMaterial3: true,
            // #217 follow-up, #236 cleanup: an AppBar computes its *own*
            // status bar style (via its own AnnotatedRegion) and otherwise
            // ignores any outer one — this is now the ONLY mechanism in
            // play for AppBar screens (Settings, History list, Logs, About
            // analysis, map picker); see the removed `builder:` comment
            // below for why a second, app-wide mechanism used to also
            // exist and why that was the actual cause of #236.
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
          // #236: there used to be a second, app-wide status-bar-style
          // mechanism here (a `builder:`-level AnnotatedRegion covering
          // every non-AppBar screen, added for #217). Removed — every
          // screen that needs one now sets its own explicit
          // AnnotatedRegion (HomeScreen, OnboardingScreen: theme-driven,
          // matching what this used to compute for them; PlayerScreen,
          // HistoryDetailScreen: hard-coded `.light`, since both are
          // always a darkened photo, never colorScheme.surface) or gets it
          // from appBarTheme.systemOverlayStyle above (any screen with an
          // AppBar). Having two mechanisms meant that during a push
          // between two screens using different ones — e.g. HistoryScreen
          // (AppBar-driven) into PlayerScreen (used to inherit this
          // builder) — Flutter had to resolve which one's value actually
          // won for a given frame, and could resolve it inconsistently
          // frame to frame while both routes were briefly mounted at
          // once, which Android rendered as a flickering/doubled status
          // bar. One explicit source of truth per screen removes the
          // ambiguity at its root instead of patching it pairwise.
          // #312: see the routing-decision AppLogger.nav() call above —
          // guide.isReady is no longer part of this condition.
          home: settings.isOnboardingComplete
              ? const HomeScreen()
              : const OnboardingScreen(),
        );
      },
    );
  }
}
