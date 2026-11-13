import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:audiolens/services/audio_guide_service.dart';
import 'package:audiolens/services/history_service.dart';

// #429: explicit visits.
const _pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory tmpDir;
  late String dbPath;
  late String image;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tmpDir = await Directory.systemTemp.createTemp('visit_test');
    dbPath = join(tmpDir.path, 'history.db');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_pathProviderChannel, (call) async => tmpDir.path);
    image = join(tmpDir.path, 'source.jpg');
    File(image).writeAsBytesSync([0xFF, 0xD8, 0xFF, 0xD9]);
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_pathProviderChannel, null);
    await tmpDir.delete(recursive: true);
  });

  Future<HistoryEntry> analyzed(HistoryService s, String title, String script) async {
    final e = await s.addPendingEntry(imagePath: image);
    await s.completeEntry(entryId: e.id!, title: title, script: script);
    return e;
  }

  test('photos taken during a visit join it and recall the previous ones', () async {
    final s = HistoryService();
    await s.init(dbPath: dbPath);
    final outside = await analyzed(s, 'Avant', 'Hors visite.');

    final visit = await s.startVisit('Louvre');
    final first = await analyzed(s, 'La Joconde', 'Voici la Joconde, peinte par Léonard. Elle sourit.');
    await Future<void>.delayed(const Duration(milliseconds: 5));
    final second = await s.addPendingEntry(imagePath: image);

    expect(s.activeVisit?.name, 'Louvre');
    expect(s.activeVisitEntryCount, 2);
    expect(s.collectionIdsForEntry(outside.id!), isEmpty);
    expect(s.collectionIdsForEntry(second.id!), {visit.id});
    expect(s.visitContextFor(first.id), isNull, reason: 'first photo of the visit');
    final context = s.visitContextFor(second.id)!;
    expect(context, contains('« Louvre »'));
    expect(context, contains('- La Joconde : Voici la Joconde, peinte par Léonard.'));
    expect(context, isNot(contains('Hors visite')));
    expect(context, isNot(contains('Elle sourit')));

    await s.endVisit();
    expect(s.activeVisit, isNull);
    expect(s.visitContextFor(second.id), isNull);
    final after = await s.addPendingEntry(imagePath: image);
    expect(s.collectionIdsForEntry(after.id!), isEmpty);
    // The visit's collection stays.
    expect(s.collections.map((c) => c.name), contains('Louvre'));
  });

  test('the visit in progress survives a restart, a deleted one does not', () async {
    final s = HistoryService();
    await s.init(dbPath: dbPath);
    final visit = await s.startVisit('Château');

    final again = HistoryService();
    await again.init(dbPath: dbPath);
    expect(again.activeVisit?.id, visit.id);

    await again.deleteCollection(visit.id!);
    final third = HistoryService();
    await third.init(dbPath: dbPath);
    expect(third.activeVisit, isNull);
  });

  test('a visit idle for 12 hours ends at the next photo', () async {
    final s = HistoryService();
    await s.init(dbPath: dbPath);
    await s.startVisit('Vieille ville');
    await s.addPendingEntry(imagePath: image);
    s.clock = () => DateTime.now().add(const Duration(hours: 13));

    final late = await s.addPendingEntry(imagePath: image);
    expect(s.activeVisit, isNull);
    expect(s.collectionIdsForEntry(late.id!), isEmpty);
  });

  test('only the last analyses are recalled, each as its first sentence', () {
    final context = buildVisitContext(visitName: 'Musée', previous: [
      for (var i = 1; i <= 6; i++) (title: 'Œuvre $i', script: 'Phrase $i. Suite $i.'),
    ])!;
    expect(context, isNot(contains('Œuvre 2')));
    expect(context, contains('- Œuvre 3 : Phrase 3.'));
    expect(context, contains('- Œuvre 6 : Phrase 6.'));
    expect(buildVisitContext(visitName: 'Musée', previous: const []), isNull);
    final long = visitSummary('${'mot ' * 60}fin.');
    expect(long.length, lessThanOrEqualTo(visitContextSummaryChars + 1));
    expect(long, endsWith('…'));
  });

  test('visit context goes after the hint and before the location', () {
    expect(composePromptContext('Lieu', 'Tour', visitContext: 'Visite'),
        startsWith("Indication de l'utilisateur"));
    expect(composePromptContext('Lieu', null, visitContext: 'Visite'), 'Visite\n\nLieu');
    expect(composePromptContext(null, null, visitContext: 'Visite'), 'Visite');
    expect(composePromptContext(null, null), isNull);
  });
}
