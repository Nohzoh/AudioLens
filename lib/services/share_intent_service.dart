import 'package:flutter/services.dart';

/// Bridges native ACTION_SEND photo-share intents to Dart (T97) — lets
/// AudioLens appear in Android's "Share via..." sheet from other apps
/// (Gallery, another photo viewer, etc.) instead of only being reachable
/// by opening the app first and picking from the gallery. See
/// MainActivity.kt/SharePlugin.kt for the native side.
class ShareIntentService {
  static const _methodChannel = MethodChannel('audio_guide/share_intent');
  static const _eventChannel = EventChannel('audio_guide/share_intent_stream');

  /// The shared image path if the app was cold-started via a share
  /// intent, or null otherwise. Only meaningful once, right after app
  /// startup — the native side clears it after this call so a later
  /// hot-reload/rebuild doesn't replay the same share.
  static Future<String?> getInitialSharedImage() async {
    try {
      return await _methodChannel
          .invokeMethod<String>('getInitialSharedImage');
    } catch (_) {
      return null;
    }
  }

  /// Fires with the image path whenever a photo is shared to AudioLens
  /// while the app is already running (warm start).
  static Stream<String> get sharedImageStream =>
      _eventChannel.receiveBroadcastStream().map((event) => event as String);
}
