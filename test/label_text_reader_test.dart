import 'dart:io';
import 'package:audiolens/services/label_text_reader.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a label keeps its title, author, technique and date', () {
    expect(
      labelTextFromLines(['Luis ALVAREZ', 'Marie-Madeleine', 'Huile sur toile', '1885']),
      'Luis ALVAREZ / Marie-Madeleine / Huile sur toile / 1885',
    );
  });

  test('stray characters and duplicates are dropped', () {
    expect(labelTextFromLines(['|', 'l1 //', '~~ 3', 'Musée', 'Musée', '  Salle   2 ']),
        'Musée / Salle 2');
    expect(labelTextFromLines(['|', '--', '42']), isNull);
    expect(labelTextFromLines(const []), isNull);
  });

  test('a long wall text is cut on a line boundary', () {
    final lines = [for (var i = 0; i < 30; i++) 'Ligne de texte numero $i du panneau'];
    final text = labelTextFromLines(lines)!;
    expect(text.length, lessThanOrEqualTo(labelTextMaxChars));
    expect(text.endsWith('du panneau'), isTrue);
  });

  test('straight quotes cannot break out of the prompt quoting', () {
    expect(labelTextFromLines(['Le "Penseur" de Rodin']), "Le 'Penseur' de Rodin");
  });

  test('a failing recognition gives no text instead of an error', () async {
    final reader = LabelTextReader(recognizeLines: (_) async => throw StateError('no model'));
    expect(await reader.read(File('missing.jpg')), isNull);
    final ok = LabelTextReader(
        recognizeLines: (_) async => const [RecognizedLine('Marie-Madeleine')]);
    expect(await ok.read(File('missing.jpg')), 'Marie-Madeleine');
  });

  // #617
  test('a low-confidence line is marked as possibly misread', () async {
    final reader = LabelTextReader(
        recognizeLines: (_) async => const [
              RecognizedLine('Lais Alvarcz', 0.52),
              RecognizedLine('Marie Madeleine', 0.93),
              RecognizedLine('Huile sur toile'),
            ]);
    expect(await reader.read(File('missing.jpg')),
        'Lais Alvarcz$uncertainMark / Marie Madeleine / Huile sur toile');
    expect(reader.lastConfidences, '0.52 / 0.93 / ?');
  });
}
