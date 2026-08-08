import 'package:flutter_test/flutter_test.dart';
import 'package:audiolens/services/history_service.dart';

void main() {
  test('HistoryEntry round-trips status and optional fields', () {
    final original = HistoryEntry(
      id: 12,
      imagePath: '/tmp/photo.jpg',
      title: 'Titre',
      script: 'Script',
      locationName: 'Lyon',
      createdAt: DateTime.utc(2024, 1, 2, 3, 4),
      status: AnalysisStatus.pending,
      aiModel: 'gemini-nano',
      gpsSource: 'realtime',
      wikipediaUsed: true,
      wordCount: 80,
      analysisDurationMs: 1800,
      gpsLatitude: 45.76,
      gpsLongitude: 4.84,
      gpsAddress: 'Lyon',
      aiFallback: true,
      ttsFallback: true,
    );

    final map = original.toMap();
    final restored = HistoryEntry.fromMap(map);

    expect(restored.id, original.id);
    expect(restored.title, original.title);
    expect(restored.status, AnalysisStatus.pending);
    expect(restored.aiModel, 'gemini-nano');
    expect(restored.wikipediaUsed, isTrue);
    expect(restored.gpsLatitude, 45.76);
    expect(restored.gpsAddress, 'Lyon');
    expect(restored.aiFallback, isTrue);
    expect(restored.ttsFallback, isTrue);
  });

  test('HistoryEntry defaults fallback flags to false', () {
    final entry = HistoryEntry(
      imagePath: '/tmp/photo.jpg',
      title: 'Titre',
      script: 'Script',
      createdAt: DateTime.utc(2024, 1, 1),
    );

    final restored = HistoryEntry.fromMap(entry.toMap());

    expect(restored.aiFallback, isFalse);
    expect(restored.ttsFallback, isFalse);
  });
}
