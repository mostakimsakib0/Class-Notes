import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../db.dart';
import '../models.dart';
import '../services/notifications.dart';
import '../services/recorder.dart';
import 'common.dart';
import 'lecture_screen.dart';
import 'routine_screen.dart';

class SubjectsScreen extends StatelessWidget {
  const SubjectsScreen({super.key});

  Future<List<(Subject, int)>> _load() async {
    final db = await AppDb.open();
    final counts = {
      for (final r in await db.db.rawQuery(
        "SELECT subject_id, COUNT(*) AS n FROM lectures WHERE notes_md IS NOT NULL GROUP BY subject_id",
      ))
        r['subject_id'] as int: r['n'] as int,
    };
    return [for (final s in await db.subjects()) (s, counts[s.id] ?? 0)];
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Subjects')),
    body: DataBuilder<List<(Subject, int)>>(
      load: _load,
      builder: (context, items) => items.isEmpty
          ? const Center(child: Text('No subjects yet. Add one with +'))
          : ListView(
              padding: const EdgeInsets.only(bottom: 96),
              children: [
                for (final (s, n) in items)
                  ListTile(
                    leading: SubjectDot(s),
                    title: Text('${s.code} – ${s.name}'),
                    subtitle: Text([if (s.teacher != null) s.teacher!, '$n note${n == 1 ? '' : 's'}'].join(' · ')),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => SubjectScreen(subject: s))),
                  ),
              ],
            ),
    ),
    floatingActionButton: FloatingActionButton(
      tooltip: 'Add subject',
      onPressed: () => showSubjectEditor(context),
      child: const Icon(Icons.add),
    ),
  );
}

Future<void> showSubjectEditor(BuildContext context, {Subject? subject}) async {
  final code = TextEditingController(text: subject?.code);
  final name = TextEditingController(text: subject?.name);
  final teacher = TextEditingController(text: subject?.teacher);
  final db = await AppDb.open();
  var color = subject?.color ?? subjectColors[(await db.subjects()).length % subjectColors.length];
  if (!context.mounted) return;
  final saved = await showDialog<bool>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, setState) => AlertDialog(
        title: Text(subject == null ? 'New subject' : 'Edit subject'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: code,
                decoration: const InputDecoration(labelText: 'Course code', hintText: 'CSE 2101'),
                textCapitalization: TextCapitalization.characters,
              ),
              TextField(
                controller: name,
                decoration: const InputDecoration(labelText: 'Name', hintText: 'Data Structures'),
                textCapitalization: TextCapitalization.words,
              ),
              TextField(
                controller: teacher,
                decoration: const InputDecoration(labelText: 'Teacher (optional)'),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final col in subjectColors)
                    GestureDetector(
                      onTap: () => setState(() => color = col),
                      child: CircleAvatar(
                        radius: 14,
                        backgroundColor: Color(col),
                        child: color == col ? const Icon(Icons.check, size: 16, color: Colors.white) : null,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Save')),
        ],
      ),
    ),
  );
  if (saved != true || !context.mounted) return;
  if (code.text.trim().isEmpty || name.text.trim().isEmpty) return toast(context, 'Code and name are required');
  try {
    await db.saveSubject(
      Subject(
        id: subject?.id,
        code: code.text.trim(),
        name: name.text.trim(),
        teacher: teacher.text.trim().isEmpty ? null : teacher.text.trim(),
        color: color,
      ),
    );
    dataChanged();
  } catch (_) {
    if (context.mounted) toast(context, 'A subject with code ${code.text.trim()} already exists');
  }
}

/// One subject: its notes (main tab) and its weekly class times.
class SubjectScreen extends StatelessWidget {
  const SubjectScreen({super.key, required this.subject});
  final Subject subject;

  Future<(Subject, List<Lecture>, List<Slot>)> _load() async {
    final db = await AppDb.open();
    final s = (await db.subjectMap())[subject.id] ?? subject;
    return (
      s,
      await db.lecturesForSubject(subject.id!),
      (await db.slots()).where((x) => x.subjectId == subject.id).toList(),
    );
  }

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 2,
    child: DataBuilder<(Subject, List<Lecture>, List<Slot>)>(
      load: _load,
      builder: (context, data) {
        final (s, lectures, slots) = data;
        return Scaffold(
          appBar: AppBar(
            title: Text(s.code),
            actions: [
              IconButton(
                icon: const Icon(Icons.edit_outlined),
                onPressed: () => showSubjectEditor(context, subject: s),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline),
                onPressed: () async {
                  if (!await confirm(
                    context,
                    'Delete ${s.code}?',
                    'Its class times and notes on this phone are deleted. Files already in Telegram stay there.',
                    ok: 'Delete',
                  )) {
                    return;
                  }
                  final db = await AppDb.open();
                  await db.deleteSubject(s.id!);
                  await Notifications.rescheduleAll(db);
                  dataChanged();
                  if (context.mounted) Navigator.pop(context);
                },
              ),
            ],
            bottom: const TabBar(
              tabs: [
                Tab(text: 'Notes'),
                Tab(text: 'Class times'),
              ],
            ),
          ),
          body: TabBarView(
            children: [
              lectures.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(32),
                        child: Text('No notes yet. Record a class to create notes.'),
                      ),
                    )
                  : ListView(
                      children: [
                        for (final l in lectures)
                          ListTile(
                            leading: Icon(l.hasNotes ? Icons.description_outlined : Icons.hourglass_empty),
                            title: Text(DateFormat('EEE, d MMM yyyy').format(parseDateKey(l.date))),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${fmtTime12(l.startMin)}${l.durationSec != null ? ' · ${(l.durationSec! / 60).round()} min' : ''}',
                                ),
                                StatusChip(l),
                              ],
                            ),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => LectureScreen(lectureId: l.id)),
                            ),
                          ),
                      ],
                    ),
              ListView(
                children: [
                  if (s.name.isNotEmpty)
                    ListTile(title: Text(s.name), subtitle: s.teacher != null ? Text(s.teacher!) : null),
                  for (final slot in slots)
                    ListTile(
                      leading: const Icon(Icons.schedule),
                      title: Text(weekdayNames[slot.weekday - 1]),
                      subtitle: Text(
                        '${fmtTime12(slot.startMin)} – ${fmtTime12(slot.endMin)}${slot.room != null ? ' · ${slot.room}' : ''}',
                      ),
                      onTap: () => showSlotEditor(context, slot: slot),
                    ),
                  ListTile(
                    leading: const Icon(Icons.add),
                    title: const Text('Add class time'),
                    onTap: () => showSlotEditor(context, subjectId: s.id),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    ),
  );
}
