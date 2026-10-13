/// Renders the structured notes JSON from Gemini into Markdown.
String notesToMarkdown(Map<String, dynamic> n, {required String subject, required String date}) {
  final b = StringBuffer();
  List<dynamic> list(String key) => (n[key] as List?) ?? const [];
  String s(Object? v) => (v ?? '').toString().trim();

  void section(String title, String key, void Function(dynamic item) write) {
    final items = list(key);
    if (items.isEmpty) return;
    b.writeln('\n## $title\n');
    items.forEach(write);
  }

  b.writeln('# ${s(n['title']).isEmpty ? subject : s(n['title'])}');
  b.writeln('\n*$subject · $date*');
  if (s(n['summary']).isNotEmpty) b.writeln('\n## Summary\n\n${s(n['summary'])}');

  section('Learning objectives', 'objectives', (o) => b.writeln('- ${s(o)}'));
  section('Topics', 'topics', (t) {
    final ts = s(t['timestamp']);
    b.writeln('### ${s(t['heading'])}${ts.isNotEmpty ? ' `[$ts]`' : ''}\n\n${s(t['explanation'])}\n');
  });
  section('Definitions', 'definitions', (d) => b.writeln('- **${s(d['term'])}** — ${s(d['meaning'])}'));
  section('Formulas', 'formulas', (f) => b.writeln('- `${s(f['formula'])}` — ${s(f['explanation'])}'));
  section('Examples', 'examples', (e) => b.writeln('- ${s(e)}'));
  section('Points the lecturer emphasized', 'emphasized_points', (p) => b.writeln('- ${s(p)}'));
  section('Short questions', 'short_questions', (q) => b.writeln('1. ${s(q)}'));

  final mcqs = list('mcqs');
  if (mcqs.isNotEmpty) {
    b.writeln('\n## MCQs\n');
    for (var i = 0; i < mcqs.length; i++) {
      final q = mcqs[i];
      b.writeln('**${i + 1}. ${s(q['question'])}**\n');
      final options = (q['options'] as List?) ?? const [];
      for (var j = 0; j < options.length; j++) {
        b.writeln('${String.fromCharCode(97 + j)}) ${s(options[j])}  ');
      }
      b.writeln('\n> **Answer:** ${s(q['answer'])} — ${s(q['explanation'])}\n');
    }
  }

  section('Flashcards', 'flashcards', (f) => b.writeln('- **Q:** ${s(f['front'])}  \n  **A:** ${s(f['back'])}'));
  section('Revision checklist', 'revision_checklist', (c) => b.writeln('- [ ] ${s(c)}'));
  section('Needs checking', 'uncertain', (u) => b.writeln('- ⚠️ ${s(u)}'));

  b.writeln('\n---\n*AI-generated from the lecture recording. Check important points against your course material.*');
  return b.toString();
}
