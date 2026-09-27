import 'package:flutter/material.dart';

import '../state/app_state.dart';
import '../util/currencies.dart';
import 'categories_screen.dart';
import 'currencies_screen.dart';
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
            subtitle: Text('Version 0.1 — accounts, transactions, transfers'),
          ),
        ],
      ),
    );
  }
}
