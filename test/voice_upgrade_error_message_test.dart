import 'package:flutter_test/flutter_test.dart';
import 'package:audiolens/utils/user_message_utils.dart';

void main() {
  test('formats Gemini 429 errors into a clear user-facing message', () {
    final message = formatVoiceUpgradeErrorMessage(
      Exception(
          'La synthèse vocale a échoué (429). Veuillez réessayer plus tard.'),
    );

    expect(message, contains('temporairement'));
    expect(message.toLowerCase(), contains('réessayez'));
  });

  test('falls back to a generic message for other errors', () {
    final message = formatVoiceUpgradeErrorMessage(Exception('boom'));

    expect(message, contains('La mise à jour de la voix a échoué'));
  });
}
