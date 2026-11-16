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
  final Future<List<RecognizedLine>> Function(File image) recognizeLines;

  /// #617: confidence of each line of the last reading ("0.62 / 0.91"),
  /// for the lab export — the threshold is tuned from device runs.
  String? lastConfidences;

  LabelTextReader({Future<List<RecognizedLine>> Function(File image)? recognizeLines})
      : recognizeLines = recognizeLines ?? _mlKitLines;

  static Future<List<RecognizedLine>> _mlKitLines(File image) async {
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final result = await recognizer.processImage(InputImage.fromFilePath(image.path));
      return [
        for (final block in result.blocks)
          for (final line in block.lines) RecognizedLine(line.text, line.confidence),
      ];
    } finally {
      await recognizer.close();
    }
  }

  /// The text worth giving to the model, or null when there is none or
  /// the recognition failed (the analysis then runs as before).
  Future<String?> read(File image) async {
    try {
      lastConfidences = null;
      final lines = await recognizeLines(image).timeout(const Duration(seconds: 8));
      final kept = labelLinesFrom(lines);
      if (kept.isEmpty) return null;
      lastConfidences =
          kept.map((l) => l.confidence?.toStringAsFixed(2) ?? '?').join(' / ');
      return kept.map((l) => l.uncertain ? '${l.text}$uncertainMark' : l.text).join(' / ');
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

/// #617: a line of recognised text and how sure the recogniser is (0-1,
/// null when the platform does not say).
class RecognizedLine {
  final String text;
  final double? confidence;
  const RecognizedLine(this.text, [this.confidence]);

  bool get uncertain => confidence != null && confidence! < uncertainBelow;
}

/// Below this confidence a line is handed to the model as possibly
/// misread (« Lais Alvarcz » for « Luis Alvarez » on a small label).
const uncertainBelow = 0.75;

/// Suffix of a possibly misread line in the label text.
const uncertainMark = ' (lecture incertaine)';

/// Keeps the lines that look like words (a painting's texture often
/// yields stray characters), joined with " / ", capped at
/// [labelTextMaxChars] on a line boundary. Null when nothing is left.
String? labelTextFromLines(List<String> lines) {
  final kept = labelLinesFrom([for (final l in lines) RecognizedLine(l)]);
  return kept.isEmpty ? null : kept.map((l) => l.text).join(' / ');
}

/// The lines of [labelTextFromLines], with their confidence.
List<RecognizedLine> labelLinesFrom(List<RecognizedLine> lines) {
  final kept = <RecognizedLine>[];
  var length = 0;
  for (final rawLine in lines) {
    final raw = rawLine.text;
    final line = raw.replaceAll(RegExp(r'\s+'), ' ').replaceAll('"', "'").trim();
    final letters = RegExp(r'[A-Za-zÀ-ÿ]').allMatches(line).length;
    final isYear = RegExp(r'\b1[0-9]{3}\b|\b20[0-9]{2}\b').hasMatch(line);
    // At least a three-letter word, mostly letters — or a year.
    final wordLike = RegExp(r'[A-Za-zÀ-ÿ]{3,}').hasMatch(line) && letters * 2 >= line.length;
    if (!wordLike && !isYear) continue;
    if (kept.any((k) => k.text == line)) continue;
    final added = (kept.isEmpty ? 0 : 3) + line.length;
    if (length + added > labelTextMaxChars) break;
    kept.add(RecognizedLine(line, rawLine.confidence));
    length += added;
  }
  return kept;
}
