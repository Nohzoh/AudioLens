/// Sanity-caps an AI-generated script's length before it reaches history
/// and TTS (T117).
///
/// The prompt asks for 300-400 words (100-150 in 'concise' style), but
/// nothing enforced that: a model that ignored the instruction and
/// returned a runaway script would sail straight through to synthesis,
/// where an over-long script costs real time and money (Gemini TTS is
/// billed per character, and a long script delays time-to-first-audio on
/// every playback) and is unlikely to be listened to in full anyway.
///
/// Truncates rather than rejecting: an over-long script is still
/// legitimate, useful content, so cutting it back is a better outcome for
/// the user than discarding it and retrying (which costs another
/// round-trip and might return something worse).
library;

import 'package:characters/characters.dart';
import 'app_logger.dart';
import 'text_chunker.dart' show splitSentences;

/// Default ceiling, in characters.
///
/// ~6.5 chars/word in French puts the prompt's 400-word target near 2600
/// chars; 4000 leaves roughly 50% headroom so this only ever fires on
/// genuinely runaway output, never on a script that merely ran a bit long.
const int kDefaultScriptMaxChars = 4000;

/// Returns [script] unchanged if within [maxChars], otherwise truncated
/// back to the last sentence boundary that fits.
///
/// Cutting at a sentence boundary (rather than mid-word, or mid-sentence
/// with an ellipsis) matters more here than in most truncation cases:
/// this text is read aloud, so a script ending mid-sentence sounds like
/// the app broke rather than like the guide finished speaking. Sentence
/// boundaries are found via [splitSentences] — the same definition
/// `chunkScript` (T76) already uses for streamed TTS — rather than a
/// second, independently-tuned one that could silently disagree with it.
///
/// [maxChars] comes from remote config (see the call sites), so a bad
/// value (zero, negative — a typo, or an attempt to mean "unlimited")
/// must not crash or silently reduce every script to nothing: treated as
/// "capping disabled" instead.
String capScriptLength(String script, {int maxChars = kDefaultScriptMaxChars}) {
  if (maxChars <= 0) return script;
  if (script.length <= maxChars) return script;

  final sentences = splitSentences(script);
  final kept = StringBuffer();
  for (final sentence in sentences) {
    final candidate = kept.isEmpty ? sentence : '${kept.toString()} $sentence';
    if (candidate.length > maxChars) break;
    if (kept.isNotEmpty) kept.write(' ');
    kept.write(sentence);
  }

  final result = kept.isEmpty ? _hardCut(script, maxChars) : kept.toString();

  AppLogger.ai('Script truncated: ${script.length} -> ${result.length} chars '
      '(cap: $maxChars)');
  return result;
}

/// Hard-cuts [text] to at most [maxChars] UTF-16 code units, but only ever
/// at a grapheme-cluster (Characters) boundary — never mid-surrogate-pair,
/// which a raw `text.substring(0, maxChars)` could do to a character like
/// an emoji that occupies two code units, leaving an unpaired surrogate.
String _hardCut(String text, int maxChars) {
  final buffer = StringBuffer();
  for (final grapheme in text.characters) {
    if (buffer.length + grapheme.length > maxChars) break;
    buffer.write(grapheme);
  }
  return buffer.toString().trimRight();
}
