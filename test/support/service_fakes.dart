import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:audiolens/l10n/app_localizations.dart';
import 'package:audiolens/services/audio_guide_service.dart';
import 'package:audiolens/services/gemini_tts_service.dart';
import 'package:audiolens/services/history_service.dart';
import 'package:audiolens/services/native_tts_service.dart';
import 'package:audiolens/services/settings_service.dart';
import 'package:audiolens/utils/cancel_token.dart';

/// T85's wrappers (NativeTtsService/GeminiTtsService) talk to native code
/// that doesn't exist in the Flutter test environment — these override
/// just the network/native-touching methods so AudioGuideService can run
/// safely in tests. Shared here (was previously duplicated as private
/// classes in background_execution_test.dart).
class FakeNativeTts extends NativeTtsService {
  @override
  Future<void> speak(String text,
      {CancelToken? cancelToken, double speed = 1.0}) async {
    onComplete?.call();
  }
}

class FakeGeminiTts extends GeminiTtsService {
  FakeGeminiTts() : super(apiKey: 'test-key');

  @override
  Future<void> speak(String text,
      {CancelToken? cancelToken, double speed = 1.0}) async {}
}

const _secureStorageChannel =
    MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

/// Mocks flutter_secure_storage's platform channel with a plain in-memory
/// map (same approach as secure_key_storage_test.dart). Needed by any
/// widget test that touches SettingsService.init()/AudioGuideService's
/// setGeminiApiKey — both read/write through SecureKeyStorage.
void setUpSecureStorageMock() {
  final store = <String, String>{};
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_secureStorageChannel, (call) async {
    final args = (call.arguments as Map?)?.cast<String, dynamic>();
    switch (call.method) {
      case 'write':
        store[args!['key'] as String] = args['value'] as String;
        return null;
      case 'read':
        return store[args!['key'] as String];
      case 'delete':
        store.remove(args!['key'] as String);
        return null;
      case 'deleteAll':
        store.clear();
        return null;
      case 'readAll':
        return Map<String, String>.from(store);
      case 'containsKey':
        return store.containsKey(args!['key'] as String);
    }
    return null;
  });
}

void tearDownSecureStorageMock() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_secureStorageChannel, null);
}

/// Wraps [child] in the same MultiProvider shape main.dart builds
/// (`ChangeNotifierProvider.value` for SettingsService/AudioGuideService/
/// HistoryService) plus a MaterialApp with localization delegates, ready
/// to pump. All three services are required rather than defaulted here —
/// SettingsService/HistoryService need an async `init()` (SharedPreferences/
/// sqflite) before use, which can't happen inside this synchronous helper,
/// so callers build and initialize them in `setUp` and pass them in.
Widget wrapWithProviders(
  Widget child, {
  required SettingsService settings,
  required AudioGuideService guide,
  required HistoryService history,
}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider.value(value: settings),
      ChangeNotifierProvider.value(value: guide),
      ChangeNotifierProvider.value(value: history),
    ],
    child: MaterialApp(
      // Forced rather than left to the test environment's default locale
      // (which resolves to English, not the app's primary language) —
      // matches the rest of the test suite's convention of asserting on
      // French strings (e.g. history_service_crud_test.dart's 'Analyse
      // échouée').
      locale: const Locale('fr'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: child,
    ),
  );
}
