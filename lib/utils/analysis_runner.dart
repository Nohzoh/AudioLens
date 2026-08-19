import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../screens/player_screen.dart';
import '../services/audio_guide_service.dart';
import '../services/history_service.dart';
import '../services/settings_service.dart';
import 'app_logger.dart';

/// Runs the full analysis pipeline for [imageFile], persists the result to
/// the [entryId] history entry, and navigates to [PlayerScreen] to show
/// progress. Shared between home_screen.dart (new photo, retry) and
/// history_screen.dart (retry, launching the analysis for a captured
/// entry — T78) so this isn't duplicated per call site.
Future<void> runAnalysisAndNavigate({
  required BuildContext context,
  required File imageFile,
  required int entryId,
  required String source,
  ({double lat, double lon, String source})? knownCoordinates,
  bool deleteImageOnDispose = false,
}) async {
  final guide = context.read<AudioGuideService>();
  final history = context.read<HistoryService>();
  final settings = context.read<SettingsService>();

  Navigator.push(context, MaterialPageRoute(
    builder: (_) => PlayerScreen(
      imageFile: imageFile,
      deleteImageOnDispose: deleteImageOnDispose,
    ),
  ));

  final result = await guide.analyzeAndPlay(
    imageFile,
    generateAudio: settings.autoGenerateAudio,
    knownCoordinates: knownCoordinates,
    style: settings.scriptStyle,
    entryId: entryId,
  );

  AppLogger.info('result: ${result?.title}');
  AppLogger.info('aiModel: ${guide.actualAiModel} / ${guide.lastAiModel}');
  AppLogger.info('gpsSource: ${guide.lastGpsSource}');
  AppLogger.info('gpsLat: ${guide.lastGpsLatitude}');
  AppLogger.info('wikipedia: ${guide.lastWikipediaUsed}');
  AppLogger.info('duration: ${guide.lastAnalysisDurationMs}');

  if (result != null) {
    await history.completeEntry(
      entryId: entryId,
      title: result.title,
      script: result.script,
      locationName: result.locationName,
      aiModel: guide.actualAiModel ?? guide.lastAiModel,
      analysisSource: source,
      gpsSource: guide.lastGpsSource,
      wikipediaUsed: guide.lastWikipediaUsed,
      analysisDurationMs: guide.lastAnalysisDurationMs,
      gpsLatitude: guide.lastGpsLatitude,
      gpsLongitude: guide.lastGpsLongitude,
      gpsAddress: guide.lastGpsAddress,
      aiFallback: guide.aiModelWasFallback,
      ttsFallback: guide.ttsWasFallback,
    );
    final audioPath = guide.lastAudioPath;
    if (audioPath != null) {
      await history.saveAudioPath(entryId, audioPath, ttsModel: guide.lastTtsModel);
    }
  } else {
    // Persist whatever location was actually resolved for this attempt
    // (even though the analysis itself failed) so a retry can reuse it —
    // see HistoryService.failEntry's doc.
    await history.failEntry(
      entryId,
      gpsLatitude: guide.lastGpsLatitude,
      gpsLongitude: guide.lastGpsLongitude,
      gpsSource: guide.lastGpsSource,
    );
  }
}

/// Builds [AudioGuideService.analyzeAndPlay]'s `knownCoordinates` param
/// from a history entry's saved GPS fields, if any — shared by every
/// retry/re-launch flow (T78 captured entries, a failed analysis retry) so
/// a previously resolved location (live GPS, EXIF, or a manually picked
/// map point) is reused instead of re-resolving the device's current
/// position from scratch.
({double lat, double lon, String source})? knownCoordinatesFromEntry(HistoryEntry entry) {
  if (entry.gpsLatitude == null || entry.gpsLongitude == null) return null;
  return (
    lat: entry.gpsLatitude!,
    lon: entry.gpsLongitude!,
    source: entry.gpsSource ?? 'realtime',
  );
}
