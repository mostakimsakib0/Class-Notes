import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Secrets (API key, bot token) live in Android Keystore-backed secure storage;
/// plain preferences hold the rest.
class AppSettings {
  static const _secure = FlutterSecureStorage();

  static const defaultModel = 'gemini-2.5-flash';

  static Future<String?> geminiKey() => _secure.read(key: 'gemini_key');
  static Future<void> setGeminiKey(String? v) =>
      v == null || v.isEmpty ? _secure.delete(key: 'gemini_key') : _secure.write(key: 'gemini_key', value: v.trim());

  static Future<String?> botToken() => _secure.read(key: 'bot_token');
  static Future<void> setBotToken(String? v) =>
      v == null || v.isEmpty ? _secure.delete(key: 'bot_token') : _secure.write(key: 'bot_token', value: v.trim());

  static Future<SharedPreferences> get _prefs => SharedPreferences.getInstance();

  static Future<String> geminiModel() async => (await _prefs).getString('gemini_model') ?? defaultModel;
  static Future<void> setGeminiModel(String v) async => (await _prefs).setString('gemini_model', v);

  /// Telegram chat (private channel) where audio and notes are stored.
  static Future<int?> storageChatId() async => (await _prefs).getInt('tg_chat_id');
  static Future<String?> storageChatTitle() async => (await _prefs).getString('tg_chat_title');
  static Future<void> setStorageChat(int? id, String? title) async {
    final p = await _prefs;
    if (id == null) {
      await p.remove('tg_chat_id');
      await p.remove('tg_chat_title');
    } else {
      await p.setInt('tg_chat_id', id);
      await p.setString('tg_chat_title', title ?? '');
    }
  }

  /// Minutes after midnight.
  static Future<int> eveningPromptMin() async => (await _prefs).getInt('evening_prompt_min') ?? 22 * 60;
  static Future<void> setEveningPromptMin(int v) async => (await _prefs).setInt('evening_prompt_min', v);

  static Future<int> dailyCheckMin() async => (await _prefs).getInt('daily_check_min') ?? 18 * 60;
  static Future<void> setDailyCheckMin(int v) async => (await _prefs).setInt('daily_check_min', v);

  /// Extra minutes to keep recording after the scheduled end before auto-stopping.
  static Future<int> stopGraceMin() async => (await _prefs).getInt('stop_grace_min') ?? 5;
  static Future<void> setStopGraceMin(int v) async => (await _prefs).setInt('stop_grace_min', v);

  /// Delete the phone copy of audio once it is safely in Telegram and notes are done.
  static Future<bool> deleteLocalAudio() async => (await _prefs).getBool('delete_local_audio') ?? true;
  static Future<void> setDeleteLocalAudio(bool v) async => (await _prefs).setBool('delete_local_audio', v);
}
