/// Splits a script into sentence-bounded chunks for streamed TTS playback
/// (T76). The first chunk is kept short so playback can start quickly;
/// later chunks are larger to reduce the number of synthesis round-trips.
/// Never splits mid-sentence.
List<String> chunkScript(
  String text, {
  int firstChunkMaxChars = 120,
  int chunkMaxChars = 280,
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
