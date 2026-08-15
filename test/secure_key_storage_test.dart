import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:audiolens/services/secure_key_storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
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
}
