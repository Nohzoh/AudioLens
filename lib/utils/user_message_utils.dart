import '../l10n/app_localizations.dart';
import '../services/history_service.dart';

// #129: HistoryStorageException.message itself stays French for now —
// localizing every service-layer error message needs error-code plumbing
// (services have no BuildContext/AppLocalizations to localize with),
// split off into #230 rather than mixed into this mechanical pass.
String formatVoiceUpgradeErrorMessage(Object error, AppLocalizations l10n) {
  // T116: surface the specific storage message rather than the generic
  // fallback below.
  if (error is HistoryStorageException) return error.message;

  final message = error.toString().toLowerCase();

  if (message.contains('429') ||
      message.contains('too many requests') ||
      message.contains('rate limit')) {
    return l10n.voiceUpgradeErrorRateLimit;
  }

  return l10n.voiceUpgradeErrorGeneric;
}
