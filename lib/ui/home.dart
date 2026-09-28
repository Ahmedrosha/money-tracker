import 'package:flutter/material.dart';

import 'accounts_screen.dart';
import 'calendar_screen.dart';
import 'settings_screen.dart';
import 'transaction_edit.dart';
import 'transactions_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    const pages = [
      AccountsScreen(),
      TransactionsScreen(),
      CalendarScreen(),
      SettingsScreen(),
    ];
    // Calendar has its own add button (adds on the selected day).
    final showFab = _index == 0 || _index == 1;
    return Scaffold(
      body: IndexedStack(index: _index, children: pages),
      floatingActionButton: !showFab
          ? null
          : FloatingActionButton(
              tooltip: 'Add transaction',
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const TransactionEditScreen()),
              ),
              child: const Icon(Icons.add),
            ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.account_balance_wallet_outlined),
              selectedIcon: Icon(Icons.account_balance_wallet),
              label: 'Accounts'),
          NavigationDestination(
              icon: Icon(Icons.receipt_long_outlined),
              selectedIcon: Icon(Icons.receipt_long),
              label: 'Transactions'),
          NavigationDestination(
              icon: Icon(Icons.calendar_month_outlined),
              selectedIcon: Icon(Icons.calendar_month),
              label: 'Calendar'),
          NavigationDestination(
              icon: Icon(Icons.settings_outlined),
              selectedIcon: Icon(Icons.settings),
              label: 'Settings'),
        ],
      ),
    );
  }
}
