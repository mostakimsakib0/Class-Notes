import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../db.dart';
import '../models.dart';
import '../services/notifications.dart';
import '../services/recorder.dart';
import 'common.dart';

/// Edit the classes of ONE date. Changes here never touch the weekly routine.
class DayEditorScreen extends StatelessWidget {
  const DayEditorScreen({super.key, required this.date});
  final DateTime date;

  Future<(List<ClassInstance>, bool)> _load() async {
    final db = await AppDb.open();
    return (await db.classesFor(date), await db.isDayConfirmed(dateKey(date)));
  }

  Future<void> _saved(BuildContext context, String msg) async {
    await Notifications.rescheduleAll(await AppDb.open());
    dataChanged();
    if (context.mounted) toast(context, msg);
  }

  Future<void> _changeTime(BuildContext context, ClassInstance c) async {
    final start = await pickTime(context, c.startMin, help: 'New start time (${DateFormat.MMMd().format(date)} only)');
    if (start == null || !context.mounted) return;
    final end = await pickTime(context, start + (c.endMin - c.startMin), help: 'New end time');
    if (end == null || !context.mounted) return;
    if (end <= start) return toast(context, 'End time must be after start time');
    final room = await _askRoom(context, c.room);
    if (!context.mounted) return;
    final db = await AppDb.open();
    if (c.slotId == null) {
      // Extra class: edit it directly.
      await db.saveOverride(
        DayOverride(
          id: c.overrideId,
          date: c.date,
          subjectId: c.subject.id!,
          type: OverrideType.extra,
          startMin: start,
          endMin: end,
          room: room,
        ),
      );
    } else {
      await db.saveOverride(
        DayOverride(
          date: c.date,
          slotId: c.slotId,
          subjectId: c.subject.id!,
          type: OverrideType.change,
          startMin: start,
          endMin: end,
          room: room,
        ),
      );
    }
    if (context.mounted) await _saved(context, '${c.subject.code} moved to ${fmtTime12(start)} for this day only');
  }

  Future<String?> _askRoom(BuildContext context, String? current) async {
    final ctrl = TextEditingController(text: current);
    final result = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Room (optional)'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'e.g. 402'),
        ),
        actions: [FilledButton(onPressed: () => Navigator.pop(c, ctrl.text.trim()), child: const Text('OK'))],
      ),
    );
    if (result == null) return current; // dialog dismissed: keep the room
    return result.isEmpty ? null : result;
  }

  Future<void> _cancel(BuildContext context, ClassInstance c) async {
    final db = await AppDb.open();
    if (c.slotId == null) {
      await db.deleteOverride(c.overrideId!);
    } else {
      await db.saveOverride(
        DayOverride(date: c.date, slotId: c.slotId, subjectId: c.subject.id!, type: OverrideType.cancel),
      );
    }
    if (context.mounted) await _saved(context, '${c.subject.code} cancelled for this day');
  }

  Future<void> _restore(BuildContext context, ClassInstance c) async {
    await (await AppDb.open()).deleteOverride(c.overrideId!);
    if (context.mounted) await _saved(context, '${c.subject.code} back to the normal time');
  }

  Future<void> _addExtra(BuildContext context) async {
    final db = await AppDb.open();
    final subjects = await db.subjects();
    if (!context.mounted) return;
    if (subjects.isEmpty) return toast(context, 'Add a subject first');
    final subject = await showModalBottomSheet<Subject>(
      context: context,
      builder: (c) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(title: Text('Extra class for which subject?')),
            for (final s in subjects)
              ListTile(
                leading: SubjectDot(s, size: 32),
                title: Text('${s.code} – ${s.name}'),
                onTap: () => Navigator.pop(c, s),
              ),
          ],
        ),
      ),
    );
    if (subject == null || !context.mounted) return;
    final start = await pickTime(context, 9 * 60, help: 'Start time');
    if (start == null || !context.mounted) return;
    final end = await pickTime(context, start + 60, help: 'End time');
    if (end == null || !context.mounted) return;
    if (end <= start) return toast(context, 'End time must be after start time');
    await db.saveOverride(
      DayOverride(date: dateKey(date), subjectId: subject.id!, type: OverrideType.extra, startMin: start, endMin: end),
    );
    if (context.mounted) await _saved(context, 'Extra ${subject.code} class added');
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(DateFormat('EEEE, d MMM').format(date))),
    body: DataBuilder<(List<ClassInstance>, bool)>(
      load: _load,
      builder: (context, data) {
        final (classes, confirmed) = data;
        return ListView(
          padding: const EdgeInsets.only(bottom: 96),
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Text('Changes here apply to this day only. Your weekly routine stays the same.'),
            ),
            if (classes.isEmpty) const ListTile(title: Text('No classes on this day')),
            for (final c in classes)
              Card(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Column(
                  children: [
                    ListTile(
                      leading: SubjectDot(c.subject),
                      title: Text(
                        '${c.subject.code} – ${c.subject.name}',
                        style: c.cancelled ? const TextStyle(decoration: TextDecoration.lineThrough) : null,
                      ),
                      subtitle: Text(
                        [
                          c.timeRange,
                          if (c.room != null) c.room!,
                          if (c.cancelled)
                            'Cancelled'
                          else if (c.slotId == null)
                            'Extra class'
                          else if (c.changed)
                            'Changed',
                        ].join(' · '),
                      ),
                    ),
                    OverflowBar(
                      alignment: MainAxisAlignment.end,
                      children: [
                        if (!c.cancelled)
                          TextButton.icon(
                            icon: const Icon(Icons.schedule),
                            label: const Text('Change time'),
                            onPressed: () => _changeTime(context, c),
                          ),
                        if (!c.cancelled)
                          TextButton.icon(
                            icon: const Icon(Icons.event_busy),
                            label: Text(c.slotId == null ? 'Remove' : 'Cancel'),
                            onPressed: () => _cancel(context, c),
                          ),
                        if (c.slotId != null && c.overrideId != null)
                          TextButton.icon(
                            icon: const Icon(Icons.undo),
                            label: const Text('Restore'),
                            onPressed: () => _restore(context, c),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: OutlinedButton.icon(
                icon: const Icon(Icons.add),
                label: const Text('Add extra class'),
                onPressed: () => _addExtra(context),
              ),
            ),
            if (classes.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: confirmed
                    ? const ListTile(
                        leading: Icon(Icons.check_circle, color: Colors.green),
                        title: Text('Times confirmed'),
                      )
                    : FilledButton.icon(
                        icon: const Icon(Icons.check),
                        label: const Text('Times are correct'),
                        onPressed: () async {
                          await (await AppDb.open()).confirmDay(dateKey(date));
                          dataChanged();
                          if (context.mounted) Navigator.pop(context);
                        },
                      ),
              ),
          ],
        );
      },
    ),
  );
}
