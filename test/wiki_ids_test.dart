import 'package:flutter_test/flutter_test.dart';
import 'package:audiolens/services/wikidata_service.dart';

// #542
void main() {
  test('Wikidata ids from OSM tags are validated', () {
    expect(normalizeQid('Q90'), 'Q90');
    expect(normalizeQid(' q243 '), 'Q243');
    expect(normalizeQid('Q1;Q2'), 'Q1');
    expect(normalizeQid('junk;Q42'), 'Q42');
    expect(normalizeQid('Q1&props=claims'), isNull);
    expect(normalizeQid('Q0'), isNull);
    expect(normalizeQid(''), isNull);
    expect(normalizeQid(null), isNull);
  });
}
