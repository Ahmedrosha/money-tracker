import 'package:flutter/material.dart';

import '../data/models.dart';
import '../state/app_state.dart';
import '../util/format.dart';
import 'transaction_edit.dart';
import 'widgets.dart';

class TransactionsScreen extends StatefulWidget {
  const TransactionsScreen({super.key});

  @override
  State<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _TransactionsScreenState extends State<TransactionsScreen> {
  late DateTime _month;
  TxType? _filter;
  Future<List<Txn>>? _future;
  String _loadedKey = '';

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _month = DateTime(now.year, now.month);
  }

  void _shiftMonth(int delta) {
    setState(() => _month = DateTime(_month.year, _month.month + delta));
  }

  Future<void> _pickMonth() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _month,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      helpText: 'Pick any day in the month',
    );
    if (picked != null) {
      setState(() => _month = DateTime(picked.year, picked.month));
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final key = '${state.version}-${_month.year}-${_month.month}';
    if (key != _loadedKey) {
      _loadedKey = key;
      _future = state.db.transactions(
        from: _month,
        to: DateTime(_month.year, _month.month + 1),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Transactions'),
      ),
      body: FutureBuilder<List<Txn>>(
        future: _future,
        builder: (context, snap) {
          final all = snap.data ?? const <Txn>[];
          var income = 0.0;
          var expense = 0.0;
          for (final t in all) {
            final cur = state.accountById(t.accountId)?.currency ??
                state.baseCurrency;
            if (t.type == TxType.income) income += state.toBase(t.amount, cur);
            if (t.type == TxType.expense) {
              expense += state.toBase(t.amount, cur);
            }
          }
          final list = _filter == null
              ? all
              : all.where((t) => t.type == _filter).toList();
          final pending = state
              .pendingOccurrences(
                  _month, DateTime(_month.year, _month.month + 1))
              .where((o) => _filter == null || o.rule.type == _filter)
              .toList();

          // Merge transactions and pending recurring items, newest first.
          final items = <(DateTime, Object)>[
            for (final t in list) (t.date, t),
            for (final o in pending) (o.date, o),
          ]..sort((a, b) => b.$1.compareTo(a.$1));

          // Build rows: day headers + entries.
          final rows = <Widget>[];
          DateTime? day;
          for (final (date, item) in items) {
            final d = DateTime(date.year, date.month, date.day);
            if (day == null || d != day) {
              day = d;
              rows.add(Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                child: Text(
                  dayFmt.format(d),
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: Theme.of(context).colorScheme.primary),
                ),
              ));
            }
            if (item is Txn) {
              rows.add(TxnTile(
                txn: item,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => TransactionEditScreen(txn: item)),
                ),
              ));
            } else if (item is Occurrence) {
              rows.add(OccurrenceTile(occurrence: item));
            }
          }

          return ListView(
            padding: const EdgeInsets.only(bottom: 96),
            children: [
              _MonthBar(
                month: _month,
                onPrev: () => _shiftMonth(-1),
                onNext: () => _shiftMonth(1),
                onTap: _pickMonth,
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Expanded(
                      child: _TotalBox(
                          label: 'Income',
                          value: income,
                          currency: state.baseCurrency,
                          color: kIncomeColor),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _TotalBox(
                          label: 'Expenses',
                          value: expense,
                          currency: state.baseCurrency,
                          color: kExpenseColor),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _TotalBox(
                          label: 'Net',
                          value: income - expense,
                          currency: state.baseCurrency,
                          color: amountColor(context, income - expense)),
                    ),
                  ],
                ),
              ),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Row(
                  children: [
                    _chip('All', null),
                    _chip('Expenses', TxType.expense),
                    _chip('Income', TxType.income),
                    _chip('Transfers', TxType.transfer),
                  ],
                ),
              ),
              if (snap.connectionState == ConnectionState.done && items.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(40),
                  child: Center(child: Text('No transactions this month')),
                ),
              ...rows,
            ],
          );
        },
      ),
    );
  }

  Widget _chip(String label, TxType? type) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: _filter == type,
        onSelected: (_) => setState(() => _filter = type),
      ),
    );
  }
}

class _MonthBar extends StatelessWidget {
  const _MonthBar({
    required this.month,
    required this.onPrev,
    required this.onNext,
    required this.onTap,
  });

  final DateTime month;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          IconButton(
              onPressed: onPrev, icon: const Icon(Icons.chevron_left)),
          Expanded(
            child: TextButton(
              onPressed: onTap,
              child: Text(monthFmt.format(month),
                  style: Theme.of(context).textTheme.titleMedium),
            ),
          ),
          IconButton(
              onPressed: onNext, icon: const Icon(Icons.chevron_right)),
        ],
      ),
    );
  }
}

class _TotalBox extends StatelessWidget {
  const _TotalBox({
    required this.label,
    required this.value,
    required this.currency,
    required this.color,
  });

  final String label;
  final double value;
  final String currency;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(fmtAmount(value),
                style: TextStyle(fontWeight: FontWeight.bold, color: color)),
          ),
          Text(currency, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}
