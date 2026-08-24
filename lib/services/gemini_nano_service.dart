import 'dart:io';
import 'package:flutter/services.dart';
import '../utils/cancel_token.dart';
import '../utils/script_validation.dart';
import 'ai_service.dart';
import 'remote_config_service.dart';

const _channel = MethodChannel('audio_guide/gemini_nano');

/// Thrown when the on-device AICore API rejects a request because the app
/// isn't in the foreground (observed as the native SDK's "[ErrorCode 30]
/// Background usage is blocked" message) — unlike the cloud API, Gemini
/// Nano inference is an OS-enforced foreground-only operation, so this
/// can't be worked around, only reported clearly (see
/// AudioGuideService.analyzeAndPlay's handling).
class GeminiNanoBackgroundRestrictedException implements Exception {
  const GeminiNanoBackgroundRestrictedException();

  @override
  String toString() => 'Gemini Nano ne peut pas être utilisé en arrière-plan.';
}

class GeminiNanoService implements AIService {
  bool _initialized = false;

  @override
  String get displayName => 'Gemini Nano (on-device)';

  @override
  Future<bool> isAvailable() async {
    try {
      final result = await _channel.invokeMethod<bool>('isAvailable');
      return result ?? false;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> initialize() async {
    if (_initialized) return;
    await _channel.invokeMethod('initialize');
    _initialized = true;
  }

  @override
  Future<AudioGuideResult> analyzeImage(
    File imageFile, {
    String? locationContext,
    CancelToken? cancelToken,
    String? style,
  }) async {
    if (!_initialized) await initialize();

    try {
      final args = {'imagePath': imageFile.path};
      if (locationContext != null) args['locationContext'] = locationContext;
      if (style != null) args['style'] = style;

      final description = await _channel.invokeMethod<String>(
        'describeImage',
        args,
      );

      final text = description ?? '';
      final title = _extractTitle(text);

      return AudioGuideResult(
        title: title,
        // T117: applied here too, so the cap can't drift into being a
        // cloud-only safeguard the way other post-processing already has
        // (see the pipeline-parity issues) — Nano's 3x256-token budget
        // makes it unlikely to run long today, but that's a property of
        // the current config, not a guarantee.
        script: capScriptLength(text, maxChars: RemoteConfigService.current.scriptMaxChars),
      );
    } on PlatformException catch (e) {
      if (e.message?.contains('Background usage is blocked') ?? false) {
        throw const GeminiNanoBackgroundRestrictedException();
      }
      throw Exception('Gemini Nano: ${e.message}');
    }
  }

  String _extractTitle(String description) {
    final first = description.split('.').first.trim();
    return first.length > 50 ? '${first.substring(0, 50)}...' : first;
  }

  @override
  void dispose() {
    _initialized = false;
  }
}
