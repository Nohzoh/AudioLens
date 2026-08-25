import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../l10n/app_localizations.dart';
import '../utils/app_logger.dart';
import '../services/settings_service.dart';
import '../widgets/kofi_button.dart';

class LogsScreen extends StatefulWidget {
  const LogsScreen({super.key});

  @override
  State<LogsScreen> createState() => _LogsScreenState();
}

class _LogsScreenState extends State<LogsScreen> {
  final ScrollController _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    AppLogger.addListener(_onNewLog);
  }

  @override
  void dispose() {
    AppLogger.removeListener(_onNewLog);
    _scroll.dispose();
    super.dispose();
  }

  void _onNewLog() {
    if (mounted) {
      setState(() {});
      // Auto-scroll to bottom
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) {
          _scroll.animateTo(
            _scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 100),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  Color _lineColor(BuildContext context, String line) {
    if (line.contains('[ERROR]')) return Colors.redAccent;
    if (line.contains('[TTS]')) return Colors.purpleAccent;
    if (line.contains('[AI]')) return Colors.blueAccent;
    if (line.contains('[GPS]')) return Colors.greenAccent;
    if (line.contains('[DB]')) return Colors.orangeAccent;
    return Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.70);
  }

  @override
  Widget build(BuildContext context) {
    final lines = AppLogger.lines;
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.logsTitle(lines.length)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          Consumer<SettingsService>(
            builder: (context, settings, _) => KofiButton(
              show: settings.showKofiButton,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.copy),
            tooltip: l10n.logsCopyAll,
            onPressed: () {
              Clipboard.setData(ClipboardData(text: AppLogger.allLogs));
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(l10n.logsCopiedAll),
                  duration: const Duration(seconds: 2),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: l10n.logsClear,
            onPressed: () {
              AppLogger.clear();
              setState(() {});
            },
          ),
        ],
      ),
      body: lines.isEmpty
          ? Center(
              child: Text(l10n.logsEmpty,
                  style: TextStyle(
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withValues(alpha: 0.38))),
            )
          : ListView.builder(
              controller: _scroll,
              padding: const EdgeInsets.all(8),
              itemCount: lines.length,
              itemBuilder: (context, i) {
                final line = lines[i];
                return GestureDetector(
                  onLongPress: () {
                    Clipboard.setData(ClipboardData(text: line));
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(l10n.logsLineCopied),
                        duration: const Duration(seconds: 1),
                      ),
                    );
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 1),
                    child: Text(
                      line,
                      style: TextStyle(
                        color: _lineColor(context, line),
                        fontSize: 10,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }
}
