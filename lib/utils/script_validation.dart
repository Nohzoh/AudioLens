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
/// the app broke rather than like the guide finished speaking.
String capScriptLength(String script, {int maxChars = kDefaultScriptMaxChars}) {
  if (script.length <= maxChars) return script;

  final head = script.substring(0, maxChars);
  final lastBoundary = _lastSentenceEnd(head);

  // No sentence boundary at all in the kept portion (a wall of text with
  // no punctuation) — fall back to a hard cut, since keeping nothing at
  // all would be worse than an abrupt ending.
  if (lastBoundary == null) return head.trimRight();

  return head.substring(0, lastBoundary + 1).trimRight();
}

/// Index of the last `.`, `!` or `?` in [text], or null if there is none.
int? _lastSentenceEnd(String text) {
  for (var i = text.length - 1; i >= 0; i--) {
    final c = text[i];
    if (c == '.' || c == '!' || c == '?') return i;
  }
  return null;
}
