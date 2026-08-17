import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:audiolens/services/guide_preferences_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('loadActiveProviderName returns null when nothing saved', () async {
    final store = GuidePreferencesStore();
    expect(await store.loadActiveProviderName(), isNull);
  });

  test('saveActiveProviderName round-trips', () async {
    final store = GuidePreferencesStore();
    await store.saveActiveProviderName('geminiApi');
    expect(await store.loadActiveProviderName(), 'geminiApi');
  });

  test('loadTimings returns empty lists when nothing saved', () async {
    final store = GuidePreferencesStore();
    final timings = await store.loadTimings();
    expect(timings.gpsDurations, isEmpty);
    expect(timings.analyzeDurations, isEmpty);
  });

  test('saveTimings round-trips durations', () async {
    final store = GuidePreferencesStore();
    await store.saveTimings([1.5, 2.0], [8.0, 9.5, 10.0]);
    final timings = await store.loadTimings();
    expect(timings.gpsDurations, [1.5, 2.0]);
    expect(timings.analyzeDurations, [8.0, 9.5, 10.0]);
  });

  test('loadTtsVoiceGender defaults to female when nothing saved (T89)', () async {
    final store = GuidePreferencesStore();
    expect(await store.loadTtsVoiceGender(), 'female');
  });

  test('saveTtsVoiceGender round-trips (T89)', () async {
    final store = GuidePreferencesStore();
    await store.saveTtsVoiceGender('male');
    expect(await store.loadTtsVoiceGender(), 'male');
  });

  test('loadPlaybackSpeed defaults to 1.0 when nothing saved (T15)', () async {
    final store = GuidePreferencesStore();
    expect(await store.loadPlaybackSpeed(), 1.0);
  });

  test('savePlaybackSpeed round-trips (T15)', () async {
    final store = GuidePreferencesStore();
    await store.savePlaybackSpeed(1.25);
    expect(await store.loadPlaybackSpeed(), 1.25);
  });
}
