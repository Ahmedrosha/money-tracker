import 'package:flutter/material.dart';

import '../state/app_state.dart';
import '../util/currencies.dart';
import 'backup_screen.dart';
import 'categories_screen.dart';
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
          ListTile(
            leading: const Icon(Icons.flag_outlined),
            title: const Text('Main currency'),
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
            title: const Text('Currencies & exchange rates'),
            subtitle: const Text('Online rates, manual overrides'),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const CurrenciesScreen()),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.backup_outlined),
            title: const Text('Backup & restore'),
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
            title: const Text('Recurring items'),
            subtitle: Text(
                '${state.rules.where((r) => !r.finished).length} active · subscriptions, salary…'),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const RecurringScreen()),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.calendar_view_week),
            title: const Text('First day of week'),
            subtitle: Text(_dayName(state.weekStart)),
            onTap: () async {
              final v = await showDialog<int>(
                context: context,
                builder: (ctx) => SimpleDialog(
                  title: const Text('First day of week'),
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
                'Version 0.9 — EGP equivalent'),
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
