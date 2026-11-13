import 'package:flutter/services.dart';

/// #551: whether the phone is on an unmetered connection (Wi-Fi).
class NetworkStatus {
  static const _channel = MethodChannel('audio_guide/network');

  /// Null when it can't tell (tests, older builds).
  static Future<bool?> isUnmetered() async {
    try {
      return await _channel.invokeMethod<bool>('isUnmetered');
    } catch (_) {
      return null;
    }
  }
}
