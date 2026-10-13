import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../db.dart';
import '../models.dart';
import '../services/recorder.dart';
import '../settings.dart';
import 'common.dart';
import 'day_editor_screen.dart';
import 'lecture_screen.dart';
import 'recording_screen.dart';
import 'settings_screen.dart';

class _TodayData {
  _TodayData(this.today, this.lectures, this.tomorrow, this.missingSetup, this.subjects);
  final List<ClassInstance> today;
  final List<Lecture> lectures;
  final List<ClassInstance> tomorrow;
  final List<String> missingSetup;
  final List<Subject> subjects;
}

class TodayScreen extends StatelessWidget {
  const TodayScreen({super.key});

  Future<_TodayData> _load() async {
    final db = await AppDb.open();
    final now = DateTime.now();
    return _TodayData(
      await db.classesFor(now),
      await db.lecturesOn(dateKey(now)),
      await db.classesFor(now.add(const Duration(days: 1))),
      [
        if (await AppSettings.geminiKey() == null) 'Gemini API key',
        if (await AppSettings.botToken() == null || await AppSettings.storageChatId() == null) 'Telegram storage',
      ],
      await db.subjects(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    return Scaffold(
      appBar: AppBar(
        title: Text(DateFormat('EEEE, d MMMM').format(now)),
        actions: [
          IconButton(
            tooltip: 'Change today\'s times',
            icon: const Icon(Icons.edit_calendar_outlined),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => DayEditorScreen(date: now))),
          ),
        ],
      ),
      body: DataBuilder<_TodayData>(
        load: _load,
        builder: (context, d) => ListView(
          padding: const EdgeInsets.only(bottom: 96),
          children: [
            if (d.missingSetup.isNotEmpty)
              Card(
                margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                color: Theme.of(context).colorScheme.errorContainer,
                child: ListTile(
                  leading: const Icon(Icons.warning_amber),
                  title: Text('Set up ${d.missingSetup.join(' and ')}'),
                  subtitle: const Text('Needed to create and store notes'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen())),
                ),
              ),
            const _ActiveRecordingCard(),
            _sectionTitle(context, 'Today'),
            if (d.today.isEmpty)
              const ListTile(leading: Icon(Icons.free_breakfast_outlined), title: Text('No classes today')),
            for (final c in d.today) _ClassTile(c, d.lectures.where((l) => l.classKey == c.key).lastOrNull),
            if (d.lectures.any((l) => !d.today.any((c) => c.key == l.classKey))) ...[
              _sectionTitle(context, 'Other recordings today'),
              for (final l in d.lectures.where((l) => !d.today.any((c) => c.key == l.classKey)))
                ListTile(
                  title: Text(l.title),
                  subtitle: StatusChip(l),
                  onTap: () =>
                      Navigator.push(context, MaterialPageRoute(builder: (_) => LectureScreen(lectureId: l.id))),
                ),
            ],
            _sectionTitle(
              context,
              'Tomorrow',
              action: TextButton.icon(
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: const Text('Change times'),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => DayEditorScreen(date: now.add(const Duration(days: 1)))),
                ),
              ),
            ),
            if (d.tomorrow.isEmpty) const ListTile(dense: true, title: Text('No classes')),
            for (final c in d.tomorrow)
              ListTile(
                dense: true,
                leading: SubjectDot(c.subject, size: 28),
                title: Text(
                  '${c.subject.code} · ${c.timeRange}',
                  style: c.cancelled ? const TextStyle(decoration: TextDecoration.lineThrough) : null,
                ),
                subtitle: c.changed ? Text(c.cancelled ? 'Cancelled' : 'Changed for tomorrow only') : null,
              ),
          ],
        ),
      ),
      floatingActionButton: ListenableBuilder(
        listenable: RecorderController.instance,
        builder: (context, _) => RecorderController.instance.isRecording
            ? const SizedBox.shrink()
            : FloatingActionButton.extended(
                icon: const Icon(Icons.mic),
                label: const Text('Record now'),
                onPressed: () => _recordAdHoc(context),
              ),
      ),
    );
  }

  Widget _sectionTitle(BuildContext context, String text, {Widget? action}) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 16, 8, 4),
    child: Row(
      children: [
        Expanded(child: Text(text, style: Theme.of(context).textTheme.titleMedium)),
        ?action,
      ],
    ),
  );

  /// Record a class that isn't in the routine: pick the subject, record from now for up to 90 minutes.
  Future<void> _recordAdHoc(BuildContext context) async {
    final db = await AppDb.open();
    final subjects = await db.subjects();
    if (!context.mounted) return;
    if (subjects.isEmpty) return toast(context, 'Add a subject first (Subjects tab)');
    final now = DateTime.now();
    final today = await db.classesFor(now);
    final running = today
        .where((c) => !c.cancelled && c.start.isBefore(now.add(const Duration(minutes: 15))) && c.end.isAfter(now))
        .firstOrNull;
    if (!context.mounted) return;
    final subject = await showModalBottomSheet<Subject>(
      context: context,
      builder: (c) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(title: Text('Which subject?')),
            for (final s in subjects)
              ListTile(
                leading: SubjectDot(s, size: 32),
                title: Text('${s.code} – ${s.name}'),
                trailing: running?.subject.id == s.id ? const Text('Now') : null,
                onTap: () => Navigator.pop(c, s),
              ),
          ],
        ),
      ),
    );
    if (subject == null || !context.mounted) return;
    final startMin = now.hour * 60 + now.minute;
    final cls = running != null && running.subject.id == subject.id
        ? running
        : ClassInstance(
            date: dateKey(now),
            subject: subject,
            startMin: startMin,
            endMin: (startMin + 90).clamp(0, 24 * 60 - 1),
            overrideId: -now.millisecondsSinceEpoch ~/ 1000, // unique key for unscheduled recordings
          );
    Navigator.push(context, MaterialPageRoute(builder: (_) => RecordingScreen(classInstance: cls, autoStart: true)));
  }
}

class _ClassTile extends StatelessWidget {
  const _ClassTile(this.c, this.lecture);
  final ClassInstance c;
  final Lecture? lecture;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final live = !c.cancelled && c.start.isBefore(now.add(const Duration(minutes: 10))) && c.end.isAfter(now);
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: ListTile(
        leading: SubjectDot(c.subject),
        title: Text(
          '${c.subject.code} – ${c.subject.name}',
          style: c.cancelled ? const TextStyle(decoration: TextDecoration.lineThrough) : null,
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${c.timeRange}${c.room != null ? ' · ${c.room}' : ''}'),
            if (c.cancelled)
              Text('Cancelled today', style: TextStyle(color: Theme.of(context).colorScheme.error))
            else if (c.changed)
              Text('Changed for today', style: TextStyle(color: Theme.of(context).colorScheme.tertiary)),
            if (!c.cancelled) StatusChip(lecture),
          ],
        ),
        isThreeLine: true,
        trailing: c.cancelled
            ? null
            : lecture != null
            ? const Icon(Icons.chevron_right)
            : live
            ? FilledButton.icon(
                icon: const Icon(Icons.mic),
                label: const Text('Record'),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => RecordingScreen(classInstance: c, autoStart: true)),
                ),
              )
            : null,
        onTap: lecture == null
            ? null
            : () => Navigator.push(context, MaterialPageRoute(builder: (_) => LectureScreen(lectureId: lecture!.id))),
      ),
    );
  }
}

class _ActiveRecordingCard extends StatelessWidget {
  const _ActiveRecordingCard();

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: RecorderController.instance,
    builder: (context, _) {
      final r = RecorderController.instance;
      if (!r.isRecording) return const SizedBox.shrink();
      return Card(
        margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        color: Colors.red.shade50,
        child: ListTile(
          leading: const Icon(Icons.fiber_manual_record, color: Colors.red),
          title: Text('Recording ${r.current!.subject.code} · ${fmtDuration(r.elapsed)}'),
          subtitle: Text('Auto-stops at ${DateFormat.jm().format(r.autoStopAt!)}'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () =>
              Navigator.push(context, MaterialPageRoute(builder: (_) => RecordingScreen(classInstance: r.current!))),
        ),
      );
    },
  );
}
