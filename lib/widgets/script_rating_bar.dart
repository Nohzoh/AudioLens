import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../l10n/app_localizations.dart';
import '../services/feedback_service.dart';
import '../services/history_service.dart';
import '../utils/app_logger.dart';
import '../utils/guide_error_localizer.dart';
import 'feedback_dialog.dart';

/// #421: 1-5 star rating of a complete analysis's script, on a scrim pill
/// so it stays readable over the background photo (same idea as
/// `ScrimActionChip`, #149). Persisted on the history entry; changeable
/// at any time.
///
/// A 1-star rating on a feedback-configured build offers to send the
/// analysis as feedback (#426's dialog, analysis pre-attached). Declining
/// keeps the rating.
class ScriptRatingBar extends StatelessWidget {
  final HistoryEntry entry;

  /// Defaults to the build-time-configured service; injectable for tests.
  final FeedbackService? feedbackService;

  const ScriptRatingBar({super.key, required this.entry, this.feedbackService});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final current = entry.rating ?? 0;
    return Material(
      // #145: fixed black scrim regardless of app theme, like the chips.
      color: Colors.black.withValues(alpha: 0.35),
      borderRadius: BorderRadius.circular(100),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var stars = 1; stars <= 5; stars++)
              IconButton(
                key: ValueKey('rating-star-$stars'),
                tooltip: l10n.ratingStarLabel(stars),
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                iconSize: 20,
                icon: Icon(
                  stars <= current ? Icons.star_rounded : Icons.star_outline_rounded,
                  color: stars <= current ? Colors.amber : Colors.white70,
                ),
                onPressed: () => _rate(context, stars),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _rate(BuildContext context, int stars) async {
    final history = context.read<HistoryService>();
    final id = entry.id;
    if (id == null) return;
    try {
      await history.setRating(id, stars);
    } on HistoryStorageException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
                localizeHistoryStorageException(AppLocalizations.of(context)!, e))));
      }
      return;
    }
    if (stars != 1 || !context.mounted) return;

    final feedback = feedbackService ?? FeedbackService();
    if (!feedback.isConfigured) return;
    final l10n = AppLocalizations.of(context)!;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.ratingLowPromptTitle),
        content: Text(l10n.ratingLowPromptBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(l10n.ratingLowPromptDecline),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(l10n.ratingLowPromptAccept),
          ),
        ],
      ),
    );
    AppLogger.info('1-star feedback prompt: ${accepted == true ? 'accepted' : 'declined'}');
    if (accepted != true || !context.mounted) return;
    await showFeedbackDialogForEntry(
      context,
      feedback: feedback,
      history: history,
      entry: entry.copyWith(rating: stars),
    );
  }
}
