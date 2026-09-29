import 'package:flutter/material.dart';

import '../services/notifications.dart';
import '../state/app_state.dart';
import 'widgets.dart';

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
    const dayOptions = [(7, '7 days before'), (3, '3 days before'),
      (1, '1 day before'), (0, 'On the due day')];
    return Scaffold(
      appBar: AppBar(title: const Text('Notifications')),
      body: ListView(
        children: [
          SwitchListTile(
            secondary: const Icon(Icons.notifications_active_outlined),
            title: const Text('Reminders'),
            subtitle: const Text('Scheduled on this phone; work even when the app is closed'),
            value: on,
            onChanged: (v) async {
              if (v) {
                final ok = await state.notifier.requestPermission();
                if (!ok && context.mounted) {
                  showSnack(context,
                      'Allow notifications for Money Tracker in Android settings');
                }
              }
              _update(() => _s.enabled = v);
            },
          ),
          const Divider(),
          ListTile(
            enabled: on,
            leading: const Icon(Icons.schedule),
            title: const Text('Time of day'),
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
            child: Text('Credit card payments',
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
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 6, 16, 8),
            child: Text(
                'Only while the statement still has something to pay. Needs the card\'s statement and due days set.'),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.receipt_long_outlined),
            title: const Text('Statement closed'),
            subtitle: const Text('The day after a card statement closes'),
            value: _s.statementClosed,
            onChanged: on ? (v) => _update(() => _s.statementClosed = v) : null,
          ),
          SwitchListTile(
            secondary: const Icon(Icons.repeat),
            title: const Text('Recurring items'),
            subtitle: const Text('On the day a subscription, salary… is due'),
            value: _s.recurring,
            onChanged: on ? (v) => _update(() => _s.recurring = v) : null,
          ),
          SwitchListTile(
            secondary: const Icon(Icons.backup_outlined),
            title: const Text('Backup reminder'),
            subtitle: const Text('Every 7 days, only when Dropbox is not connected'),
            value: _s.backup,
            onChanged: on ? (v) => _update(() => _s.backup = v) : null,
          ),
          SwitchListTile(
            secondary: const Icon(Icons.savings_outlined),
            title: const Text('Budget alerts'),
            subtitle: const Text('When a budget reaches 80% and when it is exceeded'),
            value: _s.budgets,
            onChanged: on ? (v) => _update(() => _s.budgets = v) : null,
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.send_outlined),
            title: const Text('Send a test notification'),
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
