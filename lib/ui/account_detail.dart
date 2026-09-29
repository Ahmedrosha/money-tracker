import 'package:flutter/material.dart';

import '../data/models.dart';
import '../state/app_state.dart';
import '../util/format.dart';
import '../util/currencies.dart';
import 'gold_panel.dart';
import 'account_edit.dart';
import 'calendar_screen.dart';
import 'card_panel.dart';
import 'transaction_edit.dart';
import 'widgets.dart';

class AccountDetailScreen extends StatefulWidget {
  const AccountDetailScreen({super.key, required this.accountId});

  final int accountId;

  @override
  State<AccountDetailScreen> createState() => _AccountDetailScreenState();
}

class _AccountDetailScreenState extends State<AccountDetailScreen> {
  Future<List<Txn>>? _future;
  int _loadedVersion = -1;
  bool _calendar = false;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final account = state.accountById(widget.accountId);
    if (account == null) {
      return const Scaffold(body: Center(child: Text('Account not found')));
    }
    if (_loadedVersion != state.version) {
      _loadedVersion = state.version;
      _future = state.db.transactions(accountId: widget.accountId);
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(account.fullName),
        actions: [
          IconButton(
            tooltip: _calendar ? 'List view' : 'Calendar view',
            icon: Icon(_calendar ? Icons.view_list : Icons.calendar_month),
            onPressed: () => setState(() => _calendar = !_calendar),
          ),
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'edit') {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => AccountEditScreen(account: account)),
                );
              } else if (v == 'balance') {
                _setBalance(context, state, account);
              } else if (v == 'grams') {
                switchGoldToWeight(context, state, account);
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'edit', child: Text('Edit Account')),
              const PopupMenuItem(
                  value: 'balance', child: Text('Set Current Balance')),
              if (account.type == AccountType.gold && !isGold(account.currency))
                const PopupMenuItem(
                    value: 'grams', child: Text('Switch to Grams…')),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Add Transaction',
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) =>
                TransactionEditScreen(initialAccountId: account.id),
          ),
        ),
        child: const Icon(Icons.add),
      ),
      body: _calendar
          ? ListView(
              padding: const EdgeInsets.only(bottom: 96),
              children: [
                _header(context, state, account, null),
                if (state.cards[account.id] != null)
                  CardPanel(summary: state.cards[account.id]!),
                CalendarView(accountId: account.id, shrinkWrap: true),
              ],
            )
          : FutureBuilder<List<Txn>>(
        future: _future,
        builder: (context, snap) {
          final txns = snap.data ?? const <Txn>[];
          // Running balance after each transaction (list is newest first).
          // Future-dated entries are not in the balance yet.
          final running = <double?>[];
          var bal = account.balance;
          for (final t in txns) {
            if (t.isFuture) {
              running.add(null);
              continue;
            }
            running.add(bal);
            bal -= _effect(t, account.id!);
          }
          return ListView.builder(
            padding: const EdgeInsets.only(bottom: 96),
            itemCount: txns.length + 1,
            itemBuilder: (context, i) {
              if (i == 0) {
                final card = state.cards[account.id];
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _header(context, state, account, txns.length),
                    if (card != null) CardPanel(summary: card),
                    if (isGold(account.currency))
                      GoldPanel(account: account, txns: txns),
                  ],
                );
              }
              final t = txns[i - 1];
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TxnTile(
                    txn: t,
                    perspectiveAccountId: account.id,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => TransactionEditScreen(txn: t)),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(72, 0, 16, 8),
                    child: Row(
                      children: [
                        Text(shortDateFmt.format(t.date),
                            style: Theme.of(context).textTheme.bodySmall),
                        const Spacer(),
                        if (running[i - 1] != null)
                          Text('Balance ${fmtAmount(running[i - 1]!)}',
                              style: Theme.of(context).textTheme.bodySmall),
                      ],
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _setBalance(
      BuildContext context, AppState state, Account a) async {
    final liability = a.type.isLiability;
    final shown = liability ? -a.balance : a.balance;
    final ctrl = TextEditingController(text: shown.toStringAsFixed(2));
    final res = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(liability ? 'Amount owed today' : 'Balance today'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
                'Enter the real figure from your bank or wallet. The starting '
                'balance is adjusted so today\'s balance matches; no '
                'transaction is added.'),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(
                  decimal: true, signed: true),
              decoration: InputDecoration(
                suffixText: currencyUnit(a.currency),
                border: const OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text),
              child: const Text('Set')),
        ],
      ),
    );
    if (res == null) return;
    final v = parseAmount(res);
    if (v == null) return;
    await state.setCurrentBalance(a, liability ? -v : v);
  }

  static double _effect(Txn t, int accountId) {
    switch (t.type) {
      case TxType.income:
        return t.amount;
      case TxType.expense:
        return -t.amount;
      case TxType.transfer:
        if (t.toAccountId == accountId && t.accountId == accountId) return 0;
        if (t.toAccountId == accountId) return t.toAmount ?? t.amount;
        return -t.amount;
    }
  }

  Widget _header(
      BuildContext context, AppState state, Account account, int? count) {
    final liability = account.type.isLiability;
    final shown = liability ? -account.balance : account.balance;
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.all(16),
      color: scheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
                '${account.type.label} · ${currencyUnit(account.currency)}'
                '${liability ? ' · amount owed' : ''}',
                style: TextStyle(color: scheme.onPrimaryContainer)),
            const SizedBox(height: 4),
            Text(
              fmtMoney(shown, account.currency),
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  color: scheme.onPrimaryContainer,
                  fontWeight: FontWeight.bold),
            ),
            if (account.currency != state.baseCurrency &&
                state.convert(1, account.currency, state.baseCurrency) != null)
              Text(
                '≈ ${fmtMoney(state.toBase(account.balance, account.currency), state.baseCurrency)}',
                style: TextStyle(color: scheme.onPrimaryContainer),
              ),
            if (count != null) ...[
              const SizedBox(height: 8),
              Text('$count transaction(s)',
                  style: TextStyle(
                      color: scheme.onPrimaryContainer.withValues(alpha: 0.75),
                      fontSize: 12)),
            ],
          ],
        ),
      ),
    );
  }
}
