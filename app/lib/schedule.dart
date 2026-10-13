import 'models.dart';

/// Effective classes on [date]: the weekly routine with that day's overrides applied.
///
/// Overrides only affect their own date, so the weekly routine is never modified.
/// Cancelled classes are included (with [ClassInstance.cancelled]) so the UI can show them;
/// filter with `.where((c) => !c.cancelled)` for reminders and recording.
List<ClassInstance> classesOn(
  DateTime date,
  List<Slot> slots,
  List<DayOverride> overrides,
  Map<int, Subject> subjects,
) {
  final key = dateKey(date);
  final dayOverrides = overrides.where((o) => o.date == key).toList();
  final result = <ClassInstance>[];

  for (final slot in slots.where((s) => s.weekday == date.weekday)) {
    final subject = subjects[slot.subjectId];
    if (subject == null) continue;
    final o = dayOverrides.where((o) => o.slotId == slot.id).firstOrNull;
    if (o == null) {
      result.add(
        ClassInstance(
          date: key,
          subject: subject,
          startMin: slot.startMin,
          endMin: slot.endMin,
          room: slot.room,
          slotId: slot.id,
        ),
      );
    } else if (o.type == OverrideType.cancel) {
      result.add(
        ClassInstance(
          date: key,
          subject: subject,
          startMin: slot.startMin,
          endMin: slot.endMin,
          room: slot.room,
          slotId: slot.id,
          overrideId: o.id,
          changed: true,
          cancelled: true,
          note: o.note,
        ),
      );
    } else {
      result.add(
        ClassInstance(
          date: key,
          subject: subject,
          startMin: o.startMin ?? slot.startMin,
          endMin: o.endMin ?? slot.endMin,
          room: o.room ?? slot.room,
          slotId: slot.id,
          overrideId: o.id,
          changed: true,
          note: o.note,
        ),
      );
    }
  }

  for (final o in dayOverrides.where((o) => o.type == OverrideType.extra)) {
    final subject = subjects[o.subjectId];
    if (subject == null || o.startMin == null || o.endMin == null) continue;
    result.add(
      ClassInstance(
        date: key,
        subject: subject,
        startMin: o.startMin!,
        endMin: o.endMin!,
        room: o.room,
        overrideId: o.id,
        changed: true,
        note: o.note,
      ),
    );
  }

  result.sort((a, b) => a.startMin.compareTo(b.startMin));
  return result;
}

/// Weekly slots on the same weekday that overlap [startMin, endMin).
List<Slot> overlappingSlots(List<Slot> slots, int weekday, int startMin, int endMin, {int? excludeId}) => slots
    .where((s) => s.weekday == weekday && s.id != excludeId && s.startMin < endMin && s.endMin > startMin)
    .toList();
