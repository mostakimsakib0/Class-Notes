import 'dart:convert';
import 'dart:io';

import '../db.dart';
import '../models.dart';
import '../settings.dart';
import 'gemini.dart';
import 'notes_format.dart';
import 'telegram.dart';

class PipelineResult {
  PipelineResult(this.ok, this.message, {this.retryLater = false});
  final bool ok;
  final String message;
  final bool retryLater;
}

/// After-class processing. Each step is skipped if its result already exists, so a retry
/// resumes where the last attempt stopped:
///   1. archive audio to Telegram   2. transcribe with Gemini
///   3. generate notes with Gemini  4. archive notes to Telegram   5. delete phone copy (optional)
class Pipeline {
  Pipeline(this.db);
  final AppDb db;

  Future<PipelineResult> process(int lectureId) async {
    if (!await db.tryLock(lectureId, const Duration(minutes: 30))) {
      return PipelineResult(false, 'Already being processed');
    }
    try {
      return await _run(lectureId);
    } finally {
      await db.unlock(lectureId);
    }
  }

  Future<void> _stage(int id, String stage) =>
      db.updateLecture(id, {'status': LectureStatus.processing, 'stage': stage, 'error': null});

  Future<PipelineResult> _run(int id) async {
    var lecture = await db.lecture(id);
    if (lecture == null) return PipelineResult(false, 'Lecture not found');
    final subject = (await db.subjectMap())[lecture.subjectId];
    if (subject == null) return PipelineResult(false, 'Subject was deleted');

    final apiKey = await AppSettings.geminiKey();
    final botToken = await AppSettings.botToken();
    final chatId = await AppSettings.storageChatId();
    final missing = [if (apiKey == null) 'Gemini API key', if (botToken == null || chatId == null) 'Telegram storage'];
    if (missing.isNotEmpty) {
      final msg = 'Set up ${missing.join(' and ')} in Settings';
      await db.updateLecture(id, {'status': LectureStatus.failed, 'error': msg});
      return PipelineResult(false, msg);
    }

    final tg = Telegram(botToken!);
    final model = await AppSettings.geminiModel();
    final gemini = Gemini(apiKey!, model);
    final tag = '#${subject.code.replaceAll(RegExp(r'[^A-Za-z0-9_]'), '_')}';
    String? geminiFile;

    try {
      // 1. Archive the original audio before anything else.
      if (lecture.tgAudioMsgId == null) {
        await _stage(id, 'Saving audio to Telegram');
        final audio = _audioFile(lecture);
        if (audio == null) throw StateError('The recording file is missing from the phone');
        final sent = await tg.sendFile(
          chatId!,
          audio,
          caption:
              '🎙 $tag ${subject.name}\n${lecture.date} · ${fmtMinutes(lecture.startMin)}–${fmtMinutes(lecture.endMin)}',
          filename: '${subject.code}_${lecture.date}_${fmtMinutes(lecture.startMin).replaceAll(':', '')}.ogg',
        );
        await db.updateLecture(id, {'tg_audio_msg_id': sent.messageId, 'tg_audio_file_id': sent.fileId});
        lecture = (await db.lecture(id))!;
      }

      // 2. Transcribe.
      if (lecture.transcript == null) {
        await _stage(id, 'Transcribing with Gemini');
        final audio = await _localOrDownloaded(lecture, tg);
        final uploaded = await gemini.uploadAudio(audio, 'audio/ogg');
        geminiFile = uploaded.name;
        final transcript = await gemini.transcribe(uploaded.uri, uploaded.mime);
        await db.updateLecture(id, {'transcript': transcript, 'model': model});
        lecture = (await db.lecture(id))!;
      }

      // 3. Notes.
      if (lecture.notesAiMd == null) {
        await _stage(id, 'Writing notes with Gemini');
        final json = await gemini.makeNotes(
          transcript: lecture.transcript!,
          subjectCode: subject.code,
          subjectName: subject.name,
          teacher: subject.teacher,
          date: lecture.date,
        );
        final md = notesToMarkdown(json, subject: '${subject.code} – ${subject.name}', date: lecture.date);
        // Keep user edits if they already edited notes during a previous attempt.
        await db.updateLecture(id, {'notes_ai_md': md, if (lecture.notesMd == null) 'notes_md': md, 'model': model});
        lecture = (await db.lecture(id))!;
      }

      // 4. Archive notes (and transcript) to Telegram.
      if (lecture.tgNotesMsgId == null) {
        await _stage(id, 'Saving notes to Telegram');
        final base = '${subject.code}_${lecture.date}';
        final sent = await tg.sendBytes(
          chatId!,
          utf8.encode(lecture.notesMd ?? lecture.notesAiMd!),
          '${base}_notes.md',
          caption: '📝 $tag ${subject.name} — notes\n${lecture.date}',
        );
        await tg.sendBytes(
          chatId,
          utf8.encode(lecture.transcript!),
          '${base}_transcript.txt',
          caption: '📄 $tag transcript · ${lecture.date}',
        );
        await db.updateLecture(id, {'tg_notes_msg_id': sent.messageId});
      }

      // 5. Telegram is the storage; optionally free phone space.
      if (await AppSettings.deleteLocalAudio()) {
        final audio = _audioFile(lecture);
        if (audio != null) await audio.delete();
        await db.updateLecture(id, {'audio_path': null});
      }

      await db.updateLecture(id, {'status': LectureStatus.done, 'stage': null, 'error': null});
      return PipelineResult(true, 'Notes ready for ${subject.code}');
    } on GeminiException catch (e) {
      await db.updateLecture(id, {'status': LectureStatus.failed, 'error': e.message});
      return PipelineResult(false, e.message, retryLater: e.quota);
    } on SocketException {
      const msg = 'No internet connection';
      await db.updateLecture(id, {'status': LectureStatus.failed, 'error': msg});
      return PipelineResult(false, msg, retryLater: true);
    } catch (e) {
      await db.updateLecture(id, {'status': LectureStatus.failed, 'error': e.toString()});
      return PipelineResult(false, e.toString());
    } finally {
      if (geminiFile != null) await gemini.deleteFile(geminiFile);
    }
  }

  File? _audioFile(Lecture l) {
    if (l.audioPath == null) return null;
    final f = File(l.audioPath!);
    return f.existsSync() ? f : null;
  }

  Future<File> _localOrDownloaded(Lecture l, Telegram tg) async {
    final local = _audioFile(l);
    if (local != null) return local;
    if (l.tgAudioFileId == null) throw StateError('The recording is not on the phone or in Telegram');
    final target = File('${Directory.systemTemp.path}/lecture_${l.id}.ogg');
    await tg.download(l.tgAudioFileId!, target);
    return target;
  }
}
