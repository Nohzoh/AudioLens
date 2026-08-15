import 'package:flutter/foundation.dart';

class AppLogger {
  static const int _maxLines = 500;
  static final List<String> _buffer = [];
  static final List<VoidCallback> _listeners = [];

  static void log(String tag, String message) {
    final now = DateTime.now();
    final time = '${now.hour.toString().padLeft(2,'0')}:'
        '${now.minute.toString().padLeft(2,'0')}:'
        '${now.second.toString().padLeft(2,'0')}';
    final line = '[$time] [$tag] $message';

    _buffer.add(line);
    if (_buffer.length > _maxLines) _buffer.removeAt(0);

    debugPrint(line);
    for (final l in _listeners) {
      l();
    }
  }

  static void info(String message) => log('INFO', message);
  static void error(String message) => log('ERROR', message);
  static void tts(String message) => log('TTS', message);
  static void ai(String message) => log('AI', message);
  static void gps(String message) => log('GPS', message);
  static void db(String message) => log('DB', message);

  static List<String> get lines => List.unmodifiable(_buffer);

  static String get allLogs => _buffer.join('\n');

  static void clear() {
    _buffer.clear();
    for (final l in _listeners) {
      l();
    }
  }

  static void addListener(VoidCallback listener) => _listeners.add(listener);
  static void removeListener(VoidCallback listener) => _listeners.remove(listener);
}
