import 'dart:io';
import '../utils/app_logger.dart';
import '../utils/analysis_runner.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gal/gal.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../l10n/app_localizations.dart';
import '../services/audio_guide_service.dart';
import '../services/history_service.dart';
import '../services/settings_service.dart';
import '../widgets/background_photo.dart';
import '../widgets/kofi_button.dart';
import '../widgets/report_content_button.dart';
import '../utils/user_message_utils.dart';
import 'about_analysis_screen.dart';

/// Launches the analysis for a captured entry (T78), using the raw GPS
/// saved at capture time rather than the device's current location.
Future<void> _launchAnalysis(BuildContext context, HistoryEntry entry) async {
  final imageFile = File(entry.imagePath);
  if (!imageFile.existsSync()) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(AppLocalizations.of(context)!.historyImageNotFound)),
    );
    return;
  }
  final knownCoordinates = await resolveKnownCoordinatesForRelaunch(context, entry);
  if (!context.mounted) return;
  await runAnalysisAndNavigate(
    context: context,
    imageFile: imageFile,
    entryId: entry.id!,
    source: 'captured',
    knownCoordinates: knownCoordinates,
  );
}

/// Retries a failed analysis, reusing whatever location was resolved for
/// the original attempt (live GPS, EXIF, or a manually picked map point)
/// instead of re-resolving the device's current position from scratch —
/// see HistoryService.failEntry's doc.
Future<void> _retryAnalysis(BuildContext context, HistoryEntry entry) async {
  final imageFile = File(entry.imagePath);
  if (!imageFile.existsSync()) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(AppLocalizations.of(context)!.historyImageNotFound)),
    );
    return;
  }
  final knownCoordinates = await resolveKnownCoordinatesForRelaunch(context, entry);
  if (!context.mounted) return;
  await runAnalysisAndNavigate(
    context: context,
    imageFile: imageFile,
    entryId: entry.id!,
    source: 'retry',
    knownCoordinates: knownCoordinates,
  );
}

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  // T51: mutually exclusive with each other and with "all" (both null).
  bool _favoritesOnly = false;
  int? _selectedCollectionId;

  void _selectAll() =>
      setState(() { _favoritesOnly = false; _selectedCollectionId = null; });
  void _selectFavorites() =>
      setState(() { _favoritesOnly = true; _selectedCollectionId = null; });
  void _selectCollection(int id) =>
      setState(() { _favoritesOnly = false; _selectedCollectionId = id; });

  List<HistoryEntry> _filteredEntries(HistoryService history) {
    if (_favoritesOnly) {
      return history.entries.where((e) => e.isFavorite).toList();
    }
    if (_selectedCollectionId != null) {
      final id = _selectedCollectionId!;
      return history.entries
          .where((e) => e.id != null && history.collectionIdsForEntry(e.id!).contains(id))
          .toList();
    }
    return history.entries;
  }

  Future<void> _createCollection(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(l10n.historyNewCollection),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(hintText: l10n.historyNewCollectionHint),
          onSubmitted: (value) => Navigator.pop(context, value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.historyCancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: Text(l10n.historyCreateCollection),
          ),
        ],
      ),
    );
    final trimmed = name?.trim();
    if (trimmed != null && trimmed.isNotEmpty && context.mounted) {
      await context.read<HistoryService>().createCollection(trimmed);
    }
  }

  Future<void> _confirmDeleteCollection(
      BuildContext context, Collection collection) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(l10n.historyDeleteCollection),
        content: Text(l10n.historyDeleteCollectionConfirm(collection.name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.historyCancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.historyDeleteCollection,
                style: const TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      if (_selectedCollectionId == collection.id) {
        setState(() => _selectedCollectionId = null);
      }
      await context.read<HistoryService>().deleteCollection(collection.id!);
    }
  }

  Widget _buildFilterRow(BuildContext context, HistoryService history) {
    final l10n = AppLocalizations.of(context)!;
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilterChip(
              label: Text(l10n.historyAllFilter),
              selected: !_favoritesOnly && _selectedCollectionId == null,
              onSelected: (_) => _selectAll(),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilterChip(
              avatar: const Icon(Icons.star, size: 16),
              label: Text(l10n.historyFavoritesFilter),
              selected: _favoritesOnly,
              onSelected: (_) => _selectFavorites(),
            ),
          ),
          for (final c in history.collections)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: GestureDetector(
                onLongPress: () => _confirmDeleteCollection(context, c),
                child: FilterChip(
                  label: Text(c.name),
                  selected: _selectedCollectionId == c.id,
                  onSelected: (_) => _selectCollection(c.id!),
                ),
              ),
            ),
          ActionChip(
            avatar: const Icon(Icons.add, size: 16),
            label: Text(l10n.historyNewCollection),
            onPressed: () => _createCollection(context),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.historyTitle),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          Consumer<SettingsService>(
            builder: (context, settings, _) => KofiButton(
              show: settings.showKofiButton,
            ),
          ),
        ],
      ),
      body: Consumer<HistoryService>(
        builder: (context, history, _) {
          if (history.entries.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.history, size: 64, color: Colors.white12),
                  const SizedBox(height: 16),
                  Text(
                    l10n.historyEmptyTitle,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: Colors.white38,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    l10n.historyEmptySubtitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Colors.white24,
                    ),
                  ),
                ],
              ),
            );
          }

          final filtered = _filteredEntries(history);

          return Column(
            children: [
              _buildFilterRow(context, history),
              const SizedBox(height: 8),
              Expanded(
                child: filtered.isEmpty
                    ? Center(
                        child: Text(
                          l10n.historyNoFilterResults,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: Colors.white38,
                          ),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        itemCount: filtered.length,
                        itemBuilder: (context, index) {
                          final entry = filtered[index];
                          return _HistoryCard(key: ValueKey(entry.id), entry: entry)
                              .animate(delay: (index * 50).ms)
                              .fadeIn()
                              .slideY(begin: 0.1);
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// T51: bottom sheet to add/remove [entry] from any number of collections,
/// with inline creation of a new one. Shared by the history card's
/// long-press and the detail screen's collections button.
Future<void> _openCollectionsSheet(BuildContext context, HistoryEntry entry) async {
  if (entry.id == null) return;
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (_) => _CollectionsSheet(entryId: entry.id!),
  );
}

class _CollectionsSheet extends StatefulWidget {
  final int entryId;
  const _CollectionsSheet({required this.entryId});

  @override
  State<_CollectionsSheet> createState() => _CollectionsSheetState();
}

class _CollectionsSheetState extends State<_CollectionsSheet> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _create(HistoryService history) async {
    final name = _controller.text.trim();
    if (name.isEmpty) return;
    final collection = await history.createCollection(name);
    await history.setEntryInCollection(widget.entryId, collection.id!, true);
    _controller.clear();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return SafeArea(
      child: Consumer<HistoryService>(
        builder: (context, history, _) {
          final memberIds = history.collectionIdsForEntry(widget.entryId);
          return Padding(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 16,
              bottom: 16 + MediaQuery.of(context).viewInsets.bottom,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.historyAddToCollection,
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                if (history.collections.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(l10n.historyNoCollectionsYet,
                        style: const TextStyle(color: Colors.white38)),
                  )
                else
                  Flexible(
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        for (final c in history.collections)
                          CheckboxListTile(
                            value: memberIds.contains(c.id),
                            title: Text(c.name),
                            contentPadding: EdgeInsets.zero,
                            onChanged: (checked) => history.setEntryInCollection(
                                widget.entryId, c.id!, checked ?? false),
                          ),
                      ],
                    ),
                  ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        decoration:
                            InputDecoration(hintText: l10n.historyNewCollectionHint),
                        onSubmitted: (_) => _create(history),
                      ),
                    ),
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: () => _create(history),
                      child: Text(l10n.historyCreateCollection),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _HistoryCard extends StatelessWidget {
  final HistoryEntry entry;
  const _HistoryCard({super.key, required this.entry});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final dateStr = DateFormat('d MMM yyyy · HH:mm',
            Localizations.localeOf(context).toString())
        .format(entry.createdAt);
    final isFailed = entry.status == AnalysisStatus.failed;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () {
            if (entry.isPending || isFailed) {
              _retryAnalysis(context, entry);
            } else if (entry.isCaptured) {
              _launchAnalysis(context, entry);
            } else {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => HistoryDetailScreen(entry: entry),
                ),
              );
            }
          },
          // T51: long-press anywhere on the card to assign it to collections.
          onLongPress: entry.id == null
              ? null
              : () => _openCollectionsSheet(context, entry),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                // Thumbnail
                Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: SizedBox(
                        width: 72,
                        height: 72,
                        child: File(entry.imagePath).existsSync()
                            ? Image.file(
                                File(entry.imagePath),
                                fit: BoxFit.cover,
                              )
                            : Container(
                                color: theme.colorScheme.surfaceContainerHighest,
                                child: const Icon(Icons.image_not_supported,
                                    color: Colors.white24),
                              ),
                      ),
                    ),
                    if (entry.id != null)
                      Positioned(
                        top: 2,
                        left: 2,
                        child: GestureDetector(
                          onTap: () => context
                              .read<HistoryService>()
                              .toggleFavorite(entry.id!),
                          child: Container(
                            padding: const EdgeInsets.all(3),
                            decoration: const BoxDecoration(
                              color: Colors.black45,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              entry.isFavorite ? Icons.star : Icons.star_border,
                              size: 14,
                              color: entry.isFavorite
                                  ? Colors.amberAccent
                                  : Colors.white70,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(width: 12),

                // Info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry.title,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (entry.locationName != null) ...[
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            const Icon(Icons.location_on,
                                size: 12, color: Colors.white38),
                            const SizedBox(width: 2),
                            Text(
                              entry.locationName!,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: Colors.white38,
                              ),
                            ),
                          ],
                        ),
                      ],
                      if (entry.status == AnalysisStatus.complete && !entry.hasAudio) ...[
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            const Icon(Icons.text_snippet_outlined,
                                size: 12, color: Colors.white38),
                            const SizedBox(width: 2),
                            Text(
                              l10n.historyScriptOnly,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: Colors.white38,
                              ),
                            ),
                          ],
                        ),
                      ],
                      if (entry.isCaptured) ...[
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            const Icon(Icons.cloud_off_outlined,
                                size: 12, color: Colors.white38),
                            const SizedBox(width: 2),
                            Text(
                              l10n.historyCapturedTapToAnalyze,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: Colors.white38,
                              ),
                            ),
                          ],
                        ),
                      ],
                      if (isFailed) ...[
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            const Icon(Icons.refresh,
                                size: 12, color: Colors.orangeAccent),
                            const SizedBox(width: 2),
                            Text(
                              l10n.historyFailedTapToRetry,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: Colors.orangeAccent,
                              ),
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 4),
                      Text(
                        dateStr,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: Colors.white24,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),

                const Icon(Icons.chevron_right, color: Colors.white24),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class HistoryDetailScreen extends StatefulWidget {
  final HistoryEntry entry;
  /// Starts playback automatically once this screen is shown — used when
  /// arriving here from a "ready" notification tap for an analysis that
  /// finished while the app was backgrounded (playback was deliberately
  /// deferred, see [AudioGuideService.analyzeAndPlay]'s background gating).
  final bool autoPlay;
  const HistoryDetailScreen({super.key, required this.entry, this.autoPlay = false});

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
  bool _photoMode = false; // T94: show the plain photo instead of the script overlay

  /// Always read the latest version from the service (not the stale widget.entry)
  HistoryEntry _liveEntry(BuildContext context) {
    final history = context.read<HistoryService>();
    return history.entries.firstWhere(
      (e) => e.id == widget.entry.id,
      orElse: () => widget.entry,
    );
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
    // Captured now, not read from context in dispose(): during a bulk
    // teardown (the whole tree unmounting at once, e.g. app shutdown or
    // a test's finalization) an ancestor Provider can already be
    // deactivated by the time a descendant's dispose() runs, and
    // context.read() at that point throws ("Looking up a deactivated
    // widget's ancestor is unsafe").
    _guide = context.read<AudioGuideService>();
    if (widget.autoPlay) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _toggleAudio());
    }
  }

  late final AudioGuideService _guide;

  /// Set only while this screen owns [AudioGuideService.nativeTtsService]'s
  /// `onComplete` (see [_withTrackedNativeCompletion]) — the callback it's about to
  /// restore once the current speech either finishes or this screen goes
  /// away, whichever comes first.
  void Function()? _restoreNativeOnComplete;

  /// Speaks [script] via native TTS, tracking `_isPlaying` without
  /// permanently hijacking the shared [AudioGuideService.nativeTtsService]
  /// singleton's `onComplete`.
  ///
  /// A plain `guide.nativeTtsService.onComplete = () => setState(...)`
  /// (what this used to do) leaks two ways: if this screen closes before
  /// speech finishes, the closure still fires later and calls `setState`
  /// on a disposed State; and since it's never restored, it permanently
  /// replaces [AudioGuideService]'s own default completion handler (the
  /// one set in `init()`, which resets `_state`/`canSkip`) — starving
  /// every later screen's read of that state until the app restarts.
  ///
  /// [action] is whatever triggers the speech this screen wants to track
  /// — a direct `nativeTtsService.speak()` call, or the orchestrated
  /// `generateAudioForScript()` pipeline (which copies whatever's set
  /// here onto Gemini TTS too, see [TtsOrchestrator.speak]) — the
  /// tracking closure itself self-restores the instant it fires, so both
  /// call sites can share this without needing to know which one wins.
  Future<T> _withTrackedNativeCompletion<T>(
    AudioGuideService guide,
    Future<T> Function() action,
  ) async {
    _restoreNativeOnComplete = guide.nativeTtsService.onComplete;
    guide.nativeTtsService.onComplete = () {
      guide.nativeTtsService.onComplete = _restoreNativeOnComplete;
      _restoreNativeOnComplete = null;
      if (!mounted) return;
      setState(() => _isPlaying = false);
    };
    return action();
  }

  @override
  void dispose() {
    // Stop playback when leaving screen
    channel.invokeMethod('stop');
    _guide.nativeTtsService.stop();
    // If speech is still in flight, our tracking closure above is still
    // installed — put the previous handler back so a completion firing
    // after this screen is gone doesn't touch a disposed State or leave
    // AudioGuideService's own state stuck.
    if (_restoreNativeOnComplete != null) {
      _guide.nativeTtsService.onComplete = _restoreNativeOnComplete;
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
      await _withTrackedNativeCompletion(guide, () => guide.nativeTtsService.speak(live.script));
      return;
    }

    // No cached audio (T16 — script-only entry, or a missing cache file):
    // generate via the orchestrated pipeline (cloud TTS + native fallback)
    // and persist the result so it's cached from now on.
    final guide = context.read<AudioGuideService>();
    final history = context.read<HistoryService>();
    final result = await _withTrackedNativeCompletion(
      guide,
      () => guide.generateAudioForScript(
        title: live.title,
        script: live.script,
        locationName: live.locationName,
      ),
    );

    if (result == null) {
      // Synthesis failed — onComplete above never fires, reset locally.
      setState(() => _isPlaying = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(guide.errorMessage ??
                AppLocalizations.of(context)!.historyAudioGenerationFailed),
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
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
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

    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Full image background
          if (File(live.imagePath).existsSync())
            BackgroundPhoto(file: File(live.imagePath)),

          // Gradient overlay — T96: the previous 2-stop version barely
          // darkened the very top of the screen, leaving the top bar icons
          // (esp. the red delete icon) hard to read over a bright photo
          // (sky, light walls). A 3-stop vignette protects both the top bar
          // and the bottom text without hiding the middle of the photo.
          // T94: much lighter in photo mode, matching player_screen.dart's
          // own photo-mode gradient, since there's no text left to protect.
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: _photoMode
                    ? [
                        Colors.black.withValues(alpha: 0.35),
                        Colors.transparent,
                        Colors.transparent,
                        Colors.black.withValues(alpha: 0.35),
                      ]
                    : [
                        Colors.black.withValues(alpha: 0.45),
                        Colors.black.withValues(alpha: 0.15),
                        Colors.black.withValues(alpha: 0.95),
                      ],
                stops: _photoMode
                    ? const [0.0, 0.15, 0.85, 1.0]
                    : const [0.0, 0.3, 1.0],
              ),
            ),
          ),

          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top bar — each icon gets its own scrim (T96) so it stays
                // legible regardless of gradient tuning or photo content.
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Row(
                    children: [
                      _ScrimIconButton(
                        icon: Icons.arrow_back,
                        color: Colors.white,
                        onPressed: () => Navigator.pop(context),
                      ),
                      const Spacer(),
                      _ScrimIconButton(
                        icon: live.isFavorite ? Icons.star : Icons.star_border,
                        color: live.isFavorite ? Colors.amberAccent : Colors.white70,
                        tooltip: live.isFavorite
                            ? l10n.historyRemoveFromFavorites
                            : l10n.historyAddToFavorites,
                        onPressed: () =>
                            context.read<HistoryService>().toggleFavorite(live.id!),
                      ),
                      const SizedBox(width: 4),
                      _ScrimIconButton(
                        icon: Icons.playlist_add,
                        color: Colors.white70,
                        tooltip: l10n.historyAddToCollection,
                        onPressed: () => _openCollectionsSheet(context, live),
                      ),
                      const SizedBox(width: 4),
                      _ScrimIconButton(
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
                      _ScrimIconButton(
                        icon: Icons.info_outline,
                        color: Colors.white70,
                        onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) =>
                                    AboutAnalysisScreen(entry: widget.entry))),
                      ),
                      const SizedBox(width: 4),
                      _ScrimIconButton(
                        icon: Icons.delete_outline,
                        color: Colors.redAccent,
                        onPressed: () => _deleteEntry(context),
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
                        Text(
                          dateStr,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: Colors.white54,
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
                                  color: Colors.white54, size: 14),
                              const SizedBox(width: 4),
                              Text(
                                live.locationName!,
                                style: const TextStyle(color: Colors.white54),
                              ),
                            ],
                          ),
                        ],

                        const SizedBox(height: 16),

                        // Action buttons
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            // Save to gallery
                            InkWell(
                              onTap: () async {
                                try {
                                  await Gal.putImage(live.imagePath);
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                            l10n.historyPhotoSavedToGallery),
                                        duration: const Duration(seconds: 2),
                                      ),
                                    );
                                  }
                                } catch (_) {}
                              },
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                    vertical: 4, horizontal: 8),
                                child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.save_alt,
                                          size: 14, color: Colors.white54),
                                      const SizedBox(width: 4),
                                      Text(l10n.historySave,
                                          style: const TextStyle(
                                              color: Colors.white54,
                                              fontSize: 12)),
                                    ]),
                              ),
                            ),
                            // Copy button
                            InkWell(
                              onTap: () {
                                Clipboard.setData(
                                    ClipboardData(text: live.script));
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(l10n.historyTextCopied),
                                    duration: const Duration(seconds: 2),
                                  ),
                                );
                              },
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                    vertical: 4, horizontal: 8),
                                child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.copy,
                                          size: 14, color: Colors.white54),
                                      const SizedBox(width: 4),
                                      Text(l10n.historyCopy,
                                          style: const TextStyle(
                                              color: Colors.white54,
                                              fontSize: 12)),
                                    ]),
                              ),
                            ),
                            // Report content (T91)
                            ReportContentButton(
                              title: live.title,
                              script: live.script,
                              aiModel: live.aiModel,
                              date: live.analyzedAt ?? live.createdAt,
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),

                        // Script
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.4),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                                color: Colors.white.withValues(alpha: 0.1)),
                          ),
                          child: Text(
                            live.script,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: Colors.white.withValues(alpha: 0.85),
                              height: 1.6,
                            ),
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
                            minimumSize: const Size(double.infinity, 40),
                          ),
                          onPressed: _isUpgrading
                              ? null
                              : () async {
                                  final history = context.read<HistoryService>();
                                  setState(() => _isUpgrading = true);
                                  try {
                                    final tts = guide.geminiTtsService!;
                                    tts.onComplete =
                                        () => setState(() => _isPlaying = false);
                                    // Generate audio first, then play
                                    await tts.speak(live.script);
                                    // Save upgraded audio
                                    final lastPath = tts.lastWavPath;
                                    AppLogger.tts(
                                        'upgrade lastAudioPath: $lastPath, entry.id: ${live.id}');
                                    if (lastPath != null && live.id != null) {
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
                                          formatVoiceUpgradeErrorMessage(error);
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                          content: Text(message),
                                          duration: const Duration(seconds: 4),
                                          backgroundColor: Colors.orange.shade800,
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
                      return Row(
                        children: [
                          // Skip only when the current playback is
                          // seekable — see _canSkip.
                          if (showSkip) ...[
                            IconButton(
                              icon: const Icon(Icons.replay_10),
                              iconSize: 32,
                              tooltip: l10n.historySkipBack10,
                              onPressed: () => _skip(-10000),
                            ),
                            const SizedBox(width: 4),
                          ],
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: _toggleAudio,
                              icon: Icon(_isPlaying
                                  ? Icons.stop
                                  : ((live.hasAudio || live.hasLowQualityTts)
                                      ? Icons.play_arrow
                                      : Icons.auto_awesome)),
                              label: Text(_isPlaying
                                  ? l10n.historyStop
                                  : ((live.hasAudio || live.hasLowQualityTts)
                                      ? l10n.historyListen
                                      : l10n.historyGenerateAudio)),
                              style: FilledButton.styleFrom(
                                minimumSize: const Size(0, 52),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14)),
                              ),
                            ),
                          ),
                          if (showSkip) ...[
                            const SizedBox(width: 4),
                            IconButton(
                              icon: const Icon(Icons.forward_10),
                              iconSize: 32,
                              tooltip: l10n.historySkipForward10,
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
    );
  }
}

/// A top-bar icon button with its own subtle circular scrim (T96) — keeps
/// it legible over any photo content, independent of the screen's own
/// background gradient.
class _ScrimIconButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String? tooltip;
  final VoidCallback onPressed;

  const _ScrimIconButton({
    required this.icon,
    required this.color,
    required this.onPressed,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.black.withValues(alpha: 0.35),
      ),
      child: IconButton(
        icon: Icon(icon, color: color),
        tooltip: tooltip,
        onPressed: onPressed,
      ),
    );
  }
}
