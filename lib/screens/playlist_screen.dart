import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../l10n/app_localizations.dart';
import '../services/history_service.dart';
import '../utils/app_logger.dart';

/// #550: plays the saved audio of several entries one after the other — a
/// collection, a finished visit — with the current photo and title, and
/// previous / pause / next controls. Entries without saved audio are left
/// out (the caller says how many).
class PlaylistScreen extends StatefulWidget {
  const PlaylistScreen({super.key, required this.title, required this.entries, this.player});

  final String title;

  /// Entries to play, in order; all must have saved audio.
  final List<HistoryEntry> entries;

  /// Native player; injectable for tests.
  final PlaylistPlayer? player;

  @override
  State<PlaylistScreen> createState() => _PlaylistScreenState();
}

/// The few native audio calls the playlist needs.
class PlaylistPlayer {
  const PlaylistPlayer();
  static const _channel = MethodChannel('audio_guide/audio_player');

  /// Completes when the file has played to the end, or was stopped.
  Future<void> play(String path) => _channel.invokeMethod('playWav', {'path': path});
  Future<void> pause() => _channel.invokeMethod('pause');
  Future<void> resume() => _channel.invokeMethod('play');
  Future<void> stop() => _channel.invokeMethod('stop');
}

class _PlaylistScreenState extends State<PlaylistScreen> {
  late final PlaylistPlayer _player = widget.player ?? const PlaylistPlayer();
  int _index = 0;
  bool _paused = false;
  bool _finished = false;

  /// Bumped on every jump, so a playback that ends after the user moved
  /// on doesn't advance the list a second time.
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    AppLogger.nav('PlaylistScreen opened (${widget.entries.length} entries)');
    WidgetsBinding.instance.addPostFrameCallback((_) => _playAt(0));
  }

  @override
  void dispose() {
    _generation++;
    _player.stop().catchError((_) {});
    AppLogger.nav('PlaylistScreen closed');
    super.dispose();
  }

  Future<void> _playAt(int index) async {
    if (index < 0 || index >= widget.entries.length) return;
    final generation = ++_generation;
    setState(() {
      _index = index;
      _paused = false;
      _finished = false;
    });
    try {
      await _player.stop();
      await _player.play(widget.entries[index].audioPath!);
    } catch (e) {
      AppLogger.error('Playlist: playback failed');
    }
    if (!mounted || generation != _generation) return;
    if (index + 1 < widget.entries.length) {
      _playAt(index + 1);
    } else {
      setState(() => _finished = true);
    }
  }

  Future<void> _togglePause() async {
    if (_finished) {
      _playAt(0);
      return;
    }
    if (_paused) {
      await _player.resume();
    } else {
      await _player.pause();
    }
    if (mounted) setState(() => _paused = !_paused);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final entry = widget.entries[_index];
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: Column(
        children: [
          SizedBox(
            height: MediaQuery.sizeOf(context).height * 0.3,
            width: double.infinity,
            child: RotatedBox(
              quarterTurns: entry.rotationQuarters,
              child: Image.file(
                File(entry.imagePath),
                fit: BoxFit.cover,
                width: double.infinity,
                errorBuilder: (_, __, ___) => const ColoredBox(color: Colors.black26),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.playlistPosition(_index + 1, widget.entries.length),
                    style: theme.textTheme.labelMedium),
                const SizedBox(height: 4),
                Text(entry.title,
                    style: theme.textTheme.titleMedium, maxLines: 2, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                iconSize: 36,
                tooltip: l10n.playlistPrevious,
                icon: const Icon(Icons.skip_previous),
                onPressed: _index > 0 ? () => _playAt(_index - 1) : null,
              ),
              const SizedBox(width: 12),
              IconButton.filled(
                iconSize: 40,
                tooltip: _finished
                    ? l10n.playlistRestart
                    : _paused
                        ? l10n.playlistResume
                        : l10n.playlistPause,
                icon: Icon(_finished
                    ? Icons.replay
                    : _paused
                        ? Icons.play_arrow
                        : Icons.pause),
                onPressed: _togglePause,
              ),
              const SizedBox(width: 12),
              IconButton(
                iconSize: 36,
                tooltip: l10n.playlistNext,
                icon: const Icon(Icons.skip_next),
                onPressed:
                    _index + 1 < widget.entries.length ? () => _playAt(_index + 1) : null,
              ),
            ],
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView.builder(
              itemCount: widget.entries.length,
              itemBuilder: (context, i) {
                final e = widget.entries[i];
                return ListTile(
                  selected: i == _index,
                  leading: Text('${i + 1}', style: theme.textTheme.labelLarge),
                  title: Text(e.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                  trailing: i == _index && !_finished
                      ? Icon(_paused ? Icons.pause : Icons.graphic_eq, size: 18)
                      : null,
                  onTap: () => _playAt(i),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
