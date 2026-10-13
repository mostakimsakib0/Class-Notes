import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:intl/intl.dart';

import '../db.dart';
import '../models.dart';
import '../services/recorder.dart';
import 'common.dart';

class LectureScreen extends StatefulWidget {
  const LectureScreen({super.key, required this.lectureId});
  final int lectureId;

  @override
  State<LectureScreen> createState() => _LectureScreenState();
}

class _LectureScreenState extends State<LectureScreen> {
  Lecture? lecture;
  Subject? subject;
  bool editing = false;
  final editor = TextEditingController();
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _load();
    dataVersion.addListener(_load);
    // Refresh while processing runs in the background.
    _poll = Timer.periodic(const Duration(seconds: 3), (_) {
      if (lecture?.status == LectureStatus.processing || lecture?.status == LectureStatus.recorded) _load();
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    dataVersion.removeListener(_load);
    editor.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final db = await AppDb.open();
    final l = await db.lecture(widget.lectureId);
    final s = l == null ? null : (await db.subjectMap())[l.subjectId];
    if (!mounted) return;
    setState(() {
      lecture = l;
      subject = s;
    });
  }

  Future<void> _saveEdit() async {
    await (await AppDb.open()).updateLecture(lecture!.id, {'notes_md': editor.text});
    setState(() => editing = false);
    await _load();
    if (mounted) toast(context, 'Saved on phone. Tap "Send to Telegram" to update the copy there.');
  }

  Future<void> _resendNotes() async {
    await (await AppDb.open()).updateLecture(lecture!.id, {'tg_notes_msg_id': null, 'status': LectureStatus.recorded});
    unawaited(RecorderController.processNow(lecture!.id, subject?.code ?? ''));
    await _load();
  }

  Future<void> _retry() async {
    await (await AppDb.open()).updateLecture(lecture!.id, {'status': LectureStatus.recorded, 'error': null});
    unawaited(RecorderController.processNow(lecture!.id, subject?.code ?? ''));
    await _load();
  }

  Future<void> _regenerate() async {
    if (!await confirm(
      context,
      'Regenerate notes?',
      'Gemini writes new notes from the transcript. Your edits to the current notes will be replaced.',
      ok: 'Regenerate',
    )) {
      return;
    }
    await (await AppDb.open()).updateLecture(lecture!.id, {
      'notes_ai_md': null,
      'notes_md': null,
      'tg_notes_msg_id': null,
      'status': LectureStatus.recorded,
    });
    unawaited(RecorderController.processNow(lecture!.id, subject?.code ?? ''));
    await _load();
  }

  Future<void> _delete() async {
    if (!await confirm(
      context,
      'Delete this lecture?',
      'Removes it from the phone. Files already saved in Telegram are not deleted.',
      ok: 'Delete',
    )) {
      return;
    }
    await (await AppDb.open()).deleteLecture(lecture!.id);
    dataChanged();
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final l = lecture;
    if (l == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final busy = l.status == LectureStatus.processing || l.status == LectureStatus.recorded;
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Text('${subject?.code ?? ''} · ${DateFormat('d MMM').format(parseDateKey(l.date))}'),
          actions: [
            if (l.hasNotes && !editing)
              IconButton(
                tooltip: 'Edit notes',
                icon: const Icon(Icons.edit_outlined),
                onPressed: () => setState(() {
                  editor.text = l.notesMd!;
                  editing = true;
                }),
              ),
            if (editing) IconButton(tooltip: 'Save', icon: const Icon(Icons.check), onPressed: _saveEdit),
            PopupMenuButton<String>(
              onSelected: (v) => switch (v) {
                'copy' => Clipboard.setData(ClipboardData(text: l.notesMd ?? '')).then((_) {
                  if (context.mounted) toast(context, 'Notes copied');
                }),
                'resend' => _resendNotes(),
                'regenerate' => _regenerate(),
                'delete' => _delete(),
                _ => null,
              },
              itemBuilder: (_) => [
                if (l.hasNotes) const PopupMenuItem(value: 'copy', child: Text('Copy notes (Markdown)')),
                if (l.hasNotes) const PopupMenuItem(value: 'resend', child: Text('Send edited notes to Telegram')),
                if (l.transcript != null) const PopupMenuItem(value: 'regenerate', child: Text('Regenerate notes')),
                const PopupMenuItem(value: 'delete', child: Text('Delete')),
              ],
            ),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Notes'),
              Tab(text: 'Transcript'),
              Tab(text: 'Status'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            // Notes
            if (editing)
              Padding(
                padding: const EdgeInsets.all(12),
                child: TextField(
                  controller: editor,
                  maxLines: null,
                  expands: true,
                  textAlignVertical: TextAlignVertical.top,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                  decoration: const InputDecoration(border: OutlineInputBorder()),
                ),
              )
            else if (l.hasNotes)
              Markdown(data: l.notesMd!, selectable: true, padding: const EdgeInsets.fromLTRB(16, 16, 16, 48))
            else
              _placeholder(context, l, busy),
            // Transcript
            l.transcript == null
                ? _placeholder(context, l, busy)
                : SingleChildScrollView(padding: const EdgeInsets.all(16), child: SelectableText(l.transcript!)),
            // Status
            ListView(
              padding: const EdgeInsets.all(8),
              children: [
                ListTile(title: const Text('Status'), subtitle: StatusChip(l)),
                if (l.error != null)
                  ListTile(
                    leading: Icon(Icons.error_outline, color: Theme.of(context).colorScheme.error),
                    title: Text(l.error!),
                  ),
                ListTile(
                  title: const Text('Class time'),
                  subtitle: Text('${fmtTime12(l.startMin)} – ${fmtTime12(l.endMin)}'),
                ),
                if (l.durationSec != null)
                  ListTile(
                    title: const Text('Recorded'),
                    subtitle: Text(fmtDuration(Duration(seconds: l.durationSec!))),
                  ),
                _check('Audio saved to Telegram', l.tgAudioMsgId != null),
                _check('Transcript', l.transcript != null),
                _check('Notes', l.notesAiMd != null),
                _check('Notes saved to Telegram', l.tgNotesMsgId != null),
                _check('Copy on phone', l.audioPath != null),
                if (l.model != null) ListTile(title: const Text('Gemini model'), subtitle: Text(l.model!)),
                if (l.status == LectureStatus.failed)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: FilledButton.icon(
                      icon: const Icon(Icons.refresh),
                      label: const Text('Try again'),
                      onPressed: _retry,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _check(String label, bool done) => ListTile(
    dense: true,
    leading: Icon(done ? Icons.check_circle : Icons.radio_button_unchecked, color: done ? Colors.green : null),
    title: Text(label),
  );

  Widget _placeholder(BuildContext context, Lecture l, bool busy) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (busy) const CircularProgressIndicator() else const Icon(Icons.hourglass_empty, size: 48),
          const SizedBox(height: 16),
          Text(
            l.status == LectureStatus.recording
                ? 'Recording in progress'
                : busy
                ? (l.stage ?? 'Waiting to process…')
                : l.error ?? 'Not available',
            textAlign: TextAlign.center,
          ),
          if (l.status == LectureStatus.failed) ...[
            const SizedBox(height: 16),
            FilledButton.icon(icon: const Icon(Icons.refresh), label: const Text('Try again'), onPressed: _retry),
          ],
        ],
      ),
    ),
  );
}
