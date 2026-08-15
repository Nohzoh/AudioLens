import 'dart:async';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../models/guide_error.dart';
import '../utils/app_logger.dart';
import '../utils/cancel_token.dart';
import '../utils/error_sanitizer.dart';
import '../utils/text_chunker.dart';
import 'gemini_tts_service.dart';
import 'tts_service.dart';

/// Speaks a script via Gemini TTS (cloud) when available, falling back to
/// Piper (local) on failure (T06 — extracted from
/// AudioGuideService.analyzeAndPlay).
class TtsOrchestrator {
  TtsOrchestrator({required this.piper});

  final TtsService piper;

  /// Speaks [script] in one blocking synthesis call. Returns the model
  /// actually used ('gemini-tts' or 'piper'). Throws [GuideError] if both
  /// engines fail. Prefer [speakChunked], which uses this as its fallback
  /// for scripts too short to chunk or when Gemini TTS isn't configured.
  Future<String> speak(
    String script, {
    required CancelToken cancelToken,
    GeminiTtsService? geminiTts,
  }) async {
    if (geminiTts != null) {
      try {
        geminiTts.onComplete = piper.onComplete;
        await geminiTts.speak(script, cancelToken: cancelToken);
        return 'gemini-tts';
      } catch (ttsError) {
        AppLogger.error('Gemini TTS failed, falling back to Piper: $ttsError');
        try {
          await piper.speak(script, cancelToken: cancelToken);
          return 'piper';
        } catch (fallbackError) {
          throw GuideError(GuideErrorKind.tts,
              'La lecture audio a échoué. ${sanitizeError(fallbackError.toString())}');
        }
      }
    }
    try {
      await piper.speak(script, cancelToken: cancelToken);
      return 'piper';
    } catch (ttsError) {
      throw GuideError(GuideErrorKind.tts, 'La lecture audio a échoué. ${sanitizeError(ttsError.toString())}');
    }
  }

  /// Speaks [script] in streamed chunks via Gemini TTS (T76): synthesizes
  /// the first (short) chunk and starts playing it immediately, then
  /// synthesizes each following chunk while the previous one is still
  /// playing — instead of waiting for the whole script (often ~30s) to be
  /// synthesized before any audio starts.
  ///
  /// Falls back to [speak] (unchanged, single-shot) when there's no Gemini
  /// TTS configured or the script is too short to be worth chunking. If a
  /// chunk fails to synthesize partway through, the remaining text is
  /// spoken via Piper as one block — the already-played chunks stay as
  /// they were (no restart), and the rest is announced consistently in a
  /// single fallback voice rather than bouncing between engines.
  ///
  /// [onChunkStart] is called with the (0-based) index of each chunk as
  /// its playback begins and the total chunk count, e.g. to drive a
  /// "morceau N/M" progress indicator.
  ///
  /// Returns the model used, like [speak].
  Future<String> speakChunked(
    String script, {
    required CancelToken cancelToken,
    GeminiTtsService? geminiTts,
    void Function(int chunkIndex, int totalChunks)? onChunkStart,
  }) async {
    if (geminiTts == null) {
      return speak(script, cancelToken: cancelToken, geminiTts: geminiTts);
    }

    final chunks = chunkScript(script);
    if (chunks.length <= 1) {
      return speak(script, cancelToken: cancelToken, geminiTts: geminiTts);
    }

    final tmpDir = await getTemporaryDirectory();
    final chunkPaths = List.generate(
      chunks.length,
      (i) => p.join(tmpDir.path, 'gemini_tts_chunk_$i.wav'),
    );

    try {
      await geminiTts.synthesizeToFile(chunks[0], chunkPaths[0]);
    } catch (ttsError) {
      AppLogger.error('Gemini TTS (chunk 0) failed, falling back to Piper: $ttsError');
      try {
        await piper.speak(script, cancelToken: cancelToken);
        return 'piper';
      } catch (fallbackError) {
        throw GuideError(GuideErrorKind.tts,
            'La lecture audio a échoué. ${sanitizeError(fallbackError.toString())}');
      }
    }

    geminiTts.onComplete = piper.onComplete;

    for (var i = 0; i < chunks.length; i++) {
      if (cancelToken.isCancelled) return 'gemini-tts';
      onChunkStart?.call(i, chunks.length);

      final isLast = i == chunks.length - 1;
      final hasNext = i + 1 < chunks.length;

      // Synthesize the next chunk while this one plays. The error handler
      // is attached synchronously (via .then's onError, not a later
      // try/catch) so a rejection during the awaited playback below isn't
      // ever briefly unlistened — Dart's zone flags that as an unhandled
      // error even when a try/catch does eventually run.
      final Future<Object?>? nextSynthesisOutcome = hasNext
          ? geminiTts
              .synthesizeToFile(chunks[i + 1], chunkPaths[i + 1])
              .then<Object?>((_) => null, onError: (Object e) => e)
          : null;

      if (isLast) {
        // Match speak()'s contract: don't await final playback, just kick
        // it off — onComplete fires (once) when it actually finishes.
        unawaited(geminiTts.playFile(chunkPaths[i]));
      } else {
        // notifyComplete: false — onComplete must fire only once, for the
        // truly last chunk, not after every intermediate one.
        await Future.any([
          geminiTts.playFile(chunkPaths[i], notifyComplete: false),
          cancelToken.onCancel,
        ]);
        if (cancelToken.isCancelled) return 'gemini-tts';
      }

      if (nextSynthesisOutcome != null) {
        final ttsError = await nextSynthesisOutcome;
        if (ttsError != null) {
          AppLogger.error(
              'Gemini TTS (chunk ${i + 1}) failed, falling back to Piper for the rest: $ttsError');
          final remaining = chunks.sublist(i + 1).join(' ');
          try {
            await piper.speak(remaining, cancelToken: cancelToken);
          } catch (fallbackError) {
            throw GuideError(GuideErrorKind.tts,
                'La lecture audio a échoué. ${sanitizeError(fallbackError.toString())}');
          }
          return 'piper';
        }
      }
    }

    // Every chunk was synthesized via Gemini — concatenate them into the
    // same conventional path speak() would have used, so history caching
    // (AudioGuideService._getLastWavPath) keeps working transparently.
    final combinedPath = p.join(tmpDir.path, 'gemini_tts_output.wav');
    await GeminiTtsService.concatenateWavFiles(chunkPaths, combinedPath);

    return 'gemini-tts';
  }
}
