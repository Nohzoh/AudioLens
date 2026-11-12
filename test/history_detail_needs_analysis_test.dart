import 'package:flutter_test/flutter_test.dart';
import 'package:audiolens/screens/history_screen.dart';
import 'package:audiolens/services/history_service.dart';

// #508: an entry reached by swiping in the detail screen used to offer
// « Générer l'audio » even when it had never been analyzed.
HistoryEntry _entry(AnalysisStatus status) => HistoryEntry(
      title: '',
      script: '',
      imagePath: '/tmp/x.jpg',
      createdAt: DateTime(2026, 11, 12),
      status: status,
    );

void main() {
  test('captured, pending and failed entries need an analysis first', () {
    for (final status in [
      AnalysisStatus.captured,
      AnalysisStatus.pending,
      AnalysisStatus.failed,
    ]) {
      expect(historyDetailNeedsAnalysis(_entry(status)), isTrue, reason: '$status');
    }
  });

  test('a complete entry plays or generates its audio as before', () {
    expect(historyDetailNeedsAnalysis(_entry(AnalysisStatus.complete)), isFalse);
  });
}
