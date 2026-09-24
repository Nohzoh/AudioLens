import 'dart:io';
import 'package:flutter/material.dart';
import 'package:gal/gal.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../l10n/app_localizations.dart';
import '../services/feedback_service.dart';
import '../services/history_service.dart';
import '../utils/app_logger.dart';
import '../utils/error_sanitizer.dart';
import '../utils/rotated_image_export.dart';
import 'feedback_dialog.dart';
import 'report_content_button.dart';
import 'scrim_action_chip.dart';

/// Analysis actions shared by `PlayerScreen` and `HistoryDetailScreen`
/// (#147). #427: one compact "Actions" chip that opens a bottom sheet of
/// explicit actions, instead of a row of 4 short-labelled chips that
/// wrapped onto two lines in French and didn't say what they acted on.
/// Each action names its object (photo, text, audio) and destination.
class GuideActionRow extends StatelessWidget {
  final String imagePath;
  final int rotationQuarters;
  final String script;
  final String title;
  final String? audioPath;
  final String? aiModel;
  final DateTime reportDate;

  /// #426: the displayed analysis, when it's a complete history entry —
  /// the "Send as feedback" action attaches it. Null hides the action.
  final HistoryEntry? feedbackEntry;

  /// Defaults to the build-time-configured service; injectable for tests
  /// (a plain `flutter test` run is never configured, see SettingsScreen).
  final FeedbackService? feedbackService;

  /// Injectable for tests — [SharePlus.instance] is a lazily-constructed
  /// singleton that only captures `SharePlatform.instance` at its first
  /// access process-wide, so a per-test fake platform would silently stop
  /// taking effect after the first test to share (#125).
  final SharePlus? sharePlus;

  const GuideActionRow({
    super.key,
    required this.imagePath,
    required this.rotationQuarters,
    required this.script,
    required this.title,
    required this.reportDate,
    this.audioPath,
    this.aiModel,
    this.feedbackEntry,
    this.feedbackService,
    this.sharePlus,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Align(
      alignment: Alignment.centerRight,
      child: ScrimActionChip(
        icon: Icons.more_horiz,
        label: l10n.guideActionsButton,
        onTap: () => _showActions(context),
      ),
    );
  }

  Future<void> _showActions(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    final feedback = feedbackService ?? FeedbackService();
    final entry = feedbackEntry;
    final canSendFeedback = feedback.isConfigured &&
        entry != null &&
        entry.status == AnalysisStatus.complete;
    final path = audioPath;
    final hasAudioFile = path != null && File(path).existsSync();

    // Actions run on the screen's context once the sheet is closed, so
    // their snackbars/dialogs aren't tied to the sheet's own lifetime.
    final action = await showModalBottomSheet<_GuideAction>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        Widget tile(IconData icon, String label, _GuideAction a) => ListTile(
              leading: Icon(icon),
              title: Text(label),
              onTap: () => Navigator.of(sheetContext).pop(a),
            );
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              tile(Icons.add_photo_alternate_outlined, l10n.guideActionSavePhoto,
                  _GuideAction.savePhoto),
              tile(Icons.notes, l10n.guideActionShareText, _GuideAction.shareText),
              if (hasAudioFile)
                tile(Icons.audio_file_outlined, l10n.guideActionShareAudio,
                    _GuideAction.shareAudio),
              if (canSendFeedback)
                tile(Icons.feedback_outlined, l10n.guideActionSendFeedback,
                    _GuideAction.sendFeedback),
              tile(Icons.flag_outlined, l10n.guideActionReport, _GuideAction.report),
            ],
          ),
        );
      },
    );
    if (action == null || !context.mounted) return;
    AppLogger.info('Analysis action: ${action.name}');

    switch (action) {
      case _GuideAction.savePhoto:
        await _savePhoto(context);
      case _GuideAction.shareText:
        await (sharePlus ?? SharePlus.instance)
            .share(ShareParams(text: script, subject: title));
      case _GuideAction.shareAudio:
        await (sharePlus ?? SharePlus.instance)
            .share(ShareParams(text: title, files: [XFile(path!)]));
      case _GuideAction.sendFeedback:
        await showFeedbackDialogForEntry(
          context,
          feedback: feedback,
          history: context.read<HistoryService>(),
          entry: entry!,
        );
      case _GuideAction.report:
        await showReportContentDialog(context,
            title: title, script: script, date: reportDate, aiModel: aiModel);
    }
  }

  Future<void> _savePhoto(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final galleryPath = await imagePathForGallerySave(imagePath, rotationQuarters);
      await Gal.putImage(galleryPath);
      messenger.showSnackBar(SnackBar(
        content: Text(l10n.historyPhotoSavedToGallery),
        duration: const Duration(seconds: 2),
      ));
    } catch (e) {
      // #427: used to be swallowed by a bare `catch (_) {}`.
      AppLogger.error('Gallery save failed: ${sanitizeError(e.toString())}');
      messenger.showSnackBar(SnackBar(content: Text(l10n.guideActionSavePhotoError)));
    }
  }
}

enum _GuideAction { savePhoto, shareText, shareAudio, sendFeedback, report }
