import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../l10n/app_localizations.dart';
import '../screens/history_screen.dart';
import '../services/audio_guide_service.dart';
import '../services/history_service.dart';
import '../services/network_status.dart';
import '../services/settings_service.dart';
import '../utils/analysis_runner.dart';

/// #556/#551: what the home screen offers once there is a history, in
/// place of the « point your phone » hint — the photos set aside waiting
/// for an analysis (all analyzed in one tap, suggested more strongly on
/// Wi-Fi), and the last guide to listen to again.
class HomeSuggestions extends StatefulWidget {
  const HomeSuggestions({super.key, this.unmetered});

  /// Wi-Fi check; injectable for tests.
  final Future<bool?> Function()? unmetered;

  @override
  State<HomeSuggestions> createState() => _HomeSuggestionsState();
}

class _HomeSuggestionsState extends State<HomeSuggestions> {
  bool? _onWifi;
  ({int done, int total})? _batch;

  @override
  void initState() {
    super.initState();
    (widget.unmetered ?? NetworkStatus.isUnmetered)().then((v) {
      if (mounted) setState(() => _onWifi = v);
    });
  }

  Future<void> _analyzeAll(List<HistoryEntry> captured) async {
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _batch = (done: 0, total: captured.length));
    final ok = await analyzeCapturedEntries(
      guide: context.read<AudioGuideService>(),
      history: context.read<HistoryService>(),
      settings: context.read<SettingsService>(),
      entries: captured,
      onProgress: (done, total) {
        if (mounted) setState(() => _batch = (done: done, total: total));
      },
    );
    if (!mounted) return;
    final skipped = captured.length - (_batch?.total ?? captured.length);
    setState(() => _batch = null);
    messenger.showSnackBar(SnackBar(
      content: Text([
        l10n.homeBatchDone(ok),
        if (skipped > 0) l10n.homeBatchSkipped(skipped),
      ].join(' ')),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final history = context.watch<HistoryService>();
    final busy = context.select<AudioGuideService, bool>((g) => g.isBusy);
    final captured = [for (final e in history.entries) if (e.isCaptured) e];
    HistoryEntry? last;
    for (final e in history.entries) {
      if (e.status == AnalysisStatus.complete && e.script.trim().isNotEmpty) {
        last = e;
        break; // entries are newest first
      }
    }
    final batch = _batch;

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (captured.isNotEmpty)
          Card(
            child: ListTile(
              leading: Icon(_onWifi == true ? Icons.wifi : Icons.photo_library_outlined),
              title: Text(l10n.homePendingCount(captured.length)),
              subtitle: Text(batch != null
                  ? l10n.homeBatchProgress(batch.done + 1 > batch.total ? batch.total : batch.done + 1,
                      batch.total)
                  : _onWifi == true
                      ? l10n.homePendingOnWifi
                      : l10n.homePendingHint),
              trailing: batch != null
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : TextButton(
                      onPressed: busy ? null : () => _analyzeAll(captured),
                      child: Text(l10n.homeAnalyzeAll),
                    ),
            ),
          ),
        if (last != null) ...[
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              leading: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: 48,
                  height: 48,
                  child: RotatedBox(
                    quarterTurns: last.rotationQuarters,
                    child: Image.file(File(last.imagePath),
                        fit: BoxFit.cover,
                        cacheWidth: 144,
                        errorBuilder: (_, __, ___) => const ColoredBox(color: Colors.black26)),
                  ),
                ),
              ),
              title: Text(l10n.homeListenAgain, style: theme.textTheme.labelMedium),
              subtitle: Text(last.title, maxLines: 2, overflow: TextOverflow.ellipsis),
              trailing: const Icon(Icons.play_circle_outline),
              onTap: busy
                  ? null
                  : () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => HistoryDetailScreen(entry: last!, autoPlay: true)),
                      ),
            ),
          ),
        ],
      ],
    );
  }
}
