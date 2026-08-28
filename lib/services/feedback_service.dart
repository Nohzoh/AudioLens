import 'dart:convert';
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
///
/// The dart-define values themselves are XOR-obfuscated (hex-encoded) by
/// build-android.yml before being embedded, not the raw token/chat_id —
/// [_deobfuscate] undoes that at runtime. This is explicitly NOT real
/// security: [_obfuscationKey] ships in this same binary, so anyone
/// willing to decompile (or just hook the app and dump the value right
/// before [send] uses it) recovers the original exactly as easily as if
/// it were embedded raw. It's worth doing anyway because the realistic
/// threat here is a naive `strings`/regex scan of a public APK — bots
/// that scrape for exposed credentials via simple string-pattern
/// matching, not a dedicated attacker — and this defeats that specific,
/// zero-effort scan (a Telegram bot token has a recognizable shape,
/// `\d+:[A-Za-z0-9_-]{35}`, exactly the kind of pattern such scanners
/// grep for).
const String _envBotTokenObf = String.fromEnvironment('TELEGRAM_BOT_TOKEN_OBF');
const String _envChatIdObf = String.fromEnvironment('TELEGRAM_CHAT_ID_OBF');

const String _obfuscationKey = 'AudioLensObfuscationKeyDoNotUseElsewhere';

/// XOR is its own inverse — this is the exact same transform
/// build-android.yml's Python step applies before hex-encoding, just
/// run in reverse (hex-decode first, XOR undoes itself). Returns '' on
/// any malformed input (odd-length hex, non-hex characters, invalid
/// UTF-8 after XOR) rather than throwing — a misconfigured/absent value
/// should look "not configured", not crash the app.
///
/// Round-trip correctness against the Python side verified manually
/// (`dart run` with the obfuscated hex values passed via `-D`, comparing
/// the deobfuscated result byte-for-byte against the known original)
/// rather than as a permanent automated test — this function only does
/// anything interesting when the dart-define is actually set, which the
/// standard `flutter test` invocation this repo's CI runs never passes.
String _deobfuscate(String hex) {
  if (hex.isEmpty || hex.length.isOdd) return '';
  try {
    final keyBytes = utf8.encode(_obfuscationKey);
    final bytes = List<int>.generate(
      hex.length ~/ 2,
      (i) => int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16),
    );
    final xored = List<int>.generate(
      bytes.length,
      (i) => bytes[i] ^ keyBytes[i % keyBytes.length],
    );
    return utf8.decode(xored);
  } catch (_) {
    return '';
  }
}

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
  })  : botToken = botToken ?? _deobfuscate(_envBotTokenObf),
        chatId = chatId ?? _deobfuscate(_envChatIdObf),
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
