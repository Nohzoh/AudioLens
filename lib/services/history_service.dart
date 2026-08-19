import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

enum AnalysisStatus {
  complete,
  pending,
  failed,

  /// Photo + raw GPS captured, analysis not started yet (T78) — distinct
  /// from [pending], which means an analysis is currently in progress.
  captured,
}

class HistoryEntry {
  final int? id;
  final String imagePath;
  final String title;
  final String script;
  final String? locationName;
  final String? audioPath;
  final DateTime createdAt;
  final AnalysisStatus status;
  final String? ttsModel; // e.g. "gemini-tts", "native-tts" (was "piper" before T89)
  final String? aiModel; // e.g. "gemini-3.5-flash", "gemini-nano"
  final DateTime? analyzedAt;
  final String? analysisSource; // "camera", "gallery", "retry"
  final String? gpsSource; // "realtime", "exif", "none"
  final bool wikipediaUsed;
  final int? wordCount;
  final int? analysisDurationMs;
  final double? gpsLatitude;
  final double? gpsLongitude;
  final String? gpsAddress;
  final bool aiFallback; // a fallback model was used for the analysis
  final bool ttsFallback; // Gemini TTS failed → fell back to the native engine

  const HistoryEntry({
    this.id,
    required this.imagePath,
    required this.title,
    required this.script,
    this.locationName,
    this.audioPath,
    required this.createdAt,
    this.status = AnalysisStatus.complete,
    this.ttsModel,
    this.aiModel,
    this.analyzedAt,
    this.analysisSource,
    this.gpsSource,
    this.wikipediaUsed = false,
    this.wordCount,
    this.analysisDurationMs,
    this.gpsLatitude,
    this.gpsLongitude,
    this.gpsAddress,
    this.aiFallback = false,
    this.ttsFallback = false,
  });

  bool get hasAudio => audioPath != null && File(audioPath!).existsSync();
  bool get isPending => status == AnalysisStatus.pending;
  bool get isCaptured => status == AnalysisStatus.captured;
  // Only checks for the old "piper" value: post-T89 native-tts entries
  // never have a cached audioPath (they're re-synthesized on replay
  // instead, being instant and free), so this condition is naturally
  // moot for them regardless.
  bool get hasLowQualityTts => ttsModel == "piper" && audioPath != null;
  String get audioDurationEstimate {
    if (wordCount == null) return '';
    final seconds = (wordCount! / 2.5).round(); // ~150 words/min
    if (seconds < 60) return '~${seconds}s';
    return '~${seconds ~/ 60}min${seconds % 60 > 0 ? " ${seconds % 60}s" : ""}';
  }

  Map<String, dynamic> toMap() => {
    if (id != null) 'id': id,
    'imagePath': imagePath,
    'title': title,
    'script': script,
    'locationName': locationName,
    'audioPath': audioPath,
    'createdAt': createdAt.toIso8601String(),
    'status': status.name,
    'ttsModel': ttsModel,
    'aiModel': aiModel,
    'analyzedAt': analyzedAt?.toIso8601String(),
    'analysisSource': analysisSource,
    'gpsSource': gpsSource,
    'wikipediaUsed': wikipediaUsed ? 1 : 0,
    'wordCount': wordCount,
    'analysisDurationMs': analysisDurationMs,
    'gpsLatitude': gpsLatitude,
    'gpsLongitude': gpsLongitude,
    'gpsAddress': gpsAddress,
    'aiFallback': aiFallback ? 1 : 0,
    'ttsFallback': ttsFallback ? 1 : 0,
  };

  factory HistoryEntry.fromMap(Map<String, dynamic> map) => HistoryEntry(
    id: map['id'] as int?,
    imagePath: map['imagePath'] as String,
    title: map['title'] as String,
    script: map['script'] as String,
    locationName: map['locationName'] as String?,
    audioPath: map['audioPath'] as String?,
    createdAt: DateTime.parse(map['createdAt'] as String),
    ttsModel: map['ttsModel'] as String?,
    aiModel: map['aiModel'] as String?,
    analyzedAt: map['analyzedAt'] != null ? DateTime.parse(map['analyzedAt'] as String) : null,
    analysisSource: map['analysisSource'] as String?,
    gpsSource: map['gpsSource'] as String?,
    wikipediaUsed: (map['wikipediaUsed'] as int? ?? 0) == 1,
    wordCount: map['wordCount'] as int?,
    analysisDurationMs: map['analysisDurationMs'] as int?,
    gpsLatitude: map['gpsLatitude'] as double?,
    gpsLongitude: map['gpsLongitude'] as double?,
    gpsAddress: map['gpsAddress'] as String?,
    aiFallback: (map['aiFallback'] as int? ?? 0) == 1,
    ttsFallback: (map['ttsFallback'] as int? ?? 0) == 1,
    status: AnalysisStatus.values.firstWhere(
      (s) => s.name == (map['status'] as String? ?? 'complete'),
      orElse: () => AnalysisStatus.complete,
    ),
  );

  HistoryEntry copyWith({
    String? audioPath,
    AnalysisStatus? status,
    String? ttsModel,
    String? aiModel,
    String? title,
    String? script,
    String? locationName,
    DateTime? analyzedAt,
    String? analysisSource,
    String? gpsSource,
    bool? wikipediaUsed,
    int? wordCount,
    int? analysisDurationMs,
    double? gpsLatitude,
    double? gpsLongitude,
    String? gpsAddress,
    bool? aiFallback,
    bool? ttsFallback,
  }) => HistoryEntry(
    id: id,
    imagePath: imagePath,
    title: title ?? this.title,
    script: script ?? this.script,
    locationName: locationName ?? this.locationName,
    audioPath: audioPath ?? this.audioPath,
    createdAt: createdAt,
    status: status ?? this.status,
    ttsModel: ttsModel ?? this.ttsModel,
    aiModel: aiModel ?? this.aiModel,
    analyzedAt: analyzedAt ?? this.analyzedAt,
    analysisSource: analysisSource ?? this.analysisSource,
    gpsSource: gpsSource ?? this.gpsSource,
    wikipediaUsed: wikipediaUsed ?? this.wikipediaUsed,
    wordCount: wordCount ?? this.wordCount,
    analysisDurationMs: analysisDurationMs ?? this.analysisDurationMs,
    gpsLatitude: gpsLatitude ?? this.gpsLatitude,
    gpsLongitude: gpsLongitude ?? this.gpsLongitude,
    gpsAddress: gpsAddress ?? this.gpsAddress,
    aiFallback: aiFallback ?? this.aiFallback,
    ttsFallback: ttsFallback ?? this.ttsFallback,
  );
}

class HistoryService extends ChangeNotifier {
  Database? _db;
  List<HistoryEntry> _entries = [];

  List<HistoryEntry> get entries => _entries;

  /// [dbPath] allows pointing at an isolated database file in tests
  /// instead of the app's real one.
  Future<void> init({String? dbPath}) async {
    final path = dbPath ?? join(await getDatabasesPath(), 'audio_guide_history.db');
    _db = await openDatabase(
      path,
      version: 6,
      onCreate: (db, version) {
        return db.execute('''
          CREATE TABLE history(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            imagePath TEXT NOT NULL,
            title TEXT NOT NULL,
            script TEXT NOT NULL,
            locationName TEXT,
            audioPath TEXT,
            status TEXT NOT NULL DEFAULT 'complete',
            ttsModel TEXT,
            aiModel TEXT,
            analyzedAt TEXT,
            analysisSource TEXT,
            gpsSource TEXT,
            wikipediaUsed INTEGER NOT NULL DEFAULT 0,
            wordCount INTEGER,
            analysisDurationMs INTEGER,
            gpsLatitude REAL,
            gpsLongitude REAL,
            gpsAddress TEXT,
            aiFallback INTEGER NOT NULL DEFAULT 0,
            ttsFallback INTEGER NOT NULL DEFAULT 0,
            createdAt TEXT NOT NULL
          )
        ''');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute('ALTER TABLE history ADD COLUMN audioPath TEXT');
        }
        if (oldVersion < 3) {
          await db.execute("ALTER TABLE history ADD COLUMN status TEXT NOT NULL DEFAULT 'complete'");
        }
        if (oldVersion < 4) {
          await db.execute('ALTER TABLE history ADD COLUMN ttsModel TEXT');
        }
        if (oldVersion < 5) {
          for (final col in [
            'ALTER TABLE history ADD COLUMN aiModel TEXT',
            'ALTER TABLE history ADD COLUMN analyzedAt TEXT',
            'ALTER TABLE history ADD COLUMN analysisSource TEXT',
            'ALTER TABLE history ADD COLUMN gpsSource TEXT',
            "ALTER TABLE history ADD COLUMN wikipediaUsed INTEGER NOT NULL DEFAULT 0",
            'ALTER TABLE history ADD COLUMN wordCount INTEGER',
            'ALTER TABLE history ADD COLUMN analysisDurationMs INTEGER',
            'ALTER TABLE history ADD COLUMN gpsLatitude REAL',
            'ALTER TABLE history ADD COLUMN gpsLongitude REAL',
            'ALTER TABLE history ADD COLUMN gpsAddress TEXT',
          ]) {
            await db.execute(col);
          }
        }
        if (oldVersion < 6) {
          await db.execute('ALTER TABLE history ADD COLUMN aiFallback INTEGER NOT NULL DEFAULT 0');
          await db.execute('ALTER TABLE history ADD COLUMN ttsFallback INTEGER NOT NULL DEFAULT 0');
        }
      },
    );
    await _loadEntries();
  }

  Future<void> _loadEntries() async {
    final maps = await _db!.query('history', orderBy: 'createdAt DESC');
    _entries = maps.map(HistoryEntry.fromMap).toList();
    notifyListeners();
  }

  /// Add a pending entry immediately when photo is taken
  /// so it appears in gallery even before analysis completes
  Future<HistoryEntry> addPendingEntry({required String imagePath}) async {
    final permanentPath = await _copyImageToPermanentStorage(imagePath);
    final entry = HistoryEntry(
      imagePath: permanentPath,
      title: 'Analyse en attente...',
      script: '',
      createdAt: DateTime.now(),
      status: AnalysisStatus.pending,
    );
    final id = await _db!.insert('history', entry.toMap());
    final withId = HistoryEntry(
      id: id,
      imagePath: permanentPath,
      title: 'Analyse en attente...',
      script: '',
      createdAt: entry.createdAt,
      status: AnalysisStatus.pending,
    );
    _entries.insert(0, withId);
    notifyListeners();
    return withId;
  }

  /// Add a captured entry: photo + raw GPS saved, no analysis run yet
  /// (T78 — deferred capture, e.g. to save data until back on wifi).
  /// [gpsLatitude]/[gpsLongitude] are the raw coordinates only — no
  /// reverse geocoding/Wikipedia/AI has run, so there's no address or
  /// city yet; those are resolved when the analysis is later launched.
  Future<HistoryEntry> addCapturedEntry({
    required String imagePath,
    double? gpsLatitude,
    double? gpsLongitude,
    String? gpsSource,
  }) async {
    final permanentPath = await _copyImageToPermanentStorage(imagePath);
    final entry = HistoryEntry(
      imagePath: permanentPath,
      title: 'Capturé — analyse à lancer',
      script: '',
      createdAt: DateTime.now(),
      status: AnalysisStatus.captured,
      gpsLatitude: gpsLatitude,
      gpsLongitude: gpsLongitude,
      gpsSource: gpsSource,
    );
    final id = await _db!.insert('history', entry.toMap());
    final withId = HistoryEntry(
      id: id,
      imagePath: permanentPath,
      title: entry.title,
      script: '',
      createdAt: entry.createdAt,
      status: AnalysisStatus.captured,
      gpsLatitude: gpsLatitude,
      gpsLongitude: gpsLongitude,
      gpsSource: gpsSource,
    );
    _entries.insert(0, withId);
    notifyListeners();
    return withId;
  }

  /// Update a pending entry with completed analysis result
  Future<void> completeEntry({
    required int entryId,
    required String title,
    required String script,
    String? locationName,
    String? aiModel,
    String? analysisSource,
    String? gpsSource,
    bool wikipediaUsed = false,
    int? analysisDurationMs,
    double? gpsLatitude,
    double? gpsLongitude,
    String? gpsAddress,
    bool aiFallback = false,
    bool ttsFallback = false,
  }) async {
    // Delete stale audio file if it exists
    final existing = _entries.firstWhere((e) => e.id == entryId,
        orElse: () => HistoryEntry(id: entryId, imagePath: '', title: '',
            script: '', createdAt: DateTime.now()));
    if (existing.audioPath != null) {
      try { await File(existing.audioPath!).delete(); } catch (_) {}
    }

    await _db!.update(
      'history',
      {
        'title': title,
        'script': script,
        'locationName': locationName,
        'status': AnalysisStatus.complete.name,
        'audioPath': null,
        'ttsModel': null,
        'aiModel': aiModel,
        'analyzedAt': DateTime.now().toIso8601String(),
        'analysisSource': analysisSource,
        'gpsSource': gpsSource,
        'wikipediaUsed': wikipediaUsed ? 1 : 0,
        'wordCount': script.trim().split(RegExp(r'\s+')).length,
        'analysisDurationMs': analysisDurationMs,
        'gpsLatitude': gpsLatitude,
        'gpsLongitude': gpsLongitude,
        'gpsAddress': gpsAddress,
        'aiFallback': aiFallback ? 1 : 0,
        'ttsFallback': ttsFallback ? 1 : 0,
      },
      where: 'id = ?',
      whereArgs: [entryId],
    );
    final idx = _entries.indexWhere((e) => e.id == entryId);
    if (idx != -1) {
      _entries[idx] = HistoryEntry(
        id: entryId,
        imagePath: _entries[idx].imagePath,
        title: title,
        script: script,
        locationName: locationName,
        audioPath: null, // cleared — will regenerate on next listen
        createdAt: _entries[idx].createdAt,
        status: AnalysisStatus.complete,
        aiModel: aiModel,
        analyzedAt: DateTime.now(),
        analysisSource: analysisSource,
        gpsSource: gpsSource,
        wikipediaUsed: wikipediaUsed,
        wordCount: script.trim().split(RegExp(r'\s+')).length,
        analysisDurationMs: analysisDurationMs,
        gpsLatitude: gpsLatitude,
        gpsLongitude: gpsLongitude,
        gpsAddress: gpsAddress,
        aiFallback: aiFallback,
        ttsFallback: ttsFallback,
      );
      notifyListeners();
    }
  }

  /// Mark a pending entry as failed. [gpsLatitude]/[gpsLongitude]/[gpsSource]
  /// persist whatever location was actually resolved for this attempt
  /// (live GPS, EXIF, or a manually picked map point) so a later retry can
  /// reuse it instead of re-resolving the device's current location from
  /// scratch — same rationale as [addCapturedEntry] (T78), for the case
  /// where the location was known but the analysis itself failed.
  Future<void> failEntry(
    int entryId, {
    double? gpsLatitude,
    double? gpsLongitude,
    String? gpsSource,
  }) async {
    await _db!.update(
      'history',
      {
        'status': AnalysisStatus.failed.name,
        'title': 'Analyse échouée',
        if (gpsLatitude != null) 'gpsLatitude': gpsLatitude,
        if (gpsLongitude != null) 'gpsLongitude': gpsLongitude,
        if (gpsSource != null) 'gpsSource': gpsSource,
      },
      where: 'id = ?',
      whereArgs: [entryId],
    );
    final idx = _entries.indexWhere((e) => e.id == entryId);
    if (idx != -1) {
      _entries[idx] = _entries[idx].copyWith(
        status: AnalysisStatus.failed,
        gpsLatitude: gpsLatitude,
        gpsLongitude: gpsLongitude,
        gpsSource: gpsSource,
      );
      notifyListeners();
    }
  }

  Future<HistoryEntry> addEntry({
    required String imagePath,
    required String title,
    required String script,
    String? locationName,
  }) async {
    final permanentPath = await _copyImageToPermanentStorage(imagePath);

    final entry = HistoryEntry(
      imagePath: permanentPath,
      title: title,
      script: script,
      locationName: locationName,
      createdAt: DateTime.now(),
    );

    final id = await _db!.insert('history', entry.toMap());
    final saved = HistoryEntry(
      id: id,
      imagePath: permanentPath,
      title: title,
      script: script,
      locationName: locationName,
      createdAt: entry.createdAt,
    );

    _entries.insert(0, saved);
    notifyListeners();
    return saved;
  }

  /// Save generated audio file path for an entry
  Future<void> saveAudioPath(int entryId, String sourcePath, {String? ttsModel, bool? ttsFallback}) async {
    // Copy WAV to permanent storage
    final dir = await getApplicationDocumentsDirectory();
    final audioDir = Directory('${dir.path}/history_audio');
    if (!await audioDir.exists()) await audioDir.create();

    final fileName = 'audio_$entryId.wav';
    final destPath = '${audioDir.path}/$fileName';
    await File(sourcePath).copy(destPath);

    // Update DB
    await _db!.update(
      'history',
      {
        'audioPath': destPath,
        if (ttsModel != null) 'ttsModel': ttsModel,
        if (ttsFallback != null) 'ttsFallback': ttsFallback ? 1 : 0,
      },
      where: 'id = ?',
      whereArgs: [entryId],
    );

    // Update in-memory
    final idx = _entries.indexWhere((e) => e.id == entryId);
    if (idx != -1) {
      _entries[idx] = _entries[idx]
          .copyWith(audioPath: destPath, ttsModel: ttsModel, ttsFallback: ttsFallback);
      notifyListeners();
    }
  }

  Future<void> deleteEntry(int id) async {
    final entry = _entries.firstWhere((e) => e.id == id);
    try {
      if (await File(entry.imagePath).exists()) {
        await File(entry.imagePath).delete();
      }
      if (entry.audioPath != null && await File(entry.audioPath!).exists()) {
        await File(entry.audioPath!).delete();
      }
    } catch (_) {}

    await _db!.delete('history', where: 'id = ?', whereArgs: [id]);
    _entries.removeWhere((e) => e.id == id);
    notifyListeners();
  }

  Future<String> _copyImageToPermanentStorage(String sourcePath) async {
    final dir = await getApplicationDocumentsDirectory();
    final historyDir = Directory('${dir.path}/history_images');
    if (!await historyDir.exists()) await historyDir.create();

    final fileName = '${DateTime.now().millisecondsSinceEpoch}.jpg';
    final destPath = '${historyDir.path}/$fileName';
    await File(sourcePath).copy(destPath);
    return destPath;
  }

  @override
  void dispose() {
    _db?.close();
    super.dispose();
  }
}


