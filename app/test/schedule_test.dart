import 'package:class_recorder/models.dart';
import 'package:class_recorder/schedule.dart';
import 'package:class_recorder/services/notes_format.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const cse = Subject(id: 1, code: 'CSE101', name: 'Programming');
  const mat = Subject(id: 2, code: 'MAT101', name: 'Calculus');
  final subjects = {1: cse, 2: mat};
  // 2026-10-17 is a Saturday (weekday 6), 2026-10-24 the following Saturday.
  final sat = DateTime(2026, 10, 17);
  final nextSat = DateTime(2026, 10, 24);
  final slots = [
    const Slot(id: 10, subjectId: 1, weekday: 6, startMin: 9 * 60, endMin: 10 * 60 + 20, room: '402'),
    const Slot(id: 11, subjectId: 2, weekday: 6, startMin: 11 * 60, endMin: 12 * 60),
    const Slot(id: 12, subjectId: 2, weekday: 1, startMin: 8 * 60, endMin: 9 * 60),
  ];

  test('weekly routine gives the classes for that weekday, in time order', () {
    final classes = classesOn(sat, slots, [], subjects);
    expect(classes.map((c) => c.subject.code), ['CSE101', 'MAT101']);
    expect(classes.first.room, '402');
    expect(classes.every((c) => !c.changed && !c.cancelled), isTrue);
  });

  test('a time change applies to that date only', () {
    final overrides = [
      DayOverride(id: 1, date: dateKey(sat), slotId: 10, subjectId: 1, type: OverrideType.change, startMin: 14 * 60, endMin: 15 * 60),
    ];
    final changed = classesOn(sat, slots, overrides, subjects);
    expect(changed.map((c) => c.subject.code), ['MAT101', 'CSE101']); // re-sorted by new time
    final cse101 = changed.firstWhere((c) => c.subject.id == 1);
    expect((cse101.startMin, cse101.endMin, cse101.changed), (14 * 60, 15 * 60, true));
    expect(cse101.room, '402', reason: 'room is kept when the change does not set one');

    final following = classesOn(nextSat, slots, overrides, subjects);
    expect(following.firstWhere((c) => c.subject.id == 1).startMin, 9 * 60);
  });

  test('cancelled classes are flagged, extra classes are added', () {
    final overrides = [
      DayOverride(id: 1, date: dateKey(sat), slotId: 11, subjectId: 2, type: OverrideType.cancel),
      DayOverride(id: 2, date: dateKey(sat), subjectId: 1, type: OverrideType.extra, startMin: 16 * 60, endMin: 17 * 60),
    ];
    final classes = classesOn(sat, slots, overrides, subjects);
    expect(classes.length, 3);
    expect(classes.firstWhere((c) => c.subject.id == 2).cancelled, isTrue);
    final extra = classes.last;
    expect((extra.subject.code, extra.slotId, extra.key), ('CSE101', null, '2026-10-17:o2'));
  });

  test('class keys are stable per slot and date', () {
    final a = classesOn(sat, slots, [], subjects).first.key;
    final b = classesOn(sat, slots, [
      DayOverride(id: 5, date: dateKey(sat), slotId: 10, subjectId: 1, type: OverrideType.change, startMin: 600, endMin: 660),
    ], subjects).firstWhere((c) => c.slotId == 10).key;
    expect(a, '2026-10-17:s10');
    expect(b, a, reason: 'changing the time must not orphan an existing recording');
  });

  test('overlap detection', () {
    expect(overlappingSlots(slots, 6, 10 * 60, 11 * 60).map((s) => s.id), [10]);
    expect(overlappingSlots(slots, 6, 10 * 60 + 20, 11 * 60), isEmpty, reason: 'back-to-back is fine');
    expect(overlappingSlots(slots, 6, 9 * 60, 10 * 60, excludeId: 10), isEmpty);
  });

  test('notes markdown includes sections and skips empty ones', () {
    final md = notesToMarkdown({
      'title': 'Pointers',
      'summary': 'Intro to pointers.',
      'topics': [
        {'heading': 'Addresses', 'timestamp': '00:05:10', 'explanation': 'Every variable has an address.'},
      ],
      'definitions': [],
      'mcqs': [
        {'question': 'What does & do?', 'options': ['Address-of', 'AND'], 'answer': 'a', 'explanation': 'Gets the address.'},
      ],
      'uncertain': ['Board example was not audible'],
    }, subject: 'CSE101 – Programming', date: '2026-10-17');
    expect(md, contains('# Pointers'));
    expect(md, contains('### Addresses `[00:05:10]`'));
    expect(md, contains('a) Address-of'));
    expect(md, contains('## Needs checking'));
    expect(md, isNot(contains('## Definitions')));
  });
}
