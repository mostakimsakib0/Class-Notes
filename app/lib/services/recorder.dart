import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../db.dart';
import '../models.dart';
import '../settings.dart';
import 'background.dart';
import 'notifications.dart';
import 'pipeline.dart';

/// Records a class with the phone microphone in a foreground service (keeps running with the screen off),
/// stops automatically after the class ends, then starts note processing.
class RecorderController extends ChangeNotifier {
  RecorderController._();
  static final instance = RecorderController._();

  final _rec = AudioRecorder();
  ClassInstance? current;
  int? lectureId;
  DateTime? startedAt;
  DateTime? autoStopAt;
  double level = -160; // dBFS, for the input meter
  DateTime? lastSoundAt;
  Timer? _autoStop;
  Timer? _tick;
  StreamSubscription<Amplitude>? _amp;

  bool get isRecording => current != null;
  Duration get elapsed => startedAt == null ? Duration.zero : DateTime.now().difference(startedAt!);

  /// No sound above -45 dBFS for 2+ minutes: probably a covered mic or an empty room.
  bool get seemsSilent => lastSoundAt != null && DateTime.now().difference(lastSoundAt!) > const Duration(minutes: 2);

  /// Returns an error message, or null when recording started.
  Future<String?> start(ClassInstance c) async {
    if (isRecording) return 'Already recording ${current!.subject.code}';
    if (!await _rec.hasPermission()) return 'Microphone permission is required';

    final dir = Directory('${(await getApplicationDocumentsDirectory()).path}/recordings');
    await dir.create(recursive: true);
    final stamp = DateTime.now().toIso8601String().replaceAll(RegExp(r'[:.]'), '-');
    final path = '${dir.path}/${c.subject.code}_$stamp.ogg';

    final db = await AppDb.open();
    final grace = await AppSettings.stopGraceMin();
    try {
      await _rec.start(
        RecordConfig(
          encoder: AudioEncoder.opus, // OGG/Opus on Android 10+: ~11 MB per hour at 24 kbps
          bitRate: 24000,
          sampleRate: 16000,
          numChannels: 1,
          androidConfig: AndroidRecordConfig(
            service: AndroidService(
              title: 'Recording ${c.subject.code}',
              content: 'Stops automatically at ${fmtTime12(c.endMin + grace)}',
            ),
          ),
        ),
        path: path,
      );
    } catch (e) {
      return 'Could not start recording: $e';
    }

    lectureId = await db.createLecture(c, path);
    current = c;
    startedAt = DateTime.now();
    lastSoundAt = startedAt;
    var stopAt = c.end.add(Duration(minutes: grace));
    if (!stopAt.isAfter(DateTime.now())) stopAt = DateTime.now().add(const Duration(minutes: 90));
    autoStopAt = stopAt;
    _autoStop = Timer(stopAt.difference(DateTime.now()), () => stop());
    _tick = Timer.periodic(const Duration(seconds: 1), (_) => notifyListeners());
    _amp = _rec.onAmplitudeChanged(const Duration(milliseconds: 400)).listen((a) {
      level = a.current;
      if (a.current > -45) lastSoundAt = DateTime.now();
    });
    notifyListeners();
    return null;
  }

  /// Push the automatic stop later (e.g. the class ran over).
  void extend(Duration by) {
    if (!isRecording || autoStopAt == null) return;
    _autoStop?.cancel();
    autoStopAt = autoStopAt!.add(by);
    _autoStop = Timer(autoStopAt!.difference(DateTime.now()), () => stop());
    notifyListeners();
  }

  Future<void> stop() async {
    if (!isRecording) return;
    _autoStop?.cancel();
    _tick?.cancel();
    await _amp?.cancel();
    final id = lectureId!;
    final duration = elapsed.inSeconds;
    final c = current!;
    String? path;
    try {
      path = await _rec.stop();
    } catch (_) {}
    current = null;
    lectureId = null;
    startedAt = null;
    autoStopAt = null;
    notifyListeners();

    final db = await AppDb.open();
    final ok = path != null && File(path).existsSync() && File(path).lengthSync() > 0;
    await db.updateLecture(id, {
      'status': ok ? LectureStatus.recorded : LectureStatus.failed,
      'duration_sec': duration,
      if (!ok) 'error': 'The recording file was not saved',
    });
    dataChanged();
    if (ok) unawaited(processNow(id, c.subject.code));
  }

  /// Runs the pipeline now; if it fails for a temporary reason, queue a background retry.
  static Future<void> processNow(int id, String code) async {
    final db = await AppDb.open();
    final result = await Pipeline(db).process(id);
    dataChanged();
    if (result.ok) {
      await Notifications.showLecture(id, 'Notes ready: $code', 'Saved to Telegram. Tap to open.');
    } else if (result.message != 'Already being processed') {
      await Notifications.showLecture(id, 'Notes for $code not created yet', result.message);
      if (result.retryLater) await scheduleRetry();
    }
  }

  /// After a crash or force-stop, lectures left in "recording" are recovered or marked failed.
  static Future<void> recoverInterrupted() async {
    if (instance.isRecording) return;
    final db = await AppDb.open();
    final rows = await db.db.query('lectures', where: 'status = ?', whereArgs: [LectureStatus.recording]);
    for (final l in rows.map(Lecture.fromMap)) {
      final f = l.audioPath == null ? null : File(l.audioPath!);
      final usable = f != null && f.existsSync() && f.lengthSync() > 10 * 1024;
      await db.updateLecture(l.id, {
        'status': usable ? LectureStatus.recorded : LectureStatus.failed,
        if (!usable) 'error': 'Recording was interrupted (app closed or phone restarted)',
      });
    }
  }
}

/// Bumped whenever stored data changes so open screens reload.
final dataVersion = ValueNotifier<int>(0);
void dataChanged() => dataVersion.value++;
