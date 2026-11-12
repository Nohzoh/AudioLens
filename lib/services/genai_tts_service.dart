import 'package:flutter/services.dart';

/// #485: one voice of ML Kit's on-device generative Text to Speech, with
/// the status of its model on this device.
class GenAiVoice {
  final String name;

  /// `available`, `downloadable`, `downloading`, `unavailable`, or an
  /// error label.
  final String status;

  /// Locale and gender, e.g. `fr-FR, female`.
  final String details;

  /// `female`, `male` or `unknown`.
  final String gender;

  /// The voice's name inside Google's TTS engine, when it could be read
  /// — what the app's native voice would have to select to use it.
  final String? engineName;

  const GenAiVoice({
    required this.name,
    required this.status,
    required this.details,
    this.gender = 'unknown',
    this.engineName,
  });
}

/// #485: what one synthesis attempt produced, as observed on the device.
class GenAiTtsProbe {
  final String? voice;
  final int textLength;

  /// Status updates and milestones, each prefixed with its time in ms.
  final List<String> events;
  final int chunkCount;
  final List<int> chunkSizes;
  final int totalBytes;
  final int? firstChunkMs;

  /// When the engine reported the start and the end of playback.
  final int? startMs;
  final int? doneMs;

  /// Audio bytes per second of playback. The library does not say what
  /// format its audio is in; for 16-bit mono PCM this is twice the sample
  /// rate (48000 for 24 kHz).
  int? get bytesPerSecond {
    if (startMs == null || doneMs == null || doneMs! <= startMs! || totalBytes == 0) {
      return null;
    }
    return (totalBytes * 1000 / (doneMs! - startMs!)).round();
  }

  /// First 16 bytes of the audio, in hex — enough to tell a WAV header
  /// from raw PCM.
  final String? firstBytesHex;
  final int totalMs;

  /// Raw audio bytes as received, in the app's cache, when any came.
  final String? audioFile;
  final String? error;

  const GenAiTtsProbe({
    required this.voice,
    required this.textLength,
    required this.events,
    required this.chunkCount,
    required this.chunkSizes,
    required this.totalBytes,
    required this.firstChunkMs,
    this.startMs,
    this.doneMs,
    required this.firstBytesHex,
    required this.totalMs,
    required this.audioFile,
    required this.error,
  });

  factory GenAiTtsProbe.fromMap(Map<dynamic, dynamic> map) => GenAiTtsProbe(
        voice: map['voice'] as String?,
        textLength: (map['textLength'] as num?)?.toInt() ?? 0,
        events: (map['events'] as List? ?? const []).cast<String>(),
        chunkCount: (map['chunkCount'] as num?)?.toInt() ?? 0,
        chunkSizes: (map['chunkSizes'] as List? ?? const [])
            .map((e) => (e as num).toInt())
            .toList(),
        totalBytes: (map['totalBytes'] as num?)?.toInt() ?? 0,
        firstChunkMs: (map['firstChunkMs'] as num?)?.toInt(),
        startMs: (map['startMs'] as num?)?.toInt(),
        doneMs: (map['doneMs'] as num?)?.toInt(),
        firstBytesHex: map['firstBytesHex'] as String?,
        totalMs: (map['totalMs'] as num?)?.toInt() ?? 0,
        audioFile: map['audioFile'] as String?,
        error: map['error'] as String?,
      );

  /// Plain-text report, for copying into an issue.
  String describe() {
    final buffer = StringBuffer()
      ..writeln('GenAI TTS probe')
      ..writeln('Voice: ${voice ?? 'none'}')
      ..writeln('Text length: $textLength chars')
      ..writeln('Total: $totalMs ms')
      ..writeln('First audio chunk: ${firstChunkMs == null ? 'none' : '$firstChunkMs ms'}')
      ..writeln('Chunks: $chunkCount, $totalBytes bytes')
      ..writeln('Chunk sizes: ${chunkSizes.join(', ')}')
      ..writeln('First bytes: ${firstBytesHex ?? 'none'}')
      ..writeln('Playback: ${startMs == null || doneMs == null ? 'unknown' : '$startMs to $doneMs ms'}')
      ..writeln('Bytes per second of playback: ${bytesPerSecond ?? 'unknown'}')
      ..writeln('Error: ${error ?? 'none'}')
      ..writeln('Events:');
    for (final event in events) {
      buffer.writeln('  $event');
    }
    return buffer.toString();
  }
}

/// #485: probe of ML Kit's on-device generative Text to Speech
/// (`GenAiTtsPlugin.kt`). Used by the Voice Lab only; the guide's voice
/// chain does not use it yet.
class GenAiTtsService {
  static const _channel = MethodChannel('audio_guide/genai_tts');

  /// Voices offered for [locale] (a BCP 47 tag such as `fr-FR`). Throws
  /// if the platform call fails — typically an unsupported device.
  Future<List<GenAiVoice>> voices(String locale) async {
    final raw = await _channel.invokeListMethod<Map>('voices', {'locale': locale}) ?? [];
    return [
      for (final v in raw)
        GenAiVoice(
          name: v['name'] as String? ?? '',
          status: v['status'] as String? ?? 'unknown',
          details: v['details'] as String? ?? '',
          gender: v['gender'] as String? ?? 'unknown',
          engineName: v['engineName'] as String?,
        ),
    ];
  }

  /// #485: name of a generative voice ready to use on this device for
  /// [locale] and [gender] (`female`/`male`), or null — no such voice,
  /// its model not installed, or a device without this feature. The name
  /// is the one Android's speech engine knows the voice by.
  Future<String?> availableVoiceName(String locale, String gender) async {
    try {
      final all = await voices(locale);
      for (final voice in all) {
        if (voice.status == 'available' && voice.gender == gender) return voice.name;
      }
    } catch (_) {
      // Unsupported device, or no platform side (tests): no such voice.
    }
    return null;
  }

  /// Downloads [voice]'s model; returns the download statuses seen.
  Future<List<String>> download(String locale, String voice) async {
    final raw = await _channel
            .invokeListMethod<String>('download', {'locale': locale, 'voice': voice}) ??
        [];
    return raw;
  }

  Future<GenAiTtsProbe> probe({
    required String locale,
    required String voice,
    required String text,
  }) async {
    final raw = await _channel.invokeMapMethod<dynamic, dynamic>(
        'probe', {'locale': locale, 'voice': voice, 'text': text});
    return GenAiTtsProbe.fromMap(raw ?? const {});
  }

  Future<void> stop() => _channel.invokeMethod('stop');

  /// #501: stack trace left by a probe that crashed the app, or null.
  Future<String?> lastCrash() => _channel.invokeMethod<String>('lastCrash');

  Future<void> clearCrash() => _channel.invokeMethod('clearCrash');
}
