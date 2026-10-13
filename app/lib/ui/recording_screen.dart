import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models.dart';
import '../services/recorder.dart';
import 'common.dart';

class RecordingScreen extends StatefulWidget {
  const RecordingScreen({super.key, required this.classInstance, this.autoStart = false});
  final ClassInstance classInstance;
  final bool autoStart;

  @override
  State<RecordingScreen> createState() => _RecordingScreenState();
}

class _RecordingScreenState extends State<RecordingScreen> {
  final r = RecorderController.instance;
  String? error;

  @override
  void initState() {
    super.initState();
    if (widget.autoStart && !r.isRecording) WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  Future<void> _start() async {
    final e = await r.start(widget.classInstance);
    if (mounted) setState(() => error = e);
  }

  Future<void> _stop() async {
    if (!await confirm(context, 'Stop recording?', 'Notes will be created and saved to Telegram.', ok: 'Stop')) return;
    await r.stop();
    if (mounted) {
      toast(context, 'Saved. Creating notes in the background…');
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.classInstance;
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(c.subject.code)),
      body: ListenableBuilder(
        listenable: r,
        builder: (context, _) {
          final recordingThis = r.isRecording && r.current?.key == c.key;
          final recordingOther = r.isRecording && !recordingThis;
          // Map -60..0 dBFS onto 0..1 for the meter.
          final level = ((r.level + 60) / 60).clamp(0.0, 1.0);
          return Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(c.subject.name, style: Theme.of(context).textTheme.titleLarge, textAlign: TextAlign.center),
                Text('${c.timeRange}${c.room != null ? ' · ${c.room}' : ''}', textAlign: TextAlign.center),
                const Spacer(),
                if (recordingThis) ...[
                  const Icon(Icons.fiber_manual_record, color: Colors.red, size: 32),
                  Text(
                    fmtDuration(r.elapsed),
                    textAlign: TextAlign.center,
                    style: Theme.of(
                      context,
                    ).textTheme.displayMedium?.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
                  ),
                  const SizedBox(height: 16),
                  LinearProgressIndicator(value: level, minHeight: 10, borderRadius: BorderRadius.circular(5)),
                  const SizedBox(height: 8),
                  Text(
                    r.seemsSilent ? '⚠ No sound for 2+ minutes — is the mic covered?' : 'Microphone level',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: r.seemsSilent ? scheme.error : null),
                  ),
                  const SizedBox(height: 24),
                  Text('Stops automatically at ${DateFormat.jm().format(r.autoStopAt!)}', textAlign: TextAlign.center),
                  TextButton(
                    onPressed: () => r.extend(const Duration(minutes: 15)),
                    child: const Text('Extend 15 min'),
                  ),
                  const Text('You can lock the phone; recording continues.', textAlign: TextAlign.center),
                ] else if (recordingOther)
                  Text('Already recording ${r.current!.subject.code}. Stop it first.', textAlign: TextAlign.center)
                else ...[
                  const Icon(Icons.mic_none, size: 64),
                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: Text(
                        error!,
                        textAlign: TextAlign.center,
                        style: TextStyle(color: scheme.error),
                      ),
                    ),
                ],
                const Spacer(),
                if (recordingThis)
                  FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: Colors.red, minimumSize: const Size.fromHeight(56)),
                    icon: const Icon(Icons.stop),
                    label: const Text('Stop & make notes'),
                    onPressed: _stop,
                  )
                else if (!recordingOther)
                  FilledButton.icon(
                    style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
                    icon: const Icon(Icons.mic),
                    label: const Text('Start recording'),
                    onPressed: _start,
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}
