import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../l10n/app_localizations.dart';
import '../services/history_service.dart';

/// #429: home screen control for visits — « Commencer une visite » when
/// none is running, else the visit's name, photo count and « Terminer ».
class VisitBar extends StatelessWidget {
  const VisitBar({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final history = context.watch<HistoryService>();
    final visit = history.activeVisit;

    if (visit == null) {
      return Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          icon: const Icon(Icons.tour_outlined, size: 18),
          label: Text(l10n.homeVisitStart),
          onPressed: () => _start(context),
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.only(left: 12, right: 4, top: 4, bottom: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.tertiaryContainer.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(Icons.tour, size: 18, color: theme.colorScheme.onTertiaryContainer),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.homeVisitActive(visit.name),
                    style: theme.textTheme.bodyMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
                Text(l10n.homeVisitPhotos(history.activeVisitEntryCount),
                    style: theme.textTheme.bodySmall),
              ],
            ),
          ),
          TextButton(
            onPressed: () async {
              await history.endVisit();
              if (!context.mounted) return;
              ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                SnackBar(content: Text(l10n.homeVisitEnded(visit.name))),
              );
            },
            child: Text(l10n.homeVisitEnd),
          ),
        ],
      ),
    );
  }

  Future<void> _start(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    final history = context.read<HistoryService>();
    final locale = Localizations.localeOf(context).toLanguageTag();
    final fallback = l10n.homeVisitDefaultName(DateFormat.MMMd(locale).format(DateTime.now()));
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        void submit() {
          final typed = controller.text.trim();
          Navigator.pop(dialogContext, typed.isEmpty ? fallback : typed);
        }

        return AlertDialog(
          title: Text(l10n.homeVisitStartTitle),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.homeVisitStartExplanation),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                autofocus: true,
                maxLength: 60,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  labelText: l10n.homeVisitNameLabel,
                  hintText: fallback,
                ),
                onSubmitted: (_) => submit(),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(MaterialLocalizations.of(dialogContext).cancelButtonLabel),
            ),
            FilledButton(onPressed: submit, child: Text(l10n.homeVisitStartAction)),
          ],
        );
      },
    );
    controller.dispose();
    if (name != null) await history.startVisit(name);
  }
}
