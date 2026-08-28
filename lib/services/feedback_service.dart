import 'package:http/http.dart' as http;
import 'network_config.dart';

/// #294: no backend — feedback is posted directly to a Telegram chat via
/// the Bot API's sendMessage endpoint. The token has to live somewhere
/// without a server to hide it behind; it ships baked into the compiled
/// app (via --dart-define, injected from a GitHub Actions secret at CI
/// build time — see build-android.yml) rather than committed to source.
/// Accepted risk: a determined attacker could extract it from the APK
/// and spam the feedback chat with it — bounded to that (no user data
/// exposure), and recoverable by regenerating the token via BotFather.
const String _envBotToken = String.fromEnvironment('TELEGRAM_BOT_TOKEN');
const String _envChatId = String.fromEnvironment('TELEGRAM_CHAT_ID');

class FeedbackSendException implements Exception {
  final String message;
  const FeedbackSendException(this.message);

  @override
  String toString() => message;
}

class FeedbackService {
  /// [botToken]/[chatId] default to the build-time --dart-define values;
  /// only ever overridden in tests, where a real build-time value isn't
  /// available (a plain `flutter test` run doesn't pass --dart-define).
  FeedbackService({
    String? botToken,
    String? chatId,
    http.Client? client,
  })  : botToken = botToken ?? _envBotToken,
        chatId = chatId ?? _envChatId,
        _client = client;

  final String botToken;
  final String chatId;
  final http.Client? _client;

  /// False on every local/dev build — these values only exist in builds
  /// produced by CI, which alone has the GitHub Actions secrets. The
  /// Settings screen uses this to hide the feedback entry entirely
  /// rather than offering a button that would just fail.
  bool get isConfigured => botToken.isNotEmpty && chatId.isNotEmpty;

  /// Sends [message] to the configured Telegram chat, prefixed with
  /// [appVersion]/[platform] so a report is traceable to a build without
  /// asking the user to type it themselves.
  Future<void> send(
    String message, {
    required String appVersion,
    required String platform,
  }) async {
    if (!isConfigured) {
      throw const FeedbackSendException('Feedback non configuré sur ce build.');
    }
    final text = 'Feedback AudioLens ($appVersion, $platform) :\n\n$message';
    try {
      final client = _client ?? http.Client();
      final response = await client
          .post(
            Uri.parse('https://api.telegram.org/bot$botToken/sendMessage'),
            headers: {
              'User-Agent': NetworkConfig.userAgent,
              'Content-Type': 'application/x-www-form-urlencoded',
            },
            body: {'chat_id': chatId, 'text': text},
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        throw FeedbackSendException(
            'Échec de l\'envoi (code ${response.statusCode}).');
      }
    } on FeedbackSendException {
      rethrow;
    } catch (e) {
      throw FeedbackSendException('Échec de l\'envoi : $e');
    }
  }
}
