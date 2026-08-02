String formatVoiceUpgradeErrorMessage(Object error) {
  final message = error.toString().toLowerCase();

  if (message.contains('429') ||
      message.contains('too many requests') ||
      message.contains('rate limit')) {
    return 'La mise à jour de la voix a été temporairement impossible à cause d’une limite de requêtes. Réessayez dans un instant.';
  }

  return 'La mise à jour de la voix a échoué. Vous pouvez réessayer à nouveau.';
}
