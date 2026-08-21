import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:audiolens/services/history_service.dart';

void main() {
  test('HistoryEntry exposes derived flags and estimate', () {
    final tempDir = Directory.systemTemp.createTempSync('history-entry-test');
    final audioFile = File('${tempDir.path}/audio.wav');
    audioFile.writeAsStringSync('audio');

    final entry = HistoryEntry(
      imagePath: '/tmp/photo.jpg',
      title: 'Titre',
      script: 'script',
      createdAt: DateTime.utc(2024, 1, 1),
      status: AnalysisStatus.complete,
      audioPath: audioFile.path,
      wordCount: 180,
      ttsModel: 'piper',
    );

    expect(entry.hasAudio, isTrue);
    expect(entry.isPending, isFalse);
    expect(entry.hasLowQualityTts, isTrue);
    expect(entry.audioDurationEstimate, '~1min 12s');

    tempDir.deleteSync(recursive: true);
  });

  test('hasLowQualityTts (T133): covers legacy piper and native-tts-fallback, '
      'not a genuine native-tts choice or a plain gemini-tts entry', () {
    HistoryEntry entry({String? ttsModel, String? audioPath, bool ttsFallback = false}) =>
        HistoryEntry(
          imagePath: '/tmp/photo.jpg',
          title: 'Titre',
          script: 'script',
          createdAt: DateTime.utc(2024, 1, 1),
          ttsModel: ttsModel,
          audioPath: audioPath,
          ttsFallback: ttsFallback,
        );

    // Legacy piper entry with its cached file — upgradeable.
    expect(entry(ttsModel: 'piper', audioPath: '/tmp/a.wav').hasLowQualityTts, isTrue);
    // native-tts because Gemini TTS failed at analysis time — upgradeable,
    // even with no cached file (native TTS never caches).
    expect(entry(ttsModel: 'native-tts', ttsFallback: true).hasLowQualityTts, isTrue);
    // native-tts genuinely chosen (no fallback) — nothing to upgrade from.
    expect(entry(ttsModel: 'native-tts', ttsFallback: false).hasLowQualityTts, isFalse);
    // Already the good voice.
    expect(entry(ttsModel: 'gemini-tts').hasLowQualityTts, isFalse);
    // A piper ttsModel with no cached file left (deleted/missing) — same
    // as before T133, still not upgradeable without a file to replace.
    expect(entry(ttsModel: 'piper').hasLowQualityTts, isFalse);
  });

  test('HistoryEntry.fromMap and toMap round-trip data', () {
    final entry = HistoryEntry(
      id: 7,
      imagePath: '/tmp/photo.jpg',
      title: 'Titre',
      script: 'script',
      locationName: 'Paris',
      createdAt: DateTime.utc(2024, 1, 1, 12, 30),
      status: AnalysisStatus.failed,
      aiModel: 'gemini-nano',
      gpsSource: 'exif',
      wikipediaUsed: true,
      wordCount: 120,
      analysisDurationMs: 2500,
      gpsLatitude: 48.8,
      gpsLongitude: 2.3,
      gpsAddress: 'Paris',
    );

    final map = entry.toMap();
    final restored = HistoryEntry.fromMap(map);

    expect(restored.id, entry.id);
    expect(restored.title, entry.title);
    expect(restored.locationName, entry.locationName);
    expect(restored.status, AnalysisStatus.failed);
    expect(restored.wikipediaUsed, isTrue);
    expect(restored.gpsSource, 'exif');
    expect(restored.gpsLatitude, 48.8);
  });
}
