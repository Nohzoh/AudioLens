import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:audiolens/services/secure_key_storage.dart';

const _secureChannel =
    MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final secureStore = <String, String>{};
  var failWrites = false;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    secureStore.clear();
    failWrites = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_secureChannel, (call) async {
      final args = (call.arguments as Map?)?.cast<String, dynamic>();
      switch (call.method) {
        case 'write':
          if (failWrites) {
            throw PlatformException(code: 'write_error', message: 'boom');
          }
          secureStore[args!['key'] as String] = args['value'] as String;
          return null;
        case 'read':
          return secureStore[args!['key'] as String];
        case 'delete':
          secureStore.remove(args!['key'] as String);
          return null;
        case 'deleteAll':
          secureStore.clear();
          return null;
        case 'readAll':
          return Map<String, String>.from(secureStore);
        case 'containsKey':
          return secureStore.containsKey(args!['key'] as String);
      }
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_secureChannel, null);
  });

  test('retourne null quand aucune clé n\'est stockée', () async {
    expect(await SecureKeyStorage.readApiKey(), isNull);
  });

  test('lit une clé legacy laissée dans SharedPreferences (migration)', () async {
    SharedPreferences.setMockInitialValues({'gemini_api_key': 'AIza-legacy'});
    expect(await SecureKeyStorage.readApiKey(), 'AIza-legacy');
  });

  test('writeApiKey vide supprime la clé legacy', () async {
    SharedPreferences.setMockInitialValues({'gemini_api_key': 'AIza-legacy'});
    await SecureKeyStorage.writeApiKey('');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('gemini_api_key'), isNull);
  });

  test('clearApiKey supprime la clé legacy', () async {
    SharedPreferences.setMockInitialValues({'gemini_api_key': 'AIza-legacy'});
    await SecureKeyStorage.clearApiKey();
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('gemini_api_key'), isNull);
  });

  test('writeApiKey enregistre bien dans le secure storage puis se relit', () async {
    await SecureKeyStorage.writeApiKey('AIza-secure');
    expect(await SecureKeyStorage.readApiKey(), 'AIza-secure');
  });

  test('writeApiKey lève une exception si le secure storage échoue, sans '
      'jamais retomber sur du texte en clair (T123 follow-up)', () async {
    SharedPreferences.setMockInitialValues({});
    failWrites = true;

    await expectLater(
      SecureKeyStorage.writeApiKey('AIza-should-not-leak'),
      throwsA(isA<SecureStorageUnavailableException>()),
    );

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('gemini_api_key'), isNull);
  });
}
