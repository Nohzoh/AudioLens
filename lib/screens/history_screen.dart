import 'dart:async';
import 'dart:io';
import '../utils/app_logger.dart';
import '../utils/error_sanitizer.dart';
import '../utils/analysis_runner.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../constants/output_languages.dart';
import '../l10n/app_localizations.dart';
import '../services/audio_guide_service.dart';
import '../services/history_service.dart';
import '../services/settings_service.dart';
import '../widgets/seekable_script.dart';
import '../widgets/guide_action_row.dart';
import '../widgets/script_rating_bar.dart';
import '../widgets/kofi_button.dart';
import '../widgets/mini_map.dart';
import '../widgets/photo_gradient_background.dart';
import '../widgets/scrim_icon_button.dart';
import '../widgets/skip_icon_button.dart';
import '../utils/guide_error_localizer.dart';
import '../utils/user_message_utils.dart';
import '../utils/script_style_label.dart';
import 'about_analysis_screen.dart';
import 'analyses_map_screen.dart';

// #553: the detail screen lives in its own file; as a part it shares this
// file's private helpers (relaunch, regenerate and collections sheets).
part 'history_detail_screen.dart';

/// Launches the analysis for a captured entry (T78), using the raw GPS
/// saved at capture time rather than the device's current location.
Future<void> _launchAnalysis(BuildContext context, HistoryEntry entry,
    {String? userHint}) async {
  final imageFile = File(entry.imagePath);
  if (!imageFile.existsSync()) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text(AppLocalizations.of(context)!.historyImageNotFound)),
    );
    return;
  }
  final knownCoordinates =
      await resolveKnownCoordinatesForRelaunch(context, entry);
  if (!context.mounted) return;
  await runAnalysisAndNavigate(
    context: context,
    imageFile: imageFile,
    entryId: entry.id!,
    source: 'captured',
    knownCoordinates: knownCoordinates,
    userHint: userHint,
  );
}

/// #508: whether a history entry still has to be analyzed before it has
/// anything to play — the same states the list sends to (re)analysis on
/// tap instead of opening the detail screen.
@visibleForTesting
bool historyDetailNeedsAnalysis(HistoryEntry entry) =>
    entry.isCaptured || entry.isPending || entry.status == AnalysisStatus.failed;

/// Retries a failed analysis, reusing whatever location was resolved for
/// the original attempt (live GPS, EXIF, or a manually picked map point)
/// instead of re-resolving the device's current position from scratch —
/// see HistoryService.failEntry's doc.
Future<void> _retryAnalysis(BuildContext context, HistoryEntry entry,
    {String? userHint}) async {
  final imageFile = File(entry.imagePath);
  if (!imageFile.existsSync()) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text(AppLocalizations.of(context)!.historyImageNotFound)),
    );
    return;
  }
  final knownCoordinates =
      await resolveKnownCoordinatesForRelaunch(context, entry);
  if (!context.mounted) return;
  await runAnalysisAndNavigate(
    context: context,
    imageFile: imageFile,
    entryId: entry.id!,
    source: 'retry',
    knownCoordinates: knownCoordinates,
    userHint: userHint,
  );
}

/// #131: what the user picked in [_RegenerateSheet].
class _RegenerateChoice {
  final String style;
  final String language;
  final AIProvider provider;

  /// #467: what the user says the photo shows, or null.
  final String? hint;
  const _RegenerateChoice({
    required this.style,
    required this.language,
    required this.provider,
    this.hint,
  });
}

/// #131: lets the user regenerate [entry]'s script with a different style/
/// language/model instead of only being able to retry with the same
/// settings. Per explicit product decision, picking new values here also
/// becomes the new default going forward (same as changing them from
/// Settings) — simplest mental model, and reuses the exact same
/// SettingsService/AudioGuideService plumbing every other analysis already
/// goes through, rather than inventing a separate "one-off override"
/// mechanism. The snackbar below is the one concession to that: it makes
/// the side effect visible instead of silently changing a global default.
Future<void> _openRegenerateSheet(
    BuildContext context, HistoryEntry entry) async {
  final settings = context.read<SettingsService>();
  final guide = context.read<AudioGuideService>();
  final choice = await showModalBottomSheet<_RegenerateChoice>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _RegenerateSheet(
      initialStyle: entry.scriptStyle ?? settings.scriptStyle,
      initialLanguage: entry.outputLanguage ?? settings.outputLanguage,
      initialProvider: guide.activeProvider,
      nanoAvailable: guide.nanoAvailable,
      geminiApiAvailable: guide.geminiApiKey?.isNotEmpty == true,
    ),
  );
  if (choice == null || !context.mounted) return;

  var settingsChanged = false;
  if (choice.style != settings.scriptStyle) {
    await settings.setScriptStyle(choice.style);
    settingsChanged = true;
  }
  if (choice.language != settings.outputLanguage) {
    await settings.setOutputLanguage(choice.language);
    settingsChanged = true;
  }
  if (choice.provider != guide.activeProvider) {
    await guide.setActiveProvider(choice.provider);
    settingsChanged = true;
  }
  if (settingsChanged && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
            AppLocalizations.of(context)!.historyRegenerateSettingsUpdated),
      ),
    );
  }
  if (!context.mounted) return;
  // #467: a captured entry is launched as such (same location handling
  // as a tap on its card); anything else is re-analyzed.
  if (entry.isCaptured) {
    await _launchAnalysis(context, entry, userHint: choice.hint);
  } else {
    await _retryAnalysis(context, entry, userHint: choice.hint);
  }
}

class _RegenerateSheet extends StatefulWidget {
  final String initialStyle;
  final String initialLanguage;
  final AIProvider initialProvider;
  final bool nanoAvailable;
  final bool geminiApiAvailable;

  const _RegenerateSheet({
    required this.initialStyle,
    required this.initialLanguage,
    required this.initialProvider,
    required this.nanoAvailable,
    required this.geminiApiAvailable,
  });

  @override
  State<_RegenerateSheet> createState() => _RegenerateSheetState();
}

class _RegenerateSheetState extends State<_RegenerateSheet> {
  late String _style = widget.initialStyle;
  late String _language = widget.initialLanguage;
  late AIProvider _provider = widget.initialProvider;
  final _hintController = TextEditingController();

  @override
  void dispose() {
    _hintController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 20,
          bottom: 20 + MediaQuery.of(context).viewInsets.bottom,
        ),
        // #467: the hint field made the sheet taller than small screens
        // (and the keyboard) leave room for.
        child: SingleChildScrollView(
          child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.historyRegenerateTitle,
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 16),
            // #467: optional — empty, the analysis runs as before.
            TextField(
              key: const ValueKey('regenerate-hint'),
              controller: _hintController,
              maxLength: maxUserHintChars,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: l10n.historyHintLabel,
                helperText: l10n.historyHintHelper,
                helperMaxLines: 2,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Text(l10n.settingsScriptStyleSection,
                style: Theme.of(context).textTheme.labelSmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final (value, label) in scriptStyleOptions(l10n))
                  ChoiceChip(
                    label: Text(label),
                    selected: _style == value,
                    onSelected: (_) => setState(() => _style = value),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Text(l10n.settingsOutputLanguageSection,
                style: Theme.of(context).textTheme.labelSmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final language in outputLanguageLocales.keys)
                  ChoiceChip(
                    label: Text(language),
                    selected: _language == language,
                    onSelected: (_) => setState(() => _language = language),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Text(l10n.historyRegenerateModelLabel,
                style: Theme.of(context).textTheme.labelSmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ChoiceChip(
                  // #253: matches the Settings screen's provider card —
                  // "IA locale", not the brand name.
                  label: Text(l10n.settingsLocalAiName),
                  selected: _provider == AIProvider.geminiNano,
                  onSelected: widget.nanoAvailable
                      ? (_) => setState(() => _provider = AIProvider.geminiNano)
                      : null,
                ),
                ChoiceChip(
                  label: const Text('Gemini API'),
                  selected: _provider == AIProvider.geminiApi,
                  onSelected: widget.geminiApiAvailable
                      ? (_) => setState(() => _provider = AIProvider.geminiApi)
                      : null,
                ),
              ],
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(l10n.historyCancel),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: () => Navigator.pop(
                    context,
                    _RegenerateChoice(
                        style: _style,
                        language: _language,
                        provider: _provider,
                        hint: normalizeUserHint(_hintController.text)),
                  ),
                  child: Text(l10n.historyRegenerateConfirm),
                ),
              ],
            ),
          ],
        ),
        ),
      ),
    );
  }
}

/// T51/#423: the entries matching the history's favorites/collection
/// filter (both off = every entry). Shared by the list and the map, so
/// the two always show the same set.
List<HistoryEntry> filterHistoryEntries(
  HistoryService history, {
  bool favoritesOnly = false,
  int? collectionId,
}) {
  if (favoritesOnly) {
    return history.entries.where((e) => e.isFavorite).toList();
  }
  if (collectionId != null) {
    return history.entries
        .where((e) =>
            e.id != null &&
            history.collectionIdsForEntry(e.id!).contains(collectionId))
        .toList();
  }
  return history.entries;
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

  /// #428: ids of the cards picked in selection mode. Selection mode is
  /// simply "this is non-empty": long-press starts it, deselecting the
  /// last card (or ✕ / back) ends it. Changing the filter clears it, so
  /// nothing stays selected out of sight.
  final Set<int> _selectedIds = {};
  bool get _selecting => _selectedIds.isNotEmpty;

  void _selectAll() => setState(() {
        _favoritesOnly = false;
        _selectedCollectionId = null;
        _selectedIds.clear();
      });
  void _selectFavorites() => setState(() {
        _favoritesOnly = true;
        _selectedCollectionId = null;
        _selectedIds.clear();
      });
  void _selectCollection(int id) => setState(() {
        _favoritesOnly = false;
        _selectedCollectionId = id;
        _selectedIds.clear();
      });

  void _toggleSelected(int id) => setState(() {
        if (!_selectedIds.remove(id)) _selectedIds.add(id);
      });
  void _clearSelection() => setState(_selectedIds.clear);

  void _selectAllVisible(HistoryService history) => setState(() {
        _selectedIds.addAll(_filteredEntries(history)
            .where((e) => e.id != null)
            .map((e) => e.id!));
      });

  /// Leaves selection mode once the sheet applied a change (the job is
  /// done); a sheet dismissed untouched keeps the selection, so a large
  /// one isn't lost to a stray swipe.
  Future<void> _addSelectionToCollection(BuildContext context) async {
    final changed = await _openCollectionsSheet(context, {..._selectedIds});
    if (changed && mounted) _clearSelection();
  }

  PreferredSizeWidget _buildSelectionAppBar(
      BuildContext context, AppLocalizations l10n) {
    return AppBar(
      leading: IconButton(
        icon: const Icon(Icons.close),
        tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
        onPressed: _clearSelection,
      ),
      title: Text(l10n.historySelectedCount(_selectedIds.length)),
      actions: [
        IconButton(
          icon: const Icon(Icons.select_all),
          tooltip: l10n.historySelectAll,
          onPressed: () => _selectAllVisible(context.read<HistoryService>()),
        ),
        IconButton(
          icon: const Icon(Icons.playlist_add),
          tooltip: l10n.historyAddToCollection,
          onPressed: () => _addSelectionToCollection(context),
        ),
      ],
    );
  }

  List<HistoryEntry> _filteredEntries(HistoryService history) =>
      filterHistoryEntries(history,
          favoritesOnly: _favoritesOnly, collectionId: _selectedCollectionId);

  /// #423: opens the map with the same filter as the list, so a
  /// collection's map ("Rome trip") is one tap away.
  void _openMap(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AnalysesMapScreen(
          favoritesOnly: _favoritesOnly,
          collectionId: _selectedCollectionId,
        ),
      ),
    );
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
    return PopScope(
      // #428: back leaves selection mode before it leaves the screen.
      canPop: !_selecting,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _clearSelection();
      },
      child: Scaffold(
        appBar: _selecting
            ? _buildSelectionAppBar(context, l10n)
            : AppBar(
                title: Text(l10n.historyTitle),
                backgroundColor: Colors.transparent,
                elevation: 0,
                actions: [
                  IconButton(
                    icon: const Icon(Icons.map_outlined),
                    tooltip: l10n.historyMapTooltip,
                    onPressed: () => _openMap(context),
                  ),
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
                    Icon(Icons.history,
                        size: 64,
                        color:
                            theme.colorScheme.onSurface.withValues(alpha: 0.12)),
                    const SizedBox(height: 16),
                    Text(
                      l10n.historyEmptyTitle,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color:
                            theme.colorScheme.onSurface.withValues(alpha: 0.38),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      l10n.historyEmptySubtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color:
                            theme.colorScheme.onSurface.withValues(alpha: 0.24),
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
                              color: theme.colorScheme.onSurface
                                  .withValues(alpha: 0.38),
                            ),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                          itemCount: filtered.length,
                          itemBuilder: (context, index) {
                            final entry = filtered[index];
                            return _HistoryCard(
                              key: ValueKey(entry.id),
                              entry: entry,
                              selectionMode: _selecting,
                              selected: _selectedIds.contains(entry.id),
                              onToggleSelected: entry.id == null
                                  ? null
                                  : () => _toggleSelected(entry.id!),
                            )
                                // #489: stagger only the first
                                // screenful. The builder is lazy, so a
                                // delay growing with the index made a
                                // card far down the list wait seconds
                                // before appearing while scrolling.
                                .animate(delay: historyCardEntranceDelay(index))
                                .fadeIn()
                                .slideY(begin: 0.1);
                          },
                        ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// #489: entrance delay of the history card at [index] — a short
/// stagger for the cards visible when the list opens, none afterwards.
@visibleForTesting
Duration historyCardEntranceDelay(int index) =>
    Duration(milliseconds: index < 8 ? index * 50 : 0);

/// T51/#428: bottom sheet to add/remove [entryIds] from any number of
/// collections, with inline creation of a new one. Shared by the history
/// list's selection mode and the detail screen's menu (a single id).
/// Returns whether any membership changed.
Future<bool> _openCollectionsSheet(
    BuildContext context, Set<int> entryIds) async {
  if (entryIds.isEmpty) return false;
  var changed = false;
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (_) =>
        _CollectionsSheet(entryIds: entryIds, onChanged: () => changed = true),
  );
  return changed;
}

class _CollectionsSheet extends StatefulWidget {
  final Set<int> entryIds;
  final VoidCallback onChanged;
  const _CollectionsSheet({required this.entryIds, required this.onChanged});

  @override
  State<_CollectionsSheet> createState() => _CollectionsSheetState();
}

class _CollectionsSheetState extends State<_CollectionsSheet> {
  final _controller = TextEditingController();

  /// Shown inline rather than as a SnackBar: this sheet's modal route
  /// sits above the Scaffold a SnackBar would appear in.
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _apply(
      HistoryService history, int collectionId, bool inCollection) async {
    try {
      await history.setEntriesInCollection(
          widget.entryIds, collectionId, inCollection);
      widget.onChanged();
      if (mounted && _error != null) setState(() => _error = null);
    } on HistoryStorageException catch (e) {
      if (!mounted) return;
      setState(() => _error =
          localizeHistoryStorageException(AppLocalizations.of(context)!, e));
    }
  }

  Future<void> _create(HistoryService history) async {
    final name = _controller.text.trim();
    if (name.isEmpty) return;
    final Collection collection;
    try {
      collection = await history.createCollection(name);
    } catch (e) {
      AppLogger.db(
          'Collection creation failed: ${sanitizeError(e.toString())}');
      if (!mounted) return;
      setState(() => _error = AppLocalizations.of(context)!
          .guideErrorStorageCollectionFailed);
      return;
    }
    _controller.clear();
    await _apply(history, collection.id!, true);
  }

  /// true = every selected entry is in [collectionId], false = none,
  /// null = only some (the checkbox's mixed state).
  bool? _membership(HistoryService history, int collectionId) {
    final inIt = widget.entryIds
        .where((id) => history.collectionIdsForEntry(id).contains(collectionId))
        .length;
    if (inIt == 0) return false;
    if (inIt == widget.entryIds.length) return true;
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return SafeArea(
      child: Consumer<HistoryService>(
        builder: (context, history, _) {
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
                        style: TextStyle(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurface
                                .withValues(alpha: 0.38))),
                  )
                else
                  Flexible(
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        for (final c in history.collections)
                          Builder(builder: (context) {
                            final membership = _membership(history, c.id!);
                            return CheckboxListTile(
                              value: membership,
                              tristate: true,
                              title: Text(c.name),
                              contentPadding: EdgeInsets.zero,
                              // Mixed or unticked -> add everyone; ticked ->
                              // remove everyone (not the checkbox's own
                              // false/true/null cycle).
                              onChanged: (_) =>
                                  _apply(history, c.id!, membership != true),
                            );
                          }),
                      ],
                    ),
                  ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(_error!,
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.error)),
                  ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        decoration: InputDecoration(
                            hintText: l10n.historyNewCollectionHint),
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

  /// #428: in selection mode a tap toggles [selected] instead of opening
  /// the entry; outside it, a long-press starts it with this card.
  final bool selectionMode;
  final bool selected;
  final VoidCallback? onToggleSelected;

  const _HistoryCard({
    super.key,
    required this.entry,
    this.selectionMode = false,
    this.selected = false,
    this.onToggleSelected,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final dateStr = DateFormat(
            'd MMM yyyy · HH:mm', Localizations.localeOf(context).toString())
        .format(entry.createdAt);
    final isFailed = entry.status == AnalysisStatus.failed;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: selected
            ? theme.colorScheme.primaryContainer
            : theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () {
            if (selectionMode) {
              onToggleSelected?.call();
            } else if (entry.isPending || isFailed) {
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
          // #428: long-press enters selection mode with this card (it
          // used to open the collections sheet directly, T51 — that is
          // now long-press -> "Add to collection" in the contextual bar).
          onLongPress: onToggleSelected,
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
                            ? RotatedBox(
                                // #152/#183: this thumbnail is a fixed
                                // 72x72 square, so the width/height swap
                                // RotatedBox does for an odd quarter turn
                                // is a no-op here — unlike the full-bleed
                                // BackgroundPhoto, which accounts for it
                                // explicitly.
                                quarterTurns: entry.rotationQuarters,
                                child: Image.file(
                                  File(entry.imagePath),
                                  fit: BoxFit.cover,
                                  // #489: decode at thumbnail size, not
                                  // the full 1280 px photo. x2 leaves
                                  // room for BoxFit.cover on a 4:3
                                  // image, whichever way it is turned.
                                  cacheWidth: (72 *
                                          2 *
                                          MediaQuery.devicePixelRatioOf(context))
                                      .round(),
                                ),
                              )
                            : Container(
                                color:
                                    theme.colorScheme.surfaceContainerHighest,
                                child: Icon(Icons.image_not_supported,
                                    color: theme.colorScheme.onSurface
                                        .withValues(alpha: 0.24)),
                              ),
                      ),
                    ),
                    if (selected)
                      Positioned.fill(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          // #145-style fixed scrim over the photo.
                          child: Container(
                            color: Colors.black45,
                            child: const Icon(Icons.check_circle,
                                color: Colors.white, size: 32),
                          ),
                        ),
                      ),
                    if (entry.id != null && !selectionMode)
                      Positioned(
                        top: 2,
                        left: 2,
                        child: Semantics(
                          // #232
                          button: true,
                          toggled: entry.isFavorite,
                          label: entry.isFavorite
                              ? AppLocalizations.of(context)!.historyRemoveFromFavorites
                              : AppLocalizations.of(context)!.historyAddToFavorites,
                          child: GestureDetector(
                          onTap: () => context
                              .read<HistoryService>()
                              .toggleFavorite(entry.id!),
                          // #145: fixed black/white — this badge sits on
                          // the thumbnail photo, not themed chrome.
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
                        )),
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
                            Icon(Icons.location_on,
                                size: 12,
                                color: theme.colorScheme.onSurface
                                    .withValues(alpha: 0.38)),
                            const SizedBox(width: 2),
                            Text(
                              entry.locationName!,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurface
                                    .withValues(alpha: 0.38),
                              ),
                            ),
                          ],
                        ),
                      ],
                      if (entry.status == AnalysisStatus.complete &&
                          !entry.hasAudio) ...[
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Icon(Icons.text_snippet_outlined,
                                size: 12,
                                color: theme.colorScheme.onSurface
                                    .withValues(alpha: 0.38)),
                            const SizedBox(width: 2),
                            Text(
                              l10n.historyScriptOnly,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurface
                                    .withValues(alpha: 0.38),
                              ),
                            ),
                          ],
                        ),
                      ],
                      if (entry.isCaptured) ...[
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Icon(Icons.cloud_off_outlined,
                                size: 12,
                                color: theme.colorScheme.onSurface
                                    .withValues(alpha: 0.38)),
                            const SizedBox(width: 2),
                            Text(
                              l10n.historyCapturedTapToAnalyze,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurface
                                    .withValues(alpha: 0.38),
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
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: 0.24),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),

                Icon(
                    selectionMode
                        ? (selected
                            ? Icons.check_box
                            : Icons.check_box_outline_blank)
                        : Icons.chevron_right,
                    color: selectionMode && selected
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurface.withValues(alpha: 0.24)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
