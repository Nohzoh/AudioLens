import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../l10n/app_localizations.dart';

/// The address AI-generated content reports are sent to — same contact
/// address published in PRIVACY.md. Not remote-configured, matching
/// settings_screen.dart's "View source code" link (a static, low-stakes
/// URL isn't worth the extra indirection).
const _reportContactEmail = 'thomas.arnaud@gmail.com';

/// A small "Report this content" action (T91 — Google Play's
/// AI-Generated Content policy requires an in-app way to flag offensive
/// or incorrect AI output). No backend exists for this app, so the report
/// is composed as a pre-filled email via the device's own mail client —
/// the user sees exactly what's being sent before choosing to send it.
///
/// Matches the visual style of the existing Save/Copy action rows in
/// player_screen.dart and history_screen.dart (small icon + text, tap
/// target via InkWell) — pass this as a sibling item in that same Row.
class ReportContentButton extends StatelessWidget {
  final String title;
  final String script;
  final String? aiModel;
  final DateTime date;

  const ReportContentButton({
    super.key,
    required this.title,
    required this.script,
    required this.date,
    this.aiModel,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return InkWell(
      onTap: () => _showReportDialog(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.flag_outlined, size: 14, color: Colors.white38),
            const SizedBox(width: 4),
            Text(l10n.reportContentButton,
                style: const TextStyle(color: Colors.white38, fontSize: 12)),
          ],
        ),
      ),
    );
  }

  Future<void> _showReportDialog(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    // Created externally (not via TextField's own default constructor
    // path), so nothing disposes it automatically — done explicitly below,
    // on every exit path.
    final reasonController = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.reportContentDialogTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.reportContentDialogBody),
            const SizedBox(height: 12),
            TextField(
              controller: reasonController,
              maxLines: 3,
              decoration: InputDecoration(
                hintText: l10n.reportContentReasonHint,
                border: const OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(l10n.reportContentCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(l10n.reportContentSend),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) {
      reasonController.dispose();
      return;
    }

    final reason = reasonController.text.trim().isEmpty
        ? l10n.reportContentReasonNotSpecified
        : reasonController.text.trim();
    reasonController.dispose();

    final body = l10n.reportContentEmailBody(
      title,
      aiModel ?? l10n.reportContentReasonNotSpecified,
      DateFormat('dd/MM/yyyy HH:mm').format(date),
      script,
      reason,
    );

    final uri = Uri(
      scheme: 'mailto',
      path: _reportContactEmail,
      query: _encodeQueryParameters({
        'subject': l10n.reportContentEmailSubject,
        'body': body,
      }),
    );

    final launched = await launchUrl(uri);
    if (!launched && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.reportContentNoEmailApp(_reportContactEmail)),
          duration: const Duration(seconds: 6),
        ),
      );
    }
  }

  static String _encodeQueryParameters(Map<String, String> params) {
    return params.entries
        .map((e) =>
            '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}')
        .join('&');
  }
}
