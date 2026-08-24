import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:audiolens/services/history_service.dart';

/// #152/#183 — rotateEntry's persisted quarter-turn counter.
const _pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory tmpDir;
  late String dbPath;
  late String sourceImagePath;

  setUp(() async {
    tmpDir = await Directory.systemTemp.createTemp('photo_rotation_test');
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

  test('rotateEntry cycles through 0/1/2/3 and back, persisting across a reload', () async {
    final service = HistoryService();
    await service.init(dbPath: dbPath);
    final entry = await service.addPendingEntry(imagePath: sourceImagePath);
    expect(entry.rotationQuarters, 0);

    await service.rotateEntry(entry.id!);
    expect(service.entries.single.rotationQuarters, 1);
    await service.rotateEntry(entry.id!);
    expect(service.entries.single.rotationQuarters, 2);
    await service.rotateEntry(entry.id!);
    expect(service.entries.single.rotationQuarters, 3);
    await service.rotateEntry(entry.id!);
    final reopened = HistoryService();
    await reopened.init(dbPath: dbPath);
    expect(reopened.entries.single.rotationQuarters, 0);
  });

  // The rotate button's natural use is several rapid taps to spin the
  // photo through more than one quarter turn — two calls fired close
  // together, neither awaited before the next starts. Before the fix,
  // both read the same pre-update value from _entries and collapsed
  // into a single +1 instead of +2.
  test('two rotateEntry calls fired without awaiting the first both apply, not just one', () async {
    final service = HistoryService();
    await service.init(dbPath: dbPath);
    final entry = await service.addPendingEntry(imagePath: sourceImagePath);

    final first = service.rotateEntry(entry.id!);
    final second = service.rotateEntry(entry.id!);
    await Future.wait([first, second]);

    expect(service.entries.single.rotationQuarters, 2);
  });
}
