import 'package:flutter/services.dart';

/// Wraps the native Android foreground service that protects the app
/// process's priority while an analysis is in flight (T85) — without it,
/// Android can kill the whole process while backgrounded, silently
/// dropping an in-progress analysis. Best-effort by design: a
/// foreground-service hiccup must never break the actual analysis, and
/// platforms without this concept (iOS, or tests with no platform mock)
/// should just no-op rather than throw.
class AnalysisForegroundService {
  static const _channel = MethodChannel('audio_guide/foreground_service');

  Future<void> start() async {
    try {
      await _channel.invokeMethod('start');
    } catch (_) {
      // Best-effort — see class doc.
    }
  }

  Future<void> stop() async {
    try {
      await _channel.invokeMethod('stop');
    } catch (_) {
      // Best-effort — see class doc.
    }
  }
}
