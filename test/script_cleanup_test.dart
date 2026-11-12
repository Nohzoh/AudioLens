import 'package:flutter_test/flutter_test.dart';
import 'package:audiolens/utils/script_cleanup.dart';

/// Extracted from GeminiApiService's private _cleanMarkdown (#168) so
/// GeminiNanoService can share it — this is its first dedicated test.
void main() {
  group('cleanMarkdown', () {
    test('strips asterisk emphasis markers', () {
      expect(cleanMarkdown('Ceci est **important** et *nuancé*.'),
          'Ceci est important et nuancé.');
    });

    test('strips leading bullet markers', () {
      expect(cleanMarkdown('- Premier point\n• Deuxième point'),
          'Premier point\nDeuxième point');
    });

    test('strips markdown headers', () {
      expect(cleanMarkdown('## Titre\nTexte normal'), 'Titre\nTexte normal');
    });

    test('strips parenthetical footnote-style numbers', () {
      expect(cleanMarkdown('Une phrase (1) avec une note (23).'),
          'Une phrase avec une note.');
    });

    test('collapses 3+ newlines to a blank line', () {
      expect(cleanMarkdown('Un\n\n\n\nDeux'), 'Un\n\nDeux');
    });

    test('drops English thinking-leakage lines', () {
      final result = cleanMarkdown(
        'Voici la description.\n'
        'Let me reconsider the word count here.\n'
        "Okay, I should expand this slightly to stay within the word range.\n"
        'La suite du texte.',
      );
      expect(result, 'Voici la description.\nLa suite du texte.');
    });

    test('leaves ordinary French text untouched', () {
      const text = 'Bienvenue devant ce monument, construit en 1889.';
      expect(cleanMarkdown(text), text);
    });

    // #492 — real Nano output, 2026-11-11.
    test('removes a stage direction and the ellipsis that follows it', () {
      const text = 'Le quartier a changé. (Voix douce et chaleureuse)\n\n'
          '…Et ce petit coin de verdure invite à la pause.';

      expect(cleanMarkdown(text),
          'Le quartier a changé.\n\nEt ce petit coin de verdure invite à la pause.');
    });

    test('removes a stage direction standing alone on its line', () {
      expect(cleanMarkdown('(Pause)\nBienvenue devant ce monument.'),
          'Bienvenue devant ce monument.');
    });

    test('keeps parentheticals that belong to the sentence', () {
      for (final text in [
        'La tour (achevée en 1889) domine le Champ-de-Mars.',
        'Elle fut dessinée par Stephen Sauvestre (architecte).',
        'Le pont (reconstruit après la crue de 1910)\nfut rouvert ensuite.',
        'Son surnom (la Dame de fer)\nlui vient de sa structure.',
      ]) {
        expect(cleanMarkdown(text), text);
      }
    });

    test('trims leading/trailing whitespace', () {
      expect(cleanMarkdown('   Texte avec espaces.   '), 'Texte avec espaces.');
    });
  });
}
