import 'package:flutter/material.dart';

import '../data/models.dart';
import '../state/app_state.dart';
import '../util/format.dart';
import 'calendar_screen.dart';
import 'search_screen.dart';
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
  bool _calendar = false;
  int? _calAccountId;
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
      floatingActionButton: _calendar
          ? null // the calendar adds on the selected day
          : FloatingActionButton(
              tooltip: 'Add transaction',
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const TransactionEditScreen()),
              ),
              child: const Icon(Icons.add),
            ),
      appBar: AppBar(
        title: const Text('Transactions'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(52),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Row(
              children: [
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(
                        value: false,
                        icon: Icon(Icons.view_list),
                        label: Text('List')),
                    ButtonSegment(
                        value: true,
                        icon: Icon(Icons.calendar_month),
                        label: Text('Calendar')),
                  ],
                  selected: {_calendar},
                  showSelectedIcon: false,
                  onSelectionChanged: (v) => setState(() => _calendar = v.first),
                ),
                const SizedBox(width: 8),
                if (_calendar)
                  Expanded(
                    child: TextButton.icon(
                      icon: const Icon(Icons.filter_list),
                      label: Text(
                          state.accountById(_calAccountId)?.name ?? 'All accounts',
                          overflow: TextOverflow.ellipsis),
                      onPressed: () async {
                        final id = await pickAccount(context,
                            current: _calAccountId,
                            title: 'Show calendar for',
                            allowAll: true);
                        if (id == null) return;
                        setState(() => _calAccountId = id == -1 ? null : id);
                      },
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          const HideAmountsButton(),
          IconButton(
            tooltip: 'Search all transactions',
            icon: const Icon(Icons.search),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SearchScreen()),
            ),
          ),
        ],
      ),
      body: _calendar
          ? CalendarView(key: ValueKey(_calAccountId), accountId: _calAccountId)
          : FutureBuilder<List<Txn>>(
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

          final byCategory = state.txnSort == 'category';

          // Merge transactions and pending recurring items, newest first.
          final items = <(DateTime, Object)>[
            for (final t in list) (t.date, t),
            for (final o in pending) (o.date, o),
          ]..sort((a, b) => b.$1.compareTo(a.$1));

          // Build rows: day headers + entries.
          final rows = <Widget>[];
          if (byCategory) {
            rows.addAll(_groupedRows(context, state, list));
          }
          DateTime? day;
          for (final (date, item) in byCategory ? const <(DateTime, Object)>[] : items) {
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
                    const SizedBox(width: 4),
                    PopupMenuButton<String>(
                      tooltip: 'Sort by',
                      initialValue: state.txnSort,
                      onSelected: state.setTxnSort,
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 'date', child: Text('Sort by date')),
                        PopupMenuItem(
                            value: 'category',
                            child: Text('Sort by type (category / account)')),
                      ],
                      child: Chip(
                        avatar: const Icon(Icons.sort, size: 18),
                        label: Text(byCategory ? 'By type' : 'By date'),
                      ),
                    ),
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

  /// "Sort by type": expenses/income grouped by category group and
  /// category; transfers grouped by account with In and Out.
  List<Widget> _groupedRows(
      BuildContext context, AppState state, List<Txn> list) {
    final out = <Widget>[];
    final expenses = list.where((t) => t.type == TxType.expense).toList();
    final incomes = list.where((t) => t.type == TxType.income).toList();
    final transfers = list.where((t) => t.type == TxType.transfer).toList();
    final showHeaders = _filter == null;
    if (list.isNotEmpty) out.add(_orderBar(context, state));
    if (expenses.isNotEmpty) {
      if (showHeaders) out.add(_sectionTitle(context, 'Expenses'));
      out.addAll(_categoryGroups(context, state, expenses, kExpenseColor));
    }
    if (incomes.isNotEmpty) {
      if (showHeaders) out.add(_sectionTitle(context, 'Income'));
      out.addAll(_categoryGroups(context, state, incomes, kIncomeColor));
    }
    if (transfers.isNotEmpty) {
      if (showHeaders) out.add(_sectionTitle(context, 'Transfers'));
      out.addAll(_transferGroups(context, state, transfers));
    }
    return out;
  }

  /// Compares two groups according to the chosen order.
  static int _compare(AppState state, double va, double vb, int ca, int cb,
      String na, String nb) {
    final parts = state.groupOrder.split('_');
    final desc = parts.length > 1 && parts[1] == 'desc';
    int r;
    switch (parts.first) {
      case 'count':
        r = ca.compareTo(cb);
        break;
      case 'name':
        r = na.toLowerCase().compareTo(nb.toLowerCase());
        break;
      default:
        r = va.compareTo(vb);
    }
    return desc ? -r : r;
  }

  static const _orders = [
    ('value_desc', 'Value: highest first'),
    ('value_asc', 'Value: lowest first'),
    ('count_desc', 'Count: most transactions first'),
    ('count_asc', 'Count: fewest transactions first'),
    ('name_asc', 'Name: A → Z'),
    ('name_desc', 'Name: Z → A'),
  ];

  Widget _orderBar(BuildContext context, AppState state) {
    final label =
        _orders.firstWhere((o) => o.$1 == state.groupOrder, orElse: () => _orders.first).$2;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Align(
        alignment: Alignment.centerLeft,
        child: PopupMenuButton<String>(
          tooltip: 'Order groups by',
          initialValue: state.groupOrder,
          onSelected: state.setGroupOrder,
          itemBuilder: (_) => [
            for (final (v, l) in _orders) PopupMenuItem(value: v, child: Text(l)),
          ],
          child: Chip(
            avatar: const Icon(Icons.swap_vert, size: 18),
            label: Text('Order: $label'),
          ),
        ),
      ),
    );
  }

  Widget _sectionTitle(BuildContext context, String text) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
        child: Text(text,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.bold)),
      );

  Widget _txnWithDate(BuildContext context, Txn t, {int? perspective}) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TxnTile(
            txn: t,
            perspectiveAccountId: perspective,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => TransactionEditScreen(txn: t)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(72, 0, 16, 6),
            child: Text(dayFmt.format(t.date),
                style: Theme.of(context).textTheme.bodySmall),
          ),
        ],
      );

  List<Widget> _categoryGroups(
      BuildContext context, AppState state, List<Txn> txns, Color color) {
    double base(Txn t) => state.toBase(
        t.amount, state.accountById(t.accountId)?.currency ?? state.baseCurrency);
    // group -> category id -> txns
    final groups = <String, Map<int?, List<Txn>>>{};
    for (final t in txns) {
      final c = state.categoryById(t.categoryId);
      final g = c == null
          ? 'Uncategorized'
          : (c.group.isEmpty ? 'Other' : c.group);
      groups.putIfAbsent(g, () => {}).putIfAbsent(t.categoryId, () => []).add(t);
    }
    double sum(Iterable<Txn> l) => l.fold(0.0, (s, t) => s + base(t));
    final sorted = groups.entries.toList()
      ..sort((a, b) => _compare(
          state,
          sum(a.value.values.expand((l) => l)),
          sum(b.value.values.expand((l) => l)),
          a.value.values.fold<int>(0, (n, l) => n + l.length),
          b.value.values.fold<int>(0, (n, l) => n + l.length),
          a.key,
          b.key));
    final cur = state.baseCurrency;
    return [
      for (final g in sorted)
        ExpansionTile(
          key: PageStorageKey('g-${_filter?.name}-${g.key}-${color == kExpenseColor ? 'e' : 'i'}'),
          title: Text(g.key, style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text(
              '${g.value.values.fold<int>(0, (n, l) => n + l.length)} transactions'),
          trailing: Text(fmtMoney(sum(g.value.values.expand((l) => l)), cur),
              style: TextStyle(color: color, fontWeight: FontWeight.bold)),
          children: [
            for (final c in (g.value.entries.toList()
              ..sort((a, b) => _compare(
                  state,
                  sum(a.value),
                  sum(b.value),
                  a.value.length,
                  b.value.length,
                  state.categoryById(a.key)?.name ?? '',
                  state.categoryById(b.key)?.name ?? ''))))
              Padding(
                padding: const EdgeInsets.only(left: 12),
                child: ExpansionTile(
                  key: PageStorageKey('c-${_filter?.name}-${c.key}-${color == kExpenseColor ? 'e' : 'i'}'),
                  leading: CategoryAvatar(category: state.categoryById(c.key)),
                  title: Text(state.categoryById(c.key)?.name ?? 'No category'),
                  subtitle: Text('${c.value.length} transactions'),
                  trailing: Text(fmtMoney(sum(c.value), cur),
                      style: TextStyle(color: color)),
                  children: [
                    for (final t in c.value) _txnWithDate(context, t),
                  ],
                ),
              ),
          ],
        ),
    ];
  }

  List<Widget> _transferGroups(
      BuildContext context, AppState state, List<Txn> txns) {
    final outs = <int, List<Txn>>{};
    final ins = <int, List<Txn>>{};
    for (final t in txns) {
      outs.putIfAbsent(t.accountId, () => []).add(t);
      if (t.toAccountId != null) ins.putIfAbsent(t.toAccountId!, () => []).add(t);
    }
    final ids = {...outs.keys, ...ins.keys}.toList();
    double outSum(int id) => (outs[id] ?? []).fold(0.0, (s, t) => s + t.amount);
    double inSum(int id) =>
        (ins[id] ?? []).fold(0.0, (s, t) => s + (t.toAmount ?? t.amount));
    double volume(int id) {
      final a = state.accountById(id);
      final c = a?.currency ?? state.baseCurrency;
      return state.toBase(outSum(id) + inSum(id), c);
    }

    int count(int id) => (outs[id]?.length ?? 0) + (ins[id]?.length ?? 0);
    ids.sort((a, b) => _compare(state, volume(a), volume(b), count(a),
        count(b), state.accountById(a)?.fullName ?? '',
        state.accountById(b)?.fullName ?? ''));
    final small = Theme.of(context).textTheme.labelLarge;
    return [
      for (final id in ids)
        Builder(builder: (context) {
          final a = state.accountById(id);
          final cur = a?.currency ?? '';
          return ExpansionTile(
            key: PageStorageKey('t-$id'),
            leading: CircleAvatar(
                child: Icon(a == null ? Icons.help_outline : accountTypeIcon(a.type))),
            title: Text(a?.fullName ?? '?',
                style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text.rich(TextSpan(children: [
              TextSpan(
                  text: 'Out ${fmtAmount(outSum(id))}',
                  style: const TextStyle(color: kExpenseColor)),
              const TextSpan(text: '  ·  '),
              TextSpan(
                  text: 'In ${fmtAmount(inSum(id))}',
                  style: const TextStyle(color: kIncomeColor)),
              TextSpan(text: '  $cur'),
            ])),
            children: [
              if ((outs[id] ?? []).isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 8, 16, 4),
                  child: Text('Transfers out (${outs[id]!.length})',
                      style: small?.copyWith(color: kExpenseColor)),
                ),
                for (final t in outs[id]!)
                  _txnWithDate(context, t, perspective: id),
              ],
              if ((ins[id] ?? []).isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 8, 16, 4),
                  child: Text('Transfers in (${ins[id]!.length})',
                      style: small?.copyWith(color: kIncomeColor)),
                ),
                for (final t in ins[id]!)
                  _txnWithDate(context, t, perspective: id),
              ],
            ],
          );
        }),
    ];
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
