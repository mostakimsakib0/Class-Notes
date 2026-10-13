import 'dart:ui';

import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:intl/intl.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../db.dart';
import '../models.dart';
import '../settings.dart';

/// Notification ids by purpose, so rescheduling only replaces our own scheduled ones.
class NotifIds {
  static const classReminderBase = 1000; // + day offset * 50 + index
  static const eveningBase = 2000; // + day offset
  static const lectureBase = 3000; // + lecture id % 1000
  static const dailyCheck = 4000;
  static bool isScheduled(int id) => id >= classReminderBase && id < lectureBase;
}

class NotifActions {
  static const startRecording = 'start_record';
  static const noChanges = 'no_changes';
  static const updateDay = 'update_day';
}

/// Payloads: `record|<classKey>`, `day|<yyyy-MM-dd>`, `lecture|<id>`, `today`.
typedef NotificationRoute = void Function(String payload, String? actionId);

final _plugin = FlutterLocalNotificationsPlugin();

/// Runs in a background isolate when "No changes" is tapped without opening the app.
@pragma('vm:entry-point')
void notificationTapBackground(NotificationResponse r) async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  if (r.actionId == NotifActions.noChanges && r.payload != null && r.payload!.startsWith('day|')) {
    await (await AppDb.open()).confirmDay(r.payload!.substring(4));
  }
}

class Notifications {
  static bool _tzReady = false;

  static Future<void> initTimezone() async {
    if (_tzReady) return;
    tzdata.initializeTimeZones();
    try {
      tz.setLocalLocation(tz.getLocation((await FlutterTimezone.getLocalTimezone()).identifier));
    } catch (_) {
      tz.setLocalLocation(tz.getLocation('Asia/Dhaka'));
    }
    _tzReady = true;
  }

  static Future<void> init({NotificationRoute? onTap}) async {
    await initTimezone();
    await _plugin.initialize(
      settings: const InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher')),
      onDidReceiveNotificationResponse: (r) async {
        if (r.actionId == NotifActions.noChanges && r.payload != null) {
          await (await AppDb.open()).confirmDay(r.payload!.substring(4));
          return;
        }
        if (r.payload != null) onTap?.call(r.payload!, r.actionId);
      },
      onDidReceiveBackgroundNotificationResponse: notificationTapBackground,
    );
  }

  /// Payload if the app was launched by tapping a notification.
  static Future<(String, String?)?> launchPayload() async {
    final details = await _plugin.getNotificationAppLaunchDetails();
    final r = details?.notificationResponse;
    if (details?.didNotificationLaunchApp != true || r?.payload == null) return null;
    return (r!.payload!, r.actionId);
  }

  static AndroidFlutterLocalNotificationsPlugin? get _android =>
      _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

  static Future<void> requestPermissions() async {
    await _android?.requestNotificationsPermission();
    if (await _android?.canScheduleExactNotifications() != true) {
      await _android?.requestExactAlarmsPermission();
    }
  }

  static Future<AndroidScheduleMode> _mode() async => await _android?.canScheduleExactNotifications() == true
      ? AndroidScheduleMode.exactAllowWhileIdle
      : AndroidScheduleMode.inexactAllowWhileIdle;

  static const _reminderDetails = NotificationDetails(
    android: AndroidNotificationDetails(
      'class_reminders',
      'Class reminders',
      channelDescription: 'When a class starts',
      importance: Importance.max,
      priority: Priority.high,
      category: AndroidNotificationCategory.reminder,
      actions: [AndroidNotificationAction(NotifActions.startRecording, 'Start recording', showsUserInterface: true)],
    ),
  );

  static NotificationDetails _eveningDetails(String body) => NotificationDetails(
    android: AndroidNotificationDetails(
      'evening_check',
      'Tomorrow\'s classes',
      channelDescription: 'Evening reminder to confirm tomorrow\'s class times',
      importance: Importance.high,
      priority: Priority.high,
      styleInformation: BigTextStyleInformation(body),
      actions: const [
        AndroidNotificationAction(NotifActions.noChanges, 'No changes'),
        AndroidNotificationAction(NotifActions.updateDay, 'Update times', showsUserInterface: true),
      ],
    ),
  );

  static const _infoDetails = NotificationDetails(
    android: AndroidNotificationDetails(
      'results',
      'Notes & processing',
      channelDescription: 'Notes ready, failures, and the daily check',
      importance: Importance.defaultImportance,
    ),
  );

  /// Rebuilds all scheduled notifications for the next 7 days. Call after any routine change,
  /// on app start, and from the daily background check (keeps the window rolling).
  static Future<void> rescheduleAll(AppDb db) async {
    await initTimezone();
    for (final p in await _plugin.pendingNotificationRequests()) {
      if (NotifIds.isScheduled(p.id)) await _plugin.cancel(id: p.id);
    }
    final mode = await _mode();
    final now = tz.TZDateTime.now(tz.local);
    final today = DateTime(now.year, now.month, now.day);
    final eveningMin = await AppSettings.eveningPromptMin();

    for (var offset = 0; offset <= 7; offset++) {
      final day = today.add(Duration(days: offset));
      final classes = (await db.classesFor(day)).where((c) => !c.cancelled).toList();

      for (var i = 0; i < classes.length && i < 50; i++) {
        final c = classes[i];
        final at = tz.TZDateTime(tz.local, day.year, day.month, day.day, c.startMin ~/ 60, c.startMin % 60);
        if (at.isBefore(now)) continue;
        await _plugin.zonedSchedule(
          id: NotifIds.classReminderBase + offset * 50 + i,
          title: '${c.subject.code} is starting',
          body:
              '${c.subject.name} · ${c.timeRange}${c.room != null ? ' · ${c.room}' : ''}${c.changed ? ' (changed today)' : ''}',
          scheduledDate: at,
          notificationDetails: _reminderDetails,
          androidScheduleMode: mode,
          payload: 'record|${c.key}',
        );
      }

      // Evening before: list tomorrow's classes and ask whether any time changed.
      final tomorrow = day.add(const Duration(days: 1));
      final tomorrowClasses = await db.classesFor(tomorrow);
      final active = tomorrowClasses.where((c) => !c.cancelled).toList();
      final promptAt = tz.TZDateTime(tz.local, day.year, day.month, day.day, eveningMin ~/ 60, eveningMin % 60);
      if (active.isEmpty || promptAt.isBefore(now)) continue;
      final lines = tomorrowClasses
          .map(
            (c) => c.cancelled
                ? '✕ ${c.subject.code} cancelled'
                : '• ${fmtTime12(c.startMin)} ${c.subject.code}${c.room != null ? ' (${c.room})' : ''}${c.changed ? ' — changed' : ''}',
          )
          .join('\n');
      final body = '$lines\n\nDid any class time change?';
      await _plugin.zonedSchedule(
        id: NotifIds.eveningBase + offset,
        title:
            'Tomorrow (${DateFormat.EEEE().format(tomorrow)}): ${active.length} class${active.length == 1 ? '' : 'es'}',
        body: body,
        scheduledDate: promptAt,
        notificationDetails: _eveningDetails(body),
        androidScheduleMode: mode,
        payload: 'day|${dateKey(tomorrow)}',
      );
    }
  }

  static Future<void> showLecture(int lectureId, String title, String body) => _plugin.show(
    id: NotifIds.lectureBase + lectureId % 1000,
    title: title,
    body: body,
    notificationDetails: _infoDetails,
    payload: 'lecture|$lectureId',
  );

  static Future<void> showInfo(int id, String title, String body, {String? payload}) =>
      _plugin.show(id: id, title: title, body: body, notificationDetails: _infoDetails, payload: payload);
}
