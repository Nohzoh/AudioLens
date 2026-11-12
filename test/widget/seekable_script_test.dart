import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:audiolens/widgets/seekable_script.dart';

// #228
void main() {
  const text = 'Voici la tour. Elle date de 1890 ! Qui l’a bâtie ? Un ingénieur…';

  test('sentence starts', () {
    expect(scriptSentenceStarts(text), [0, 15, 35, 51]);
    expect(scriptSentenceStarts('Sans point final'), [0]);
    expect(scriptSentenceStarts('« Bonjour. » Puis la suite.'), [0, 13]);
    expect(scriptSentenceStarts(''), isEmpty);
  });

  Future<void> pump(WidgetTester tester, {ValueChanged<double>? onSeek, double progress = 0}) =>
      tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 2000,
            child: SeekableScript(text: text, progress: progress, onSeek: onSeek),
          ),
        ),
      ));

  testWidgets('long-pressing a sentence seeks to its start', (tester) async {
    final seeks = <double>[];
    await pump(tester, onSeek: seeks.add, progress: 0.3);

    // Sentence 3 starts at offset 35: press inside it.
    final rich = find.byType(RichText);
    final box = tester.renderObject<RenderParagraph>(rich);
    final caret = box.getOffsetForCaret(const TextPosition(offset: 40), Rect.zero);
    await tester.longPressAt(tester.getTopLeft(rich) + caret + const Offset(2, 8));

    expect(seeks, [35 / text.length]);
  });

  testWidgets('the whole text is shown, split by progress', (tester) async {
    await pump(tester, progress: 0.5);
    final rich = tester.widget<RichText>(find.byType(RichText));
    expect(rich.text.toPlainText(), text);
  });
}
