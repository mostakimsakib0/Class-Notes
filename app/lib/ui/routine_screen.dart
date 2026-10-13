import 'package:flutter/material.dart';

import '../db.dart';
import '../models.dart';
import '../schedule.dart';
import '../services/notifications.dart';
import '../services/recorder.dart';
import 'common.dart';
import 'day_editor_screen.dart';
import 'subjects_screen.dart';

/// Week order used in Bangladesh: Saturday first.
const _weekOrder = [6, 7, 1, 2, 3, 4, 5];

class RoutineScreen extends StatelessWidget {
  const RoutineScreen({super.key});

  Future<(List<Slot>, Map<int, Subject>)> _load() async {
    final db = await AppDb.open();
    return (await db.slots(), await db.subjectMap());
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Weekly routine'),
      actions: [
        IconButton(
          tooltip: 'Change one specific day',
          icon: const Icon(Icons.edit_calendar_outlined),
          onPressed: () async {
            final now = DateTime.now();
            final d = await showDatePicker(
              context: context,
              firstDate: now.subtract(const Duration(days: 1)),
              lastDate: now.add(const Duration(days: 120)),
            );
            if (d != null && context.mounted) {
              Navigator.push(context, MaterialPageRoute(builder: (_) => DayEditorScreen(date: d)));
            }
          },
        ),
      ],
    ),
    body: DataBuilder<(List<Slot>, Map<int, Subject>)>(
      load: _load,
      builder: (context, data) {
        final (slots, subjects) = data;
        if (slots.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.calendar_month_outlined, size: 64),
                  const SizedBox(height: 12),
                  Text(
                    subjects.isEmpty
                        ? 'Add your subjects first, then add their weekly class times.'
                        : 'Add your weekly class times with the + button.',
                  ),
                  const SizedBox(height: 12),
                  if (subjects.isEmpty)
                    FilledButton(
                      onPressed: () =>
                          Navigator.push(context, MaterialPageRoute(builder: (_) => const SubjectsScreen())),
                      child: const Text('Add subjects'),
                    ),
                ],
              ),
            ),
          );
        }
        return ListView(
          padding: const EdgeInsets.only(bottom: 96),
          children: [
            for (final wd in _weekOrder)
              if (slots.any((s) => s.weekday == wd)) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                  child: Text(weekdayNames[wd - 1], style: Theme.of(context).textTheme.titleMedium),
                ),
                for (final s in slots.where((s) => s.weekday == wd))
                  if (subjects[s.subjectId] case final subject?)
                    ListTile(
                      leading: SubjectDot(subject, size: 36),
                      title: Text('${subject.code} – ${subject.name}'),
                      subtitle: Text(
                        '${fmtTime12(s.startMin)} – ${fmtTime12(s.endMin)}${s.room != null ? ' · ${s.room}' : ''}',
                      ),
                      onTap: () => showSlotEditor(context, slot: s),
                    ),
              ],
          ],
        );
      },
    ),
    floatingActionButton: FloatingActionButton(
      tooltip: 'Add class time',
      onPressed: () => showSlotEditor(context),
      child: const Icon(Icons.add),
    ),
  );
}

/// Add or edit a weekly class slot; warns about overlaps before saving.
Future<void> showSlotEditor(BuildContext context, {Slot? slot, int? subjectId}) async {
  final db = await AppDb.open();
  final subjects = await db.subjects();
  if (!context.mounted) return;
  if (subjects.isEmpty) {
    toast(context, 'Add a subject first');
    Navigator.push(context, MaterialPageRoute(builder: (_) => const SubjectsScreen()));
    return;
  }
  var sid = slot?.subjectId ?? subjectId ?? subjects.first.id!;
  var weekday = slot?.weekday ?? DateTime.now().weekday;
  var start = slot?.startMin ?? 9 * 60;
  var end = slot?.endMin ?? 10 * 60 + 20;
  final room = TextEditingController(text: slot?.room);

  final action = await showDialog<String>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, setState) => AlertDialog(
        title: Text(slot == null ? 'Add class time' : 'Edit class time'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<int>(
                initialValue: sid,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Subject'),
                items: [
                  for (final s in subjects)
                    DropdownMenuItem(
                      value: s.id,
                      child: Text('${s.code} – ${s.name}', overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: (v) => setState(() => sid = v!),
              ),
              DropdownButtonFormField<int>(
                initialValue: weekday,
                decoration: const InputDecoration(labelText: 'Day'),
                items: [for (final wd in _weekOrder) DropdownMenuItem(value: wd, child: Text(weekdayNames[wd - 1]))],
                onChanged: (v) => setState(() => weekday = v!),
              ),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () async {
                        final t = await pickTime(c, start, help: 'Start time');
                        if (t != null) setState(() => start = t);
                      },
                      child: Text('Starts ${fmtTime12(start)}'),
                    ),
                  ),
                  Expanded(
                    child: TextButton(
                      onPressed: () async {
                        final t = await pickTime(c, end, help: 'End time');
                        if (t != null) setState(() => end = t);
                      },
                      child: Text('Ends ${fmtTime12(end)}'),
                    ),
                  ),
                ],
              ),
              TextField(
                controller: room,
                decoration: const InputDecoration(labelText: 'Room (optional)'),
              ),
            ],
          ),
        ),
        actions: [
          if (slot != null) TextButton(onPressed: () => Navigator.pop(c, 'delete'), child: const Text('Delete')),
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, 'save'), child: const Text('Save')),
        ],
      ),
    ),
  );
  if (action == null || !context.mounted) return;

  if (action == 'delete') {
    if (!await confirm(context, 'Delete this class time?', 'It will be removed from every week.', ok: 'Delete')) return;
    await db.deleteSlot(slot!.id!);
  } else {
    if (end <= start) return toast(context, 'End time must be after start time');
    final clashes = overlappingSlots(await db.slots(), weekday, start, end, excludeId: slot?.id);
    if (clashes.isNotEmpty && context.mounted) {
      final names = await db.subjectMap();
      if (!context.mounted) return;
      final ok = await confirm(
        context,
        'Overlapping class',
        'This overlaps ${clashes.map((s) => '${names[s.subjectId]?.code} ${fmtTime12(s.startMin)}–${fmtTime12(s.endMin)}').join(', ')}. Save anyway?',
        ok: 'Save anyway',
      );
      if (!ok) return;
    }
    await db.saveSlot(
      Slot(
        id: slot?.id,
        subjectId: sid,
        weekday: weekday,
        startMin: start,
        endMin: end,
        room: room.text.trim().isEmpty ? null : room.text.trim(),
      ),
    );
  }
  await Notifications.rescheduleAll(db);
  dataChanged();
}
