import 'package:flutter_test/flutter_test.dart';
import 'package:audiolens/utils/script_validation.dart';

void main() {
  group('capScriptLength', () {
    test('leaves a normal-length script untouched', () {
      const script = 'Bienvenue devant ce monument. Il fut construit en 1889.';
      expect(capScriptLength(script), script);
    });

    test('leaves a script exactly at the cap untouched', () {
      final script = 'a' * 100;
      expect(capScriptLength(script, maxChars: 100), script);
    });

    test('truncates back to the last sentence boundary that fits', () {
      // Second sentence would cross the cap, so only the first survives.
      const script = 'Première phrase courte. Deuxième phrase beaucoup plus longue qui dépasse.';
      final result = capScriptLength(script, maxChars: 40);

      expect(result, 'Première phrase courte.');
      expect(result.length, lessThanOrEqualTo(40));
    });

    test('keeps as many whole sentences as fit', () {
      const script = 'Un. Deux. Trois. Quatre. Cinq.';
      final result = capScriptLength(script, maxChars: 16);

      expect(result, 'Un. Deux. Trois.');
    });

    test('recognizes ! and ? as sentence boundaries too', () {
      const script = 'Quelle vue magnifique! Une deuxième phrase bien plus longue ici.';
      expect(capScriptLength(script, maxChars: 30), 'Quelle vue magnifique!');

      const question = 'Saviez-vous ceci? Une deuxième phrase bien plus longue ici.';
      expect(capScriptLength(question, maxChars: 30), 'Saviez-vous ceci?');
    });

    test('never returns more than maxChars', () {
      final script = '${'mot ' * 500}fin.';
      final result = capScriptLength(script, maxChars: 200);
      expect(result.length, lessThanOrEqualTo(200));
    });

    test('falls back to a hard cut when there is no sentence boundary at all', () {
      // A wall of text with no punctuation — keeping nothing would be
      // worse than an abrupt ending.
      final script = 'a' * 500;
      final result = capScriptLength(script, maxChars: 100);

      expect(result.length, 100);
      expect(result, 'a' * 100);
    });

    test('does not leave trailing whitespace after truncating', () {
      const script = 'Une phrase.                                   Une autre phrase ici.';
      final result = capScriptLength(script, maxChars: 40);

      expect(result, isNot(endsWith(' ')));
    });

    test('handles an empty script without throwing', () {
      expect(capScriptLength(''), '');
    });

    test('default cap is generous enough for a normal 400-word script', () {
      // ~6.5 chars/word in French: the prompt's own upper target must never
      // trip the cap, or every normal analysis would get truncated.
      final typicalLongScript = '${'mot ' * 400}fin.';
      expect(typicalLongScript.length, lessThan(kDefaultScriptMaxChars));
      expect(capScriptLength(typicalLongScript), typicalLongScript);
    });
  });
}
