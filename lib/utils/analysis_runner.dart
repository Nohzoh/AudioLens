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
    await history.failEntry(entryId);
  }
}
