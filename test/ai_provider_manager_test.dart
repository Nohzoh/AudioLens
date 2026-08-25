import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:audiolens/services/ai_provider_manager.dart';
import 'package:audiolens/services/ai_service.dart';
import 'package:audiolens/services/gemini_api_service.dart';
import 'package:audiolens/services/gemini_nano_service.dart';
import 'package:audiolens/services/guide_preferences_store.dart';
import 'package:audiolens/utils/cancel_token.dart';

const _secureChannel =
    MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

class _FakeNano extends GeminiNanoService {
  _FakeNano({required this.available});
  final bool available;

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<void> initialize() async {}

  @override
  Future<AudioGuideResult> analyzeImage(
    File imageFile, {
    String? locationContext,
    CancelToken? cancelToken,
    String? style,
    String? language,
  }) async =>
      const AudioGuideResult(title: 'Nano', script: 'Nano script');
}

/// #136 — extracted from AudioGuideService, the one piece of its original
/// "does everything" audit not already behind its own collaborator class.
/// This covers the provider-selection logic standalone; the fallback/init
/// integration with AudioGuideService itself stays covered by the
/// existing fallback_orchestration_test.dart, t70_cancellation_test.dart,
/// etc. — this refactor is meant to be behavior-preserving, not to
/// duplicate that coverage.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final secureStore = <String, String>{};

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    secureStore.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_secureChannel, (call) async {
      final args = (call.arguments as Map?)?.cast<String, dynamic>();
      switch (call.method) {
        case 'write':
          secureStore[args!['key'] as String] = args['value'] as String;
          return null;
        case 'read':
          return secureStore[args!['key'] as String];
        case 'delete':
          secureStore.remove(args!['key'] as String);
          return null;
      }
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_secureChannel, null);
  });

  test('defaults to Nano with no service available before init()', () {
    final manager = AiProviderManager(preferencesStore: GuidePreferencesStore());

    expect(manager.activeProvider, AIProvider.geminiNano);
    expect(manager.nanoAvailable, isFalse);
    expect(manager.currentService, isNull);
    expect(manager.providerName, isEmpty);
  });

  test('init() resolves Nano availability and sets the provider name', () async {
    final manager = AiProviderManager(
      preferencesStore: GuidePreferencesStore(),
      nanoService: _FakeNano(available: true),
    );

    await manager.init();

    expect(manager.nanoAvailable, isTrue);
    expect(manager.activeProvider, AIProvider.geminiNano);
    expect(manager.providerName, 'Gemini Nano');
    expect(manager.currentService, same(manager.nanoService));
  });

  test('init() switches to the API when Nano is unavailable but a key is stored', () async {
    secureStore['gemini_api_key'] = 'stored-key';
    final manager = AiProviderManager(
      preferencesStore: GuidePreferencesStore(),
      nanoService: _FakeNano(available: false),
    );

    await manager.init();

    expect(manager.nanoAvailable, isFalse);
    expect(manager.activeProvider, AIProvider.geminiApi);
    expect(manager.providerName, 'Gemini API');
    expect(manager.currentService, isA<GeminiApiService>());
  });

  test('init() stays on Nano (currentService null) when unavailable and no key is stored', () async {
    final manager = AiProviderManager(
      preferencesStore: GuidePreferencesStore(),
      nanoService: _FakeNano(available: false),
    );

    await manager.init();

    expect(manager.activeProvider, AIProvider.geminiNano);
    expect(manager.currentService, isNull);
  });

  test('setActiveProvider updates the provider name and persists the choice', () async {
    final prefs = GuidePreferencesStore();
    final manager = AiProviderManager(preferencesStore: prefs);

    await manager.setActiveProvider(AIProvider.geminiApi);

    expect(manager.activeProvider, AIProvider.geminiApi);
    expect(manager.providerName, 'Gemini API');
    expect(await prefs.loadActiveProviderName(), 'geminiApi');
  });

  test('setGeminiApiKey creates the API/TTS services and auto-switches to the API', () async {
    final manager = AiProviderManager(preferencesStore: GuidePreferencesStore());

    await manager.setGeminiApiKey('my-key');

    expect(manager.geminiApiKey, 'my-key');
    expect(manager.geminiApiService, isNotNull);
    expect(manager.geminiTtsService, isNotNull);
    expect(manager.activeProvider, AIProvider.geminiApi);
    expect(secureStore['gemini_api_key'], 'my-key');
  });

  test('setGeminiApiKey("") clears the services and switches back to Nano if available', () async {
    final manager = AiProviderManager(
      preferencesStore: GuidePreferencesStore(),
      nanoService: _FakeNano(available: true),
    );
    await manager.init();
    await manager.setGeminiApiKey('my-key');

    await manager.setGeminiApiKey('');

    expect(manager.geminiApiKey, isNull);
    expect(manager.geminiApiService, isNull);
    expect(manager.geminiTtsService, isNull);
    expect(manager.activeProvider, AIProvider.geminiNano);
  });
}
