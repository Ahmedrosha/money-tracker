import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../data/db.dart';
import '../util/format.dart';

/// User choices for reminders (stored in the settings table).
class NotifSettings {
  bool enabled;
  Set<int> cardDays; // days before the due date, 0 = on the day
  int hour;
  int minute;
  bool recurring;
  bool statementClosed;
  bool backup;

  NotifSettings({
    this.enabled = true,
    Set<int>? cardDays,
    this.hour = 10,
    this.minute = 0,
    this.recurring = true,
    this.statementClosed = true,
    this.backup = true,
  }) : cardDays = cardDays ?? {3, 1, 0};

  static Future<NotifSettings> load(AppDb db) async {
    Future<String?> g(String k) => db.getSetting(k);
    final days = await g('notif_card_days');
    return NotifSettings(
      enabled: (await g('notif_enabled') ?? '1') == '1',
      cardDays: days == null
          ? null
          : days
              .split(',')
              .where((s) => s.isNotEmpty)
              .map(int.parse)
              .toSet(),
      hour: int.tryParse(await g('notif_hour') ?? '') ?? 10,
      minute: int.tryParse(await g('notif_minute') ?? '') ?? 0,
      recurring: (await g('notif_recurring') ?? '1') == '1',
      statementClosed: (await g('notif_statement') ?? '1') == '1',
      backup: (await g('notif_backup') ?? '1') == '1',
    );
  }

  Future<void> save(AppDb db) async {
    String b(bool v) => v ? '1' : '0';
    await db.setSetting('notif_enabled', b(enabled));
    await db.setSetting('notif_card_days', (cardDays.toList()..sort()).join(','));
    await db.setSetting('notif_hour', '$hour');
    await db.setSetting('notif_minute', '$minute');
    await db.setSetting('notif_recurring', b(recurring));
    await db.setSetting('notif_statement', b(statementClosed));
    await db.setSetting('notif_backup', b(backup));
  }
}

/// One reminder to schedule.
class Reminder {
  final DateTime at;
  final String title;
  final String body;
  const Reminder(this.at, this.title, this.body);
}

/// Schedules reminders on the phone, so they arrive even when the app is
/// closed. Everything is rebuilt from the current data whenever it changes.
class Notifier {
  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  static const _details = NotificationDetails(
    android: AndroidNotificationDetails(
      'reminders',
      'Payment reminders',
      channelDescription: 'Card payments, recurring items and backups',
      importance: Importance.high,
      priority: Priority.high,
    ),
  );

  Future<void> init() async {
    if (_ready) return;
    try {
      tzdata.initializeTimeZones();
      await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        ),
      );
      _ready = true;
    } catch (_) {
      // Notifications are a convenience; never break the app over them.
    }
  }

  AndroidFlutterLocalNotificationsPlugin? get _android =>
      _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();

  /// Asks for permission (Android 13+). Returns true when allowed.
  Future<bool> requestPermission() async {
    await init();
    try {
      return await _android?.requestNotificationsPermission() ?? true;
    } catch (_) {
      return false;
    }
  }

  Future<void> showTest() async {
    await init();
    await _plugin.show(
      id: 999999,
      title: 'Money Tracker',
      body: 'Notifications are working.',
      notificationDetails: _details,
    );
  }

  /// Replaces all scheduled reminders with [items] (future ones only).
  Future<void> replaceAll(List<Reminder> items) async {
    await init();
    if (!_ready) return;
    try {
      await _plugin.cancelAll();
      final now = DateTime.now();
      final upcoming = items.where((r) => r.at.isAfter(now)).toList()
        ..sort((a, b) => a.at.compareTo(b.at));
      var id = 1;
      for (final r in upcoming.take(60)) {
        await _plugin.zonedSchedule(
          id: id++,
          title: r.title,
          body: r.body,
          // The local time converted to an exact instant.
          scheduledDate: tz.TZDateTime.from(r.at, tz.UTC),
          notificationDetails: _details,
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        );
      }
    } catch (_) {}
  }
}

String reminderWhen(int daysBefore, DateTime due) {
  if (daysBefore == 0) return 'today';
  if (daysBefore == 1) return 'tomorrow';
  return 'on ${shortDateFmt.format(due)}';
}
