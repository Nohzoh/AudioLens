import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'network_config.dart';

/// #294: no backend — feedback is posted directly to a Telegram chat via
/// the Bot API's sendMessage/sendPhoto endpoints. The token has to live
/// somewhere without a server to hide it behind; it ships baked into the
/// compiled app (via --dart-define, injected from a GitHub Actions
/// secret at CI build time — see build-android.yml) rather than
/// committed to source. Accepted risk: a determined attacker could
/// extract it from the APK and spam the feedback chat with it — bounded
/// to that (no user data exposure), and recoverable by regenerating the
/// token via BotFather.
///
/// The dart-define values themselves are XOR-obfuscated (hex-encoded) by
/// build-android.yml before being embedded, not the raw token/chat_id —
/// [_deobfuscate] undoes that at runtime. This is explicitly NOT real
/// security: [_obfuscationKey] ships in this same binary, so anyone
/// willing to decompile (or just hook the app and dump the value right
/// before [FeedbackService.send] uses it) recovers the original exactly
/// as easily as if it were embedded raw. It's worth doing anyway because
/// the realistic threat here is a naive `strings`/regex scan of a public
/// APK — bots that scrape for exposed credentials via simple
/// string-pattern matching, not a dedicated attacker — and this defeats
/// that specific, zero-effort scan (a Telegram bot token has a
/// recognizable shape, `\d+:[A-Za-z0-9_-]{35}`, exactly the kind of
/// pattern such scanners grep for).
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

/// Splits [text] into chunks of at most [maxChars] characters each
/// (only the first chunk uses [firstChunkMaxChars] instead, when given —
/// mirrors `chunkScript`'s same two-budget shape in text_chunker.dart),
/// breaking only at whitespace — never mid-word. A single word longer
/// than the current budget (a long URL, say) has no valid word boundary
/// to break at, so it's hard-cut across chunks rather than left to
/// silently exceed the budget or loop forever.
List<String> _chunkByWords(String text, int maxChars, {int? firstChunkMaxChars}) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) return [];

  final chunks = <String>[];
  var current = '';
  var budget = firstChunkMaxChars ?? maxChars;

  void emit(String chunk) {
    chunks.add(chunk);
    budget = maxChars;
  }

  void flushCurrent() {
    if (current.isNotEmpty) {
      emit(current);
      current = '';
    }
  }

  for (var word in trimmed.split(RegExp(r'\s+'))) {
    while (word.length > budget) {
      flushCurrent();
      emit(word.substring(0, budget));
      word = word.substring(budget);
    }
    final candidate = current.isEmpty ? word : '$current $word';
    if (candidate.length > budget) {
      flushCurrent();
      current = word;
    } else {
      current = candidate;
    }
  }
  flushCurrent();
  return chunks;
}

class FeedbackSendException implements Exception {
  final String message;
  const FeedbackSendException(this.message);

  @override
  String toString() => message;
}

class FeedbackService {
  /// #296: Telegram caps a sendMessage text and a sendPhoto caption
  /// differently (4096 vs 1024 chars) — chunking every message at the
  /// smaller of the two keeps one consistent budget regardless of
  /// whether a screenshot ends up attached, rather than two separate
  /// limits to reason about.
  static const int _maxChunkChars = 1024;

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
  /// asking the user to type it themselves. [image] (#296, e.g. a
  /// screenshot) is optional — when given, it's sent as the first
  /// message (via sendPhoto, with the message's opening chunk as
  /// caption) so it's visually attached to the report instead of
  /// arriving as a separate, disconnected message.
  ///
  /// A message longer than Telegram's per-message/caption limit is
  /// split at word boundaries (see [_chunkByWords]) into several
  /// sequential messages rather than truncated — the user typing a long
  /// report shouldn't lose the end of it.
  Future<void> send(
    String message, {
    required String appVersion,
    required String platform,
    File? image,
  }) async {
    if (!isConfigured) {
      throw const FeedbackSendException('Feedback non configuré sur ce build.');
    }
    // The prefix (with its intentional blank line separating it from the
    // message) is kept intact on chunk 1 rather than passed through the
    // word-splitter itself — only its length counts against that chunk's
    // budget, so a long prefix can't silently push the message's own
    // first words out.
    final prefix = 'Feedback AudioLens ($appVersion, $platform) :\n\n';
    final firstChunkBudget = (_maxChunkChars - prefix.length).clamp(1, _maxChunkChars);
    final messageChunks =
        _chunkByWords(message, _maxChunkChars, firstChunkMaxChars: firstChunkBudget);
    final chunks = messageChunks.isEmpty
        ? [prefix.trimRight()]
        : [prefix + messageChunks.first, ...messageChunks.skip(1)];

    try {
      final client = _client ?? http.Client();
      var remaining = chunks;
      if (image != null) {
        await _sendPhoto(client, image, caption: chunks.first);
        remaining = chunks.skip(1).toList();
      }
      // Sequential, not concurrent — Telegram delivers messages in
      // whatever order the API calls actually complete, so awaiting each
      // one keeps a multi-chunk report readable in the order it was
      // written instead of arriving scrambled.
      for (final chunk in remaining) {
        await _sendMessage(client, chunk);
      }
    } on FeedbackSendException {
      rethrow;
    } catch (e) {
      throw FeedbackSendException('Échec de l\'envoi : $e');
    }
  }

  Future<void> _sendMessage(http.Client client, String text) async {
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
      throw FeedbackSendException('Échec de l\'envoi (code ${response.statusCode}).');
    }
  }

  Future<void> _sendPhoto(http.Client client, File image, {required String caption}) async {
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('https://api.telegram.org/bot$botToken/sendPhoto'),
    )
      ..headers['User-Agent'] = NetworkConfig.userAgent
      ..fields['chat_id'] = chatId
      ..fields['caption'] = caption
      ..files.add(await http.MultipartFile.fromPath('photo', image.path));

    final streamedResponse = await client.send(request).timeout(const Duration(seconds: 20));
    final response = await http.Response.fromStream(streamedResponse);

    if (response.statusCode != 200) {
      throw FeedbackSendException('Échec de l\'envoi de l\'image (code ${response.statusCode}).');
    }
  }
}
