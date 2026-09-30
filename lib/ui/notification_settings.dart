import 'package:flutter/material.dart';

import '../services/notifications.dart';
import '../state/app_state.dart';
import 'widgets.dart';
import '../l10n/l10n.dart';

class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({super.key});

  @override
  State<NotificationSettingsScreen> createState() =>
      _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState
    extends State<NotificationSettingsScreen> {
  late NotifSettings _s;
  bool _init = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_init) return;
    _init = true;
    final cur = AppScope.read(context).notifSettings;
    _s = NotifSettings(
      enabled: cur.enabled,
      cardDays: {...cur.cardDays},
      hour: cur.hour,
      minute: cur.minute,
      recurring: cur.recurring,
      statementClosed: cur.statementClosed,
      backup: cur.backup,
      budgets: cur.budgets,
    );
  }

  Future<void> _save() => AppScope.read(context).saveNotifSettings(_s);

  void _update(VoidCallback f) {
    setState(f);
    _save();
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final on = _s.enabled;
    final dayOptions = [(7, tr('7 days before')), (3, tr('3 days before')),
      (1, tr('1 day before')), (0, tr('On the due day'))];
    return Scaffold(
      appBar: AppBar(title: Text(tr('Notifications'))),
      body: ListView(
        children: [
          SwitchListTile(
            secondary: const Icon(Icons.notifications_active_outlined),
            title: Text(tr('Reminders')),
            subtitle: Text(tr('Scheduled on this phone; work even when the app is closed')),
            value: on,
            onChanged: (v) async {
              if (v) {
                final ok = await state.notifier.requestPermission();
                if (!ok && context.mounted) {
                  showSnack(context,
                      tr('Allow notifications for Expense & Wealth Tracker in Android settings'));
                }
              }
              _update(() => _s.enabled = v);
            },
          ),
          const Divider(),
          ListTile(
            enabled: on,
            leading: const Icon(Icons.schedule),
            title: Text(tr('Time of Day')),
            subtitle: Text(TimeOfDay(hour: _s.hour, minute: _s.minute).format(context)),
            onTap: () async {
              final t = await showTimePicker(
                  context: context,
                  initialTime: TimeOfDay(hour: _s.hour, minute: _s.minute));
              if (t != null) {
                _update(() {
                  _s.hour = t.hour;
                  _s.minute = t.minute;
                });
              }
            },
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text(tr('Credit Card Payments'),
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: Theme.of(context).colorScheme.primary)),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(
              spacing: 8,
              children: [
                for (final (d, label) in dayOptions)
                  FilterChip(
                    label: Text(label),
                    selected: _s.cardDays.contains(d),
                    onSelected: on
                        ? (v) => _update(() =>
                            v ? _s.cardDays.add(d) : _s.cardDays.remove(d))
                        : null,
                  ),
              ],
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(16, 6, 16, 8),
            child: Text(
                tr('Only while the statement still has something to pay. Needs the card\'s statement and due days set.')),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.receipt_long_outlined),
            title: Text(tr('Statement Closed')),
            subtitle: Text(tr('The day after a card statement closes')),
            value: _s.statementClosed,
            onChanged: on ? (v) => _update(() => _s.statementClosed = v) : null,
          ),
          SwitchListTile(
            secondary: const Icon(Icons.repeat),
            title: Text(tr('Recurring Items')),
            subtitle: Text(tr('On the day a subscription, salary… is due')),
            value: _s.recurring,
            onChanged: on ? (v) => _update(() => _s.recurring = v) : null,
          ),
          SwitchListTile(
            secondary: const Icon(Icons.backup_outlined),
            title: Text(tr('Backup Reminder')),
            subtitle: Text(tr('Every 7 days, only when Dropbox is not connected')),
            value: _s.backup,
            onChanged: on ? (v) => _update(() => _s.backup = v) : null,
          ),
          SwitchListTile(
            secondary: const Icon(Icons.savings_outlined),
            title: Text(tr('Budget Alerts')),
            subtitle: Text(tr('When a budget reaches 80% and when it is exceeded')),
            value: _s.budgets,
            onChanged: on ? (v) => _update(() => _s.budgets = v) : null,
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.send_outlined),
            title: Text(tr('Send a Test Notification')),
            onTap: () async {
              await state.notifier.requestPermission();
              await state.notifier.showTest();
            },
          ),
        ],
      ),
    );
  }
}
