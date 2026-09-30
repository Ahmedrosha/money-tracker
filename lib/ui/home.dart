import 'package:flutter/material.dart';

import 'accounts_screen.dart';
import 'budgets_screen.dart';
import 'reports_screen.dart';
import 'settings_screen.dart';
import 'transaction_edit.dart';
import 'transactions_screen.dart';
import '../l10n/l10n.dart';

/// The selected bottom tab; other screens can switch tabs through it.
final ValueNotifier<int> homeTab = ValueNotifier<int>(0);

class HomeTabs {
  static const accounts = 0;
  static const transactions = 1;
  static const budgets = 2;
  static const reports = 3;
  static const settings = 4;
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    const pages = [
      AccountsScreen(),
      TransactionsScreen(),
      BudgetsScreen(),
      ReportsScreen(),
      SettingsScreen(),
    ];
    return ValueListenableBuilder<int>(
      valueListenable: homeTab,
      builder: (context, index, _) => Scaffold(
        body: IndexedStack(index: index, children: pages),
        // Transactions and Budgets have their own add buttons.
        floatingActionButton: index != HomeTabs.accounts
            ? null
            : FloatingActionButton(
                tooltip: tr('Add Transaction'),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const TransactionEditScreen()),
                ),
                child: const Icon(Icons.add),
              ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: index,
          onDestinationSelected: (i) => homeTab.value = i,
          destinations: [
            NavigationDestination(
                icon: Icon(Icons.account_balance_wallet_outlined),
                selectedIcon: Icon(Icons.account_balance_wallet),
                label: tr('Accounts')),
            NavigationDestination(
                icon: Icon(Icons.receipt_long_outlined),
                selectedIcon: Icon(Icons.receipt_long),
                label: tr('Transactions')),
            NavigationDestination(
                icon: Icon(Icons.savings_outlined),
                selectedIcon: Icon(Icons.savings),
                label: tr('Budgets')),
            NavigationDestination(
                icon: Icon(Icons.insights_outlined),
                selectedIcon: Icon(Icons.insights),
                label: tr('Reports')),
            NavigationDestination(
                icon: Icon(Icons.settings_outlined),
                selectedIcon: Icon(Icons.settings),
                label: tr('Settings')),
          ],
        ),
      ),
    );
  }
}
