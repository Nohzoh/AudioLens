import 'dart:io';
import '../utils/cancel_token.dart';

class AudioGuideResult {
  final String title;
  final String script;
  final String? locationName;

  const AudioGuideResult({
    required this.title,
    required this.script,
    this.locationName,
  });
}

abstract class AIService {
  String get displayName;
  Future<bool> isAvailable();
  Future<void> initialize();
  /// [cancelToken] lets the caller actually abort an in-flight cloud
  /// request (T70) — implementations that don't make cancellable network
  /// calls (e.g. on-device inference) may ignore it.
  Future<AudioGuideResult> analyzeImage(
    File imageFile, {
    String? locationContext,
    CancelToken? cancelToken,
  });
  void dispose();
}
