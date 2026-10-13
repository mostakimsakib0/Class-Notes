import 'package:intl/intl.dart';

/// Minutes since midnight <-> "HH:mm".
String fmtMinutes(int m) => '${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';

String fmtTime12(int m) => DateFormat.jm().format(DateTime(2000, 1, 1, m ~/ 60, m % 60));

String dateKey(DateTime d) => DateFormat('yyyy-MM-dd').format(d);

DateTime parseDateKey(String s) => DateFormat('yyyy-MM-dd').parse(s);

const weekdayNames = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];

class Subject {
  final int? id;
  final String code;
  final String name;
  final String? teacher;
  final int color;

  const Subject({this.id, required this.code, required this.name, this.teacher, this.color = 0xFF3F51B5});

  factory Subject.fromMap(Map<String, Object?> m) => Subject(
    id: m['id'] as int,
    code: m['code'] as String,
    name: m['name'] as String,
    teacher: m['teacher'] as String?,
    color: m['color'] as int,
  );

  Map<String, Object?> toMap() => {'code': code, 'name': name, 'teacher': teacher, 'color': color};
}

/// A weekly class slot. [weekday] follows DateTime.weekday (1 = Monday ... 7 = Sunday).
class Slot {
  final int? id;
  final int subjectId;
  final int weekday;
  final int startMin;
  final int endMin;
  final String? room;

  const Slot({
    this.id,
    required this.subjectId,
    required this.weekday,
    required this.startMin,
    required this.endMin,
    this.room,
  });

  factory Slot.fromMap(Map<String, Object?> m) => Slot(
    id: m['id'] as int,
    subjectId: m['subject_id'] as int,
    weekday: m['weekday'] as int,
    startMin: m['start_min'] as int,
    endMin: m['end_min'] as int,
    room: m['room'] as String?,
  );

  Map<String, Object?> toMap() => {
    'subject_id': subjectId,
    'weekday': weekday,
    'start_min': startMin,
    'end_min': endMin,
    'room': room,
  };
}

enum OverrideType { cancel, change, extra }

/// A change that applies to one date only. `cancel`/`change` refer to a weekly slot; `extra` adds a class.
class DayOverride {
  final int? id;
  final String date;
  final int? slotId;
  final int subjectId;
  final OverrideType type;
  final int? startMin;
  final int? endMin;
  final String? room;
  final String? note;

  const DayOverride({
    this.id,
    required this.date,
    this.slotId,
    required this.subjectId,
    required this.type,
    this.startMin,
    this.endMin,
    this.room,
    this.note,
  });

  factory DayOverride.fromMap(Map<String, Object?> m) => DayOverride(
    id: m['id'] as int,
    date: m['date'] as String,
    slotId: m['slot_id'] as int?,
    subjectId: m['subject_id'] as int,
    type: OverrideType.values.byName(m['type'] as String),
    startMin: m['start_min'] as int?,
    endMin: m['end_min'] as int?,
    room: m['room'] as String?,
    note: m['note'] as String?,
  );

  Map<String, Object?> toMap() => {
    'date': date,
    'slot_id': slotId,
    'subject_id': subjectId,
    'type': type.name,
    'start_min': startMin,
    'end_min': endMin,
    'room': room,
    'note': note,
  };
}

/// One class on a concrete date, after applying that day's overrides.
class ClassInstance {
  final String date;
  final Subject subject;
  final int startMin;
  final int endMin;
  final String? room;
  final int? slotId;
  final int? overrideId;
  final bool changed; // time/room differs from the weekly routine, or it is an extra class
  final bool cancelled;
  final String? note;

  const ClassInstance({
    required this.date,
    required this.subject,
    required this.startMin,
    required this.endMin,
    this.room,
    this.slotId,
    this.overrideId,
    this.changed = false,
    this.cancelled = false,
    this.note,
  });

  /// Stable key for this class on this date (used for notification payloads and lecture lookup).
  String get key => slotId != null ? '$date:s$slotId' : '$date:o$overrideId';

  DateTime get start => parseDateKey(date).add(Duration(minutes: startMin));
  DateTime get end => parseDateKey(date).add(Duration(minutes: endMin));

  String get timeRange => '${fmtTime12(startMin)} – ${fmtTime12(endMin)}';
}

class LectureStatus {
  static const recording = 'recording';
  static const recorded = 'recorded';
  static const processing = 'processing';
  static const done = 'done';
  static const failed = 'failed';
}

class Lecture {
  final int id;
  final int subjectId;
  final String date;
  final String classKey;
  final int startMin;
  final int endMin;
  final String title;
  final String? audioPath;
  final int? durationSec;
  final String status;
  final String? stage;
  final String? error;
  final int? tgAudioMsgId;
  final String? tgAudioFileId;
  final String? transcript;
  final String? notesMd;
  final String? notesAiMd;
  final int? tgNotesMsgId;
  final String? model;
  final String createdAt;

  const Lecture({
    required this.id,
    required this.subjectId,
    required this.date,
    required this.classKey,
    required this.startMin,
    required this.endMin,
    required this.title,
    this.audioPath,
    this.durationSec,
    required this.status,
    this.stage,
    this.error,
    this.tgAudioMsgId,
    this.tgAudioFileId,
    this.transcript,
    this.notesMd,
    this.notesAiMd,
    this.tgNotesMsgId,
    this.model,
    required this.createdAt,
  });

  factory Lecture.fromMap(Map<String, Object?> m) => Lecture(
    id: m['id'] as int,
    subjectId: m['subject_id'] as int,
    date: m['date'] as String,
    classKey: m['class_key'] as String,
    startMin: m['start_min'] as int,
    endMin: m['end_min'] as int,
    title: m['title'] as String,
    audioPath: m['audio_path'] as String?,
    durationSec: m['duration_sec'] as int?,
    status: m['status'] as String,
    stage: m['stage'] as String?,
    error: m['error'] as String?,
    tgAudioMsgId: m['tg_audio_msg_id'] as int?,
    tgAudioFileId: m['tg_audio_file_id'] as String?,
    transcript: m['transcript'] as String?,
    notesMd: m['notes_md'] as String?,
    notesAiMd: m['notes_ai_md'] as String?,
    tgNotesMsgId: m['tg_notes_msg_id'] as int?,
    model: m['model'] as String?,
    createdAt: m['created_at'] as String,
  );

  bool get hasNotes => notesMd != null && notesMd!.isNotEmpty;
}
