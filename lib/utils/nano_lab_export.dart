import '../services/gemini_nano_service.dart';
import 'build_info.dart';

/// #477: one full-pipeline run of the Nano Prompt Lab, kept in memory
/// for the session so a series of runs can be exported in one file.
class NanoLabRun {
  final DateTime startedAt;

  /// Benchmark case this run belongs to (`manifest.json` id), if typed.
  final String? caseId;

  /// Model variant used; null = the default model.
  final NanoModelVariant? variant;

  /// How many pipeline runs this variant had already done in the session
  /// before this one: 0 means the model was not warmed up by the lab.
  final int priorRunsForVariant;

  final String? style;
  final String? language;
  final int maxOutputTokens;
  final double? temperature;
  final double? latitude;
  final double? longitude;

  /// The location context sent to the model, as resolved on the device.
  final String? locationContext;

  final NanoDebugCascadeResult? result;
  final String? error;
  final Duration elapsed;

  const NanoLabRun({
    required this.startedAt,
    required this.caseId,
    required this.variant,
    required this.priorRunsForVariant,
    required this.style,
    required this.language,
    required this.maxOutputTokens,
    required this.temperature,
    required this.latitude,
    required this.longitude,
    required this.locationContext,
    required this.result,
    required this.error,
    required this.elapsed,
  });
}

final _bracketTitle = RegExp(r'^\s*\[([^\]]{1,80})\]\s*');

/// Title and script of a run, as production would split them: the typed
/// title when segment 1 used structured output, else the bracketed title
/// at the start of the text.
///
/// #493: built from the production-assembled text when the platform
/// returned it, so the script is what a user would hear rather than the
/// raw concatenation of the segments.
({String? title, String script}) splitNanoLabTitle(NanoDebugCascadeResult r) {
  final text = r.productionText ?? r.fullText;
  final typed = r.seg1Title?.trim();
  if (typed != null && typed.isNotEmpty) return (title: typed, script: text);
  final match = _bracketTitle.firstMatch(text);
  if (match != null) {
    return (
      title: match.group(1)!.trim(),
      script: text.substring(match.end).trim(),
    );
  }
  return (title: null, script: text);
}

/// Builds the benchmark export for [runs], in the shape of
/// `benchmark/results/nano_template.json` (same top-level keys as the
/// cloud results, so both can be compared).
///
/// [environment] is `GeminiNanoService.environmentInfo()`; missing keys
/// are exported as null rather than guessed.
Map<String, dynamic> buildNanoLabExport({
  required List<NanoLabRun> runs,
  required Map<String, dynamic> environment,
  required String appVersion,
  required String appBuildNumber,
}) {
  return {
    'run_started_utc':
        runs.isEmpty ? null : runs.first.startedAt.toUtc().toIso8601String(),
    'engine': 'gemini_nano_on_device',
    'device': {
      'manufacturer': environment['deviceManufacturer'],
      'model': environment['deviceModel'],
      'android_version': environment['androidVersion'],
      'sdk_int': environment['sdkInt'],
      'aicore_version': environment['aicoreVersion'],
      'total_memory_mb': environment['totalMemMb'],
    },
    'app': {
      'version': appVersion,
      'build_number': appBuildNumber,
      'git_commit': gitCommit,
      'build_date': buildDate,
      'genai_prompt_version': genaiPromptVersion,
    },
    'results': [for (final run in runs) _runToJson(run)],
  };
}

Map<String, dynamic> _runToJson(NanoLabRun run) {
  final r = run.result;
  final split = r != null ? splitNanoLabTitle(r) : null;
  final script = split?.script;
  return {
    'case_id': run.caseId,
    'started_utc': run.startedAt.toUtc().toIso8601String(),
    'model_variant': run.variant?.key ?? 'default',
    'base_model_name': r?.baseModelName,
    'prior_runs_for_variant': run.priorRunsForVariant,
    'style': run.style,
    'language': run.language,
    'max_output_tokens': run.maxOutputTokens,
    'temperature': r?.temperatureUsed ?? run.temperature,
    'gps': run.latitude != null && run.longitude != null
        ? {'latitude': run.latitude, 'longitude': run.longitude}
        : null,
    'location_context': run.locationContext,
    'title': split?.title,
    'script': script,
    'word_count': script == null || script.trim().isEmpty
        ? null
        : script.trim().split(RegExp(r'\s+')).length,
    'latency_ms_total': run.elapsed.inMilliseconds,
    'latency_ms_segments': r == null ? null : [r.seg1Ms, r.seg2Ms, r.seg3Ms],
    // #466: facts looked up on segment 1's title and injected into
    // segments 2-3 (null: lookup off, no match, or offline).
    'title_facts': r?.titleFacts,
    'title_lookup_ms': r?.titleLookupMs,
    'avail_memory_before_mb': r?.availMemBeforeMb,
    'min_avail_memory_mb': r?.minAvailMemMb,
    'peak_memory_drop_mb': r?.peakMemoryDropMb,
    'low_memory_after': r?.lowMemoryAfter,
    'seg1_mode': r?.seg1Mode,
    'seg1_finish_reason': r?.seg1FinishReason,
    'segments': r == null ? null : [r.seg1Output, r.seg2Output, r.seg3Output],
    'error': run.error,
  };
}
