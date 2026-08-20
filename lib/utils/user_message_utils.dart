import '../services/history_service.dart';

String formatVoiceUpgradeErrorMessage(Object error) {
  // T116: surface the specific storage message rather than the generic
  // fallback below.
  if (error is HistoryStorageException) return error.message;

  final message = error.toString().toLowerCase();

  if (message.contains('429') ||
      message.contains('too many requests') ||
      message.contains('rate limit')) {
    return 'La mise à jour de la voix a été temporairement impossible à cause d’une limite de requêtes. Réessayez dans un instant.';
  }

  return 'La mise à jour de la voix a échoué. Vous pouvez réessayer à nouveau.';
}
