/// Splits a script into sentence-bounded chunks for streamed TTS playback
/// (T76). The first chunk is kept short so playback can start quickly;
/// later chunks are larger to reduce the number of synthesis round-trips.
/// Never splits mid-sentence.
///
/// [chunkMaxChars] was raised from 280 to 700 (2026-08-16): a typical
/// ~400-word cloud script (~2200 chars) produced 7-8 separate Gemini TTS
/// calls at 280 — enough to reliably hit rate limiting in practice. At
/// 700 the same script needs about 4. Synthesis stays consistently
/// faster than playback for the same text length (observed ~0.7x on real
/// devices), so larger chunks don't break the prefetch overlap.
List<String> chunkScript(
  String text, {
  int firstChunkMaxChars = 120,
  int chunkMaxChars = 700,
}) {
  final sentences = splitSentences(text);
  if (sentences.isEmpty) return [];

  final chunks = <String>[];
  var current = '';
  var maxChars = firstChunkMaxChars;

  for (final sentence in sentences) {
    final candidate = current.isEmpty ? sentence : '$current $sentence';
    if (current.isNotEmpty && candidate.length > maxChars) {
      chunks.add(current);
      current = sentence;
      maxChars = chunkMaxChars;
    } else {
      current = candidate;
    }
  }
  if (current.isNotEmpty) chunks.add(current);
  return chunks;
}

/// Splits [text] into sentences at '.', '!', '?' followed by whitespace.
/// Trailing text without terminal punctuation is kept as its own sentence
/// (not dropped).
List<String> splitSentences(String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) return [];
  return trimmed
      .split(RegExp(r'(?<=[.!?])\s+'))
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();
}
