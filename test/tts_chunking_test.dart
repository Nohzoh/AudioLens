import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:audiolens/services/gemini_tts_service.dart';
import 'package:audiolens/services/tts_orchestrator.dart';
import 'package:audiolens/services/native_tts_service.dart';
import 'package:audiolens/utils/cancel_token.dart';
import 'package:audiolens/utils/text_chunker.dart';

class _FakeNativeTts extends NativeTtsService {
  final List<String> spokenTexts = [];

  @override
  Future<void> speak(String text, {CancelToken? cancelToken}) async {
    spokenTexts.add(text);
    onComplete?.call();
  }
}

class _FakeGeminiTts extends GeminiTtsService {
  _FakeGeminiTts({
    this.failOnChunk,
    this.failSpeak = false,
    this.rateLimited = false,
    this.synthDelay,
    this.playDelay,
  }) : super(apiKey: 'test-key');

  /// 0-based chunk index whose synthesis should throw, or null to never fail.
  final int? failOnChunk;

  /// Makes the single-shot [speak] path throw instead of [synthesizeToFile].
  final bool failSpeak;

  /// When a failure is triggered, throw [GeminiTtsRateLimitException]
  /// instead of a plain [Exception] — to test that TtsOrchestrator tells
  /// the two apart.
  final bool rateLimited;

  /// Simulates network/playback latency, to verify chunk N+1's synthesis
  /// genuinely overlaps chunk N's playback rather than just being called
  /// first and then blocking on it (T76 prefetch — see the timing test).
  final Duration? synthDelay;
  final Duration? playDelay;

  final List<String> log = [];
  final List<String> synthesizedTexts = [];
  int _nextIndex = 0;

  @override
  Future<void> speak(String text, {CancelToken? cancelToken}) async {
    log.add('speak');
    synthesizedTexts.add(text);
    if (failSpeak) {
      throw rateLimited
          ? const GeminiTtsRateLimitException()
          : Exception('speak failed');
    }
    onComplete?.call();
  }

  @override
  Future<void> synthesizeToFile(String text, String outputPath) async {
    final index = _nextIndex++;
    log.add('synth:$index');
    synthesizedTexts.add(text);
    if (synthDelay != null) await Future.delayed(synthDelay!);
    if (failOnChunk == index) {
      throw rateLimited
          ? const GeminiTtsRateLimitException()
          : Exception('synthesis failed for chunk $index');
    }
    await File(outputPath).writeAsBytes(Uint8List(60));
  }

  @override
  Future<void> playFile(String path, {bool notifyComplete = true}) async {
    log.add('play:${path.split('/').last}');
    if (playDelay != null) await Future.delayed(playDelay!);
    if (notifyComplete) onComplete?.call();
  }
}

const _pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmpDir;

  setUp(() {
    tmpDir = Directory.systemTemp.createTempSync('tts-chunking');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_pathProviderChannel, (call) async {
      if (call.method == 'getTemporaryDirectory') return tmpDir.path;
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_pathProviderChannel, null);
    tmpDir.deleteSync(recursive: true);
  });

  // ~2200 chars (matching a typical ~400-word real cloud script) — long
  // enough to always produce 4+ chunks under chunkScript()'s defaults
  // (700 chars/chunk after the first). The old 280-char default only
  // needed ~550 chars for the same coverage; this fixture replaces that
  // shorter one now that chunkMaxChars was raised (2026-08-16).
  const longScript =
      'Premiere phrase courte. Deuxieme phrase un peu plus longue ici, avec quelques mots de plus. '
      'Troisieme phrase, qui elle aussi rallonge legerement le texte total du script. '
      'Quatrieme phrase qui rallonge encore un peu le texte total pour ce test de decoupage. '
      'Cinquieme phrase, plus courte. Sixieme phrase pour continuer a remplir le script de test. '
      'Septieme phrase assez longue pour ce test de decoupage en plusieurs morceaux distincts. '
      'Huitieme phrase finale de ce premier groupe de phrases du script de test. '
      'Neuvieme phrase qui ajoute encore un peu de contenu au script en cours de redaction. '
      'Dixieme phrase pour etre certain de depasser largement trois morceaux au decoupage. '
      'Onzieme phrase, toujours plus longue que les precedentes pour ce test de decoupage. '
      'Douzieme phrase qui continue de rallonger le texte total du script de test en cours. '
      'Treizieme phrase, courte. Quatorzieme phrase, plus longue, pour ajouter du contenu. '
      'Quinzieme phrase qui approche de la fin de ce script de test assez consequent. '
      'Seizieme phrase, avant-derniere du script, qui rallonge encore un peu le texte total. '
      'Dix-septieme phrase, plus courte celle-ci, pour varier un peu le rythme du texte. '
      'Dix-huitieme phrase qui ajoute du contenu supplementaire au script de test en cours. '
      'Dix-neuvieme et derniere phrase qui cloture ce script de test assez long et complet.';

  test('a short script falls through to the single-shot speak() path', () async {
    final native = _FakeNativeTts();
    final gemini = _FakeGeminiTts();
    final orchestrator = TtsOrchestrator(nativeTts: native);

    final model = await orchestrator.speakChunked(
      'Une seule phrase.',
      cancelToken: CancelToken(),
      geminiTts: gemini,
    );

    expect(model, 'gemini-tts');
    expect(gemini.log, ['speak']);
    expect(gemini.synthesizedTexts, ['Une seule phrase.']);
  });

  test('chunks a long script, plays every chunk, calls onComplete once, and caches the result', () async {
    final native = _FakeNativeTts();
    final gemini = _FakeGeminiTts();
    final orchestrator = TtsOrchestrator(nativeTts: native);

    var completeCount = 0;
    // speakChunked mirrors native.onComplete onto geminiTts.onComplete
    // (same as speak()), so set it here — matches how AudioGuideService
    // wires it in practice.
    native.onComplete = () => completeCount++;

    final expectedChunks = chunkScript(longScript);
    expect(expectedChunks.length, greaterThanOrEqualTo(3),
        reason: 'test script should chunk into 3+ pieces for this test to be meaningful');

    final chunkStarts = <int>[];
    final model = await orchestrator.speakChunked(
      longScript,
      cancelToken: CancelToken(),
      geminiTts: gemini,
      onChunkStart: (i, total) => chunkStarts.add(i),
    );

    expect(model, 'gemini-tts');
    expect(gemini.synthesizedTexts, expectedChunks);
    expect(chunkStarts, List.generate(expectedChunks.length, (i) => i));
    // onComplete must fire exactly once — not once per intermediate chunk.
    expect(completeCount, 1);

    // Prefetch pattern: chunk 1's synthesis starts before chunk 0's
    // playback is awaited.
    expect(gemini.log.indexOf('synth:1'), lessThan(gemini.log.indexOf('play:gemini_tts_chunk_0.wav')));

    // All-gemini success concatenates chunks into the conventional cached
    // path (AudioGuideService._getLastWavPath looks for this exact name).
    expect(File('${tmpDir.path}/gemini_tts_output.wav').existsSync(), isTrue);
  });

  test('chunk synthesis genuinely overlaps the previous chunk\'s playback, not just called-then-blocked', () async {
    // Log-order alone (as in the test above) only proves synthesizeToFile
    // is *called* before playFile is awaited — it wouldn't catch a bug
    // where that call is somehow serialized behind playback in practice.
    // Real delays make that observable: with synthesis (100ms) shorter
    // than playback (300ms) for every chunk, a correctly-overlapped run
    // pays the synthesis cost only once (for chunk 0, before the loop);
    // a sequential run would pay it again before every later chunk.
    const synthDelay = Duration(milliseconds: 100);
    const playDelay = Duration(milliseconds: 300);
    final native = _FakeNativeTts();
    final gemini = _FakeGeminiTts(synthDelay: synthDelay, playDelay: playDelay);
    final orchestrator = TtsOrchestrator(nativeTts: native);

    final expectedChunks = chunkScript(longScript);
    expect(expectedChunks.length, greaterThanOrEqualTo(3));
    final intermediateChunks = expectedChunks.length - 1;

    final stopwatch = Stopwatch()..start();
    await orchestrator.speakChunked(
      longScript,
      cancelToken: CancelToken(),
      geminiTts: gemini,
    );
    stopwatch.stop();

    final sequentialEstimate = synthDelay +
        (synthDelay + playDelay) * intermediateChunks;
    final overlappedEstimate = synthDelay + playDelay * intermediateChunks;

    // Comfortable margin either side of the overlapped estimate — must be
    // well under sequential (proves overlap happened) without being
    // suspiciously fast (proves the delays were actually awaited at all).
    expect(stopwatch.elapsed, lessThan(sequentialEstimate - const Duration(milliseconds: 150)));
    expect(stopwatch.elapsed, greaterThanOrEqualTo(overlappedEstimate - const Duration(milliseconds: 50)));
  });

  test('falls back to native TTS for the whole script if the first chunk fails', () async {
    final native = _FakeNativeTts();
    final gemini = _FakeGeminiTts(failOnChunk: 0);
    final orchestrator = TtsOrchestrator(nativeTts: native);

    final model = await orchestrator.speakChunked(
      longScript,
      cancelToken: CancelToken(),
      geminiTts: gemini,
    );

    expect(model, 'native-tts');
    expect(native.spokenTexts, [longScript]);
    expect(gemini.log.where((l) => l.startsWith('play:')), isEmpty);
  });

  test('falls back to native TTS for the remaining text if a later chunk fails', () async {
    final native = _FakeNativeTts();
    final gemini = _FakeGeminiTts(failOnChunk: 1);
    final orchestrator = TtsOrchestrator(nativeTts: native);

    final expectedChunks = chunkScript(longScript);

    final model = await orchestrator.speakChunked(
      longScript,
      cancelToken: CancelToken(),
      geminiTts: gemini,
    );

    expect(model, 'native-tts');
    // Chunk 0 was already played via Gemini before the fallback kicked in.
    expect(gemini.log, contains('play:gemini_tts_chunk_0.wav'));
    expect(native.spokenTexts, [expectedChunks.sublist(1).join(' ')]);
  });

  test('cancellation between chunks stops the sequence early', () async {
    final native = _FakeNativeTts();
    final gemini = _FakeGeminiTts();
    final orchestrator = TtsOrchestrator(nativeTts: native);
    final cancelToken = CancelToken();

    final expectedChunks = chunkScript(longScript);
    expect(expectedChunks.length, greaterThanOrEqualTo(3));

    final model = await orchestrator.speakChunked(
      longScript,
      cancelToken: cancelToken,
      geminiTts: gemini,
      onChunkStart: (i, total) {
        if (i == 1) cancelToken.cancel();
      },
    );

    expect(model, 'gemini-tts');
    final playedCount = gemini.log.where((l) => l.startsWith('play:')).length;
    expect(playedCount, lessThan(expectedChunks.length));
  });

  test('wasRateLimited is set when the first chunk fails with a 429', () async {
    final native = _FakeNativeTts();
    final gemini = _FakeGeminiTts(failOnChunk: 0, rateLimited: true);
    final orchestrator = TtsOrchestrator(nativeTts: native);

    await orchestrator.speakChunked(longScript, cancelToken: CancelToken(), geminiTts: gemini);

    expect(orchestrator.wasRateLimited, isTrue);
  });

  test('wasRateLimited stays false when the first chunk fails for another reason', () async {
    final native = _FakeNativeTts();
    final gemini = _FakeGeminiTts(failOnChunk: 0, rateLimited: false);
    final orchestrator = TtsOrchestrator(nativeTts: native);

    await orchestrator.speakChunked(longScript, cancelToken: CancelToken(), geminiTts: gemini);

    expect(orchestrator.wasRateLimited, isFalse);
  });

  test('wasRateLimited is set when a later chunk fails with a 429', () async {
    final native = _FakeNativeTts();
    final gemini = _FakeGeminiTts(failOnChunk: 1, rateLimited: true);
    final orchestrator = TtsOrchestrator(nativeTts: native);

    await orchestrator.speakChunked(longScript, cancelToken: CancelToken(), geminiTts: gemini);

    expect(orchestrator.wasRateLimited, isTrue);
  });

  test('wasRateLimited resets to false on a subsequent successful call', () async {
    final native = _FakeNativeTts();
    final failingGemini = _FakeGeminiTts(failOnChunk: 0, rateLimited: true);
    final orchestrator = TtsOrchestrator(nativeTts: native);

    await orchestrator.speakChunked(longScript, cancelToken: CancelToken(), geminiTts: failingGemini);
    expect(orchestrator.wasRateLimited, isTrue);

    final okGemini = _FakeGeminiTts();
    await orchestrator.speakChunked(longScript, cancelToken: CancelToken(), geminiTts: okGemini);
    expect(orchestrator.wasRateLimited, isFalse);
  });

  test('speak() (single-shot path) also sets wasRateLimited on a 429', () async {
    final native = _FakeNativeTts();
    final gemini = _FakeGeminiTts(failSpeak: true, rateLimited: true);
    final orchestrator = TtsOrchestrator(nativeTts: native);

    final model = await orchestrator.speak('Un script.', cancelToken: CancelToken(), geminiTts: gemini);

    expect(model, 'native-tts');
    expect(orchestrator.wasRateLimited, isTrue);
  });
}
