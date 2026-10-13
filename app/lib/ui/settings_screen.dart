import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../db.dart';
import '../models.dart';
import '../services/background.dart';
import '../services/gemini.dart';
import '../services/notifications.dart';
import '../services/recorder.dart';
import '../services/telegram.dart';
import '../settings.dart';
import 'common.dart';

class _SettingsData {
  String? geminiKey;
  String model = AppSettings.defaultModel;
  String? botToken;
  int? chatId;
  String? chatTitle;
  int eveningMin = 22 * 60;
  int checkMin = 18 * 60;
  int graceMin = 5;
  bool deleteLocal = true;
}

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  _SettingsData? d;
  List<GeminiModel>? models;
  bool busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final s = _SettingsData()
      ..geminiKey = await AppSettings.geminiKey()
      ..model = await AppSettings.geminiModel()
      ..botToken = await AppSettings.botToken()
      ..chatId = await AppSettings.storageChatId()
      ..chatTitle = await AppSettings.storageChatTitle()
      ..eveningMin = await AppSettings.eveningPromptMin()
      ..checkMin = await AppSettings.dailyCheckMin()
      ..graceMin = await AppSettings.stopGraceMin()
      ..deleteLocal = await AppSettings.deleteLocalAudio();
    if (mounted) setState(() => d = s);
  }

  String _mask(String? secret) =>
      secret == null ? 'Not set' : '••••••••${secret.length > 4 ? secret.substring(secret.length - 4) : ''}';

  Future<String?> _askSecret(String title, String hint, {String? help}) async {
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (help != null) Text(help, style: Theme.of(c).textTheme.bodySmall),
            TextField(
              controller: ctrl,
              autofocus: true,
              obscureText: true,
              decoration: InputDecoration(hintText: hint),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, ctrl.text.trim()), child: const Text('Save')),
        ],
      ),
    );
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() => busy = true);
    try {
      await action();
    } catch (e) {
      if (mounted) toast(context, e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  // --- Gemini ---

  Future<void> _changeGeminiKey() async {
    final key = await _askSecret('Gemini API key', 'AIza…', help: 'Get a key at aistudio.google.com → Get API key');
    if (key == null || key.isEmpty) return;
    await _run(() async {
      final list = await Gemini(key, d!.model).listModels(); // validates the key before saving
      await AppSettings.setGeminiKey(key);
      models = list;
      if (list.isNotEmpty && !list.any((m) => m.id == d!.model)) {
        await AppSettings.setGeminiModel(list.first.id);
      }
      await _load();
      dataChanged();
      if (mounted) toast(context, 'Gemini key saved and working');
    });
  }

  Future<void> _loadModels() => _run(() async {
    models = await Gemini(d!.geminiKey!, d!.model).listModels();
    setState(() {});
  });

  // --- Telegram ---

  Future<void> _changeBotToken() async {
    final token = await _askSecret(
      'Telegram bot token',
      '123456:ABC…',
      help: 'Create a bot with @BotFather in Telegram and paste its token.',
    );
    if (token == null || token.isEmpty) return;
    await _run(() async {
      final name = await Telegram(token).botName();
      await AppSettings.setBotToken(token);
      await _load();
      dataChanged();
      if (mounted) toast(context, 'Connected to $name');
    });
  }

  Future<void> _detectChat() => _run(() async {
    final chats = await Telegram(d!.botToken!).recentChats();
    if (!mounted) return;
    if (chats.isEmpty) {
      await showDialog<void>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('No channel found yet'),
          content: const Text(
            '1. Create a private Telegram channel (e.g. "Class Notes").\n'
            '2. Add your bot to it as an admin (allow posting).\n'
            '3. Post any message in the channel.\n'
            '4. Come back and tap "Find channel" again.',
          ),
          actions: [FilledButton(onPressed: () => Navigator.pop(c), child: const Text('OK'))],
        ),
      );
      return;
    }
    final chat = await showModalBottomSheet<TgChat>(
      context: context,
      builder: (c) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(title: Text('Store notes and recordings in…')),
            for (final ch in chats)
              ListTile(
                leading: Icon(ch.type == 'channel' ? Icons.campaign_outlined : Icons.group_outlined),
                title: Text(ch.title),
                subtitle: Text(ch.type),
                onTap: () => Navigator.pop(c, ch),
              ),
          ],
        ),
      ),
    );
    if (chat == null) return;
    await Telegram(
      d!.botToken!,
    ).sendMessage(chat.id, '✅ Class Recorder connected. Recordings and notes will be saved here.');
    await AppSettings.setStorageChat(chat.id, chat.title);
    await _load();
    dataChanged();
    if (mounted) toast(context, 'Saving to "${chat.title}"');
  });

  // --- schedule ---

  Future<void> _pickTime(int current, Future<void> Function(int) save, String help) async {
    final t = await pickTime(context, current, help: help);
    if (t == null) return;
    await save(t);
    final db = await AppDb.open();
    await Notifications.rescheduleAll(db);
    await scheduleDailyCheck();
    await _load();
  }

  Future<void> _permissions() async {
    await Notifications.requestPermissions();
    await Permission.microphone.request();
    await Permission.ignoreBatteryOptimizations.request();
    if (mounted) toast(context, 'Permissions updated');
  }

  @override
  Widget build(BuildContext context) {
    final s = d;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        bottom: busy ? const PreferredSize(preferredSize: Size.fromHeight(4), child: LinearProgressIndicator()) : null,
      ),
      body: s == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                _header('Gemini (notes)'),
                ListTile(
                  leading: const Icon(Icons.key),
                  title: const Text('API key'),
                  subtitle: Text(_mask(s.geminiKey)),
                  trailing: TextButton(
                    onPressed: busy ? null : _changeGeminiKey,
                    child: Text(s.geminiKey == null ? 'Add' : 'Change'),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.auto_awesome_outlined),
                  title: const Text('Model'),
                  subtitle: models == null
                      ? Text(s.model)
                      : DropdownButton<String>(
                          isExpanded: true,
                          value: models!.any((m) => m.id == s.model) ? s.model : null,
                          hint: Text(s.model),
                          items: [for (final m in models!) DropdownMenuItem(value: m.id, child: Text(m.id))],
                          onChanged: (v) async {
                            if (v == null) return;
                            await AppSettings.setGeminiModel(v);
                            await _load();
                          },
                        ),
                  trailing: models == null && s.geminiKey != null
                      ? TextButton(onPressed: busy ? null : _loadModels, child: const Text('Choose'))
                      : null,
                ),
                if (s.geminiKey != null)
                  ListTile(
                    leading: const Icon(Icons.delete_outline),
                    title: const Text('Remove API key'),
                    onTap: () async {
                      await AppSettings.setGeminiKey(null);
                      models = null;
                      await _load();
                      dataChanged();
                    },
                  ),
                _header('Telegram (storage)'),
                ListTile(
                  leading: const Icon(Icons.smart_toy_outlined),
                  title: const Text('Bot token'),
                  subtitle: Text(_mask(s.botToken)),
                  trailing: TextButton(
                    onPressed: busy ? null : _changeBotToken,
                    child: Text(s.botToken == null ? 'Add' : 'Change'),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.campaign_outlined),
                  title: const Text('Storage channel'),
                  subtitle: Text(s.chatId == null ? 'Not connected' : s.chatTitle ?? '${s.chatId}'),
                  trailing: TextButton(
                    onPressed: busy || s.botToken == null ? null : _detectChat,
                    child: Text(s.chatId == null ? 'Find channel' : 'Change'),
                  ),
                ),
                _header('Reminders'),
                ListTile(
                  leading: const Icon(Icons.nightlight_outlined),
                  title: const Text('Ask about tomorrow\'s times at'),
                  subtitle: Text(fmtTime12(s.eveningMin)),
                  onTap: () => _pickTime(s.eveningMin, AppSettings.setEveningPromptMin, 'Evening check time'),
                ),
                ListTile(
                  leading: const Icon(Icons.fact_check_outlined),
                  title: const Text('Check for missing notes at'),
                  subtitle: Text(fmtTime12(s.checkMin)),
                  onTap: () => _pickTime(s.checkMin, AppSettings.setDailyCheckMin, 'Daily notes check'),
                ),
                ListTile(
                  leading: const Icon(Icons.timer_outlined),
                  title: const Text('Keep recording after class ends'),
                  subtitle: Text('${s.graceMin} minutes'),
                  trailing: DropdownButton<int>(
                    value: s.graceMin,
                    items: [
                      for (final m in [0, 5, 10, 15, 30]) DropdownMenuItem(value: m, child: Text('$m min')),
                    ],
                    onChanged: (v) async {
                      await AppSettings.setStopGraceMin(v!);
                      await _load();
                    },
                  ),
                ),
                _header('Phone'),
                SwitchListTile(
                  secondary: const Icon(Icons.cleaning_services_outlined),
                  title: const Text('Delete recordings from phone after saving to Telegram'),
                  value: s.deleteLocal,
                  onChanged: (v) async {
                    await AppSettings.setDeleteLocalAudio(v);
                    await _load();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.verified_user_outlined),
                  title: const Text('Permissions'),
                  subtitle: const Text('Notifications, exact alarms, microphone, battery'),
                  trailing: TextButton(onPressed: _permissions, child: const Text('Check')),
                ),
                ListTile(
                  leading: const Icon(Icons.refresh),
                  title: const Text('Process missing notes now'),
                  onTap: busy
                      ? null
                      : () => _run(() async {
                          final r = await processPending(await AppDb.open());
                          dataChanged();
                          if (mounted) toast(this.context, 'Done: ${r.ok} created, ${r.failed} failed');
                        }),
                ),
                const SizedBox(height: 32),
              ],
            ),
    );
  }

  Widget _header(String text) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
    child: Text(
      text,
      style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w600),
    ),
  );
}
