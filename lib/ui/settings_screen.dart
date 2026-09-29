import 'package:flutter/material.dart';

import '../services/app_lock.dart';
import '../state/app_state.dart';
import '../util/currencies.dart';
import 'backup_screen.dart';
import 'categories_screen.dart';
import 'dropbox_screen.dart';
import 'notification_settings.dart';
import 'currencies_screen.dart';
import 'recurring_screen.dart';
import 'widgets.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          const _LockTile(),
          SwitchListTile(
            secondary: const Icon(Icons.visibility_off_outlined),
            title: const Text('Hide Amounts'),
            subtitle: const Text('Show •••• instead of numbers. Also the eye button at the top of each screen.'),
            value: state.hideAmounts,
            onChanged: (v) => state.setHideAmounts(v),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.flag_outlined),
            title: const Text('Main Currency'),
            subtitle: Text(
                '${state.baseCurrency} — ${currencyName(state.baseCurrency)}\nTotals and net worth are shown in this currency'),
            isThreeLine: true,
            onTap: () async {
              final c =
                  await pickCurrency(context, current: state.baseCurrency);
              if (c != null) await state.setBaseCurrency(c);
            },
          ),
          ListTile(
            leading: const Icon(Icons.currency_exchange),
            title: const Text('Currencies & Exchange Rates'),
            subtitle: const Text('Online rates, manual overrides'),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const CurrenciesScreen()),
            ),
          ),
          ListenableBuilder(
            listenable: state.dropbox,
            builder: (context, _) => ListTile(
              leading: const Icon(Icons.cloud_sync_outlined),
              title: const Text('Dropbox'),
              subtitle: Text(dropboxStatus(state.dropbox)),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const DropboxScreen()),
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.notifications_outlined),
            title: const Text('Notifications'),
            subtitle: Text(state.notifSettings.enabled
                ? 'Card payments, recurring items, backups'
                : 'Off'),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => const NotificationSettingsScreen()),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.backup_outlined),
            title: const Text('Backup & Restore'),
            subtitle: Text(state.lastBackup == null
                ? 'No backup yet'
                : 'Last backup ${state.lastBackup!.day}/${state.lastBackup!.month}/${state.lastBackup!.year}'),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const BackupScreen()),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.repeat),
            title: const Text('Recurring Items'),
            subtitle: Text(
                '${state.rules.where((r) => !r.finished).length} active · subscriptions, salary…'),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const RecurringScreen()),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.calendar_view_week),
            title: const Text('First Day of Week'),
            subtitle: Text(_dayName(state.weekStart)),
            onTap: () async {
              final v = await showDialog<int>(
                context: context,
                builder: (ctx) => SimpleDialog(
                  title: const Text('First Day of Week'),
                  children: [
                    for (final d in const [
                      DateTime.saturday,
                      DateTime.sunday,
                      DateTime.monday
                    ])
                      SimpleDialogOption(
                        onPressed: () => Navigator.pop(ctx, d),
                        child: Text(_dayName(d)),
                      ),
                  ],
                ),
              );
              if (v != null) await state.setWeekStart(v);
            },
          ),
          ListTile(
            leading: const Icon(Icons.category_outlined),
            title: const Text('Categories'),
            subtitle: Text('${state.categories.length} categories'),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const CategoriesScreen()),
            ),
          ),
          const Divider(),
          const ListTile(
            leading: Icon(Icons.info_outline),
            title: Text('Money Tracker'),
            subtitle: Text(
                'Version 0.24 — gold by weight (24K, 21K, 18K)'),
          ),
        ],
      ),
    );
  }

  static String _dayName(int d) {
    switch (d) {
      case DateTime.saturday:
        return 'Saturday';
      case DateTime.sunday:
        return 'Sunday';
      default:
        return 'Monday';
    }
  }
}

class _LockTile extends StatefulWidget {
  const _LockTile();

  @override
  State<_LockTile> createState() => _LockTileState();
}

class _LockTileState extends State<_LockTile> {
  final _lock = AppLock();
  late final Future<String> _method = _lock.methodName();

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    return FutureBuilder<String>(
      future: _method,
      builder: (context, snap) => SwitchListTile(
        secondary: const Icon(Icons.lock_outline),
        title: const Text('App Lock'),
        subtitle: Text(
            '${snap.data ?? 'Face ID / fingerprint'} when opening the app and after a minute away. Phone passcode works too.'),
        isThreeLine: true,
        value: state.lockEnabled,
        onChanged: (v) async {
          if (v) {
            if (!await _lock.available()) {
              if (context.mounted) {
                showSnack(context,
                    'Set up a screen lock (Face ID, fingerprint or passcode) on your phone first');
              }
              return;
            }
            // Confirm it works before turning it on.
            if (!await _lock.authenticate()) return;
          }
          await state.setLockEnabled(v);
        },
      ),
    );
  }
}
