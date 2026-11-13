import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'dart:async';
import 'dart:io';
import 'package:audiolens/services/genai_tts_service.dart';
import 'package:audiolens/services/native_tts_service.dart';

/// #485: stands in for ML Kit's generative voice.
class _FakeSpeaker extends GenAiTtsService {
  _FakeSpeaker({this.result, this.waitForStop = false});

  final GenAiSpeakResult? result;
  final bool waitForStop;
  final spoken = <String>[];
  final usedVoices = <String>[];
  int stopCalls = 0;
  final recordPaths = <String?>[];
  Completer<GenAiSpeakResult>? _pending;

  @override
  Future<GenAiSpeakResult> speak({
    required String locale,
    required String voice,
    required String text,
    void Function(int playedMs)? onPlayedMs,
    String? recordPath,
  }) async {
    spoken.add(text);
    recordPaths.add(recordPath);
    usedVoices.add(voice);
    if (waitForStop) {
      _pending = Completer();
      return _pending!.future;
    }
    onPlayedMs?.call(500);
    if (result != null) return result!;
    // A real recording would be a WAV; any file will do here.
    if (recordPath != null) File(recordPath).writeAsBytesSync([1, 2, 3]);
    return GenAiSpeakResult(
        started: true, completed: true, stopped: false, playedMs: 1000, recordedPath: recordPath);
  }

  @override
  Future<void> stopSpeaking() async {
    stopCalls++;
    _pending?.complete(
        const GenAiSpeakResult(started: true, completed: false, stopped: true, playedMs: 300));
  }
}

/// #545: a generative voice stopped (paused) after a chosen duration.
class _TimedSpeaker extends _FakeSpeaker {
  _TimedSpeaker() : super(waitForStop: true);
  int playedMsAtStop = 0;

  @override
  Future<void> stopSpeaking() async {
    stopCalls++;
    _pending?.complete(GenAiSpeakResult(
        started: true, completed: false, stopped: true, playedMs: playedMsAtStop));
  }
}

/// T68 — NativeTtsService had zero real coverage before this: every other
/// test that touches it fakes it via a subclass overriding speak()
/// entirely, so this service's own logic (voice-availability safeguard,
/// speed application, lazy init) never actually ran under test.
const _channel = MethodChannel('flutter_tts');

List<Map<String, String>> _defaultVoices() => [
      {'name': 'fr-fr-x-frc-network', 'locale': 'fr-FR'},
      {'name': 'fr-fr-x-frd-network', 'locale': 'fr-FR'},
      {'name': 'en-us-x-tpc-network', 'locale': 'en-US'},
    ];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<MethodCall> calls;

  void installHandler(List<Map<String, String>> voices) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
      calls.add(call);
      if (call.method == 'getVoices') return voices;
      return 1;
    });
  }

  setUp(() {
    calls = [];
    installHandler(_defaultVoices());
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
  });

  Future<void> simulateNativeCallback(String method, [Object? arguments]) {
    final envelope =
        const StandardMethodCodec().encodeMethodCall(MethodCall(method, arguments));
    return TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage('flutter_tts', envelope, (data) {});
  }

  test('voicesForLocale filters to locales starting with the given prefix', () async {
    final service = NativeTtsService();

    final voices = await service.voicesForLocale('fr');

    expect(voices.map((v) => v['name']),
        containsAll(['fr-fr-x-frc-network', 'fr-fr-x-frd-network']));
    expect(voices.map((v) => v['name']), isNot(contains('en-us-x-tpc-network')));
  });

  test('applyPreferredVoice selects the target voice when it is actually available',
      () async {
    final service = NativeTtsService()..preferredGender = 'male';

    await service.applyPreferredVoice();

    final setVoiceCall = calls.firstWhere((c) => c.method == 'setVoice');
    expect(setVoiceCall.arguments, {'name': 'fr-fr-x-frd-network', 'locale': 'fr-FR'});
  });

  test(
      'applyPreferredVoice leaves the engine default when the preferred voice '
      'is not in the catalog (T89 — listed-but-not-installed voices)', () async {
    // Only the female voice is "installed" — the male one is catalog-listed
    // by getVoices() elsewhere but never actually usable, the real-device
    // quirk T89 guards against.
    installHandler([{'name': 'fr-fr-x-frc-network', 'locale': 'fr-FR'}]);
    final service = NativeTtsService()..preferredGender = 'male';

    await service.applyPreferredVoice();

    expect(calls.where((c) => c.method == 'setVoice'), isEmpty);
  });

  // #485
  group('generative voice', () {
    test('a narration goes through ML Kit when the phone has the voice', () async {
      final speaker = _FakeSpeaker();
      var completed = 0;
      final progress = <double>[];
      final asked = <String>[];
      final service = NativeTtsService()
        ..generativeSpeaker = speaker
        ..generativeVoiceFinder = (locale, gender) async {
          asked.add('$locale|$gender');
          return 'fr-fr-x-star02';
        }
        ..onComplete = () {
          completed++;
        }
        ..onProgress = progress.add;

      await service.speak('Bonjour. Voici le monument.');
      await pumpEventQueue();
      await service.speak('Une autre phrase.');
      await pumpEventQueue();

      expect(speaker.spoken, ['Bonjour. Voici le monument.', 'Une autre phrase.']);
      expect(speaker.usedVoices, everyElement('fr-fr-x-star02'));
      expect(calls.where((c) => c.method == 'speak'), isEmpty,
          reason: 'flutter_tts must not speak the same text');
      expect(completed, 2);
      expect(progress.last, 1.0);
      expect(service.activeVoiceName, 'fr-fr-x-star02');
      expect(asked, ['fr-FR|female'], reason: 'the lookup is cached once found');
    });

    test('the usual voice takes over when the generative one fails before any audio',
        () async {
      final speaker = _FakeSpeaker(
          result: const GenAiSpeakResult(
              started: false, completed: false, stopped: false, playedMs: 0, error: 'boom'));
      final service = NativeTtsService()
        ..generativeSpeaker = speaker
        ..generativeVoiceFinder = ((_, __) async => 'fr-fr-x-star02');

      await service.speak('Premier guide.');
      await pumpEventQueue();
      await service.speak('Second guide.');
      await pumpEventQueue();

      final spoken = calls.where((c) => c.method == 'speak').map((c) => c.arguments).toList();
      expect(spoken, ['Premier guide.', 'Second guide.']);
      expect(speaker.spoken, ['Premier guide.'],
          reason: 'after a failure the session sticks to the usual voice');
      final setVoice = calls.firstWhere((c) => c.method == 'setVoice');
      expect(setVoice.arguments, {'name': 'fr-fr-x-frc-network', 'locale': 'fr-FR'});
    });

    test('the usual voice is used when the phone has none, or the lookup fails',
        () async {
      for (final finder in <Future<String?> Function(String, String)>[
        (_, __) async => null,
        (_, __) async => throw StateError('no such feature'),
      ]) {
        calls.clear();
        final speaker = _FakeSpeaker();
        final service = NativeTtsService()
          ..generativeSpeaker = speaker
          ..generativeVoiceFinder = finder;

        await service.speak('Bonjour.');

        expect(speaker.spoken, isEmpty);
        expect(calls.where((c) => c.method == 'speak').single.arguments, 'Bonjour.');
      }
    });

    test('a second pause resumes within the rest, not the whole text (#545)', () async {
      final speaker = _TimedSpeaker();
      final service = NativeTtsService()
        ..generativeSpeaker = speaker
        ..generativeVoiceFinder = ((_, __) async => 'fr-fr-x-star02');
      const text = 'Phrase un ici. Phrase deux ici. Phrase trois ici. Phrase quatre.';

      await service.speak(text);
      await pumpEventQueue();
      speaker.playedMsAtStop = 2000; // ~36 characters: inside sentence 3
      await service.pause();
      await pumpEventQueue();
      await service.resume();
      await pumpEventQueue();
      expect(speaker.spoken.last, 'Phrase trois ici. Phrase quatre.');

      speaker.playedMsAtStop = 1000; // ~18 characters into that rest
      await service.pause();
      await pumpEventQueue();
      await service.resume();
      await pumpEventQueue();
      expect(speaker.spoken.last, 'Phrase quatre.');
      await service.stop();
    });

    test('stop() stops ML Kit playback without a completion callback', () async {
      final speaker = _FakeSpeaker(waitForStop: true);
      var completed = 0;
      final service = NativeTtsService()
        ..generativeSpeaker = speaker
        ..generativeVoiceFinder = ((_, __) async => 'fr-fr-x-star02')
        ..onComplete = (() => completed++);

      await service.speak('Un long guide.');
      await pumpEventQueue();
      expect(service.isPlaying, isTrue);

      await service.stop();
      await pumpEventQueue();

      expect(speaker.stopCalls, 1);
      expect(service.isPlaying, isFalse);
      expect(completed, 0);
    });
  });

  // #517
  test('a narration played to the end is handed over as a recording, then removed',
      () async {
    final dir = Directory.systemTemp.createTempSync('genai-rec');
    addTearDown(() => dir.deleteSync(recursive: true));
    final speaker = _FakeSpeaker();
    final received = <String, List<int>>{};
    final service = NativeTtsService()
      ..generativeSpeaker = speaker
      ..generativeVoiceFinder = ((_, __) async => 'fr-fr-x-star02')
      ..recordingDirectory = (() async => dir.path)
      ..onGenerativeRecording = (text, path) async {
        received[text] = File(path).readAsBytesSync();
      };

    await service.speak('Le guide complet.');
    await pumpEventQueue();

    expect(speaker.recordPaths.single, startsWith('${dir.path}/genai_tts_'));
    expect(received, {'Le guide complet.': [1, 2, 3]});
    expect(dir.listSync(), isEmpty, reason: 'the temporary recording is deleted');
  });

  test('no recording is asked for when nobody would keep it', () async {
    final speaker = _FakeSpeaker();
    final service = NativeTtsService()
      ..generativeSpeaker = speaker
      ..generativeVoiceFinder = ((_, __) async => 'fr-fr-x-star02');

    await service.speak('Bonjour.');
    await pumpEventQueue();

    expect(speaker.recordPaths.single, isNull);
  });

  test('generativeResumeText restarts at the sentence playback had reached', () {
    const text = 'Première phrase ici. Deuxième phrase un peu plus longue. Troisième.';

    expect(generativeResumeText(text, 0), text);
    // 1.5 s at 18 characters per second = 27 characters, inside sentence 2.
    expect(generativeResumeText(text, 1500),
        'Deuxième phrase un peu plus longue. Troisième.');
    expect(generativeResumeText(text, 600000), text);
  });

  test('speak() applies the speed multiplier on top of the tuned baseline rate',
      () async {
    final service = NativeTtsService();

    await service.speak('Bonjour', speed: 1.5);

    final rateCalls = calls.where((c) => c.method == 'setSpeechRate').toList();
    expect(rateCalls.last.arguments, closeTo(0.45 * 1.5, 0.0001));
  });

  test('setPitch is only sent once across multiple speak() calls (lazy init)', () async {
    final service = NativeTtsService();

    await service.speak('Un');
    await service.speak('Deux');

    expect(calls.where((c) => c.method == 'setPitch'), hasLength(1));
  });

  // #130: unlike setPitch, setLanguage must be re-sent on every speak() —
  // preferredLanguageLocale can differ from one narration to the next
  // (the user's chosen output language), so it can't be a one-time,
  // lazy-init-only call the way setPitch is.
  test('setLanguage is re-applied on every speak() call, not just once', () async {
    final service = NativeTtsService();

    await service.speak('Un');
    await service.speak('Deux');

    expect(calls.where((c) => c.method == 'setLanguage'), hasLength(2));
  });

  test('speakAndWaitForResult resolves true when the platform reports completion',
      () async {
    // The completion callback must fire only once the app has actually
    // registered its pending-speak completer — driving it as a reaction to
    // the mocked "speak" call itself (rather than racing it externally)
    // guarantees that ordering instead of depending on scheduling luck.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
      calls.add(call);
      if (call.method == 'getVoices') return _defaultVoices();
      if (call.method == 'speak') await simulateNativeCallback('speak.onComplete');
      return 1;
    });
    final service = NativeTtsService();

    final result = await service.speakAndWaitForResult('Test');

    expect(result, isTrue);
  });

  test('speakAndWaitForResult resolves false when the platform reports an error',
      () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
      calls.add(call);
      if (call.method == 'getVoices') return _defaultVoices();
      if (call.method == 'speak') {
        await simulateNativeCallback('speak.onError', 'native failure');
      }
      return 1;
    });
    final service = NativeTtsService();

    final result = await service.speakAndWaitForResult('Test');

    expect(result, isFalse);
  });
}
