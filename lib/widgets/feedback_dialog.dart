import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../l10n/app_localizations.dart';
import '../services/feedback_service.dart';
import '../services/history_service.dart';
import '../utils/date_format_utils.dart';
import '../utils/exif_strip.dart';

/// #426: opens [FeedbackDialog] from an analysis screen with [entry]
/// attached. Reads the app version itself, since those screens don't
/// already have it the way Settings does.
Future<void> showFeedbackDialogForEntry(
  BuildContext context, {
  required FeedbackService feedback,
  required HistoryService history,
  required HistoryEntry entry,
}) async {
  String? version;
  try {
    final info = await PackageInfo.fromPlatform();
    version = '${info.version} (${info.buildNumber})';
  } catch (_) {
    // Unknown version is fine: FeedbackService falls back to 'unknown'.
  }
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (_) => FeedbackDialog(
      feedback: feedback,
      appVersion: version,
      history: history,
      initialEntry: entry,
    ),
  );
}

/// #294 feedback dialog (Telegram via [FeedbackService]). Extracted from
/// settings_screen.dart (#426) so an analysis screen can open it with the
/// displayed analysis already attached ([initialEntry]).
class FeedbackDialog extends StatefulWidget {
  const FeedbackDialog({
    super.key,
    required this.feedback,
    required this.appVersion,
    required this.history,
    this.initialEntry,
  });

  final FeedbackService feedback;
  final String? appVersion;
  final HistoryService history;

  /// #426: pre-attached analysis. Only a complete one is useful (#318);
  /// the user can still remove or change it.
  final HistoryEntry? initialEntry;

  @override
  State<FeedbackDialog> createState() => FeedbackDialogStateX();
}

class FeedbackDialogStateX extends State<FeedbackDialog> {
  final _controller = TextEditingController();
  bool _sending = false;
  String? _error;
  // #296: e.g. a screenshot of the problem being reported.
  File? _image;
  // #315: an analysis picked from history instead of a manual screenshot —
  // mutually exclusive with _image (Telegram only takes one photo per
  // message), see _pickImage/_pickAnalysis.
  late HistoryEntry? _selectedEntry = widget.initialEntry;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final xFile = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 90);
    if (xFile == null || !mounted) return;
    setState(() {
      _image = File(xFile.path);
      _selectedEntry = null;
    });
  }

  Future<void> _pickAnalysis() async {
    final l10n = AppLocalizations.of(context)!;
    // #318: pending/captured/failed entries have an empty script and null
    // model/timing details (never populated until an analysis actually
    // completes) — attaching one would silently send a feedback report
    // with a photo but no exploitable content, defeating the point of the
    // feature. Only a finished analysis has something worth attaching.
    final entries = widget.history.entries
        .where((e) => e.status == AnalysisStatus.complete)
        .toList();
    final selected = await showDialog<HistoryEntry>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.feedbackDialogSelectAnalysisTitle),
        content: SizedBox(
          width: double.maxFinite,
          child: entries.isEmpty
              ? Text(l10n.feedbackDialogNoAnalyses)
              : SizedBox(
                  height: 320,
                  child: ListView.builder(
                    itemCount: entries.length,
                    itemBuilder: (context, index) {
                      final entry = entries[index];
                      return ListTile(
                        leading: ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: Image.file(File(entry.imagePath),
                              width: 40, height: 40, fit: BoxFit.cover),
                        ),
                        title: Text(entry.title,
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text(formatLocalDateTime(
                            entry.createdAt, Localizations.localeOf(context).toString())),
                        onTap: () => Navigator.of(dialogContext).pop(entry),
                      );
                    },
                  ),
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(l10n.feedbackDialogCancel),
          ),
        ],
      ),
    );
    if (selected != null && mounted) {
      setState(() {
        _selectedEntry = selected;
        _image = null;
      });
    }
  }

  /// #315: appended to the typed message so the report carries the same
  /// details (model used, timing, etc.) visible in About analysis, without
  /// asking the user to copy them by hand.
  String _formatAttachedAnalysis(HistoryEntry entry) {
    final lines = <String>['', '--- Analyse jointe : ${entry.title} ---'];
    if (entry.aiModel != null) {
      lines.add('Modèle IA : ${entry.aiModel}${entry.aiFallback ? ' (secours)' : ''}');
    }
    if (entry.ttsModel != null) {
      lines.add('Voix : ${entry.ttsModel}${entry.ttsFallback ? ' (secours)' : ''}');
    }
    if (entry.analysisSource != null) lines.add('Source : ${entry.analysisSource}');
    if (entry.analysisDurationMs != null) {
      lines.add('Durée : ${entry.analysisDurationMs} ms');
    }
    if (entry.wordCount != null) lines.add('Mots : ${entry.wordCount}');
    lines.add('Wikipedia : ${entry.wikipediaUsed ? 'oui' : 'non'}');
    if (entry.scriptStyle != null) lines.add('Style : ${entry.scriptStyle}');
    if (entry.outputLanguage != null) lines.add('Langue : ${entry.outputLanguage}');
    if (entry.gpsSource != null) lines.add('GPS : ${entry.gpsSource}');
    if (entry.rating != null) lines.add('Note : ${entry.rating}/5');
    lines.addAll(['', 'Script :', entry.script]);
    return lines.join('\n');
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    // #426: the attached analysis is a report on its own, so the comment
    // is optional then; without one, an empty message says nothing.
    if ((text.isEmpty && _selectedEntry == null) || _sending) return;

    setState(() {
      _sending = true;
      _error = null;
    });

    final analysisEntry = _selectedEntry;
    final fullText = analysisEntry != null
        ? '$text\n${_formatAttachedAnalysis(analysisEntry)}'.trim()
        : text;

    // #319: an attached analysis's photo can be gone from disk (external
    // storage cleanup, a manual deletion, an orphaned DB row after a file
    // loss outside deleteEntry's normal flow) — without this check,
    // MultipartFile.fromPath below throws and the user only sees the
    // generic send-failed error, with no hint that removing the attached
    // analysis is what would fix it.
    if (analysisEntry != null && !File(analysisEntry.imagePath).existsSync()) {
      setState(() {
        _sending = false;
        _error = AppLocalizations.of(context)!.feedbackDialogAnalysisImageMissing;
      });
      return;
    }

    try {
      // #328: the details text above deliberately omits GPS coordinates —
      // the photo itself must not silently reintroduce them via EXIF.
      final image = analysisEntry != null
          ? File(await imagePathWithExifStripped(analysisEntry.imagePath))
          : _image;
      await widget.feedback.send(
        fullText,
        appVersion: widget.appVersion ?? 'unknown',
        platform: defaultTargetPlatform.name,
        image: image,
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context)!.feedbackDialogSuccess)),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _error = AppLocalizations.of(context)!.feedbackDialogError;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return AlertDialog(
      title: Text(l10n.feedbackDialogTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _controller,
            maxLines: 5,
            minLines: 3,
            autofocus: true,
            decoration: InputDecoration(
              hintText: _selectedEntry != null
                  ? l10n.feedbackDialogHintOptional
                  : l10n.feedbackDialogHint,
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              if (_image != null) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: Image.file(_image!, width: 40, height: 40, fit: BoxFit.cover),
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.image_outlined, size: 16),
                  label: Text(_image == null
                      ? l10n.feedbackDialogAttachScreenshot
                      : l10n.feedbackDialogChangeScreenshot),
                  onPressed: _sending || _selectedEntry != null ? null : _pickImage,
                ),
              ),
              if (_image != null)
                IconButton(
                  icon: const Icon(Icons.close),
                  tooltip: l10n.feedbackDialogRemoveScreenshot,
                  onPressed: _sending ? null : () => setState(() => _image = null),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              if (_selectedEntry != null) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: Image.file(File(_selectedEntry!.imagePath),
                      width: 40, height: 40, fit: BoxFit.cover),
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.history, size: 16),
                  label: Text(_selectedEntry == null
                      ? l10n.feedbackDialogAttachAnalysis
                      : l10n.feedbackDialogChangeAnalysis),
                  onPressed: _sending || _image != null ? null : _pickAnalysis,
                ),
              ),
              if (_selectedEntry != null)
                IconButton(
                  icon: const Icon(Icons.close),
                  tooltip: l10n.feedbackDialogRemoveAnalysis,
                  onPressed: _sending ? null : () => setState(() => _selectedEntry = null),
                ),
            ],
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _sending ? null : () => Navigator.of(context).pop(),
          child: Text(l10n.feedbackDialogCancel),
        ),
        FilledButton(
          onPressed: _sending ? null : _send,
          child: Text(_sending ? l10n.feedbackDialogSending : l10n.feedbackDialogSend),
        ),
      ],
    );
  }
}
