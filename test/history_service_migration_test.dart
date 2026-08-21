import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:audiolens/services/history_service.dart';

/// Builds a database file matching the exact schema an app at [version]
/// would have produced, so migration tests exercise real historical
/// schemas rather than a synthetic approximation (T09).
Future<String> _createOldSchemaDb(Directory dir, int version) async {
  final path = join(dir.path, 'old_v$version.db');
  final db = await databaseFactoryFfi.openDatabase(
    path,
    options: OpenDatabaseOptions(
      version: version,
      onCreate: (db, v) async {
        await db.execute('''
          CREATE TABLE history(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            imagePath TEXT NOT NULL,
            title TEXT NOT NULL,
            script TEXT NOT NULL,
            locationName TEXT,
            createdAt TEXT NOT NULL
          )
        ''');
        if (v >= 2) {
          await db.execute('ALTER TABLE history ADD COLUMN audioPath TEXT');
        }
        if (v >= 3) {
          await db.execute(
              "ALTER TABLE history ADD COLUMN status TEXT NOT NULL DEFAULT 'complete'");
        }
        if (v >= 4) {
          await db.execute('ALTER TABLE history ADD COLUMN ttsModel TEXT');
        }
        if (v >= 5) {
          for (final col in [
            'ALTER TABLE history ADD COLUMN aiModel TEXT',
            'ALTER TABLE history ADD COLUMN analyzedAt TEXT',
            'ALTER TABLE history ADD COLUMN analysisSource TEXT',
            'ALTER TABLE history ADD COLUMN gpsSource TEXT',
            'ALTER TABLE history ADD COLUMN wikipediaUsed INTEGER NOT NULL DEFAULT 0',
            'ALTER TABLE history ADD COLUMN wordCount INTEGER',
            'ALTER TABLE history ADD COLUMN analysisDurationMs INTEGER',
            'ALTER TABLE history ADD COLUMN gpsLatitude REAL',
            'ALTER TABLE history ADD COLUMN gpsLongitude REAL',
            'ALTER TABLE history ADD COLUMN gpsAddress TEXT',
          ]) {
            await db.execute(col);
          }
        }
        if (v >= 6) {
          await db.execute('ALTER TABLE history ADD COLUMN aiFallback INTEGER NOT NULL DEFAULT 0');
          await db.execute('ALTER TABLE history ADD COLUMN ttsFallback INTEGER NOT NULL DEFAULT 0');
        }
      },
    ),
  );

  await db.insert('history', {
    'imagePath': '/tmp/photo_v$version.jpg',
    'title': 'Entry from schema v$version',
    'script': 'Some narration text.',
    'locationName': 'Paris',
    'createdAt': DateTime(2026, 1, version).toIso8601String(),
  });
  await db.close();
  return path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('history_migration_test');
  });

  tearDown(() async {
    await tempDir.delete(recursive: true);
  });

  for (final oldVersion in [1, 2, 3, 4, 5, 6]) {
    test('migrates cleanly from schema v$oldVersion to v7, keeping data (T09)', () async {
      final path = await _createOldSchemaDb(tempDir, oldVersion);

      final service = HistoryService();
      await service.init(dbPath: path);

      expect(service.entries, hasLength(1));
      final entry = service.entries.single;
      expect(entry.title, 'Entry from schema v$oldVersion');
      expect(entry.script, 'Some narration text.');
      expect(entry.locationName, 'Paris');
      // Columns added after this version should carry their defaults,
      // not null-crash or silently drop the row.
      expect(entry.status, AnalysisStatus.complete);
      expect(entry.aiFallback, isFalse);
      expect(entry.ttsFallback, isFalse);
      expect(entry.wikipediaUsed, isFalse);
      expect(entry.isFavorite, isFalse); // T51
      expect(service.collections, isEmpty); // T51

      final version = await databaseFactoryFfi.openDatabase(path).then((db) async {
        final v = await db.getVersion();
        await db.close();
        return v;
      });
      expect(version, 7);
    });
  }

  test('a fresh install (no prior db) creates schema v7 directly', () async {
    final path = join(tempDir.path, 'fresh.db');
    final service = HistoryService();
    await service.init(dbPath: path);

    expect(service.entries, isEmpty);
    expect(service.collections, isEmpty); // T51
    final version = await databaseFactoryFfi.openDatabase(path).then((db) async {
      final v = await db.getVersion();
      await db.close();
      return v;
    });
    expect(version, 7);
  });

  test('onUpgrade runs inside a single transaction: a mid-migration failure '
      'leaves the database untouched at the old version, not half-upgraded',
      () async {
    // Documents a real sqflite guarantee (verified by reading
    // sqflite_common's source, not assumed): openDatabase wraps the whole
    // onCreate/onUpgrade callback in one exclusive transaction, so a
    // failure partway through rolls back everything already executed in
    // that callback and never calls setVersion. Reproduced directly here
    // rather than against HistoryService, since forcing a failure in the
    // real migration would require invasive fault injection.
    final path = join(tempDir.path, 'rollback.db');
    final db = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, v) =>
            db.execute('CREATE TABLE t(id INTEGER PRIMARY KEY, a TEXT)'),
      ),
    );
    await db.close();

    Future<Database> reopenAndUpgrade() => databaseFactoryFfi.openDatabase(
          path,
          options: OpenDatabaseOptions(
            version: 2,
            onUpgrade: (db, oldV, newV) async {
              await db.execute('ALTER TABLE t ADD COLUMN b TEXT');
              throw Exception('simulated failure after the first ALTER');
            },
          ),
        );

    await expectLater(reopenAndUpgrade(), throwsException);

    final reopened = await databaseFactoryFfi.openDatabase(path);
    expect(await reopened.getVersion(), 1, reason: 'version must not bump on failure');
    final columns = await reopened.rawQuery('PRAGMA table_info(t)');
    expect(
      columns.map((c) => c['name']),
      isNot(contains('b')),
      reason: 'the ALTER from the failed migration must have been rolled back',
    );
    await reopened.close();
  });
}
