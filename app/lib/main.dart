import 'package:flutter/material.dart';

import 'db.dart';
import 'models.dart';
import 'services/background.dart';
import 'services/notifications.dart';
import 'services/recorder.dart';
import 'ui/day_editor_screen.dart';
import 'ui/lecture_screen.dart';
import 'ui/recording_screen.dart';
import 'ui/routine_screen.dart';
import 'ui/settings_screen.dart';
import 'ui/subjects_screen.dart';
import 'ui/today_screen.dart';

final navigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final db = await AppDb.open();
  await Notifications.init(onTap: openFromNotification);
  await initBackground();
  await RecorderController.recoverInterrupted();
  runApp(const ClassRecorderApp());

  // Startup housekeeping after the first frame so the UI appears immediately.
  WidgetsBinding.instance.addPostFrameCallback((_) async {
    await Notifications.requestPermissions();
    await Notifications.rescheduleAll(db);
    await scheduleDailyCheck();
    final launch = await Notifications.launchPayload();
    if (launch != null) openFromNotification(launch.$1, launch.$2);
  });
}

/// Routes notification taps: `record|<classKey>`, `day|<date>`, `lecture|<id>`, `today`.
Future<void> openFromNotification(String payload, String? actionId) async {
  final nav = navigatorKey.currentState;
  if (nav == null) return;
  final sep = payload.indexOf('|');
  final kind = sep < 0 ? payload : payload.substring(0, sep);
  final value = sep < 0 ? '' : payload.substring(sep + 1);
  final db = await AppDb.open();

  switch (kind) {
    case 'record':
      final date = parseDateKey(value.split(':').first);
      final cls = (await db.classesFor(date)).where((c) => c.key == value).firstOrNull;
      if (cls == null || cls.cancelled) return;
      nav.push(
        MaterialPageRoute(
          builder: (_) => RecordingScreen(classInstance: cls, autoStart: actionId == NotifActions.startRecording),
        ),
      );
    case 'day':
      nav.push(MaterialPageRoute(builder: (_) => DayEditorScreen(date: parseDateKey(value))));
    case 'lecture':
      final id = int.tryParse(value);
      if (id != null) nav.push(MaterialPageRoute(builder: (_) => LectureScreen(lectureId: id)));
    default:
      nav.popUntil((r) => r.isFirst);
  }
}

class ClassRecorderApp extends StatelessWidget {
  const ClassRecorderApp({super.key});

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF3F51B5);
    return MaterialApp(
      title: 'Class Recorder',
      navigatorKey: navigatorKey,
      theme: ThemeData(colorSchemeSeed: seed, useMaterial3: true),
      darkTheme: ThemeData(colorSchemeSeed: seed, brightness: Brightness.dark, useMaterial3: true),
      home: const HomeShell(),
    );
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int index = 0;

  static const _pages = [TodayScreen(), RoutineScreen(), SubjectsScreen(), SettingsScreen()];

  @override
  Widget build(BuildContext context) => Scaffold(
    body: IndexedStack(index: index, children: _pages),
    bottomNavigationBar: NavigationBar(
      selectedIndex: index,
      onDestinationSelected: (i) => setState(() => index = i),
      destinations: const [
        NavigationDestination(icon: Icon(Icons.today_outlined), selectedIcon: Icon(Icons.today), label: 'Today'),
        NavigationDestination(
          icon: Icon(Icons.calendar_month_outlined),
          selectedIcon: Icon(Icons.calendar_month),
          label: 'Routine',
        ),
        NavigationDestination(
          icon: Icon(Icons.menu_book_outlined),
          selectedIcon: Icon(Icons.menu_book),
          label: 'Subjects',
        ),
        NavigationDestination(
          icon: Icon(Icons.settings_outlined),
          selectedIcon: Icon(Icons.settings),
          label: 'Settings',
        ),
      ],
    ),
  );
}
