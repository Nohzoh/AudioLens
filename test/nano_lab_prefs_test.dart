import 'package:audiolens/utils/nano_lab_prefs.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('settings survive a save / load round trip', () async {
    SharedPreferences.setMockInitialValues({});
    const prefs = NanoLabPrefs(
      pipelineMode: true,
      variantKey: 'preview_fast',
      maxTokens: '300',
      temperature: '0.2',
      prompt: 'Décris la photo',
      latitude: '44.128379',
      longitude: '4.080314',
      caseId: 'marie-madeleine',
      locationFirst: true,
      titleLookup: false,
      imageMaxSide: 2560,
      compareRounds: 3,
      imagePath: '/data/lab/photo.jpg',
    );
    await prefs.save();
    final loaded = await NanoLabPrefs.load();
    expect(loaded.toJson(), prefs.toJson());
  });

  test('nothing stored or unreadable data gives the defaults', () async {
    SharedPreferences.setMockInitialValues({});
    expect((await NanoLabPrefs.load()).toJson(), const NanoLabPrefs().toJson());
    SharedPreferences.setMockInitialValues({NanoLabPrefs.storageKey: 'not json'});
    final loaded = await NanoLabPrefs.load();
    expect(loaded.maxTokens, '256');
    expect(loaded.compareRounds, 1);
    expect(loaded.imagePath, isNull);
  });
}
