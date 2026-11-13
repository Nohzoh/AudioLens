import 'package:flutter_test/flutter_test.dart';
import 'package:audiolens/services/wikipedia_service.dart';

// #587
void main() {
  bool street(String lang, String text) =>
      WikipediaService.isStreetOrAdministrative(WikipediaResult(title: 't', extract: text, lang: lang));

  test('street articles are recognized in each edition', () {
    expect(street('fr', 'La rue Jules-Cazot est une voie d’Alès.'), isTrue);
    expect(street('de', 'Die Hauptstraße ist eine Straße in Heidelberg.'), isTrue);
    expect(street('de', 'Der Philosophenweg ist ein Weg am Nordufer des Neckars.'), isTrue);
    expect(street('de', 'Neuenheim ist ein Stadtteil von Heidelberg.'), isTrue);
    expect(street('en', 'Baker Street is a street in Marylebone.'), isTrue);
    expect(street('it', 'Via del Corso è una via di Roma.'), isTrue);
  });

  test('landmarks are kept', () {
    expect(street('de', 'Das Heidelberger Schloss ist eine der berühmtesten Ruinen.'), isFalse);
    expect(street('en', 'The Tower Bridge is a Grade I listed bridge.'), isFalse);
    expect(street('fr', 'La cathédrale Notre-Dame est une cathédrale catholique.'), isFalse);
  });
}
