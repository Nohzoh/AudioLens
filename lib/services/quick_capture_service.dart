import 'package:flutter/services.dart';

/// Bridges the home-screen quick-capture widget's tap to Dart — lets a
/// user jump straight to the camera from a widget instead of opening the
/// app first and pressing "Take a photo". Same shape as
/// ShareIntentService (T97). See MainActivity.kt/QuickCapturePlugin.kt/
/// QuickCaptureWidgetProvider.kt for the native side.
class QuickCaptureService {
  static const _methodChannel = MethodChannel('audio_guide/quick_capture');
  static const _eventChannel = EventChannel('audio_guide/quick_capture_stream');

  /// True if the app was cold-started by a tap on the quick-capture
  /// widget, false otherwise. Only meaningful once, right after app
  /// startup — the native side clears it after this call so a later
  /// hot-reload/rebuild doesn't replay the same tap.
  static Future<bool> consumePendingCapture() async {
    try {
      return await _methodChannel.invokeMethod<bool>('consumePendingCapture') ??
          false;
    } catch (_) {
      return false;
    }
  }

  /// Fires whenever the quick-capture widget is tapped while the app is
  /// already running (warm start).
  static Stream<void> get captureStream =>
      _eventChannel.receiveBroadcastStream().map((_) {});
}
