import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

class TelegramException implements Exception {
  TelegramException(this.message);
  final String message;
  @override
  String toString() => message;
}

class TgChat {
  TgChat(this.id, this.title, this.type);
  final int id;
  final String title;
  final String type;
}

class TgMessage {
  TgMessage(this.messageId, this.fileId);
  final int messageId;
  final String? fileId;
}

/// Minimal Telegram Bot API client. Telegram is used as storage: the bot posts
/// audio and notes into a private channel/group where it is an admin.
///
/// Bot API limits: uploads up to 50 MB, downloads (getFile) up to 20 MB.
class Telegram {
  Telegram(this.token);
  final String token;

  static const maxUploadBytes = 50 * 1024 * 1024;
  static const maxDownloadBytes = 20 * 1024 * 1024;

  Uri _uri(String method) => Uri.parse('https://api.telegram.org/bot$token/$method');

  Map<String, dynamic> _check(http.Response r) {
    final Map<String, dynamic> body;
    try {
      body = jsonDecode(r.body) as Map<String, dynamic>;
    } catch (_) {
      throw TelegramException('Telegram returned HTTP ${r.statusCode}');
    }
    if (body['ok'] != true) throw TelegramException('Telegram: ${body['description'] ?? 'request failed'}');
    return body;
  }

  Future<Map<String, dynamic>> _call(String method, [Map<String, dynamic>? params]) async {
    final r = await http
        .post(_uri(method), headers: {'Content-Type': 'application/json'}, body: jsonEncode(params ?? {}))
        .timeout(const Duration(seconds: 60));
    return _check(r);
  }

  Future<String> botName() async => '@${(await _call('getMe'))['result']['username']}';

  /// Channels/groups the bot has recently seen messages from. Used to auto-detect the storage chat:
  /// the user posts any message in their private channel, then the app reads it here.
  Future<List<TgChat>> recentChats() async {
    final updates =
        (await _call('getUpdates', {
              'allowed_updates': ['message', 'channel_post', 'my_chat_member'],
            }))['result']
            as List;
    final chats = <int, TgChat>{};
    for (final u in updates.cast<Map<String, dynamic>>()) {
      final chat = (u['channel_post'] ?? u['message'] ?? u['my_chat_member'])?['chat'] as Map<String, dynamic>?;
      if (chat == null || chat['type'] == 'private') continue;
      chats[chat['id'] as int] = TgChat(chat['id'] as int, (chat['title'] ?? '') as String, chat['type'] as String);
    }
    return chats.values.toList();
  }

  Future<TgMessage> sendMessage(int chatId, String text) async {
    final r = await _call('sendMessage', {'chat_id': chatId, 'text': text});
    return TgMessage(r['result']['message_id'] as int, null);
  }

  Future<TgMessage> sendFile(int chatId, File file, {String? caption, String? filename}) async {
    final size = await file.length();
    if (size > maxUploadBytes) {
      throw TelegramException(
        'File is ${(size / 1048576).toStringAsFixed(1)} MB; Telegram bots can upload at most 50 MB',
      );
    }
    final req = http.MultipartRequest('POST', _uri('sendDocument'))
      ..fields['chat_id'] = '$chatId'
      ..files.add(await http.MultipartFile.fromPath('document', file.path, filename: filename));
    if (caption != null) req.fields['caption'] = caption.length > 1024 ? caption.substring(0, 1024) : caption;
    return _parseFileMessage(await http.Response.fromStream(await req.send().timeout(const Duration(minutes: 10))));
  }

  Future<TgMessage> sendBytes(int chatId, List<int> bytes, String filename, {String? caption}) async {
    final req = http.MultipartRequest('POST', _uri('sendDocument'))
      ..fields['chat_id'] = '$chatId'
      ..files.add(http.MultipartFile.fromBytes('document', bytes, filename: filename));
    if (caption != null) req.fields['caption'] = caption.length > 1024 ? caption.substring(0, 1024) : caption;
    return _parseFileMessage(await http.Response.fromStream(await req.send().timeout(const Duration(minutes: 2))));
  }

  TgMessage _parseFileMessage(http.Response r) {
    final result = _check(r)['result'] as Map<String, dynamic>;
    final doc = (result['document'] ?? result['audio'] ?? result['voice']) as Map<String, dynamic>?;
    return TgMessage(result['message_id'] as int, doc?['file_id'] as String?);
  }

  /// Downloads a stored file back (only works for files up to 20 MB).
  Future<void> download(String fileId, File target) async {
    final info = (await _call('getFile', {'file_id': fileId}))['result'] as Map<String, dynamic>;
    final path = info['file_path'] as String?;
    if (path == null) throw TelegramException('File is larger than 20 MB; bots cannot download it');
    final r = await http
        .get(Uri.parse('https://api.telegram.org/file/bot$token/$path'))
        .timeout(const Duration(minutes: 5));
    if (r.statusCode != 200) throw TelegramException('Download failed (HTTP ${r.statusCode})');
    await target.writeAsBytes(r.bodyBytes);
  }
}
