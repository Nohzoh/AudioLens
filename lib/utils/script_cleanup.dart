/// Strips markdown formatting and English "thinking leakage" lines from a
/// model's raw text output before it reaches history/TTS.
///
/// Originally only applied to the cloud pipeline (`GeminiApiService`),
/// hardened over time (per the various T-numbered fixes in its history)
/// against real failure modes observed in production. Gemini Nano
/// (`GeminiNanoService`/`GeminiNanoPlugin.kt`) went through none of that
/// hardening and returned its raw concatenated segments as-is (#168) —
/// backwards from a risk standpoint, since Nano is the smaller, less
/// controllable model and so more likely to need exactly this cleanup,
/// not less. Shared here so both pipelines apply the same rules and can't
/// silently drift apart again.
String cleanMarkdown(String text) {
  var result = text
      .replaceAll(RegExp(r'\*{1,3}'), '')
      .replaceAll(RegExp(r'^\s*[-•]\s+', multiLine: true), '')
      .replaceAll(RegExp(r'\s*\(\d+\)'), '')
      .replaceAll(RegExp(r'^#{1,6}\s+', multiLine: true), '')
      .replaceAll(RegExp(r'\n{3,}'), '\n\n')
      .trim();
  // Remove English thinking/meta lines.
  final lines = result.split('\n');
  final filtered = lines.where((line) {
    final lower = line.trim().toLowerCase();
    if (lower.isEmpty) return true;
    // Skip lines that are clearly internal reasoning in English.
    final thinkingPatterns = [
      'rough estimate', 'word count', 'let me ', "let's",
      'okay,', 'alright,', 'i need to', 'i should', 'i will',
      'currently it is', 'this is around', 'paragraph ',
      'to ensure', 'to make sure', 'expanding', 'slightly',
      'within the', 'word range', 'falls well',
    ];
    for (final p in thinkingPatterns) {
      if (lower.contains(p)) return false;
    }
    return true;
  }).toList();
  return filtered.join('\n').trim();
}
