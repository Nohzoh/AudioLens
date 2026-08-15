import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:audiolens/services/gemini_tts_service.dart';
import 'package:audiolens/services/tts_orchestrator.dart';
import 'package:audiolens/services/tts_service.dart';
import 'package:audiolens/utils/cancel_token.dart';
import 'package:audiolens/utils/text_chunker.dart';

class _FakePiper extends TtsService {
  final List<String> spokenTexts = [];

  @override
  Future<void> speak(String text, {CancelToken? cancelToken}) async {
    spokenTexts.add(text);
    onComplete?.call();
  }
}

class _FakeGeminiTts extends GeminiTtsService {
  _FakeGeminiTts({this.failOnChunk}) : super(apiKey: 'test-key');

  /// 0-based chunk index whose synthesis should throw, or null to never fail.
  final int? failOnChunk;

  final List<String> log = [];
  final List<String> synthesizedTexts = [];
  int _nextIndex = 0;

  @override
  Future<void> speak(String text, {CancelToken? cancelToken}) async {
    log.add('speak');
    synthesizedTexts.add(text);
    onComplete?.call();
  }

  @override
  Future<void> synthesizeToFile(String text, String outputPath) async {
    final index = _nextIndex++;
    log.add('synth:$index');
    synthesizedTexts.add(text);
    if (failOnChunk == index) {
      throw Exception('synthesis failed for chunk $index');
    }
    await File(outputPath).writeAsBytes(Uint8List(60));
  }

  @override
  Future<void> playFile(String path, {bool notifyComplete = true}) async {
    log.add('play:${path.split('/').last}');
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

  // Long enough to always produce 3+ chunks under chunkScript()'s defaults.
  const longScript =
      'Premiere phrase courte. Deuxieme phrase un peu plus longue ici. '
      'Troisieme phrase. Quatrieme phrase qui rallonge un peu le texte total. '
      'Cinquieme phrase. Sixieme phrase pour continuer a remplir. '
      'Septieme phrase assez longue pour ce test de decoupage. Huitieme phrase finale. '
      'Neuvieme phrase qui ajoute encore un peu de contenu au script. '
      'Dixieme phrase pour etre certain de depasser trois morceaux. '
      'Onzieme phrase, toujours plus longue que les precedentes pour ce test. '
      'Douzieme et derniere phrase qui cloture ce script de test assez long.';

  test('a short script falls through to the single-shot speak() path', () async {
    final piper = _FakePiper();
    final gemini = _FakeGeminiTts();
    final orchestrator = TtsOrchestrator(piper: piper);

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
    final piper = _FakePiper();
    final gemini = _FakeGeminiTts();
    final orchestrator = TtsOrchestrator(piper: piper);

    var completeCount = 0;
    // speakChunked mirrors piper.onComplete onto geminiTts.onComplete
    // (same as speak()), so set it here — matches how AudioGuideService
    // wires it in practice.
    piper.onComplete = () => completeCount++;

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

  test('falls back to Piper for the whole script if the first chunk fails', () async {
    final piper = _FakePiper();
    final gemini = _FakeGeminiTts(failOnChunk: 0);
    final orchestrator = TtsOrchestrator(piper: piper);

    final model = await orchestrator.speakChunked(
      longScript,
      cancelToken: CancelToken(),
      geminiTts: gemini,
    );

    expect(model, 'piper');
    expect(piper.spokenTexts, [longScript]);
    expect(gemini.log.where((l) => l.startsWith('play:')), isEmpty);
  });

  test('falls back to Piper for the remaining text if a later chunk fails', () async {
    final piper = _FakePiper();
    final gemini = _FakeGeminiTts(failOnChunk: 1);
    final orchestrator = TtsOrchestrator(piper: piper);

    final expectedChunks = chunkScript(longScript);

    final model = await orchestrator.speakChunked(
      longScript,
      cancelToken: CancelToken(),
      geminiTts: gemini,
    );

    expect(model, 'piper');
    // Chunk 0 was already played via Gemini before the fallback kicked in.
    expect(gemini.log, contains('play:gemini_tts_chunk_0.wav'));
    expect(piper.spokenTexts, [expectedChunks.sublist(1).join(' ')]);
  });

  test('cancellation between chunks stops the sequence early', () async {
    final piper = _FakePiper();
    final gemini = _FakeGeminiTts();
    final orchestrator = TtsOrchestrator(piper: piper);
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
}
