import '../models/guide_error.dart';
import '../utils/app_logger.dart';
import '../utils/cancel_token.dart';
import '../utils/error_sanitizer.dart';
import 'gemini_tts_service.dart';
import 'tts_service.dart';

/// Speaks a script via Gemini TTS (cloud) when available, falling back to
/// Piper (local) on failure (T06 — extracted from
/// AudioGuideService.analyzeAndPlay).
class TtsOrchestrator {
  TtsOrchestrator({required this.piper});

  final TtsService piper;

  /// Speaks [script]. Returns the model actually used ('gemini-tts' or
  /// 'piper'). Throws [GuideError] if both engines fail.
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
}
