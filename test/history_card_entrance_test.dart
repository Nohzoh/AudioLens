import 'package:flutter_test/flutter_test.dart';
import 'package:audiolens/screens/history_screen.dart';

// #489: the entrance delay used to grow with the index without limit, so
// cards built while scrolling far down appeared seconds late.
void main() {
  test('only the first cards are staggered', () {
    expect(historyCardEntranceDelay(0), Duration.zero);
    expect(historyCardEntranceDelay(3), const Duration(milliseconds: 150));
    expect(historyCardEntranceDelay(7), const Duration(milliseconds: 350));
  });

  test('cards further down the list appear without delay', () {
    for (final index in [8, 50, 200, 1000]) {
      expect(historyCardEntranceDelay(index), Duration.zero);
    }
  });
}
