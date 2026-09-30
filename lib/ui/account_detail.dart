import 'package:flutter/material.dart';

import '../data/models.dart';
import '../state/app_state.dart';
import '../util/format.dart';
import '../util/currencies.dart';
import 'asset_panel.dart';
import 'gold_panel.dart';
import 'invest_panel.dart';
import 'loan_panel.dart';
import 'search_screen.dart';
import 'account_edit.dart';
import 'calendar_screen.dart';
import 'card_panel.dart';
import 'transaction_edit.dart';
import 'widgets.dart';
import '../l10n/l10n.dart';

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

  /// Type filter for the list (null = everything).
  TxType? _filter;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final account = state.accountById(widget.accountId);
    if (account == null) {
      return Scaffold(body: Center(child: Text(tr('Account not found'))));
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
            tooltip: tr('Search This Account'),
            icon: const Icon(Icons.search),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => SearchScreen(initialAccountId: account.id)),
            ),
          ),
          IconButton(
            tooltip: _calendar ? tr('List view') : tr('Calendar view'),
            icon: Icon(_calendar ? Icons.view_list : Icons.calendar_month),
            onPressed: () => setState(() => _calendar = !_calendar),
          ),
          IconButton(
            tooltip: tr('Add Transaction'),
            icon: const Icon(Icons.add),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) =>
                    TransactionEditScreen(initialAccountId: account.id),
              ),
            ),
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
              PopupMenuItem(value: 'edit', child: Text(tr('Edit Account'))),
              PopupMenuItem(
                  value: 'balance', child: Text(tr('Set Current Balance'))),
              if (account.type == AccountType.gold && !isGold(account.currency))
                PopupMenuItem(
                    value: 'grams', child: Text(tr('Switch to Grams…'))),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: tr('Add Transaction'),
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
          // Filter after the running balance, so balances stay correct.
          final shownIdx = [
            for (var k = 0; k < txns.length; k++)
              if (_filter == null || txns[k].type == _filter) k
          ];
          var shownSum = 0.0;
          for (final k in shownIdx) {
            if (!txns[k].isFuture) shownSum += _effect(txns[k], account.id!);
          }
          return ListView.builder(
            padding: const EdgeInsets.only(bottom: 96),
            itemCount: shownIdx.length + 1,
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
                    if (account.loan != null) LoanPanel(account: account),
                    if (account.investMode != null)
                      InvestPanel(account: account),
                    if (account.hasAssetValue) AssetPanel(account: account),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                      child: Row(
                        children: [
                          for (final (label, type) in [
                            (tr('All'), null),
                            (tr('Expenses'), TxType.expense),
                            (tr('Income'), TxType.income),
                            (tr('Transfers'), TxType.transfer),
                          ])
                            Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: ChoiceChip(
                                label: Text(label),
                                selected: _filter == type,
                                onSelected: (_) => setState(() => _filter = type),
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (_filter != null)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                        child: Text(
                          '${shownIdx.length} ${_filter == TxType.expense ? tr('expenses') : _filter == TxType.income ? tr('income entries') : tr('transfers')}'
                          ' · ${_filter == TxType.transfer ? tr('net ') : ''}'
                          '${fmtMoney(_filter == TxType.expense ? -shownSum : shownSum, account.currency)}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                  ],
                );
              }
              final idx = shownIdx[i - 1];
              final t = txns[idx];
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
                        if (running[idx] != null)
                          Text(tr('Balance ${fmtAmount(running[idx]!)}'),
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
        title: Text(liability ? tr('Amount owed today') : tr('Balance today')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
                tr('Enter the real figure from your bank or wallet. The starting '
                'balance is adjusted so today\'s balance matches; no '
                'transaction is added.')),
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
              child: Text(tr('Cancel'))),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text),
              child: Text(tr('Set'))),
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
    final shown = liability ? -account.balance : account.worth;
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
                '${liability ? tr(' · amount owed') : ''}',
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
                '≈ ${fmtMoney(state.toBase(account.worth, account.currency), state.baseCurrency)}',
                style: TextStyle(color: scheme.onPrimaryContainer),
              ),
            if (count != null) ...[
              const SizedBox(height: 8),
              Text(tr('$count transaction(s)'),
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
