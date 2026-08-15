import 'package:flutter_test/flutter_test.dart';
import 'package:audiolens/utils/text_chunker.dart';

void main() {
  group('splitSentences', () {
    test('splits on ., !, ? followed by whitespace', () {
      final result = splitSentences('Bonjour ! Comment allez-vous ? Bien.');
      expect(result, ['Bonjour !', 'Comment allez-vous ?', 'Bien.']);
    });

    test('keeps trailing text without terminal punctuation (no data loss)', () {
      final result = splitSentences('Bonjour. Comment allez-vous');
      expect(result, ['Bonjour.', 'Comment allez-vous']);
    });

    test('returns the whole trimmed text as one sentence if there is no punctuation', () {
      final result = splitSentences('  aucune ponctuation ici  ');
      expect(result, ['aucune ponctuation ici']);
    });

    test('returns empty for blank input', () {
      expect(splitSentences(''), isEmpty);
      expect(splitSentences('   '), isEmpty);
    });
  });

  group('chunkScript', () {
    test('never splits mid-sentence and preserves all content', () {
      const script =
          'Premiere phrase courte. Deuxieme phrase un peu plus longue ici. '
          'Troisieme phrase. Quatrieme phrase qui rallonge un peu le texte total. '
          'Cinquieme phrase. Sixieme phrase pour continuer a remplir. '
          'Septieme phrase assez longue pour ce test de decoupage. Huitieme phrase finale.';

      final chunks = chunkScript(script);

      expect(chunks, isNotEmpty);
      // Rejoining every chunk reproduces exactly the same sentences, in order.
      final rejoined = chunks.join(' ');
      final originalSentences = splitSentences(script);
      final rejoinedSentences = splitSentences(rejoined);
      expect(rejoinedSentences, originalSentences);
    });

    test('first chunk is short, later chunks are larger', () {
      const script =
          'Un. Deux. Trois quatre cinq six sept huit neuf dix onze douze treize. '
          'Quatorze quinze seize dix-sept dix-huit dix-neuf vingt vingt-et-un vingt-deux. '
          'Vingt-trois vingt-quatre vingt-cinq vingt-six vingt-sept vingt-huit vingt-neuf.';

      final chunks = chunkScript(script, firstChunkMaxChars: 10, chunkMaxChars: 60);

      expect(chunks.length, greaterThanOrEqualTo(2));
      expect(chunks.first.length, lessThanOrEqualTo(15)); // first sentence alone, close to the cap
      for (final c in chunks.skip(1)) {
        expect(c.length, lessThanOrEqualTo(60 + 40)); // allow one sentence over the cap (never split mid-sentence)
      }
    });

    test('a single short sentence produces exactly one chunk', () {
      final chunks = chunkScript('Une seule phrase courte.');
      expect(chunks, ['Une seule phrase courte.']);
    });

    test('returns empty for blank input', () {
      expect(chunkScript(''), isEmpty);
    });
  });
}
