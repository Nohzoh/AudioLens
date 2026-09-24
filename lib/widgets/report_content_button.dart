import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../l10n/app_localizations.dart';
import '../utils/date_format_utils.dart';

/// The address AI-generated content reports are sent to — same contact
/// address published in PRIVACY.md. Not remote-configured, matching
/// settings_screen.dart's "View source code" link (a static, low-stakes
/// URL isn't worth the extra indirection).
const _reportContactEmail = 'thomas.arnaud@gmail.com';

/// Opens the "Report this content" dialog (T91 — Google Play's
/// AI-Generated Content policy requires an in-app way to flag offensive
/// or incorrect AI output). No backend exists for this app, so the report
/// is composed as a pre-filled email via the device's own mail client —
/// the user sees exactly what's being sent before choosing to send it.
///
/// Reached from the analysis actions sheet (`GuideActionRow`, #427),
/// which replaced the old standalone "Report" chip.
Future<void> showReportContentDialog(
  BuildContext context, {
  required String title,
  required String script,
  required DateTime date,
  String? aiModel,
}) =>
    _ReportContent(title: title, script: script, date: date, aiModel: aiModel)
        ._showReportDialog(context);

class _ReportContent {
  final String title;
  final String script;
  final String? aiModel;
  final DateTime date;

  const _ReportContent({
    required this.title,
    required this.script,
    required this.date,
    this.aiModel,
  });

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
      formatLocalDateTime(date, Localizations.localeOf(context).toString()),
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
