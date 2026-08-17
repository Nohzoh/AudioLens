import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:audiolens/services/native_tts_service.dart';

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

  test('frenchVoices filters to locales starting with fr', () async {
    final service = NativeTtsService();

    final voices = await service.frenchVoices();

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

  test('speak() applies the speed multiplier on top of the tuned baseline rate',
      () async {
    final service = NativeTtsService();

    await service.speak('Bonjour', speed: 1.5);

    final rateCalls = calls.where((c) => c.method == 'setSpeechRate').toList();
    expect(rateCalls.last.arguments, closeTo(0.45 * 1.5, 0.0001));
  });

  test('setLanguage/setPitch are only sent once across multiple speak() calls '
      '(lazy init)', () async {
    final service = NativeTtsService();

    await service.speak('Un');
    await service.speak('Deux');

    expect(calls.where((c) => c.method == 'setLanguage'), hasLength(1));
    expect(calls.where((c) => c.method == 'setPitch'), hasLength(1));
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
