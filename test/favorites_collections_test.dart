import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:audiolens/services/history_service.dart';

/// T51 — favorites (a bool flag on HistoryEntry) and collections (a
/// many-to-many join table) against a real database.
const _pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory tmpDir;
  late String dbPath;
  late String sourceImagePath;

  setUp(() async {
    tmpDir = await Directory.systemTemp.createTemp('favorites_collections_test');
    dbPath = join(tmpDir.path, 'history.db');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_pathProviderChannel, (call) async {
      if (call.method == 'getApplicationDocumentsDirectory') return tmpDir.path;
      return null;
    });
    sourceImagePath = join(tmpDir.path, 'source.jpg');
    File(sourceImagePath).writeAsBytesSync([0xFF, 0xD8, 0xFF, 0xD9]);
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_pathProviderChannel, null);
    await tmpDir.delete(recursive: true);
  });

  test('toggleFavorite flips the flag and persists across a reload', () async {
    final service = HistoryService();
    await service.init(dbPath: dbPath);
    final entry = await service.addPendingEntry(imagePath: sourceImagePath);
    expect(entry.isFavorite, isFalse);

    await service.toggleFavorite(entry.id!);
    expect(service.entries.single.isFavorite, isTrue);

    await service.toggleFavorite(entry.id!);
    expect(service.entries.single.isFavorite, isFalse);

    await service.toggleFavorite(entry.id!);
    final reopened = HistoryService();
    await reopened.init(dbPath: dbPath);
    expect(reopened.entries.single.isFavorite, isTrue);
  });

  test('createCollection, setEntryInCollection add/remove and deleteCollection',
      () async {
    final service = HistoryService();
    await service.init(dbPath: dbPath);
    final entry = await service.addPendingEntry(imagePath: sourceImagePath);

    final rome = await service.createCollection('Rome');
    final louvre = await service.createCollection('Louvre');
    expect(service.collections.map((c) => c.name), ['Rome', 'Louvre']);
    expect(service.collectionIdsForEntry(entry.id!), isEmpty);

    await service.setEntryInCollection(entry.id!, rome.id!, true);
    await service.setEntryInCollection(entry.id!, louvre.id!, true);
    expect(service.collectionIdsForEntry(entry.id!), {rome.id, louvre.id});

    await service.setEntryInCollection(entry.id!, rome.id!, false);
    expect(service.collectionIdsForEntry(entry.id!), {louvre.id});

    await service.deleteCollection(louvre.id!);
    expect(service.collections, hasLength(1));
    expect(service.collectionIdsForEntry(entry.id!), isEmpty);

    // Membership and collections both survive a reload.
    await service.setEntryInCollection(entry.id!, rome.id!, true);
    final reopened = HistoryService();
    await reopened.init(dbPath: dbPath);
    expect(reopened.collections.map((c) => c.name), ['Rome']);
    expect(reopened.collectionIdsForEntry(entry.id!), {rome.id});
  });

  test('deleteEntry also removes its collection memberships', () async {
    final service = HistoryService();
    await service.init(dbPath: dbPath);
    final entry = await service.addPendingEntry(imagePath: sourceImagePath);
    final rome = await service.createCollection('Rome');
    await service.setEntryInCollection(entry.id!, rome.id!, true);

    await service.deleteEntry(entry.id!);

    expect(service.collectionIdsForEntry(entry.id!), isEmpty);
    // The collection itself is untouched, only the membership is gone.
    expect(service.collections, hasLength(1));
  });

  test('completeEntry preserves isFavorite set before analysis finished',
      () async {
    final service = HistoryService();
    await service.init(dbPath: dbPath);
    final entry = await service.addPendingEntry(imagePath: sourceImagePath);
    await service.toggleFavorite(entry.id!);
    expect(service.entries.single.isFavorite, isTrue);

    await service.completeEntry(
      entryId: entry.id!,
      title: 'Eiffel Tower',
      script: 'A famous landmark.',
    );

    expect(service.entries.single.isFavorite, isTrue);
  });
}
