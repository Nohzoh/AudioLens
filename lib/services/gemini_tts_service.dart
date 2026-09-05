import 'dart:async';
import 'dart:convert';
import 'dart:io';
import '../utils/app_logger.dart';
import '../utils/cancel_token.dart';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:dio/dio.dart' as dio;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'remote_config_service.dart';

/// Thrown when Gemini TTS still returns 429 after the retry in
/// [GeminiTtsService.synthesizeToFile] is exhausted. A distinct type from
/// other synthesis failures so callers can tell "rate-limited" apart from
/// e.g. a network error or a malformed response, and show the user an
/// accurate reason for the native TTS fallback instead of a generic one.
class GeminiTtsRateLimitException implements Exception {
  const GeminiTtsRateLimitException();

  @override
  String toString() => 'La synthèse vocale a échoué (429). '
      'Vous pouvez réessayer ou utiliser une autre voix/option.';
}

class GeminiTtsService {
  /// Backoff schedule for retrying a 429 in [synthesizeToFile] — each
  /// entry is the wait before that attempt.
  ///
  /// Was briefly a 2-step schedule (2s, 5s) to cover longer rate-limit
  /// windows, but real-device logs showed retries essentially never
  /// succeeding once 429 hit (0/5 across two real sessions) — the extra
  /// wait was pure latency with no payoff. Cut back to one quick check,
  /// and the real fix for actually avoiding 429 is fewer/larger TTS
  /// chunks (see chunkScript's chunkMaxChars).
  static const _retryDelaysOn429 = [
    Duration(milliseconds: 1500),
  ];

  final String apiKey;
  final dio.Dio _dio;
  Function()? onComplete;
  bool _isPlaying = false;
  String? _lastWavPath;
  String? get lastWavPath => _lastWavPath;

  bool get isPlaying => _isPlaying;

  /// #329 follow-up: the first version of this estimated progress from a
  /// words-per-second speaking rate (the same heuristic
  /// HistoryEntry.audioDurationEstimate uses for duration display) —
  /// live use showed real Gemini TTS speech doesn't actually speak at
  /// that rate consistently enough, so the estimate visibly drifted from
  /// the audio over a whole script, worst right at the end (audio
  /// finished, highlighted text stuck partway through). Polls the real
  /// MediaPlayer position instead (AudioPlayerPlugin.kt's "getPosition"),
  /// which is also simpler: pause/seek need no special handling here,
  /// since the native position itself already reflects them (it doesn't
  /// advance while paused, and seekForward/seekBack already move it).
  Function(double progress)? onProgress;
  Timer? _progressTimer;

  void _startProgressPolling() {
    _progressTimer?.cancel();
    const channel = MethodChannel('audio_guide/audio_player');
    _progressTimer = Timer.periodic(const Duration(milliseconds: 200), (_) async {
      try {
        final result = await channel.invokeMethod<Map>('getPosition');
        final position = (result?['position'] as num?)?.toInt() ?? -1;
        final duration = (result?['duration'] as num?)?.toInt() ?? -1;
        if (position < 0 || duration <= 0) return;
        onProgress?.call((position / duration).clamp(0.0, 1.0));
      } catch (_) {
        // Best-effort — a progress bar hiccup must never disrupt playback.
      }
    });
  }

  void _stopProgressPolling() {
    _progressTimer?.cancel();
    _progressTimer = null;
  }

  /// [dioClient] allows injecting a mock Dio instance in tests — see
  /// `test/support/fake_dio_adapter.dart`.
  GeminiTtsService({required this.apiKey, dio.Dio? dioClient})
      : _dio = dioClient ?? dio.Dio();

  /// [speed] is passed to the native WAV player (T15) — MediaPlayer's
  /// PlaybackParams, applied natively since the Gemini TTS engine only
  /// produces a pre-rendered file, unlike native TTS's live synthesis.
  Future<void> speak(String text, {CancelToken? cancelToken, double speed = 1.0}) async {
    // Check cancellation before starting
    if (cancelToken?.isCancelled ?? false) {
      return;
    }

    final tmpDir = await getTemporaryDirectory();
    final wavPath = p.join(tmpDir.path, 'gemini_tts_output.wav');
    await synthesizeToFile(text, wavPath, cancelToken: cancelToken);

    AppLogger.tts('Gemini TTS playing $wavPath...');
    _isPlaying = true;
    _startProgressPolling();
    const channel = MethodChannel('audio_guide/audio_player');
    channel.invokeMethod('playWav', {'path': wavPath, 'speed': speed}).then((_) {
      _isPlaying = false;
      _stopProgressPolling();
      onComplete?.call();
    });
  }

  /// Synthesizes [text] and writes the resulting WAV to [outputPath],
  /// without playing it (T76 — chunked playback synthesizes the next
  /// chunk while the previous one is still playing).
  Future<void> synthesizeToFile(
    String text,
    String outputPath, {
    CancelToken? cancelToken,
  }) async {
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

    var response = await _post(uri, body: body, cancelToken: cancelToken);

    // A chunk hitting a rate limit shouldn't force the rest of the script
    // into a different voice than the one the user is hearing — retry
    // with backoff before giving up. A single 1.5s retry wasn't enough in
    // practice (two consecutive 429s ~1.5s apart, observed on a real
    // device) — this covers longer rate-limit windows at the cost of
    // extra wait only when it's actually still being throttled.
    for (final delay in _retryDelaysOn429) {
      if (response.statusCode != 429) break;
      AppLogger.tts('synthesizeToFile got 429, retrying in ${delay.inSeconds}s');
      await Future.delayed(delay);
      response = await _post(uri, body: body, cancelToken: cancelToken);
    }

    if (response.statusCode != 200) {
      AppLogger.error('Gemini TTS error: ${response.statusCode}');
      if (response.statusCode == 429) {
        throw const GeminiTtsRateLimitException();
      }
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

  /// Posts [body] via dio, whose [dio.CancelToken] actually aborts the
  /// in-flight request when [cancelToken] cancels — unlike the old `http`
  /// client + `Future.timeout` combo, which stopped *waiting* but left a
  /// chunk's synthesis running in the background regardless (T70).
  Future<({int statusCode, String body})> _post(
    Uri uri, {
    required String body,
    CancelToken? cancelToken,
  }) async {
    final dioToken = dio.CancelToken();
    cancelToken?.onCancel.then((_) => dioToken.cancel());
    try {
      final resp = await _dio
          .postUri<String>(
            uri,
            data: body,
            cancelToken: dioToken,
            options: dio.Options(
              headers: {'Content-Type': 'application/json'},
              responseType: dio.ResponseType.plain,
              validateStatus: (_) => true,
            ),
          )
          .timeout(
            const Duration(seconds: 60),
            onTimeout: () {
              dioToken.cancel();
              throw TimeoutException('Gemini TTS: délai dépassé');
            },
          );
      return (statusCode: resp.statusCode ?? 0, body: resp.data ?? '');
    } on dio.DioException catch (e) {
      if (e.type == dio.DioExceptionType.cancel) {
        throw const CancelledException();
      }
      rethrow;
    }
  }

  /// Plays an already-synthesized WAV file, awaiting playback completion
  /// (T76). Unlike [speak], this genuinely waits — needed to sequence
  /// chunks one after another. [notifyComplete] should be false for every
  /// chunk but the last, so [onComplete] fires only once, when the whole
  /// script has actually finished playing.
  Future<void> playFile(
    String path, {
    bool notifyComplete = true,
    double speed = 1.0,
  }) async {
    final started = DateTime.now();
    AppLogger.tts('playFile start -> $path');
    _isPlaying = true;
    const channel = MethodChannel('audio_guide/audio_player');
    try {
      await channel.invokeMethod('playWav', {'path': path, 'speed': speed});
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
    // Progress polling deliberately keeps running — MediaPlayer's
    // currentPosition simply stops advancing while paused, no special
    // handling needed to keep the reported progress correctly frozen.
  }

  /// #329: previously handled by AudioGuideService.togglePause() poking
  /// the platform channel directly (mirrored pause()/stop()/skipForward()/
  /// skipBack(), all of which already went through this class) — pulled
  /// in here too for consistency.
  Future<void> resume() async {
    const channel = MethodChannel('audio_guide/audio_player');
    await channel.invokeMethod('play');
    _isPlaying = true;
  }

  Future<void> stop() async {
    const channel = MethodChannel('audio_guide/audio_player');
    await channel.invokeMethod('stop');
    _isPlaying = false;
    _stopProgressPolling();
  }

  /// T118/T21 — skip ±10s within the currently playing cached WAV
  /// (matches Icons.replay_10/forward_10 in player_screen.dart — no
  /// _15 variant exists in the Material icon set). Meaningless for
  /// native (on-device) TTS's live synthesis, so this only exists on
  /// the Gemini/cached-audio path (see
  /// AudioGuideService.skipForward/skipBack for the engine gating).
  static const _skipMs = 10000;

  Future<void> skipForward() async {
    const channel = MethodChannel('audio_guide/audio_player');
    await channel.invokeMethod('seekForward', {'deltaMs': _skipMs});
    // The next poll tick (≤200ms away) picks up the new real position —
    // no manual offset bookkeeping needed, unlike the estimate this
    // replaced.
  }

  Future<void> skipBack() async {
    const channel = MethodChannel('audio_guide/audio_player');
    await channel.invokeMethod('seekBack', {'deltaMs': _skipMs});
  }
}
