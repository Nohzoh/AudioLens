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

/// One full 3-segment `describeImage` cascade run (#276), with each
/// segment's own prompt text and raw output exposed individually instead
/// of only the final concatenated string — lets the Nano Prompt Lab debug
/// screen show every intermediate step of a real production-shaped run.
class NanoDebugCascadeResult {
  final String seg1Prompt;
  final String seg1Output;
  final String seg2Prompt;
  final String seg2Output;
  final String seg3Prompt;
  final String seg3Output;
  final String fullText;

  const NanoDebugCascadeResult({
    required this.seg1Prompt,
    required this.seg1Output,
    required this.seg2Prompt,
    required this.seg2Output,
    required this.seg3Prompt,
    required this.seg3Output,
    required this.fullText,
  });
}

/// #283: mirrors ML Kit GenAI's `FeatureStatus` — [isAvailable] collapses
/// downloadable/downloading/available all into a single bool, which is
/// enough to pick an AI provider but not enough to tell a user *why*
/// Nano isn't usable right now. [unavailable] specifically means the
/// device doesn't meet AICore's hardware/OS requirements — the one case
/// nothing (not even waiting) resolves, unlike [downloadable]/
/// [downloading]. [unknown] covers a platform error or an SDK version
/// that adds a status this app doesn't recognize yet.
enum NanoDeviceStatus { unavailable, downloadable, downloading, available, unknown }

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

  /// #283: for UI that needs to explain *why* Nano is or isn't usable
  /// (Settings' provider card) rather than just a bool — see
  /// [NanoDeviceStatus].
  Future<NanoDeviceStatus> checkDeviceStatus() async {
    try {
      final result = await _channel.invokeMethod<String>('checkNanoStatus');
      switch (result) {
        case 'unavailable':
          return NanoDeviceStatus.unavailable;
        case 'downloadable':
          return NanoDeviceStatus.downloadable;
        case 'downloading':
          return NanoDeviceStatus.downloading;
        case 'available':
          return NanoDeviceStatus.available;
        default:
          return NanoDeviceStatus.unknown;
      }
    } catch (_) {
      return NanoDeviceStatus.unknown;
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
    String? language,
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
      if (language != null) args['language'] = language;

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

  /// Debug/prompt-iteration tool (Settings > Nano Prompt Lab) — a single
  /// raw `generateContent` call with no prompt scaffolding
  /// (buildSeg1/2/3Prompt in GeminiNanoPlugin.kt aren't applied), image
  /// optional. Returns the model's raw text, unparsed/uncleaned — the
  /// caller sees exactly what the model produced, not what
  /// [analyzeImage] would extract a title/script out of it.
  Future<String> rawPrompt({
    required String prompt,
    File? imageFile,
    int? maxOutputTokens,
    double? temperature,
  }) async {
    if (!_initialized) await initialize();
    try {
      final args = <String, dynamic>{
        'prompt': prompt,
        'maxOutputTokens': maxOutputTokens ?? 256,
      };
      if (imageFile != null) args['imagePath'] = imageFile.path;
      if (temperature != null) args['temperature'] = temperature;
      final result = await _channel.invokeMethod<String>('rawPrompt', args);
      return result ?? '';
    } on PlatformException catch (e) {
      throw Exception('Gemini Nano: ${e.message}');
    }
  }

  /// #276: Nano Prompt Lab's "full pipeline" mode — runs the exact same
  /// 3-segment cascade as [analyzeImage] (same prompt scaffolding,
  /// truncation, timeout handling on the native side), but returns each
  /// segment's own prompt and raw output via `describeImageDebug`
  /// instead of only the final title/script split [analyzeImage]
  /// extracts. No cancellation support (unlike [analyzeImage]) — this is
  /// a manual debug tool, not something run unattended in the background.
  Future<NanoDebugCascadeResult> describeImageDebug({
    required File imageFile,
    String? locationContext,
    String? style,
    String? language,
    int? maxOutputTokens,
    double? temperature,
  }) async {
    if (!_initialized) await initialize();
    try {
      final config = RemoteConfigService.current;
      final args = <String, dynamic>{
        'imagePath': imageFile.path,
        'maxOutputTokens': maxOutputTokens ?? config.geminiNanoMaxTokens,
      };
      if (locationContext != null) {
        args['locationContext'] = _truncateLocationContext(locationContext);
      }
      if (style != null) args['style'] = style;
      if (language != null) args['language'] = language;
      args['temperature'] = temperature ?? config.geminiNanoTemperature;

      final result =
          await _channel.invokeMapMethod<String, dynamic>('describeImageDebug', args);
      if (result == null) throw Exception('Gemini Nano: empty debug response');

      return NanoDebugCascadeResult(
        seg1Prompt: result['seg1Prompt'] as String? ?? '',
        seg1Output: result['seg1Output'] as String? ?? '',
        seg2Prompt: result['seg2Prompt'] as String? ?? '',
        seg2Output: result['seg2Output'] as String? ?? '',
        seg3Prompt: result['seg3Prompt'] as String? ?? '',
        seg3Output: result['seg3Output'] as String? ?? '',
        fullText: result['fullText'] as String? ?? '',
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
  /// name from geocoding) is meant to come first in how this context is
  /// assembled upstream — see LocationContextResolver.
  ///
  /// #247: bumped 400 -> 800. At 400, a real capture's most relevant
  /// fact (the specific building's own Wikipedia extract) got truncated
  /// away entirely — it wasn't first, because the POI lookup that would
  /// normally put it first had failed for that location (see #248), so
  /// the context fell back to a broader, less relevant Wikipedia extract
  /// (the surrounding town) ranking ahead of it by plain proximity. #247
  /// also reorders WikipediaService.merge() to put name-matched results
  /// first when a POI *is* found, but this budget still needs enough
  /// room to not undo that when it isn't.
  static const int _maxLocationContextChars = 800;

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
