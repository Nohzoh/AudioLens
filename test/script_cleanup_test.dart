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

    test('trims leading/trailing whitespace', () {
      expect(cleanMarkdown('   Texte avec espaces.   '), 'Texte avec espaces.');
    });
  });
}
