part of 'history_screen.dart';

/// #145: every `Colors.white*`/`Colors.black*` literal in this class is
/// deliberate, not an oversight — this screen renders its entire content
/// column over [BackgroundPhoto] + a gradient vignette, not the app's
/// themed chrome. Both the vignette and the text/icons on top of it stay
/// a fixed on-scrim color regardless of the app's light/dark setting,
/// the same way the vignette itself doesn't change with the theme —
/// swapping to `colorScheme.onSurface` would make them illegible against
/// both the photo and a light theme's dark-on-light assumption.
class HistoryDetailScreen extends StatefulWidget {
  final HistoryEntry entry;

  /// Starts playback automatically once this screen is shown — used when
  /// arriving here from a "ready" notification tap for an analysis that
  /// finished while the app was backgrounded (playback was deliberately
  /// deferred, see [AudioGuideService.analyzeAndPlay]'s background gating).
  final bool autoPlay;
  const HistoryDetailScreen(
      {super.key, required this.entry, this.autoPlay = false});

  @override
  State<HistoryDetailScreen> createState() => _HistoryDetailScreenState();
}

class _HistoryDetailScreenState extends State<HistoryDetailScreen> {
  bool _isPlaying = false;

  /// The native side that owns cached-WAV playback — the same channel
  /// GeminiTtsService drives, so play/stop/seek all go through one place.
  static const channel = MethodChannel('audio_guide/audio_player');

  /// Whether skip ±10s is meaningful for what's playing right now.
  ///
  /// Mirrors [AudioGuideService.canSkip]'s reasoning rather than
  /// re-deriving it: skipping needs a seekable position, which native TTS
  /// speaking live doesn't have. Two ways playback *is* seekable here:
  ///  - [HistoryEntry.hasAudio] — a cached file replayed via `playWav`.
  ///    Note this is `hasAudio` alone, deliberately not
  ///    `hasAudio && ttsModel == 'gemini-tts'`: legacy 'piper' cached
  ///    files go through the very same MediaPlayer and seek just as well,
  ///    so gating on the model would needlessly exclude them.
  ///  - [AudioGuideService.canSkip] — audio generated on the fly for a
  ///    script-only entry (T16) and played by GeminiTtsService, which is
  ///    seekable but has no cached file on this entry yet.
  bool _canSkip(HistoryEntry live, AudioGuideService guide) =>
      _isPlaying && (live.hasAudio || guide.canSkip);
  bool _isUpgrading = false;
  bool _photoMode =
      false; // T94: show the plain photo instead of the script overlay

  /// Always read the latest version from the service (not the stale widget.entry)
  HistoryEntry _liveEntry(BuildContext context) {
    final history = context.read<HistoryService>();
    return history.entries.firstWhere(
      (e) => e.id == widget.entry.id,
      orElse: () => widget.entry,
    );
  }

  /// #126: swipe-to-navigate, always over the full unfiltered list
  /// (`HistoryService.entries`) rather than whatever favorites/collection
  /// filter was active on the list screen this was opened from — the 3
  /// call sites that push this screen (history list, home-screen recents
  /// grid, notification tap) only ever pass a single [HistoryEntry] today,
  /// not a filtered list or index, so resolving "next in the active
  /// filter" would need new plumbing through all of them. Full-list order
  /// needs none. No-ops at the first/last entry — nothing to report,
  /// there's no error to surface.
  void _navigateAdjacent(BuildContext context, int direction) {
    final entries = context.read<HistoryService>().entries;
    final live = _liveEntry(context);
    final idx = entries.indexWhere((e) => e.id == live.id);
    final target = idx + direction;
    if (idx == -1 || target < 0 || target >= entries.length) return;
    Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => HistoryDetailScreen(entry: entries[target]),
        ));
  }

  // Use AudioGuideService TTS so same voice as first analysis.
  // dynamic: GeminiTtsService/NativeTtsService share no common interface,
  // only the .stop()/.speak() calls this method's callers actually use.
  dynamic _getTts(BuildContext context) {
    final guide = context.read<AudioGuideService>();
    return guide.geminiTtsService ?? guide.nativeTtsService;
  }

  // Play cached audio file directly without re-generating TTS
  Future<void> _playCachedAudio(String path) async {
    channel.invokeMethod('playWav', {'path': path}).then((_) {
      if (!mounted) return;
      setState(() => _isPlaying = false);
    });
  }

  /// #228: jump to [fraction] of the audio playing (long-pressed sentence).
  Future<void> _seekToFraction(double fraction) async {
    AppLogger.tts('History detail: seek to ${(fraction * 100).round()}%');
    await channel.invokeMethod('seekToFraction', {'fraction': fraction});
  }

  /// Skip playback by [deltaMs], negative to go back.
  ///
  /// Talks to the same audio_guide/audio_player channel GeminiTtsService
  /// uses for its own skip controls, so this needs no new native plumbing
  /// — the channel already defaults to a 10s delta.
  Future<void> _skip(int deltaMs) async {
    await channel.invokeMethod(
      deltaMs >= 0 ? 'seekForward' : 'seekBack',
      {'deltaMs': deltaMs.abs()},
    );
  }

  @override
  void initState() {
    super.initState();
    // #255: instance hash distinguishes stacked pushes in the log (e.g.
    // this screen staying mounted underneath a pushed PlayerScreen during
    // a retry) — matters for diagnosing navigation-timing issues like
    // #246.
    AppLogger.nav(
        'HistoryDetailScreen opened (instance ${identityHashCode(this)}, '
        'entry: ${widget.entry.id}, "${widget.entry.title}", '
        'autoPlay: ${widget.autoPlay})');
    // Captured now, not read from context in dispose(): during a bulk
    // teardown (the whole tree unmounting at once, e.g. app shutdown or
    // a test's finalization) an ancestor Provider can already be
    // deactivated by the time a descendant's dispose() runs, and
    // context.read() at that point throws ("Looking up a deactivated
    // widget's ancestor is unsafe").
    _guide = context.read<AudioGuideService>();
    // #555: follow the voice in the script, as the player screen does.
    _previousNativeProgress = _guide.nativeTtsService.onProgress;
    _guide.nativeTtsService.onProgress = (p) => _nativeProgress = p;
    _progressTimer = Timer.periodic(const Duration(milliseconds: 250), (_) => _pollProgress());
    if (widget.autoPlay) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _toggleAudio());
    }
  }

  late final AudioGuideService _guide;

  /// #555: how far the voice is through the script (0 when idle).
  double _readingProgress = 0;
  double? _nativeProgress;
  Function(double)? _previousNativeProgress;
  Timer? _progressTimer;

  /// Audio files report their real position; the phone's voice reports
  /// the offset of the word it speaks (kept in [_nativeProgress]).
  Future<void> _pollProgress() async {
    if (!mounted) return;
    if (!_isPlaying) {
      _nativeProgress = null;
      if (_readingProgress != 0) setState(() => _readingProgress = 0);
      return;
    }
    // The phone's voice first: an audio player that finished earlier
    // keeps reporting its end position.
    double? progress = _nativeProgress;
    if (progress == null) {
      try {
        final result = await channel.invokeMethod<Map>('getPosition');
        final position = (result?['position'] as num?)?.toInt() ?? -1;
        final duration = (result?['duration'] as num?)?.toInt() ?? -1;
        if (position >= 0 && duration > 0) progress = (position / duration).clamp(0.0, 1.0);
      } catch (_) {
        // No audio player.
      }
    }
    if (!mounted || !_isPlaying || progress == null || progress == _readingProgress) return;
    setState(() => _readingProgress = progress!);
  }

  /// Set only while this screen owns some TTS service's `onComplete` (see
  /// [_withTrackedCompletion]) — the callback it's about to restore once
  /// the current speech either finishes or this screen goes away,
  /// whichever comes first. [_completionOwner] remembers which service
  /// (`nativeTtsService` or `geminiTtsService` — both expose the same
  /// `Function()? onComplete` shape, no common interface to type this as)
  /// that restore belongs to.
  void Function()? _restoreOnComplete;
  dynamic _completionOwner;

  /// Speaks via [tts] (`nativeTtsService` or `geminiTtsService`), tracking
  /// `_isPlaying` without permanently hijacking that shared singleton's
  /// `onComplete`.
  ///
  /// A plain `tts.onComplete = () => setState(...)` (what this used to do,
  /// for both services independently — #315's code review caught the
  /// Gemini TTS one still doing this after the native TTS instance was
  /// already fixed) leaks two ways: if this screen closes before speech
  /// finishes, the closure still fires later and calls `setState` on a
  /// disposed State; and since it's never restored, it permanently
  /// replaces [AudioGuideService]'s own default completion handler (the
  /// one set in `init()`, which resets `_state`/`canSkip`) — starving
  /// every later screen's read of that state until the app restarts.
  ///
  /// [action] is whatever triggers the speech this screen wants to track
  /// — a direct `nativeTtsService.speak()`/`geminiTtsService.speak()` call,
  /// or the orchestrated `generateAudioForScript()` pipeline (which copies
  /// whatever's set on native onto Gemini TTS too, see
  /// [TtsOrchestrator.speak]) — the tracking closure itself self-restores
  /// the instant it fires, so every call site can share this without
  /// needing to know which one wins.
  Future<T> _withTrackedCompletion<T>(
    dynamic tts,
    Future<T> Function() action,
  ) async {
    _restoreOnComplete = tts.onComplete;
    _completionOwner = tts;
    tts.onComplete = () {
      tts.onComplete = _restoreOnComplete;
      _restoreOnComplete = null;
      _completionOwner = null;
      if (!mounted) return;
      setState(() => _isPlaying = false);
    };
    return action();
  }

  @override
  void dispose() {
    AppLogger.nav(
        'HistoryDetailScreen closed (instance ${identityHashCode(this)}, '
        'entry: ${widget.entry.id})');
    // Stop playback when leaving screen
    channel.invokeMethod('stop');
    _guide.nativeTtsService.stop();
    _progressTimer?.cancel();
    _guide.nativeTtsService.onProgress = _previousNativeProgress;
    // If speech is still in flight, our tracking closure above is still
    // installed — put the previous handler back so a completion firing
    // after this screen is gone doesn't touch a disposed State or leave
    // AudioGuideService's own state stuck.
    if (_restoreOnComplete != null) {
      _completionOwner.onComplete = _restoreOnComplete;
    }
    super.dispose();
  }

  Future<void> _toggleAudio() async {
    if (_isPlaying) {
      final tts = _getTts(context);
      await tts.stop();
      setState(() => _isPlaying = false);
      return;
    }

    // #246: a regenerate (or any other analysis) already running on the
    // same shared AudioGuideService — starting a second operation here
    // raced with it finishing (both fast-failing near-simultaneously,
    // each with its own setState/SnackBar) right as the regenerate's own
    // Navigator.push transition was resolving, and showed up as this
    // screen's content bleeding through PlayerScreen. Same guard
    // runAnalysisAndNavigate already uses for the reverse direction.
    if (context.read<AudioGuideService>().isBusy) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Une analyse est déjà en cours.')),
      );
      return;
    }

    final live = _liveEntry(context);
    setState(() => _isPlaying = true);

    if (live.hasAudio) {
      // Use cached audio — no TTS regeneration needed
      await _playCachedAudio(live.audioPath!);
      return;
    }

    if (live.hasLowQualityTts) {
      // T133: this entry's last known voice was the native fallback
      // (Gemini TTS failed at analysis time) and there's no cached file
      // (native TTS speaks live, never caches) — just replay it live
      // instead of silently re-attempting Gemini here too. The dedicated
      // "Améliorer la voix" button below is the explicit way to retry
      // Gemini.
      final guide = context.read<AudioGuideService>();
      // #130: this bypasses generateAudioForScript/_synthesizeAndPlay, so
      // the native TTS language has to be applied explicitly here too.
      guide.prepareNativeTtsLanguageForReplay(
        context.read<SettingsService>().outputLanguage,
      );
      await _withTrackedCompletion(
          guide.nativeTtsService, () => guide.nativeTtsService.speak(live.script));
      return;
    }

    // No cached audio (T16 — script-only entry, or a missing cache file):
    // generate via the orchestrated pipeline (cloud TTS + native fallback)
    // and persist the result so it's cached from now on.
    final guide = context.read<AudioGuideService>();
    final history = context.read<HistoryService>();
    final result = await _withTrackedCompletion(
      guide.nativeTtsService,
      () => guide.generateAudioForScript(
        title: live.title,
        script: live.script,
        locationName: live.locationName,
        language: context.read<SettingsService>().outputLanguage,
      ),
    );

    if (result == null) {
      // Synthesis failed — onComplete above never fires, reset locally.
      setState(() => _isPlaying = false);
      if (mounted) {
        final l10n = AppLocalizations.of(context)!;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(guide.lastGuideError != null
                ? localizeGuideError(l10n, guide.lastGuideError!)
                : l10n.historyAudioGenerationFailed),
            duration: const Duration(seconds: 4),
            backgroundColor: Colors.orange.shade800,
          ),
        );
      }
      return;
    }

    final audioPath = guide.lastAudioPath;
    if (audioPath != null && live.id != null) {
      try {
        await history.saveAudioPath(
          live.id!,
          audioPath,
          ttsModel: guide.lastTtsModel,
          ttsFallback: guide.ttsWasFallback,
        );
      } on HistoryStorageException catch (e) {
        // Playback via guide already worked — only caching the audio
        // file for next time failed (T116).
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(
                  localizeHistoryStorageException(AppLocalizations.of(context)!, e))));
        }
      }
    }
  }

  Future<void> _deleteEntry(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(l10n.historyDeleteTitle),
        content: Text(l10n.historyDeleteConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.historyCancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.historyDeleteTitle,
                style: const TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      await context.read<HistoryService>().deleteEntry(widget.entry.id!);
      if (context.mounted) Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final live = _liveEntry(context);
    final dateStr = DateFormat('EEEE d MMMM yyyy · HH:mm',
            Localizations.localeOf(context).toString())
        .format(live.createdAt);

    // Always a darkened photo background, never colorScheme.surface — see
    // the matching comment in player_screen.dart's build() for why this
    // shouldn't follow the app theme's brightness like the global
    // AnnotatedRegion in main.dart does.
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        // #126: swipe between entries — only when not zoomed/panning the
        // photo (_photoMode), so this doesn't fight BackgroundPhoto's own
        // InteractiveViewer for the gesture arena.
        body: GestureDetector(
          onHorizontalDragEnd: _photoMode
              ? null
              : (details) {
                  final velocity = details.primaryVelocity ?? 0;
                  if (velocity < -200) {
                    _navigateAdjacent(context, 1); // swipe left -> next/older
                  } else if (velocity > 200) {
                    _navigateAdjacent(
                        context, -1); // swipe right -> previous/newer
                  }
                },
          child: Stack(
            fit: StackFit.expand,
            children: [
              // #147: shared with player_screen.dart. T96: the reading-mode
              // gradient here is a 3-stop vignette (stronger at the very top
              // than the player's) to protect the top bar icons — especially
              // the red delete icon — over a bright photo, not just the
              // bottom text.
              PhotoGradientBackground(
                file: File(live.imagePath),
                rotationQuarters: live.rotationQuarters,
                photoMode: _photoMode,
                readingGradientColors: [
                  Colors.black.withValues(alpha: 0.45),
                  Colors.black.withValues(alpha: 0.15),
                  Colors.black.withValues(alpha: 0.95),
                ],
                readingGradientStops: const [0.0, 0.3, 1.0],
              ),

              SafeArea(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Top bar — each icon gets its own scrim (T96) so it stays
                    // legible regardless of gradient tuning or photo content.
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      child: Row(
                        children: [
                          ScrimIconButton(
                            icon: Icons.arrow_back,
                            color: Colors.white,
                            tooltip: l10n.commonBack,
                            onPressed: () => Navigator.pop(context),
                          ),
                          // #235: was 6 icons in a horizontally-scrollable
                          // Row (rotate was the newest, #152/#183) — the
                          // least-recently-added ones (info, delete) scrolled
                          // off-screen and weren't discoverable without
                          // knowing to swipe. Only the two frequent, glanceable
                          // state toggles stay visible; the rest move into the
                          // overflow menu below.
                          const Spacer(),
                          ScrimIconButton(
                            icon: live.isFavorite
                                ? Icons.star
                                : Icons.star_border,
                            color: live.isFavorite
                                ? Colors.amberAccent
                                : Colors.white70,
                            tooltip: live.isFavorite
                                ? l10n.historyRemoveFromFavorites
                                : l10n.historyAddToFavorites,
                            // #190: same root cause as the rotate menu item
                            // below — _liveEntry(context) reads HistoryService
                            // via context.read, so nothing here rebuilds this
                            // screen just because toggleFavorite() notified a
                            // change.
                            onPressed: () async {
                              await context
                                  .read<HistoryService>()
                                  .toggleFavorite(live.id!);
                              if (mounted) setState(() {});
                            },
                          ),
                          const SizedBox(width: 4),
                          ScrimIconButton(
                            icon: _photoMode
                                ? Icons.article_outlined
                                : Icons.image_outlined,
                            color: Colors.white70,
                            tooltip: _photoMode
                                ? l10n.playerShowText
                                : l10n.playerPhotoMode,
                            onPressed: () =>
                                setState(() => _photoMode = !_photoMode),
                          ),
                          const SizedBox(width: 4),
                          // #246: regenerate disabled while a play/generate
                          // operation from the button below is in flight (or
                          // any other analysis is running elsewhere) — see
                          // the matching guard in _toggleAudio for why.
                          Consumer<AudioGuideService>(
                            builder: (context, guide, _) => _DetailOverflowMenu(
                              regenerateEnabled: !_isPlaying && !guide.isBusy,
                              onAddToCollection: () {
                                if (live.id != null) {
                                  _openCollectionsSheet(context, {live.id!});
                                }
                              },
                              onRotate: () async {
                                try {
                                  await context
                                      .read<HistoryService>()
                                      .rotateEntry(live.id!);
                                  // #190: _liveEntry(context) reads
                                  // HistoryService via context.read, not watch
                                  // — this screen never rebuilds on its own
                                  // just because HistoryService notified a
                                  // change, so without this the new rotation
                                  // stayed invisible until some unrelated
                                  // setState (e.g. toggling photo mode)
                                  // happened to force a rebuild that re-read
                                  // it fresh.
                                  if (mounted) setState(() {});
                                } on HistoryStorageException catch (e) {
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                            content: Text(localizeHistoryStorageException(
                                                AppLocalizations.of(context)!, e))));
                                  }
                                }
                              },
                              onRegenerate: () =>
                                  _openRegenerateSheet(context, live),
                              onInfo: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                      builder: (_) => AboutAnalysisScreen(
                                          entry: widget.entry))),
                              onDelete: () => _deleteEntry(context),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Content
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // T94: everything but the play/generate button below
                            // is hidden in photo mode, matching player_screen.dart
                            // — playback stays controllable while the photo is
                            // shown unobstructed.
                            if (!_photoMode) ...[
                              // Date
                              // #128: white70, not white54 — see the matching
                              // comment in player_screen.dart.
                              Text(
                                dateStr,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: Colors.white70,
                                ),
                              ),
                              const SizedBox(height: 8),

                              // Title
                              Text(
                                live.title,
                                style: theme.textTheme.headlineSmall?.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),

                              if (live.locationName != null) ...[
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    const Icon(Icons.location_on,
                                        color: Colors.white70, size: 14),
                                    const SizedBox(width: 4),
                                    Text(
                                      live.locationName!,
                                      style: const TextStyle(
                                          color: Colors.white70),
                                    ),
                                  ],
                                ),
                              ],

                              // #126
                              if (live.gpsLatitude != null &&
                                  live.gpsLongitude != null) ...[
                                const SizedBox(height: 8),
                                MiniMap(
                                  latitude: live.gpsLatitude!,
                                  longitude: live.gpsLongitude!,
                                ),
                              ],

                              const SizedBox(height: 16),

                              // #147: shared with player_screen.dart.
                              // #421: rating on the left (scaled down
                              // rather than overflowing on a narrow
                              // screen), actions on the right.
                              Row(children: [
                                Expanded(
                                  child: live.status == AnalysisStatus.complete
                                      ? Align(
                                          alignment: Alignment.centerLeft,
                                          child: FittedBox(
                                            fit: BoxFit.scaleDown,
                                            child: ScriptRatingBar(entry: live),
                                          ),
                                        )
                                      : const SizedBox.shrink(),
                                ),
                                const SizedBox(width: 8),
                                GuideActionRow(
                                  imagePath: live.imagePath,
                                  rotationQuarters: live.rotationQuarters,
                                  script: live.script,
                                  title: live.title,
                                  audioPath: live.audioPath,
                                  aiModel: live.aiModel,
                                  reportDate: live.analyzedAt ?? live.createdAt,
                                  feedbackEntry: live,
                                ),
                              ]),
                              const SizedBox(height: 8),

                              // Script
                              Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.4),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                      color:
                                          Colors.white.withValues(alpha: 0.1)),
                                ),
                                // #228: long-press a sentence to jump
                                // there while seekable audio plays.
                                child: SeekableScript(
                                  text: live.script,
                                  progress: _readingProgress,
                                  padding: EdgeInsets.zero,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: Colors.white.withValues(alpha: 0.85),
                                    height: 1.6,
                                  ),
                                  onSeek: _canSkip(
                                          live,
                                          Provider.of<AudioGuideService>(context,
                                              listen: false))
                                      ? _seekToFraction
                                      : null,
                                ),
                              ),

                              const SizedBox(height: 20),
                            ], // end if (!_photoMode)
                          ],
                        ),
                      ),
                    ),

                    // Upgrade TTS button — deliberately kept out of the
                    // scrollable content above (T133): it used to live inside
                    // the `if (!_photoMode)` section, so it silently vanished
                    // in photo mode, and for a native-TTS-fallback entry (no
                    // cached audioPath) it was the ONLY way back to Gemini's
                    // better voice — same reasoning as the play/generate
                    // button below (T122).
                    if (_liveEntry(context).hasLowQualityTts)
                      Consumer<AudioGuideService>(
                        builder: (context, guide, _) {
                          if (guide.geminiTtsService == null) {
                            return const SizedBox.shrink();
                          }
                          return Padding(
                            padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                            child: OutlinedButton.icon(
                              icon: _isUpgrading
                                  ? const SizedBox(
                                      width: 14,
                                      height: 14,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2, color: Colors.amber))
                                  : const Icon(Icons.auto_awesome, size: 16),
                              label: Text(_isUpgrading
                                  ? l10n.historyUpgradingVoice
                                  : l10n.historyUpgradeVoice),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.amber,
                                side: const BorderSide(color: Colors.amber),
                                minimumSize: const Size(double.infinity, 48),
                              ),
                              onPressed: _isUpgrading
                                  ? null
                                  : () async {
                                      final history =
                                          context.read<HistoryService>();
                                      setState(() => _isUpgrading = true);
                                      try {
                                        final tts = guide.geminiTtsService!;
                                        // Generate audio first, then play
                                        await _withTrackedCompletion(
                                            tts, () => tts.speak(live.script));
                                        // Save upgraded audio
                                        final lastPath = tts.lastWavPath;
                                        AppLogger.tts(
                                            'upgrade lastAudioPath: $lastPath, entry.id: ${live.id}');
                                        if (lastPath != null &&
                                            live.id != null) {
                                          await history.saveAudioPath(
                                              live.id!, lastPath,
                                              ttsModel: 'gemini-tts',
                                              ttsFallback: false);
                                          AppLogger.tts('saveAudioPath OK');
                                        } else {
                                          AppLogger.error(
                                              'saveAudioPath skipped: lastPath=$lastPath id=${live.id}');
                                        }
                                        setState(() => _isPlaying = true);
                                      } catch (error) {
                                        setState(() => _isPlaying = false);
                                        if (context.mounted) {
                                          final message =
                                              formatVoiceUpgradeErrorMessage(
                                                  error, l10n);
                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(
                                            SnackBar(
                                              content: Text(message),
                                              duration:
                                                  const Duration(seconds: 4),
                                              backgroundColor:
                                                  Colors.orange.shade800,
                                            ),
                                          );
                                        }
                                      } finally {
                                        setState(() => _isUpgrading = false);
                                      }
                                    },
                            ),
                          );
                        },
                      ),

                    // Play / generate button — deliberately kept out of the
                    // scrollable content above and anchored here instead
                    // (T122): when _photoMode hides everything else, a
                    // scroll view's remaining content aligns to its top, not
                    // the bottom of the screen — the button used to float
                    // awkwardly over the middle of the photo instead of
                    // sitting at the bottom like a real control, matching
                    // player_screen.dart's own playback controls.
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
                      // Scoped to just this row: canSkip flips as the
                      // service's own playback state changes (e.g. synthesis
                      // finishing for a script-only entry), and the skip
                      // buttons need to appear when it does — but nothing
                      // else in this screen (photo, gradient, script text)
                      // needs to rebuild on every AudioGuideService change.
                      child: Consumer<AudioGuideService>(
                        builder: (context, guide, _) {
                          final showSkip = _canSkip(live, guide);
                          // TTS for a script-only entry is still being
                          // synthesized — playback hasn't started yet, so
                          // show a disabled loader instead of a Stop button
                          // that implied audio was already playing.
                          final generating = _isPlaying &&
                              guide.isBusy &&
                              guide.state == GuideState.synthesizing;
                          // #508: an entry reached by swiping may not be
                          // analyzed yet (captured, failed, or stuck
                          // pending). It has no script, so « Générer
                          // l'audio » did nothing; offer what tapping its
                          // card in the list does instead.
                          if (historyDetailNeedsAnalysis(live)) {
                            return Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                FilledButton.icon(
                                  onPressed: () => live.isCaptured
                                      ? _launchAnalysis(context, live)
                                      : _retryAnalysis(context, live),
                                  icon: Icon(live.isCaptured
                                      ? Icons.auto_awesome
                                      : Icons.refresh),
                                  label: Text(live.isCaptured
                                      ? l10n.historyLaunchAnalysis
                                      : l10n.historyRetryAnalysis),
                                  style: FilledButton.styleFrom(
                                    minimumSize: const Size(double.infinity, 52),
                                    shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(14)),
                                  ),
                                ),
                                // #467: say what the photo shows first.
                                TextButton.icon(
                                  icon: const Icon(Icons.edit_note, size: 18),
                                  label: Text(l10n.historyAnalyzeWithHint),
                                  onPressed: () =>
                                      _openRegenerateSheet(context, live),
                                ),
                              ],
                            );
                          }
                          return Row(
                            children: [
                              // Skip only when the current playback is
                              // seekable — see _canSkip.
                              if (showSkip) ...[
                                // #147: shared with player_screen.dart.
                                SkipIconButton(
                                  forward: false,
                                  onPressed: () => _skip(-10000),
                                ),
                                const SizedBox(width: 4),
                              ],
                              Expanded(
                                child: FilledButton.icon(
                                  onPressed: generating ? null : _toggleAudio,
                                  icon: generating
                                      ? const SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(
                                              strokeWidth: 2))
                                      : Icon(_isPlaying
                                      ? Icons.stop
                                      : ((live.hasAudio ||
                                              live.hasLowQualityTts)
                                          ? Icons.play_arrow
                                          : Icons.auto_awesome)),
                                  label: Text(generating
                                      ? l10n.historyGeneratingAudio
                                      : _isPlaying
                                      ? l10n.historyStop
                                      : ((live.hasAudio ||
                                              live.hasLowQualityTts)
                                          ? l10n.historyListen
                                          : l10n.historyGenerateAudio)),
                                  style: FilledButton.styleFrom(
                                    minimumSize: const Size(0, 52),
                                    shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(14)),
                                  ),
                                ),
                              ),
                              if (showSkip) ...[
                                const SizedBox(width: 4),
                                SkipIconButton(
                                  forward: true,
                                  onPressed: () => _skip(10000),
                                ),
                              ],
                            ],
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// #235: the overflow menu for `HistoryDetailScreen`'s top bar — the 5
/// actions that don't need to be always-visible (add to collection,
/// rotate, regenerate, info, delete), moved out of a horizontally-
/// scrollable icon row that was pushing the least-recently-added ones
/// (info, delete) off-screen. Each callback is fired from `onSelected`
/// rather than baked into the item itself, so the caller keeps full
/// control of context/mounted-checks the same way the inlined
/// `ScrimIconButton.onPressed`s used to.
enum _DetailMenuAction { addToCollection, rotate, regenerate, info, delete }

class _DetailOverflowMenu extends StatelessWidget {
  final VoidCallback onAddToCollection;
  final VoidCallback onRotate;
  final VoidCallback onRegenerate;
  final VoidCallback onInfo;
  final VoidCallback onDelete;
  final bool regenerateEnabled;

  const _DetailOverflowMenu({
    required this.onAddToCollection,
    required this.onRotate,
    required this.onRegenerate,
    required this.onInfo,
    required this.onDelete,
    this.regenerateEnabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        // #145: stays fixed black regardless of app theme, matching
        // ScrimIconButton — see that class's doc.
        color: Colors.black.withValues(alpha: 0.35),
      ),
      child: PopupMenuButton<_DetailMenuAction>(
        tooltip: l10n.historyMoreActions,
        icon: const Icon(Icons.more_vert, color: Colors.white70),
        onSelected: (action) {
          switch (action) {
            case _DetailMenuAction.addToCollection:
              onAddToCollection();
              break;
            case _DetailMenuAction.rotate:
              onRotate();
              break;
            case _DetailMenuAction.regenerate:
              onRegenerate();
              break;
            case _DetailMenuAction.info:
              onInfo();
              break;
            case _DetailMenuAction.delete:
              onDelete();
              break;
          }
        },
        itemBuilder: (context) => [
          PopupMenuItem(
            value: _DetailMenuAction.addToCollection,
            child: _MenuRow(
                icon: Icons.playlist_add, label: l10n.historyAddToCollection),
          ),
          PopupMenuItem(
            value: _DetailMenuAction.rotate,
            child: _MenuRow(
                icon: Icons.rotate_90_degrees_cw_outlined,
                label: l10n.historyRotatePhoto),
          ),
          PopupMenuItem(
            value: _DetailMenuAction.regenerate,
            // #246: disabled while a play/generate operation is already
            // in flight, to avoid racing it with a fresh analysis.
            enabled: regenerateEnabled,
            child: _MenuRow(
                icon: Icons.tune,
                label: l10n.historyRegenerateTooltip,
                color: regenerateEnabled ? null : Colors.black38),
          ),
          PopupMenuItem(
            value: _DetailMenuAction.info,
            child: _MenuRow(
                icon: Icons.info_outline, label: l10n.aboutAnalysisTitle),
          ),
          const PopupMenuDivider(),
          PopupMenuItem(
            value: _DetailMenuAction.delete,
            child: _MenuRow(
              icon: Icons.delete_outline,
              label: l10n.historyDeleteTitle,
              color: Colors.redAccent,
            ),
          ),
        ],
      ),
    );
  }
}

class _MenuRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? color;

  const _MenuRow({required this.icon, required this.label, this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 12),
        Expanded(
          child: Text(label,
              style: TextStyle(color: color), overflow: TextOverflow.ellipsis),
        ),
      ],
    );
  }
}
