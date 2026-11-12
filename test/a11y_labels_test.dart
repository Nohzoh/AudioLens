import 'package:flutter_test/flutter_test.dart';
import 'package:audiolens/l10n/app_localizations_fr.dart';
import 'package:audiolens/screens/home_screen.dart';
import 'package:audiolens/services/history_service.dart';

// #232
void main() {
  final l10n = AppLocalizationsFr();
  HistoryEntry entry(AnalysisStatus status, {String title = 'Les tours Duo'}) => HistoryEntry(
        id: 1,
        imagePath: '/tmp/x.jpg',
        title: title,
        script: '',
        createdAt: DateTime(2026, 11, 12),
        status: status,
      );

  test('home grid thumbnails say what they are and what a tap does', () {
    expect(homeGridTileLabel(l10n, entry(AnalysisStatus.complete)), 'Les tours Duo');
    expect(homeGridTileLabel(l10n, entry(AnalysisStatus.failed)),
        'Les tours Duo, analyse échouée, toucher pour relancer');
    expect(homeGridTileLabel(l10n, entry(AnalysisStatus.pending)), 'Les tours Duo, analyse en cours');
    expect(homeGridTileLabel(l10n, entry(AnalysisStatus.captured, title: ' ')),
        startsWith('Photo sans titre, pas encore analysée'));
  });

  test('map marker count', () {
    expect(l10n.a11yMapMarker(1), '1 analyse ici');
    expect(l10n.a11yMapMarker(3), '3 analyses ici');
  });
}
