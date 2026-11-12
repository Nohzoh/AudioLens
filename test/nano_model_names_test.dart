import 'package:flutter_test/flutter_test.dart';
import 'package:audiolens/services/gemini_nano_service.dart';

// #499
void main() {
  const stableFast = NanoModelVariant(NanoReleaseStage.stable, NanoModelPreference.fast);
  const stableFull = NanoModelVariant(NanoReleaseStage.stable, NanoModelPreference.full);
  const previewFast = NanoModelVariant(NanoReleaseStage.preview, NanoModelPreference.fast);
  const previewFull = NanoModelVariant(NanoReleaseStage.preview, NanoModelPreference.full);

  test('readable model names', () {
    expect(nanoModelDisplayName('nano-v3'), 'Gemini Nano 3');
    expect(nanoModelDisplayName('nano-v4-full'), 'Gemini Nano 4 Full');
    expect(nanoModelDisplayName('nano-v4-fast'), 'Gemini Nano 4 Fast');
    expect(nanoModelDisplayName('gemma-x'), 'gemma-x');
  });

  test('choices loading the same model are offered once', () {
    final names = <NanoModelVariant?, String?>{
      null: 'nano-v3',
      stableFast: 'nano-v3',
      stableFull: 'nano-v3',
      previewFast: 'nano-v4-fast',
      previewFull: 'nano-v4-full',
    };
    expect(distinctNanoChoices(names, null), [null, previewFast, previewFull]);
  });

  test('the selected choice stays, and unknown models are all kept', () {
    final names = <NanoModelVariant?, String?>{
      null: 'nano-v3',
      stableFast: 'nano-v3',
      stableFull: null,
      previewFull: 'nano-v4-full',
    };
    expect(distinctNanoChoices(names, stableFast),
        [null, stableFast, stableFull, previewFast, previewFull]);
  });
}
