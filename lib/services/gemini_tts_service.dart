import 'dart:convert';
import 'dart:io';
import '../utils/app_logger.dart';
import '../utils/cancel_token.dart';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'remote_config_service.dart';

class GeminiTtsService {
  final String apiKey;
  final http.Client _client;
  Function()? onComplete;
  bool _isPlaying = false;
  String? _lastWavPath;
  String? get lastWavPath => _lastWavPath;

  bool get isPlaying => _isPlaying;

  /// [client] allows injecting a mock HTTP client in tests.
  GeminiTtsService({required this.apiKey, http.Client? client})
      : _client = client ?? http.Client();

  Future<void> speak(String text, {CancelToken? cancelToken}) async {
    // Check cancellation before starting
    if (cancelToken?.isCancelled ?? false) {
      return;
    }

    final tmpDir = await getTemporaryDirectory();
    final wavPath = p.join(tmpDir.path, 'gemini_tts_output.wav');
    await synthesizeToFile(text, wavPath);

    AppLogger.tts('Gemini TTS playing $wavPath...');
    _isPlaying = true;
    const channel = MethodChannel('audio_guide/audio_player');
    channel.invokeMethod('playWav', {'path': wavPath}).then((_) {
      _isPlaying = false;
      onComplete?.call();
    });
  }

  /// Synthesizes [text] and writes the resulting WAV to [outputPath],
  /// without playing it (T76 — chunked playback synthesizes the next
  /// chunk while the previous one is still playing).
  Future<void> synthesizeToFile(String text, String outputPath) async {
    final started = DateTime.now();
    AppLogger.tts('synthesizeToFile start -> $outputPath (${text.length} chars)');
    final cfg = RemoteConfigService.current;

    // Add audio guide style instruction to the TTS prompt
    final styledText =
        '[Voix chaleureuse et passionnée d\'un guide de musée, '
        'ton vivant et expressif, rythme posé] $text';

    final uri = Uri.parse(
      '${cfg.geminiApiUrl}/models/${cfg.geminiTtsModel}:generateContent'
      '?key=$apiKey',
    );
    final body = jsonEncode({
      'contents': [
        {
          'parts': [
            {'text': styledText}
          ]
        }
      ],
      'generationConfig': {
        'responseModalities': ['AUDIO'],
        'speechConfig': {
          'voiceConfig': {
            'prebuiltVoiceConfig': {
              'voiceName': cfg.geminiTtsVoice,
            }
          }
        }
      },
    });

    var response = await _client
        .post(uri, headers: {'Content-Type': 'application/json'}, body: body)
        .timeout(const Duration(seconds: 60));

    // A single chunk hitting a transient rate limit shouldn't force the
    // rest of the script into a different voice (Piper) — retry once
    // after a short delay before giving up.
    if (response.statusCode == 429) {
      AppLogger.tts('synthesizeToFile got 429, retrying once in 1.5s');
      await Future.delayed(const Duration(milliseconds: 1500));
      response = await _client
          .post(uri, headers: {'Content-Type': 'application/json'}, body: body)
          .timeout(const Duration(seconds: 60));
    }

    if (response.statusCode != 200) {
      AppLogger.error('Gemini TTS error: ${response.statusCode}');
      throw Exception(
        'La synthèse vocale a échoué (${response.statusCode}). '
        'Vous pouvez réessayer ou utiliser une autre voix/option.',
      );
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final audioData = data['candidates']?[0]?['content']?['parts']?[0]
        ?['inlineData']?['data'] as String?;

    if (audioData == null) {
      throw Exception('Gemini TTS: pas de données audio dans la réponse');
    }

    // Decode base64 PCM data and wrap in WAV
    final pcmBytes = base64Decode(audioData);
    final wavBytes = _pcmToWav(pcmBytes, sampleRate: 24000);

    await File(outputPath).writeAsBytes(wavBytes);
    _lastWavPath = outputPath;
    final elapsed = DateTime.now().difference(started).inMilliseconds;
    AppLogger.tts('synthesizeToFile done -> $outputPath: ${pcmBytes.length} bytes in ${elapsed}ms');
  }

  /// Plays an already-synthesized WAV file, awaiting playback completion
  /// (T76). Unlike [speak], this genuinely waits — needed to sequence
  /// chunks one after another. [notifyComplete] should be false for every
  /// chunk but the last, so [onComplete] fires only once, when the whole
  /// script has actually finished playing.
  Future<void> playFile(String path, {bool notifyComplete = true}) async {
    final started = DateTime.now();
    AppLogger.tts('playFile start -> $path');
    _isPlaying = true;
    const channel = MethodChannel('audio_guide/audio_player');
    try {
      await channel.invokeMethod('playWav', {'path': path});
    } finally {
      _isPlaying = false;
    }
    final elapsed = DateTime.now().difference(started).inMilliseconds;
    AppLogger.tts('playFile done -> $path (${elapsed}ms)');
    if (notifyComplete) onComplete?.call();
  }

  /// Concatenates WAV files produced by [synthesizeToFile] (same PCM
  /// format) into a single file at [outputPath] (T76 — after chunked
  /// playback finishes, so the result can still be cached like a normal
  /// single-shot synthesis).
  static Future<void> concatenateWavFiles(List<String> paths, String outputPath) async {
    final pcmParts = <int>[];
    for (final path in paths) {
      final bytes = await File(path).readAsBytes();
      if (bytes.length > 44) pcmParts.addAll(bytes.sublist(44));
    }
    final wavBytes = _pcmToWav(Uint8List.fromList(pcmParts), sampleRate: 24000);
    await File(outputPath).writeAsBytes(wavBytes);
  }

  /// Wraps raw PCM 16-bit mono data in a WAV header
  static Uint8List _pcmToWav(Uint8List pcm, {int sampleRate = 24000}) {
    final dataSize = pcm.length;
    final buffer = ByteData(44 + dataSize);

    void setStr(int offset, String s) {
      for (int i = 0; i < s.length; i++) {
        buffer.setUint8(offset + i, s.codeUnitAt(i));
      }
    }

    setStr(0, 'RIFF');
    buffer.setUint32(4, 36 + dataSize, Endian.little);
    setStr(8, 'WAVE');
    setStr(12, 'fmt ');
    buffer.setUint32(16, 16, Endian.little);   // chunk size
    buffer.setUint16(20, 1, Endian.little);    // PCM
    buffer.setUint16(22, 1, Endian.little);    // mono
    buffer.setUint32(24, sampleRate, Endian.little);
    buffer.setUint32(28, sampleRate * 2, Endian.little); // byte rate
    buffer.setUint16(32, 2, Endian.little);    // block align
    buffer.setUint16(34, 16, Endian.little);   // bits per sample
    setStr(36, 'data');
    buffer.setUint32(40, dataSize, Endian.little);

    final result = buffer.buffer.asUint8List();
    result.setRange(44, 44 + dataSize, pcm);
    return result;
  }

  Future<void> pause() async {
    const channel = MethodChannel('audio_guide/audio_player');
    await channel.invokeMethod('pause');
    _isPlaying = false;
  }

  Future<void> stop() async {
    const channel = MethodChannel('audio_guide/audio_player');
    await channel.invokeMethod('stop');
    _isPlaying = false;
  }
}
