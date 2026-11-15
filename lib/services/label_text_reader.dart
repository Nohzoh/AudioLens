import 'dart:io';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import '../utils/app_logger.dart';
import '../utils/error_sanitizer.dart';

/// #608: reads the text visible on a photo (a museum label, a plaque, an
/// inscription) with on-device text recognition, so the guide quotes a
/// title, author or date from what is really written instead of from
/// Gemini Nano's own, unreliable, reading of the image.
class LabelTextReader {
  /// Recognised lines of the photo, top to bottom. Replaceable in tests.
  final Future<List<String>> Function(File image) recognizeLines;

  LabelTextReader({Future<List<String>> Function(File image)? recognizeLines})
      : recognizeLines = recognizeLines ?? _mlKitLines;

  static Future<List<String>> _mlKitLines(File image) async {
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final result = await recognizer.processImage(InputImage.fromFilePath(image.path));
      return [
        for (final block in result.blocks)
          for (final line in block.lines) line.text,
      ];
    } finally {
      await recognizer.close();
    }
  }

  /// The text worth giving to the model, or null when there is none or
  /// the recognition failed (the analysis then runs as before).
  Future<String?> read(File image) async {
    try {
      final lines = await recognizeLines(image).timeout(const Duration(seconds: 8));
      return labelTextFromLines(lines);
    } catch (e) {
      AppLogger.ai('Label text: recognition failed (${sanitizeError(e.toString())})');
      return null;
    }
  }
}

/// Longest label text handed to the model: a label holds a title, an
/// author, a date and a technique; more is a wall text that would crowd
/// Nano's small prompt budget.
const labelTextMaxChars = 300;

/// Keeps the lines that look like words (a painting's texture often
/// yields stray characters), joined with " / ", capped at
/// [labelTextMaxChars] on a line boundary. Null when nothing is left.
String? labelTextFromLines(List<String> lines) {
  final kept = <String>[];
  var length = 0;
  for (final raw in lines) {
    final line = raw.replaceAll(RegExp(r'\s+'), ' ').replaceAll('"', "'").trim();
    final letters = RegExp(r'[A-Za-zÀ-ÿ]').allMatches(line).length;
    final isYear = RegExp(r'\b1[0-9]{3}\b|\b20[0-9]{2}\b').hasMatch(line);
    // At least a three-letter word, mostly letters — or a year.
    final wordLike = RegExp(r'[A-Za-zÀ-ÿ]{3,}').hasMatch(line) && letters * 2 >= line.length;
    if (!wordLike && !isYear) continue;
    if (kept.contains(line)) continue;
    final added = (kept.isEmpty ? 0 : 3) + line.length;
    if (length + added > labelTextMaxChars) break;
    kept.add(line);
    length += added;
  }
  return kept.isEmpty ? null : kept.join(' / ');
}
