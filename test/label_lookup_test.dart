import 'package:audiolens/services/label_lookup.dart';
import 'package:audiolens/services/wikipedia_service.dart';
import 'package:flutter_test/flutter_test.dart';

WikipediaResult _article(String title, String extract) =>
    WikipediaResult(title: title, extract: extract, lang: 'fr');

void main() {
  test('a few misread letters still match, a different name does not', () {
    expect(labelLineMatches('Lais Alvarcz', 'Luis Alvarez'), isTrue);
    expect(labelLineMatches('Marie Mludeleine', 'Marie Madeleine'), isTrue);
    expect(labelLineMatches('Marie Madeleine', 'Marie-Madeleine (Metsys)'), isTrue);
    expect(labelLineMatches('Lais Alvarcz', 'Luis Walter Alvarez'), isFalse);
    expect(labelLineMatches('Marie Mludeleine', 'Marie Madeleine Postel'), isFalse);
    // Short names must be exact.
    expect(labelLineMatches('Monet', 'Manet'), isFalse);
    expect(labelLineMatches('Monet', 'monet'), isTrue);
  });

  test('confirmed lines get the article spelling and bring their facts', () async {
    final asked = <String>[];
    final resolved = await resolveLabel('Lais Alvarcz / Marie Mludeleine / Huile sur toile',
        search: (q) async {
      asked.add(q);
      if (q.startsWith('Marie')) {
        return [
          _article('Marie Madeleine',
              'Marie Madeleine, ou Marie de Magdala, est une disciple de Jésus dans les Évangiles.'),
        ];
      }
      return const [];
    });
    expect(resolved.labelText, 'Lais Alvarcz / Marie Madeleine / Huile sur toile');
    expect(resolved.facts, startsWith('« Marie Madeleine » : Marie Madeleine, ou Marie de Magdala'));
    // The technique line is not looked up.
    expect(asked, isNot(contains('Huile sur toile')));
  });

  test('a namesake biography or a disambiguation page is not used', () async {
    final resolved = await resolveLabel('Luis Alvarez / Sans titre', search: (q) async {
      if (q == 'Luis Alvarez') {
        return [
          _article('Luis Alvarez', 'Luis Alvarez, né le 13 juin 1911 à San Francisco, est un physicien américain.'),
        ];
      }
      return [_article('Sans titre', 'Sans titre peut désigner plusieurs œuvres, films ou albums.')];
    });
    expect(resolved.labelText, 'Luis Alvarez / Sans titre');
    expect(resolved.facts, isNull);
  });

  test('an artist biography is used', () async {
    final resolved = await resolveLabel('Claude Monct', search: (_) async => [
          _article('Claude Monet', 'Claude Monet, né le 14 novembre 1840 à Paris, est un peintre français.'),
        ]);
    expect(resolved.labelText, 'Claude Monet');
    expect(resolved.facts, contains('peintre français'));
  });

  test('a failing search leaves the label as read', () async {
    final resolved =
        await resolveLabel('Lais Alvarcz', search: (_) async => throw Exception('offline'));
    expect(resolved.labelText, 'Lais Alvarcz');
    expect(resolved.facts, isNull);
  });
}
