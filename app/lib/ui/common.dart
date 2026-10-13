import 'package:flutter/material.dart';

import '../models.dart';
import '../services/recorder.dart';

/// Loads data with [load] and rebuilds whenever stored data changes (see [dataChanged]).
class DataBuilder<T> extends StatefulWidget {
  const DataBuilder({super.key, required this.load, required this.builder});
  final Future<T> Function() load;
  final Widget Function(BuildContext context, T data) builder;

  @override
  State<DataBuilder<T>> createState() => _DataBuilderState<T>();
}

class _DataBuilderState<T> extends State<DataBuilder<T>> {
  late Future<T> _future = widget.load();

  void _reload() => setState(() => _future = widget.load());

  @override
  void initState() {
    super.initState();
    dataVersion.addListener(_reload);
  }

  @override
  void dispose() {
    dataVersion.removeListener(_reload);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<T>(
    future: _future,
    builder: (context, snap) {
      if (snap.hasError) {
        return Center(
          child: Padding(padding: const EdgeInsets.all(24), child: Text('Error: ${snap.error}')),
        );
      }
      if (!snap.hasData) return const Center(child: CircularProgressIndicator());
      return widget.builder(context, snap.data as T);
    },
  );
}

void toast(BuildContext context, String message) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));

Future<bool> confirm(BuildContext context, String title, String body, {String ok = 'OK'}) async =>
    await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(ok)),
        ],
      ),
    ) ??
    false;

Future<int?> pickTime(BuildContext context, int initialMin, {String? help}) async {
  final t = await showTimePicker(
    context: context,
    helpText: help,
    initialTime: TimeOfDay(hour: initialMin ~/ 60, minute: initialMin % 60),
  );
  return t == null ? null : t.hour * 60 + t.minute;
}

class SubjectDot extends StatelessWidget {
  const SubjectDot(this.subject, {super.key, this.size = 40});
  final Subject subject;
  final double size;

  @override
  Widget build(BuildContext context) => CircleAvatar(
    radius: size / 2,
    backgroundColor: Color(subject.color),
    child: Text(
      subject.code.replaceAll(RegExp(r'[^A-Za-z]'), '').padRight(1).substring(0, 1).toUpperCase(),
      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
    ),
  );
}

class StatusChip extends StatelessWidget {
  const StatusChip(this.lecture, {super.key});
  final Lecture? lecture;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (label, color, icon) = switch (lecture?.status) {
      null => ('Not recorded', scheme.outline, Icons.mic_off_outlined),
      LectureStatus.recording => ('Recording', Colors.red, Icons.fiber_manual_record),
      LectureStatus.recorded => ('Waiting', scheme.tertiary, Icons.schedule),
      LectureStatus.processing => (lecture!.stage ?? 'Processing', scheme.primary, Icons.autorenew),
      LectureStatus.done => ('Notes ready', Colors.green.shade700, Icons.check_circle),
      _ => ('Failed', scheme.error, Icons.error_outline),
    };
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            label,
            style: TextStyle(color: color, fontSize: 12),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

String fmtDuration(Duration d) {
  final h = d.inHours, m = d.inMinutes % 60, s = d.inSeconds % 60;
  return h > 0
      ? '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}'
      : '$m:${s.toString().padLeft(2, '0')}';
}

const subjectColors = [
  0xFF3F51B5,
  0xFF009688,
  0xFFE91E63,
  0xFFFF9800,
  0xFF673AB7,
  0xFF4CAF50,
  0xFF795548,
  0xFF2196F3,
  0xFFF44336,
  0xFF607D8B,
];
