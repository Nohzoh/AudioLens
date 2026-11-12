import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:audiolens/services/gemini_nano_service.dart';
import 'package:audiolens/utils/build_info.dart';
import 'package:audiolens/utils/nano_lab_export.dart';

// #477
NanoDebugCascadeResult _result({String? seg1Title, String fullText = 'Un. Deux. Trois.'}) =>
    NanoDebugCascadeResult(
      seg1Prompt: 'p1',
      seg1Output: 'Un.',
      seg1Title: seg1Title,
      seg1Mode: seg1Title != null ? 'structured' : 'text',
      seg2Prompt: 'p2',
      seg2Output: 'Deux.',
      seg3Prompt: 'p3',
      seg3Output: 'Trois.',
      fullText: fullText,
      seg1Ms: 1200,
      seg2Ms: 800,
      seg3Ms: 700,
      baseModelName: 'nano-v4-full',
      availMemBeforeMb: 5000,
      minAvailMemMb: 3800,
    );

NanoLabRun _run({
  NanoDebugCascadeResult? result,
  String? error,
  NanoModelVariant? variant,
  int prior = 0,
  String? caseId = 'eglise_saint_joseph_ales',
}) =>
    NanoLabRun(
      startedAt: DateTime.utc(2026, 11, 11, 19, 0),
      caseId: caseId,
      variant: variant,
      priorRunsForVariant: prior,
      style: 'immersive',
      language: 'Français',
      maxOutputTokens: 256,
      temperature: 0.4,
      latitude: 44.1248726,
      longitude: 4.0804628,
      locationContext: 'Lieu identifié à cet emplacement (OpenStreetMap) : Église Saint-Joseph',
      result: result,
      error: error,
      elapsed: const Duration(milliseconds: 2900),
    );

void main() {
  const env = {
    'deviceManufacturer': 'Google',
    'deviceModel': 'Pixel 10',
    'androidVersion': '17',
    'sdkInt': 37,
    'aicoreVersion': '0.release.1 (123)',
    'totalMemMb': 16000,
  };

  test('exports device, app and per-run measurements in the benchmark shape', () {
    const variant = NanoModelVariant(NanoReleaseStage.preview, NanoModelPreference.full);
    final export = buildNanoLabExport(
      runs: [_run(result: _result(seg1Title: 'Église Saint-Joseph'), variant: variant, prior: 1)],
      environment: env,
      appVersion: '0.15.3',
      appBuildNumber: '900',
    );

    expect(export['engine'], 'gemini_nano_on_device');
    expect(export['run_started_utc'], '2026-11-11T19:00:00.000Z');
    expect(export['device'], {
      'manufacturer': 'Google',
      'model': 'Pixel 10',
      'android_version': '17',
      'sdk_int': 37,
      'aicore_version': '0.release.1 (123)',
      'total_memory_mb': 16000,
    });
    expect(export['app']['version'], '0.15.3');
    expect(export['app']['genai_prompt_version'], genaiPromptVersion);

    final r = (export['results'] as List).single as Map<String, dynamic>;
    expect(r['case_id'], 'eglise_saint_joseph_ales');
    expect(r['model_variant'], 'preview_full');
    expect(r['base_model_name'], 'nano-v4-full');
    expect(r['prior_runs_for_variant'], 1);
    expect(r['title'], 'Église Saint-Joseph');
    expect(r['script'], 'Un. Deux. Trois.');
    expect(r['word_count'], 3);
    expect(r['latency_ms_total'], 2900);
    expect(r['latency_ms_segments'], [1200, 800, 700]);
    expect(r['peak_memory_drop_mb'], 1200);
    expect(r['gps'], {'latitude': 44.1248726, 'longitude': 4.0804628});
    expect(r['error'], isNull);

    // The whole export must survive JSON encoding as-is.
    expect(jsonDecode(jsonEncode(export)), export);
  });

  test('takes a bracketed title out of the script on the text path', () {
    final split = splitNanoLabTitle(_result(fullText: '[Le chœur] Un. Deux.'));

    expect(split.title, 'Le chœur');
    expect(split.script, 'Un. Deux.');
    expect(splitNanoLabTitle(_result()).title, isNull);
  });

  // #493
  test('uses the production-assembled script and the temperature actually sent', () {
    final export = buildNanoLabExport(
      runs: [
        _run(
          result: const NanoDebugCascadeResult(
            seg1Prompt: 'p1',
            seg1Output: 'Un.',
            seg1Title: 'Titre',
            seg2Prompt: 'p2',
            seg2Output: '...Deux.',
            seg3Prompt: 'p3',
            seg3Output: 'Trois.',
            fullText: 'Un. ...Deux. Trois.',
            productionText: 'Un. Deux. Trois.',
            temperatureUsed: 0.7,
            lowMemoryAfter: false,
          ),
        ),
      ],
      environment: const {},
      appVersion: '0.15.4',
      appBuildNumber: '901',
    );

    final r = (export['results'] as List).single as Map<String, dynamic>;
    expect(r['script'], 'Un. Deux. Trois.');
    expect(r['segments'], ['Un.', '...Deux.', 'Trois.']);
    expect(r['temperature'], 0.7);
    expect(r['low_memory_after'], isFalse);
  });

  test('a failed run keeps its error and settings, with no measurements', () {
    final export = buildNanoLabExport(
      runs: [_run(error: 'Gemini Nano: timeout', caseId: null)],
      environment: const {},
      appVersion: '0.15.3',
      appBuildNumber: '900',
    );

    final r = (export['results'] as List).single as Map<String, dynamic>;
    expect(r['error'], 'Gemini Nano: timeout');
    expect(r['model_variant'], 'default');
    expect(r['script'], isNull);
    expect(r['latency_ms_segments'], isNull);
    expect(export['device']['aicore_version'], isNull);
  });

  test('genaiPromptVersion matches the dependency CI adds to the Android build', () {
    final script = File('scripts/ci/patch_build_gradle.sh').readAsStringSync();

    expect(script, contains('com.google.mlkit:genai-prompt:$genaiPromptVersion'));
  });
}
