import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import '../utils/cancel_token.dart';
import '../utils/script_cleanup.dart';
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

    // #169: a cancellation requested before this call even starts must
    // skip it entirely, not silently run anyway.
    if (cancelToken?.isCancelled ?? false) {
      throw const CancelledException();
    }

    try {
      final config = RemoteConfigService.current;
      final args = <String, dynamic>{
        'imagePath': imageFile.path,
        // #170: previously hardcoded in GeminiNanoPlugin.kt — now
        // remote-configurable like the cloud pipeline's own
        // geminiMaxTokens/geminiTemperature, so a stuck value (e.g. a
        // segment truncated too early) can be fixed without an app
        // release, same as #158 was for the cloud side.
        'maxOutputTokens': config.geminiNanoMaxTokens,
        'temperature': config.geminiNanoTemperature,
      };
      if (locationContext != null) {
        args['locationContext'] = _truncateLocationContext(locationContext);
      }
      if (style != null) args['style'] = style;

      // The 3 segments (visual description, historical context,
      // conclusion) run sequentially inside one native describeImage
      // call, not as 3 separate platform-channel calls — so unlike the
      // cloud pipeline's per-request dio CancelToken, there's no
      // in-flight native work Dart can actually interrupt mid-call.
      // Racing against cancelToken.onCancel at least stops *waiting* on
      // it as soon as cancellation is requested, instead of the
      // cancellation silently doing nothing until the whole call
      // eventually finishes on its own (#169).
      final describeFuture =
          _channel.invokeMethod<String>('describeImage', args);
      final description = cancelToken == null
          ? await describeFuture
          : await _raceWithCancellation(describeFuture, cancelToken);

      final cleaned = cleanMarkdown(description ?? '');
      final (title, text) = _extractTitleAndBody(cleaned);

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

  /// Completes with [future]'s result, or with [CancelledException] the
  /// moment [token] is cancelled — whichever happens first. [future]
  /// itself (the native call) keeps running to completion regardless;
  /// its eventual result is just discarded once this has already
  /// completed via cancellation.
  static Future<T> _raceWithCancellation<T>(Future<T> future, CancelToken token) {
    final completer = Completer<T>();
    future.then(
      (value) {
        if (!completer.isCompleted) completer.complete(value);
      },
      onError: (Object e, StackTrace st) {
        if (!completer.isCompleted) completer.completeError(e, st);
      },
    );
    token.onCancel.then((_) {
      if (!completer.isCompleted) {
        completer.completeError(const CancelledException());
      }
    });
    return completer.future;
  }

  /// #171: the cloud pipeline's `location_context` can run up to ~4500
  /// characters (up to 3 Wikipedia extracts, per #167) — injected as-is
  /// into a Nano segment budgeted for only 256 output tokens total, that
  /// risks the context alone consuming most of what the model attends
  /// to, silently degrading the actual description. Truncated to the
  /// leading portion, since the most identifying detail (a POI/place
  /// name from geocoding) consistently comes first in how this context
  /// is assembled upstream — see LocationContextResolver.
  static const int _maxLocationContextChars = 400;

  static String _truncateLocationContext(String locationContext) {
    if (locationContext.length <= _maxLocationContextChars) {
      return locationContext;
    }
    return locationContext.substring(0, _maxLocationContextChars);
  }

  /// #172: segment 1's prompt (see `buildSeg1Prompt` in
  /// `GeminiNanoPlugin.kt`) now asks the model to lead with a short title
  /// in brackets on its own line — explicit, like the cloud pipeline's
  /// structured `title` field, instead of grabbing whatever the first
  /// `.`-delimited sentence happens to be (fragile: a decimal number or
  /// abbreviation trips the naive split, and an opening sentence isn't
  /// written with "being a good title" in mind).
  ///
  /// Falls back to the old first-sentence heuristic if the model doesn't
  /// follow the bracket format — on-device model compliance isn't
  /// guaranteed the way a cloud JSON schema can be enforced, so the
  /// result must stay usable either way.
  static final _bracketTitle = RegExp(r'^\s*\[([^\]]{1,80})\]\s*');

  (String, String) _extractTitleAndBody(String description) {
    final match = _bracketTitle.firstMatch(description);
    if (match != null) {
      final title = match.group(1)!.trim();
      final body = description.substring(match.end).trim();
      if (title.isNotEmpty && body.isNotEmpty) {
        return (_capTitle(title), body);
      }
    }
    return (_extractTitle(description), description);
  }

  String _extractTitle(String description) {
    final first = description.split('.').first.trim();
    return _capTitle(first);
  }

  String _capTitle(String title) =>
      title.length > 50 ? '${title.substring(0, 50)}...' : title;

  @override
  void dispose() {
    _initialized = false;
  }
}
