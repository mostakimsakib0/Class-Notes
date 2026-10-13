import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

class GeminiException implements Exception {
  GeminiException(this.message, {this.quota = false});
  final String message;

  /// True for 429 / quota errors: retry later rather than treating as a hard failure.
  final bool quota;
  @override
  String toString() => message;
}

class GeminiModel {
  GeminiModel(this.id, this.displayName);
  final String id; // e.g. "gemini-2.5-flash"
  final String displayName;
}

/// Gemini REST client: Files API upload, transcription, and structured notes.
class Gemini {
  Gemini(this.apiKey, this.model);
  final String apiKey;
  final String model;

  static const _base = 'https://generativelanguage.googleapis.com';
  static const transcriptPromptVersion = 't1';
  static const notesPromptVersion = 'n1';

  Map<String, String> get _auth => {'x-goog-api-key': apiKey};

  Map<String, dynamic> _check(http.Response r) {
    Map<String, dynamic>? body;
    try {
      body = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
    } catch (_) {}
    if (r.statusCode >= 200 && r.statusCode < 300 && body != null) return body;
    final msg = (body?['error']?['message'] as String?) ?? 'HTTP ${r.statusCode}';
    if (r.statusCode == 429 || (body?['error']?['status'] == 'RESOURCE_EXHAUSTED')) {
      throw GeminiException('Gemini quota/rate limit reached: $msg', quota: true);
    }
    if (r.statusCode == 400 && msg.contains('API key')) throw GeminiException('Gemini API key is invalid');
    throw GeminiException('Gemini: $msg');
  }

  /// Validates the key and lists models that can generate content.
  Future<List<GeminiModel>> listModels() async {
    final r = await http
        .get(Uri.parse('$_base/v1beta/models?pageSize=200'), headers: _auth)
        .timeout(const Duration(seconds: 30));
    final models = (_check(r)['models'] as List? ?? []).cast<Map<String, dynamic>>();
    return models
        .where((m) => (m['supportedGenerationMethods'] as List? ?? []).contains('generateContent'))
        .map(
          (m) =>
              GeminiModel((m['name'] as String).replaceFirst('models/', ''), (m['displayName'] ?? m['name']) as String),
        )
        .where((m) => m.id.startsWith('gemini'))
        .toList();
  }

  /// Uploads audio via the resumable Files API and waits until it is ready.
  Future<({String name, String uri, String mime})> uploadAudio(File file, String mime) async {
    final bytes = await file.readAsBytes();
    final start = await http
        .post(
          Uri.parse('$_base/upload/v1beta/files'),
          headers: {
            ..._auth,
            'X-Goog-Upload-Protocol': 'resumable',
            'X-Goog-Upload-Command': 'start',
            'X-Goog-Upload-Header-Content-Length': '${bytes.length}',
            'X-Goog-Upload-Header-Content-Type': mime,
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'file': {'display_name': file.uri.pathSegments.last},
          }),
        )
        .timeout(const Duration(seconds: 60));
    if (start.statusCode != 200) _check(start);
    final uploadUrl = start.headers['x-goog-upload-url'];
    if (uploadUrl == null) throw GeminiException('Gemini did not return an upload URL');

    final done = await http
        .post(
          Uri.parse(uploadUrl),
          headers: {'X-Goog-Upload-Offset': '0', 'X-Goog-Upload-Command': 'upload, finalize'},
          body: bytes,
        )
        .timeout(const Duration(minutes: 10));
    var info = _check(done)['file'] as Map<String, dynamic>;

    for (var i = 0; i < 60 && info['state'] == 'PROCESSING'; i++) {
      await Future.delayed(const Duration(seconds: 5));
      info = _check(await http.get(Uri.parse('$_base/v1beta/${info['name']}'), headers: _auth));
    }
    if (info['state'] != 'ACTIVE') throw GeminiException('Gemini could not process the audio file (${info['state']})');
    return (name: info['name'] as String, uri: info['uri'] as String, mime: (info['mimeType'] ?? mime) as String);
  }

  Future<void> deleteFile(String name) async {
    try {
      await http.delete(Uri.parse('$_base/v1beta/$name'), headers: _auth).timeout(const Duration(seconds: 30));
    } catch (_) {
      // Uploaded files expire on their own after 48 hours.
    }
  }

  Future<({String text, bool truncated})> _generate(
    List<Map<String, dynamic>> parts, {
    Map<String, dynamic>? schema,
  }) async {
    final r = await http
        .post(
          Uri.parse('$_base/v1beta/models/$model:generateContent'),
          headers: {..._auth, 'Content-Type': 'application/json'},
          body: jsonEncode({
            'contents': [
              {'role': 'user', 'parts': parts},
            ],
            'generationConfig': {
              'maxOutputTokens': 65536,
              if (schema != null) 'responseMimeType': 'application/json',
              'responseSchema': ?schema,
            },
          }),
        )
        .timeout(const Duration(minutes: 15));
    final body = _check(r);
    final candidates = body['candidates'] as List?;
    if (candidates == null || candidates.isEmpty) {
      final reason = body['promptFeedback']?['blockReason'];
      throw GeminiException('Gemini returned no result${reason != null ? ' (blocked: $reason)' : ''}');
    }
    final c = candidates.first as Map<String, dynamic>;
    final text = ((c['content']?['parts'] as List?) ?? [])
        .map((p) => (p as Map<String, dynamic>)['text'] as String? ?? '')
        .join();
    if (text.trim().isEmpty) throw GeminiException('Gemini returned an empty response (${c['finishReason']})');
    return (text: text, truncated: c['finishReason'] == 'MAX_TOKENS');
  }

  Future<String> transcribe(String fileUri, String mime) async {
    final result = await _generate([
      {
        'file_data': {'mime_type': mime, 'file_uri': fileUri},
      },
      {'text': _transcriptPrompt},
    ]);
    return result.truncated
        ? '${result.text}\n\n[Transcript cut off: the lecture was too long for one response.]'
        : result.text;
  }

  Future<Map<String, dynamic>> makeNotes({
    required String transcript,
    required String subjectCode,
    required String subjectName,
    String? teacher,
    required String date,
  }) async {
    final result = await _generate([
      {
        'text':
            '$_notesPrompt\n\nCourse: $subjectCode – $subjectName'
            '${teacher != null ? '\nInstructor: $teacher' : ''}\nDate: $date\n\nTRANSCRIPT:\n$transcript',
      },
    ], schema: _notesSchema);
    try {
      return jsonDecode(result.text) as Map<String, dynamic>;
    } on FormatException {
      throw GeminiException('Gemini returned malformed notes${result.truncated ? ' (output was cut off)' : ''}');
    }
  }

  static const _transcriptPrompt = '''
Transcribe this university lecture recording.

Rules:
- The lecture may be in Bangla, English, or a mix. Write Bangla speech in Bangla script and English words,
  technical terms, code and formulas in English exactly as spoken. Do not translate.
- Transcribe faithfully. Do not summarize, correct the lecturer, or add anything that was not said.
- Start a new paragraph whenever the topic or speaker changes, beginning with a timestamp like [00:12:34].
- Prefix questions or comments from students with "Student:".
- Write [unclear] for speech you cannot make out. Never guess.
- Output plain text only.''';

  static const _notesPrompt = '''
You are making study notes for a university student from the lecture transcript below.

Rules:
- Use ONLY what is in the transcript. If something is unclear or needs checking, put it in "uncertain"
  instead of guessing. Do not invent formulas, definitions or examples that were not discussed.
- Write in English. Keep important Bangla phrases in Bangla where they carry meaning.
- Include transcript timestamps (e.g. "00:12:34") for topics so the student can find them.
- Questions and MCQs must be answerable from the lecture content.
- Leave a list empty if the lecture had nothing for it.''';

  static Map<String, dynamic> _arr(Map<String, dynamic> items) => {'type': 'ARRAY', 'items': items};
  static const _str = {'type': 'STRING'};
  static Map<String, dynamic> _obj(Map<String, dynamic> props) => {
    'type': 'OBJECT',
    'properties': props,
    'required': props.keys.toList(),
  };

  static final _notesSchema = _obj({
    'title': _str,
    'summary': _str,
    'objectives': _arr(_str),
    'topics': _arr(_obj({'heading': _str, 'timestamp': _str, 'explanation': _str})),
    'definitions': _arr(_obj({'term': _str, 'meaning': _str})),
    'formulas': _arr(_obj({'formula': _str, 'explanation': _str})),
    'examples': _arr(_str),
    'emphasized_points': _arr(_str),
    'short_questions': _arr(_str),
    'mcqs': _arr(_obj({'question': _str, 'options': _arr(_str), 'answer': _str, 'explanation': _str})),
    'flashcards': _arr(_obj({'front': _str, 'back': _str})),
    'revision_checklist': _arr(_str),
    'uncertain': _arr(_str),
  });
}
