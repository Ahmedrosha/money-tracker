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
import 'reset_screen.dart';
import 'sms_inbox_screen.dart';
import 'widgets.dart';
import '../l10n/l10n.dart';
import 'export_screen.dart';
import 'gold_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(tr('Settings'))),
      body: ListView(
        children: [
          const AppLockTile(),
          SwitchListTile(
            secondary: const Icon(Icons.visibility_off_outlined),
            title: Text(tr('Hide Amounts')),
            subtitle: Text(tr('Show •••• instead of numbers. Also the eye button at the top of each screen.')),
            value: state.hideAmounts,
            onChanged: (v) => state.setHideAmounts(v),
          ),
          ListTile(
            leading: const Icon(Icons.translate),
            // Both languages, so it can be found whichever one is showing.
            title: Text(isArabic ? 'اللغة · Language' : 'Language · اللغة'),
            subtitle: Text(_languageName(state.language)),
            onTap: () async {
              final v = await showDialog<String>(
                context: context,
                builder: (ctx) => SimpleDialog(
                  title: Text(tr('Language')),
                  children: [
                    for (final code in const ['system', 'en', 'ar'])
                      ListTile(
                        leading: Icon(state.language == code
                            ? Icons.radio_button_checked
                            : Icons.radio_button_unchecked),
                        title: Text(_languageName(code)),
                        onTap: () => Navigator.pop(ctx, code),
                      ),
                  ],
                ),
              );
              if (v != null && v != state.language) await state.setLanguage(v);
            },
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.flag_outlined),
            title: Text(tr('Main Currency')),
            subtitle: Text(
                tr('${state.baseCurrency} — ${currencyName(state.baseCurrency)}\nTotals and net worth are shown in this currency')),
            isThreeLine: true,
            onTap: () async {
              final c =
                  await pickCurrency(context, current: state.baseCurrency);
              if (c != null) await state.setBaseCurrency(c);
            },
          ),
          ListTile(
            leading: const Icon(Icons.sms_outlined),
            title: Text(tr('Bank Messages')),
            subtitle: Text(state.smsPending.isEmpty
                ? tr('Add transactions from bank SMS')
                : tr('${state.smsPending.length} bank messages to add')),
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const SmsInboxScreen())),
          ),
          ListTile(
            leading: const Icon(Icons.currency_exchange),
            title: Text(tr('Currencies & Exchange Rates')),
            subtitle: Text(tr('Online rates, manual overrides')),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const CurrenciesScreen()),
            ),
          ),
          ListenableBuilder(
            listenable: state.dropbox,
            builder: (context, _) => ListTile(
              leading: const Icon(Icons.cloud_sync_outlined),
              title: Text(tr('Dropbox')),
              subtitle: Text(dropboxStatus(state.dropbox)),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const DropboxScreen()),
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.notifications_outlined),
            title: Text(tr('Notifications')),
            subtitle: Text(state.notifSettings.enabled
                ? tr('Card payments, recurring items, backups')
                : tr('Off')),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => const NotificationSettingsScreen()),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.backup_outlined),
            title: Text(tr('Backup & Restore')),
            subtitle: Text(state.lastBackup == null
                ? tr('No backup yet')
                : tr('Last backup ${state.lastBackup!.day}/${state.lastBackup!.month}/${state.lastBackup!.year}')),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const BackupScreen()),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.workspace_premium_outlined),
            title: Text(tr('Gold')),
            subtitle: Text(tr('Prices per gram, your gold and price alerts')),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const GoldScreen()),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.table_view_outlined),
            title: Text(tr('Export to Excel')),
            subtitle: Text(tr('Transactions for any period, to share or keep')),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ExportScreen()),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.repeat),
            title: Text(tr('Recurring Items')),
            subtitle: Text(
                tr('${state.rules.where((r) => !r.finished).length} active · subscriptions, salary…')),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const RecurringScreen()),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.calendar_view_week),
            title: Text(tr('First Day of Week')),
            subtitle: Text(_dayName(state.weekStart)),
            onTap: () async {
              final v = await showDialog<int>(
                context: context,
                builder: (ctx) => SimpleDialog(
                  title: Text(tr('First Day of Week')),
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
            title: Text(tr('Categories')),
            subtitle: Text(tr('${state.categories.length} categories')),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const CategoriesScreen()),
            ),
          ),
          const Divider(),
          if (state.hasSampleData) ...[
            ListTile(
              leading: const Icon(Icons.auto_awesome_outlined),
              title: Text(tr('Clear Sample Data')),
              subtitle: Text(tr('Removes the example accounts, their transactions and budgets. Your own entries stay.')),
              onTap: () async {
                final ok = await confirmDialog(context,
                    title: 'Clear sample data?',
                    message: 'Removes the example accounts, their transactions and budgets. Your own entries stay.',
                    ok: 'Clear');
                if (ok) await state.clearSampleData();
              },
            ),
            const Divider(),
          ],
          ListTile(
            leading: Icon(Icons.restart_alt,
                color: Theme.of(context).colorScheme.error),
            title: Text(tr('Reset App'),
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
            subtitle: Text(tr('Delete your data or start over like a new install')),
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const ResetScreen())),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('Expense & Wealth Tracker'),
            subtitle: Text(tr('Version 0.49 — card points, voice, receipts, gold alerts, people')),
          ),
        ],
      ),
    );
  }

  static String _languageName(String code) {
    switch (code) {
      case 'en':
        return 'English';
      case 'ar':
        return 'العربية';
      default:
        return tr('Phone Language');
    }
  }

  static String _dayName(int d) {
    switch (d) {
      case DateTime.saturday:
        return tr('Saturday');
      case DateTime.sunday:
        return tr('Sunday');
      default:
        return tr('Monday');
    }
  }
}

class AppLockTile extends StatefulWidget {
  const AppLockTile({super.key});

  @override
  State<AppLockTile> createState() => AppLockTileState();
}

class AppLockTileState extends State<AppLockTile> {
  final _lock = AppLock();
  late final Future<String> _method = _lock.methodName();

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    return FutureBuilder<String>(
      future: _method,
      builder: (context, snap) => SwitchListTile(
        secondary: const Icon(Icons.lock_outline),
        title: Text(tr('App Lock')),
        subtitle: Text(
            tr('${snap.data ?? tr('Face ID / fingerprint')} when opening the app and after a minute away. Phone passcode works too.')),
        isThreeLine: true,
        value: state.lockEnabled,
        onChanged: (v) async {
          if (v) {
            if (!await _lock.available()) {
              if (context.mounted) {
                showSnack(context,
                    tr('Set up a screen lock (Face ID, fingerprint or passcode) on your phone first'));
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
