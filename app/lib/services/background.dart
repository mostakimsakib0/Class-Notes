import 'dart:ui';

import 'package:workmanager/workmanager.dart';

import '../db.dart';
import '../models.dart';
import '../settings.dart';
import 'notifications.dart';
import 'pipeline.dart';

const dailyCheckTask = 'daily_notes_check';
const retryTask = 'retry_pending_notes';

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, _) async {
    DartPluginRegistrant.ensureInitialized();
    final db = await AppDb.open();
    await Notifications.init();
    if (task == dailyCheckTask) {
      await runDailyCheck(db);
      await scheduleDailyCheck();
    } else if (task == retryTask) {
      await processPending(db);
    }
    await Notifications.rescheduleAll(db); // keep the 7-day reminder window rolling
    return true;
  });
}

Future<void> initBackground() => Workmanager().initialize(callbackDispatcher);

/// Schedules the daily check (default 6 PM). WorkManager may run it a few minutes late,
/// and waits for an internet connection.
Future<void> scheduleDailyCheck() async {
  final minutes = await AppSettings.dailyCheckMin();
  final now = DateTime.now();
  var next = DateTime(now.year, now.month, now.day, minutes ~/ 60, minutes % 60);
  if (!next.isAfter(now)) next = next.add(const Duration(days: 1));
  await Workmanager().registerOneOffTask(
    dailyCheckTask,
    dailyCheckTask,
    initialDelay: next.difference(now),
    constraints: Constraints(networkType: NetworkType.connected),
    existingWorkPolicy: ExistingWorkPolicy.replace,
  );
}

Future<void> scheduleRetry() => Workmanager().registerOneOffTask(
  retryTask,
  retryTask,
  initialDelay: const Duration(minutes: 15),
  constraints: Constraints(networkType: NetworkType.connected),
  existingWorkPolicy: ExistingWorkPolicy.keep,
);

/// Processes every recorded lecture that does not have finished notes yet.
Future<({int ok, int failed})> processPending(AppDb db) async {
  var ok = 0, failed = 0;
  final subjects = await db.subjectMap();
  for (final l in await db.unfinishedLectures()) {
    final result = await Pipeline(db).process(l.id);
    final code = subjects[l.subjectId]?.code ?? 'class';
    if (result.ok) {
      ok++;
      await Notifications.showLecture(l.id, 'Notes ready: $code', 'Saved to Telegram. Tap to open.');
    } else if (result.message != 'Already being processed') {
      failed++;
    }
  }
  return (ok: ok, failed: failed);
}

/// 6 PM check: for today's classes that have ended, make sure notes exist. Creates any missing
/// notes from recordings, and reports classes that were never recorded.
Future<void> runDailyCheck(AppDb db) async {
  final now = DateTime.now();
  final classes = (await db.classesFor(now)).where((c) => !c.cancelled && c.end.isBefore(now)).toList();
  final processed = await processPending(db);
  final lectures = await db.lecturesOn(dateKey(now));

  final noRecording = <String>[];
  final noNotes = <String>[];
  for (final c in classes) {
    final l = lectures.where((l) => l.classKey == c.key).firstOrNull;
    if (l == null) {
      noRecording.add(c.subject.code);
    } else if (!l.hasNotes) {
      noNotes.add('${c.subject.code}${l.error != null ? ' (${l.error})' : ''}');
    }
  }
  if (classes.isEmpty && processed.ok == 0 && processed.failed == 0) return;

  final lines = <String>[
    if (processed.ok > 0) '✓ Created ${processed.ok} missing note${processed.ok == 1 ? '' : 's'}',
    if (noRecording.isNotEmpty) '✕ Not recorded: ${noRecording.join(', ')}',
    if (noNotes.isNotEmpty) '⚠ Notes failed: ${noNotes.join('; ')}',
  ];
  final allGood = noRecording.isEmpty && noNotes.isEmpty;
  await Notifications.showInfo(
    NotifIds.dailyCheck,
    allGood ? 'All ${classes.length} class notes are ready' : 'Some class notes are missing',
    lines.isEmpty ? 'Every class today has notes.' : lines.join('\n'),
    payload: 'today',
  );
}
