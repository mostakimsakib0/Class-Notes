import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'models.dart';
import 'schedule.dart';

/// Local SQLite store. Safe to open from the UI isolate and from background isolates.
class AppDb {
  AppDb._(this.db);
  final Database db;

  static AppDb? _instance;

  static Future<AppDb> open() async {
    if (_instance != null) return _instance!;
    final path = p.join(await getDatabasesPath(), 'class_recorder.db');
    final db = await openDatabase(
      path,
      version: 1,
      onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
      onCreate: (db, _) async {
        await db.execute('''CREATE TABLE subjects(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          code TEXT NOT NULL UNIQUE,
          name TEXT NOT NULL,
          teacher TEXT,
          color INTEGER NOT NULL)''');
        await db.execute('''CREATE TABLE slots(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          subject_id INTEGER NOT NULL REFERENCES subjects(id) ON DELETE CASCADE,
          weekday INTEGER NOT NULL,
          start_min INTEGER NOT NULL,
          end_min INTEGER NOT NULL,
          room TEXT)''');
        await db.execute('''CREATE TABLE overrides(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          date TEXT NOT NULL,
          slot_id INTEGER REFERENCES slots(id) ON DELETE CASCADE,
          subject_id INTEGER NOT NULL REFERENCES subjects(id) ON DELETE CASCADE,
          type TEXT NOT NULL,
          start_min INTEGER,
          end_min INTEGER,
          room TEXT,
          note TEXT)''');
        await db.execute('CREATE INDEX overrides_date ON overrides(date)');
        await db.execute('CREATE TABLE day_confirmations(date TEXT PRIMARY KEY, confirmed_at TEXT NOT NULL)');
        await db.execute('''CREATE TABLE lectures(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          subject_id INTEGER NOT NULL REFERENCES subjects(id) ON DELETE CASCADE,
          date TEXT NOT NULL,
          class_key TEXT NOT NULL,
          start_min INTEGER NOT NULL,
          end_min INTEGER NOT NULL,
          title TEXT NOT NULL,
          audio_path TEXT,
          duration_sec INTEGER,
          status TEXT NOT NULL,
          stage TEXT,
          error TEXT,
          tg_audio_msg_id INTEGER,
          tg_audio_file_id TEXT,
          transcript TEXT,
          notes_md TEXT,
          notes_ai_md TEXT,
          tg_notes_msg_id INTEGER,
          model TEXT,
          lock_until TEXT,
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL)''');
        await db.execute('CREATE INDEX lectures_date ON lectures(date)');
      },
    );
    return _instance = AppDb._(db);
  }

  // --- subjects ---

  Future<List<Subject>> subjects() async => (await db.query('subjects', orderBy: 'code')).map(Subject.fromMap).toList();

  Future<Map<int, Subject>> subjectMap() async => {for (final s in await subjects()) s.id!: s};

  Future<int> saveSubject(Subject s) => s.id == null
      ? db.insert('subjects', s.toMap())
      : db.update('subjects', s.toMap(), where: 'id = ?', whereArgs: [s.id]);

  Future<void> deleteSubject(int id) => db.delete('subjects', where: 'id = ?', whereArgs: [id]);

  // --- weekly routine ---

  Future<List<Slot>> slots() async =>
      (await db.query('slots', orderBy: 'weekday, start_min')).map(Slot.fromMap).toList();

  Future<int> saveSlot(Slot s) =>
      s.id == null ? db.insert('slots', s.toMap()) : db.update('slots', s.toMap(), where: 'id = ?', whereArgs: [s.id]);

  Future<void> deleteSlot(int id) => db.delete('slots', where: 'id = ?', whereArgs: [id]);

  // --- one-day changes ---

  Future<List<DayOverride>> overridesBetween(String from, String to) async => (await db.query(
    'overrides',
    where: 'date >= ? AND date <= ?',
    whereArgs: [from, to],
  )).map(DayOverride.fromMap).toList();

  /// Saves a cancel/change for a weekly slot on one date, replacing any earlier change for that slot+date.
  Future<void> saveOverride(DayOverride o) async {
    await db.transaction((txn) async {
      if (o.id != null) {
        await txn.update('overrides', o.toMap(), where: 'id = ?', whereArgs: [o.id]);
        return;
      }
      if (o.slotId != null) {
        await txn.delete('overrides', where: 'date = ? AND slot_id = ?', whereArgs: [o.date, o.slotId]);
      }
      await txn.insert('overrides', o.toMap());
    });
  }

  Future<void> deleteOverride(int id) => db.delete('overrides', where: 'id = ?', whereArgs: [id]);

  Future<void> confirmDay(String date) => db.insert('day_confirmations', {
    'date': date,
    'confirmed_at': DateTime.now().toIso8601String(),
  }, conflictAlgorithm: ConflictAlgorithm.replace);

  Future<bool> isDayConfirmed(String date) async =>
      (await db.query('day_confirmations', where: 'date = ?', whereArgs: [date])).isNotEmpty;

  /// Effective classes for [date] (overrides applied).
  Future<List<ClassInstance>> classesFor(DateTime date) async {
    final key = dateKey(date);
    return classesOn(date, await slots(), await overridesBetween(key, key), await subjectMap());
  }

  // --- lectures ---

  Future<Lecture?> lecture(int id) async {
    final rows = await db.query('lectures', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : Lecture.fromMap(rows.first);
  }

  Future<List<Lecture>> lecturesOn(String date) async => (await db.query(
    'lectures',
    where: 'date = ?',
    whereArgs: [date],
    orderBy: 'start_min',
  )).map(Lecture.fromMap).toList();

  Future<List<Lecture>> lecturesForSubject(int subjectId) async => (await db.query(
    'lectures',
    where: 'subject_id = ?',
    whereArgs: [subjectId],
    orderBy: 'date DESC, start_min DESC',
  )).map(Lecture.fromMap).toList();

  Future<List<Lecture>> unfinishedLectures() async => (await db.query(
    'lectures',
    where: 'status IN (?, ?, ?)',
    whereArgs: [LectureStatus.recorded, LectureStatus.processing, LectureStatus.failed],
    orderBy: 'date, start_min',
  )).map(Lecture.fromMap).toList();

  Future<int> createLecture(ClassInstance c, String audioPath) {
    final now = DateTime.now().toIso8601String();
    return db.insert('lectures', {
      'subject_id': c.subject.id,
      'date': c.date,
      'class_key': c.key,
      'start_min': c.startMin,
      'end_min': c.endMin,
      'title': '${c.subject.code} – ${c.date}',
      'audio_path': audioPath,
      'status': LectureStatus.recording,
      'created_at': now,
      'updated_at': now,
    });
  }

  Future<void> updateLecture(int id, Map<String, Object?> values) => db.update(
    'lectures',
    {...values, 'updated_at': DateTime.now().toIso8601String()},
    where: 'id = ?',
    whereArgs: [id],
  );

  Future<void> deleteLecture(int id) => db.delete('lectures', where: 'id = ?', whereArgs: [id]);

  /// Atomically claims a lecture for processing so the UI and the background check never run it twice.
  Future<bool> tryLock(int id, Duration ttl) async {
    final now = DateTime.now();
    final changed = await db.rawUpdate(
      'UPDATE lectures SET lock_until = ? WHERE id = ? AND (lock_until IS NULL OR lock_until < ?)',
      [now.add(ttl).toIso8601String(), id, now.toIso8601String()],
    );
    return changed == 1;
  }

  Future<void> unlock(int id) => db.update('lectures', {'lock_until': null}, where: 'id = ?', whereArgs: [id]);
}
