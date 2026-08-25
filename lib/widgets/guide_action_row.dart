import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gal/gal.dart';
import '../utils/rotated_image_export.dart';
import 'report_content_button.dart';
import 'scrim_action_chip.dart';
import 'share_content_button.dart';

/// Shared Save/Copy/Share/Report action row used by `PlayerScreen` and
/// `HistoryDetailScreen` (#147) — both wrapped the same 4 actions
/// (save the photo to the gallery, copy the script, share, report) in an
/// identically-structured `Wrap`, just with slightly different snackbar
/// wording per screen (kept as parameters here rather than consolidated,
/// so this extraction stays purely structural).
class GuideActionRow extends StatelessWidget {
  final String imagePath;
  final int rotationQuarters;
  final String script;
  final String title;
  final String? audioPath;
  final String? aiModel;
  final DateTime reportDate;
  final String saveLabel;
  final String savedSnackbarText;
  final String copyLabel;
  final String copiedSnackbarText;

  const GuideActionRow({
    super.key,
    required this.imagePath,
    required this.rotationQuarters,
    required this.script,
    required this.title,
    required this.reportDate,
    required this.saveLabel,
    required this.savedSnackbarText,
    required this.copyLabel,
    required this.copiedSnackbarText,
    this.audioPath,
    this.aiModel,
  });

  @override
  Widget build(BuildContext context) {
    // Wrap, not Row: on a narrow screen or a longer locale (French labels
    // run noticeably longer than English), 4 pills plus spacing can
    // exceed the available width — Wrap drops the overflow onto a second
    // line instead of clipping/overflowing off-screen (#149).
    return Wrap(
      alignment: WrapAlignment.end,
      spacing: 8,
      runSpacing: 8,
      children: [
        ScrimActionChip(
          icon: Icons.save_alt,
          label: saveLabel,
          onTap: () async {
            try {
              final galleryPath =
                  await imagePathForGallerySave(imagePath, rotationQuarters);
              await Gal.putImage(galleryPath);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(savedSnackbarText),
                    duration: const Duration(seconds: 2),
                  ),
                );
              }
            } catch (_) {}
          },
        ),
        ScrimActionChip(
          icon: Icons.copy,
          label: copyLabel,
          onTap: () {
            Clipboard.setData(ClipboardData(text: script));
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(copiedSnackbarText),
                duration: const Duration(seconds: 2),
              ),
            );
          },
        ),
        ShareContentButton(title: title, script: script, audioPath: audioPath),
        ReportContentButton(
            title: title, script: script, aiModel: aiModel, date: reportDate),
      ],
    );
  }
}
