import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;
import '../utils/cancel_token.dart';
import 'remote_config_service.dart';

class TtsService {
  sherpa.OfflineTts? _tts;
  bool _initialized = false;
  bool _isPlaying = false;
  bool _cancelRequested = false;
  int _generationToken = 0;
  Function()? onComplete;

  // Sentence-level progress: 0.0 to 1.0
  Function(double progress)? onProgress;

  bool get isPlaying => _isPlaying;

  Future<void> initialize() async {
    if (_initialized) return;

    sherpa.initBindings();

    final dir = await getApplicationDocumentsDirectory();
    final ttsDir = p.join(dir.path, 'tts');

    final dataDirPath = p.join(ttsDir, 'espeak-ng-data');
    if (!Directory(dataDirPath).existsSync()) {
      if (Directory(ttsDir).existsSync()) {
        await Directory(ttsDir).delete(recursive: true);
      }
    }

    await _extractAssetsBackground(ttsDir);

    final modelPath = p.join(ttsDir, 'fr_FR-miro-high.onnx');
    final tokensPath = p.join(ttsDir, 'tokens.txt');

    if (!File(modelPath).existsSync()) {
      throw Exception('TTS model not found: $modelPath');
    }
    if (!Directory(dataDirPath).existsSync()) {
      final extracted = Directory(ttsDir).listSync().map((e) => e.path.split('/').last).join(', ');
      throw Exception('espeak-ng-data not found. Extracted: $extracted');
    }

    final vits = sherpa.OfflineTtsVitsModelConfig(
      model: modelPath,
      tokens: tokensPath,
      dataDir: dataDirPath,
    );

    final modelConfig = sherpa.OfflineTtsModelConfig(
      vits: vits,
      numThreads: RemoteConfigService.current.ttsNumThreads,
      debug: false,
      provider: 'cpu',
    );

    final config = sherpa.OfflineTtsConfig(
      model: modelConfig,
      maxNumSenetences: 1,
    );

    _tts = await _createTtsInBackground(config);
    _initialized = true;
  }

  Future<void> _extractAssetsBackground(String targetDir) async {
    final modelFile = File(p.join(targetDir, 'fr_FR-miro-high.onnx'));
    if (await modelFile.exists() &&
        Directory(p.join(targetDir, 'espeak-ng-data')).existsSync()) {
      return;
    }

    await Directory(targetDir).create(recursive: true);

    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    final ttsAssets = manifest.listAssets()
        .where((a) => a.startsWith('assets/tts/'))
        .toList();

    for (final asset in ttsAssets) {
      var relativePath = asset.replaceFirst('assets/tts/', '');
      if (relativePath.isEmpty) continue;
      relativePath = Uri.decodeComponent(relativePath);
      if (relativePath.endsWith('/')) continue;

      final targetPath = p.join(targetDir, relativePath);
      await Directory(p.dirname(targetPath)).create(recursive: true);

      try {
        final data = await rootBundle.load(asset);
        await File(targetPath).writeAsBytes(
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        );
      } catch (_) {}

      await Future.delayed(Duration.zero);
    }
  }

  static Future<sherpa.OfflineTts> _createTtsInBackground(
      sherpa.OfflineTtsConfig config) async {
    return await Isolate.run(() {
      sherpa.initBindings();
      return sherpa.OfflineTts(config);
    });
  }

  /// Split text into sentences for progress tracking
  static List<String> _splitSentences(String text) {
    // Split on . ! ? followed by space or end
    final parts = text.split(RegExp(r'(?<=[.!?])\s+'));
    return parts.where((s) => s.trim().isNotEmpty).toList();
  }

  Future<void> speak(String text, {CancelToken? cancelToken}) async {
    // Check cancellation before starting
    if (cancelToken?.isCancelled ?? false) {
      return;
    }

    _cancelRequested = false;
    _generationToken += 1;
    final token = _generationToken;

    if (!_initialized) await initialize();
    
    // Check cancellation after initialization
    if (cancelToken?.isCancelled ?? false) {
      return;
    }
    
    final tts = _tts;
    if (tts == null) return;

    _isPlaying = true;

    final sentences = _splitSentences(text);
    final totalChars = text.length;

    final tmpDir = await getTemporaryDirectory();
    final wavPath = p.join(tmpDir.path, 'tts_output.wav');

    try {
      await _generateInBackground(tts, text, wavPath);
      
      // Check both internal and external cancellation
      if (_cancelRequested || token != _generationToken || (cancelToken?.isCancelled ?? false)) {
        _isPlaying = false;
        return;
      }

      final wavFile = File(wavPath);
      if (!await wavFile.exists()) {
        _isPlaying = false;
        return;
      }

      final wavBytes = await wavFile.readAsBytes();
      final dataSize = wavBytes.buffer.asByteData().getUint32(40, Endian.little);
      final sr = wavBytes.buffer.asByteData().getUint32(24, Endian.little);
      final totalDurationMs = (dataSize / (sr * 2) * 1000).round();

      const channel = MethodChannel('audio_guide/audio_player');
      channel.invokeMethod('playWav', {'path': wavPath}).then((_) {
        if (_cancelRequested || token != _generationToken) {
          _isPlaying = false;
          return;
        }
        _isPlaying = false;
        onComplete?.call();
      });

      _driveSentenceProgress(sentences, totalChars, totalDurationMs, token);
    } catch (_) {
      _isPlaying = false;
      rethrow;
    }
  }

  void _driveSentenceProgress(
      List<String> sentences, int totalChars, int totalDurationMs, int token) async {
    if (sentences.isEmpty || totalDurationMs <= 0) return;

    int charsSoFar = 0;

    for (int i = 0; i < sentences.length; i++) {
      if (!_isPlaying || _cancelRequested || token != _generationToken) break;

      final progress = charsSoFar / totalChars;
      onProgress?.call(progress.clamp(0.0, 1.0));

      final sentenceChars = sentences[i].length;
      final sentenceDuration = (sentenceChars / totalChars * totalDurationMs).round();

      await Future.delayed(Duration(milliseconds: sentenceDuration));
      charsSoFar += sentenceChars + 1;
    }

    if (_isPlaying && !_cancelRequested && token == _generationToken) {
      onProgress?.call(1.0);
    }
  }

  static Future<int> _generateInBackground(
      sherpa.OfflineTts tts, String text, String wavPath) async {
    return await Isolate.run(() {
      sherpa.initBindings();
      final genConfig = sherpa.OfflineTtsGenerationConfig(
        sid: RemoteConfigService.current.ttsSid,
        speed: RemoteConfigService.current.ttsSpeed
    );
      final audio = tts.generateWithConfig(text: text, config: genConfig);
      sherpa.writeWave(
        filename: wavPath,
        samples: audio.samples,
        sampleRate: audio.sampleRate,
      );
      return audio.sampleRate;
    });
  }

  Future<void> pause() async {
    const channel = MethodChannel('audio_guide/audio_player');
    await channel.invokeMethod('pause');
    _isPlaying = false;
  }

  Future<void> stop() async {
    _cancelRequested = true;
    _generationToken += 1;
    const channel = MethodChannel('audio_guide/audio_player');
    await channel.invokeMethod('stop');
    _isPlaying = false;
  }

  void dispose() {
    _cancelRequested = true;
    _generationToken += 1;
    _tts?.free();
    _tts = null;
    _initialized = false;
  }
}
