import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../data/models.dart';
import '../state/app_state.dart';
import '../util/currencies.dart';
import '../util/format.dart';
import 'account_detail.dart';
import 'reports_more.dart';
import 'search_screen.dart';
import 'widgets.dart';

Widget _heading(BuildContext context, String t, {String? sub}) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(t,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold)),
          if (sub != null) Text(sub, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );

/// Name, value and a bar scaled to [max].
class _ShareRow extends StatelessWidget {
  const _ShareRow({
    required this.label,
    required this.value,
    required this.max,
    this.valueText,
    this.caption,
    this.color,
    this.onTap,
  });

  final String label;
  final double value;
  final double max;
  final String? valueText;
  final String? caption;
  final Color? color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final frac = max <= 0 ? 0.0 : (value.abs() / max).clamp(0.0, 1.0);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w500)),
                      ),
                      Text(valueText ?? fmtAmount(value),
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: Stack(
                      children: [
                        Container(height: 8, color: scheme.surfaceContainerHighest),
                        FractionallySizedBox(
                          widthFactor: frac,
                          child: Container(height: 8, color: color ?? scheme.primary),
                        ),
                      ],
                    ),
                  ),
                  if (caption != null) ...[
                    const SizedBox(height: 4),
                    Text(caption!, style: Theme.of(context).textTheme.bodySmall),
                  ],
                ],
              ),
            ),
            if (onTap != null) ...[
              const SizedBox(width: 4),
              Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
            ],
          ],
        ),
      ),
    );
  }
}

// ===========================================================================
// Outlook: cash and bank money over the coming weeks
// ===========================================================================

class _Event {
  final DateTime date;
  final String name;
  final double amount; // main currency, + in / - out
  final IconData icon;
  final bool estimate;
  _Event(this.date, this.name, this.amount, this.icon, {this.estimate = false});
}

class _Outlook {
  final double start;
  final List<_Event> events;
  final List<(DateTime, double)> days;
  _Outlook(this.start, this.events, this.days);
}

bool isSpendable(Account a) =>
    !a.archived &&
    !a.excludeTotal &&
    (a.type.family == AccountFamily.cash ||
        (a.type.family == AccountFamily.bank && a.type != AccountType.certificate));

class OutlookTab extends StatefulWidget {
  const OutlookTab({super.key});

  @override
  State<OutlookTab> createState() => _OutlookTabState();
}

class _OutlookTabState extends State<OutlookTab> {
  int _days = 60;
  int? _sel;
  Future<_Outlook>? _future;
  String _key = '';

  Future<_Outlook> _load(AppState state) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final end = DateTime(today.year, today.month, today.day + _days + 1);
    final liquid = {
      for (final a in state.accounts)
        if (isSpendable(a)) a.id!: a
    };
    var start = 0.0;
    for (final a in liquid.values) {
      start += state.toBase(a.balance, a.currency);
    }
    final events = <_Event>[];
    DateTime notBefore(DateTime d) => d.isBefore(today) ? today : d;

    // Effect of one entry on cash & bank accounts.
    double effect(TxType type, int accId, int? toId, double amount, double? toAmount) {
      var v = 0.0;
      final from = liquid[accId];
      final to = liquid[toId];
      switch (type) {
        case TxType.income:
          if (from != null) v += state.toBase(amount, from.currency);
        case TxType.expense:
          if (from != null) v -= state.toBase(amount, from.currency);
        case TxType.transfer:
          if (from != null) v -= state.toBase(amount, from.currency);
          if (to != null) v += state.toBase(toAmount ?? amount, to.currency);
      }
      return v;
    }

    String nameOf(TxType type, int? toId, String payee, int? catId) {
      if (type == TxType.transfer) {
        return 'Transfer to ${state.accountById(toId)?.name ?? '?'}';
      }
      if (payee.isNotEmpty) return payee;
      return state.categoryById(catId)?.name ?? type.label;
    }

    // Entries already recorded with a future date.
    for (final t in await state.db.transactions(from: now, to: end)) {
      if (!t.date.isAfter(now)) continue;
      final v = effect(t.type, t.accountId, t.toAccountId, t.amount, t.toAmount);
      if (v.abs() < 0.005) continue;
      events.add(_Event(t.date, nameOf(t.type, t.toAccountId, t.payee, t.categoryId),
          v, t.type == TxType.income ? Icons.south_west : Icons.north_east));
    }

    // Recurring items not confirmed yet (overdue ones count as today).
    for (final o in state.pendingOccurrences(DateTime(1970), end)) {
      final r = o.rule;
      final v = effect(r.type, r.accountId, r.toAccountId, r.amount, r.toAmount);
      if (v.abs() < 0.005) continue;
      events.add(_Event(notBefore(o.date),
          nameOf(r.type, r.toAccountId, r.payee, r.categoryId), v, Icons.repeat));
    }

    // Credit card payments: the open statement, then each coming cycle.
    for (final c in state.cards.values) {
      final a = c.card;
      if (a.archived || a.excludeTotal || !a.hasCycle) continue;
      final last = c.last;
      if (last != null && !last.settled && last.remaining > 0.004) {
        events.add(_Event(notBefore(last.dueDate), '${a.fullName} statement',
            -state.toBase(last.remaining, a.currency), Icons.credit_card));
      }
      var close = c.nextClose;
      if (close == null) continue;
      var prevClose = lastCloseBefore(now, a.statementDay!);
      var first = true;
      while (true) {
        final due = dueDateAfter(close!, a.dueDay!);
        if (!due.isBefore(end)) break;
        final amt = first
            ? c.cycleSpent
            : await state.db.debitsBetween(a.id!, prevClose, close);
        if (amt > 0.004) {
          events.add(_Event(due, '${a.fullName} (estimate)',
              -state.toBase(amt, a.currency), Icons.credit_card,
              estimate: true));
        }
        first = false;
        prevClose = close;
        close = cycleCloseIn(close.year, close.month + 1, a.statementDay!);
      }
    }

    // Loan installments still to pay.
    for (final a in state.plannedLoans) {
      final t = a.loan!;
      final from = liquid[t.payAccountId];
      if (from == null) continue;
      for (final r in t.schedule().skip(t.nextIndex)) {
        if (!r.date.isBefore(end)) break;
        events.add(_Event(notBefore(r.date),
            '${a.name} installment ${r.index + 1}/${t.months}',
            -state.toBase(r.payment, a.currency), Icons.request_quote_outlined));
      }
    }

    events.sort((x, y) => x.date.compareTo(y.date));
    final days = <(DateTime, double)>[];
    var bal = start;
    var k = 0;
    for (var i = 0; i <= _days; i++) {
      final d = DateTime(today.year, today.month, today.day + i);
      final next = DateTime(d.year, d.month, d.day + 1);
      while (k < events.length && events[k].date.isBefore(next)) {
        bal += events[k].amount;
        k++;
      }
      days.add((d, bal));
    }
    return _Outlook(start, events, days);
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final key = '${state.version}-$_days';
    if (key != _key) {
      _key = key;
      _sel = null;
      _future = _load(state);
    }
    final cur = state.baseCurrency;
    final small = Theme.of(context).textTheme.bodySmall;
    return FutureBuilder<_Outlook>(
      future: _future,
      builder: (context, snap) {
        final o = snap.data;
        return ListView(
          padding: const EdgeInsets.only(bottom: 32),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: SegmentedButton<int>(
                segments: const [
                  ButtonSegment(value: 30, label: Text('30 days')),
                  ButtonSegment(value: 60, label: Text('60 days')),
                  ButtonSegment(value: 90, label: Text('90 days')),
                ],
                selected: {_days},
                onSelectionChanged: (s) => setState(() => _days = s.first),
              ),
            ),
            if (o == null)
              const Padding(
                padding: EdgeInsets.all(40),
                child: Center(child: CircularProgressIndicator()),
              )
            else ..._body(context, o, cur, small),
          ],
        );
      },
    );
  }

  List<Widget> _body(
      BuildContext context, _Outlook o, String cur, TextStyle? small) {
    final sel = _sel == null || _sel! >= o.days.length ? o.days.length - 1 : _sel!;
    final low = o.days.reduce((a, b) => b.$2 < a.$2 ? b : a);
    final endV = o.days.last.$2;
    final inflow = o.events.where((e) => e.amount > 0).fold<double>(0, (t, e) => t + e.amount);
    final outflow = o.events.where((e) => e.amount < 0).fold<double>(0, (t, e) => t - e.amount);
    final dayFmt2 = DateFormat('d MMM');
    final labels = List<String?>.filled(o.days.length, null);
    final step = (o.days.length / 5).ceil();
    for (var i = 0; i < o.days.length; i += step) {
      labels[i] = dayFmt2.format(o.days[i].$1);
    }
    var running = o.start;
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(sel == 0 ? 'Today' : 'On ${dayFmt.format(o.days[sel].$1)}',
                style: small),
            Text(fmtMoney(o.days[sel].$2, cur),
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: o.days[sel].$2 < 0 ? kExpenseColor : null)),
            Text('Cash, wallets and bank accounts · drag across the chart',
                style: small),
          ],
        ),
      ),
      LineChart(
        points: o.days,
        selected: sel,
        xLabels: labels,
        height: 200,
        color: low.$2 < 0 ? kExpenseColor : null,
        onSelect: (i) => setState(() => _sel = i),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _chip(context, 'Now', fmtMoney(o.start, cur)),
            _chip(context, 'In $_days days', fmtMoney(endV, cur)),
            _chip(context, 'Lowest',
                '${fmtMoney(low.$2, cur)} · ${dayFmt2.format(low.$1)}',
                warn: low.$2 < 0),
            _chip(context, 'Coming in', fmtMoney(inflow, cur)),
            _chip(context, 'Going Out', fmtMoney(outflow, cur)),
          ],
        ),
      ),
      if (low.$2 < 0)
        Card(
          color: kExpenseColor.withValues(alpha: 0.12),
          margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
                'Your cash and bank money goes below zero on ${dayFmt.format(o.days.firstWhere((d) => d.$2 < 0).$1)}. Move money in or plan a smaller card payment before then.'),
          ),
        ),
      _heading(context, 'What\'s coming',
          sub: o.events.isEmpty
              ? 'Nothing scheduled'
              : 'Recurring items, future-dated entries and card payments'),
      for (final e in o.events)
        () {
          running += e.amount;
          return ListTile(
            dense: true,
            leading: Icon(e.icon),
            title: Text(e.name, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(
                '${dayFmt.format(e.date)} · balance ${fmtAmount(running)}'),
            trailing: Text(
              '${e.amount > 0 ? '+' : ''}${fmtAmount(e.amount)}',
              style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: amountColor(context, e.amount),
                  fontStyle: e.estimate ? FontStyle.italic : null),
            ),
          );
        }(),
      const Padding(
        padding: EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: Text(
          'Card amounts for cycles still open are estimates: what has posted so '
          'far plus installments already scheduled. Foreign currencies use '
          'today\'s rates.',
        ),
      ),
    ];
  }

  Widget _chip(BuildContext context, String label, String value,
          {bool warn = false}) =>
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: warn
              ? kExpenseColor.withValues(alpha: 0.12)
              : Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: Theme.of(context).textTheme.bodySmall),
            Text(value,
                style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: warn ? kExpenseColor : null)),
          ],
        ),
      );
}

// ===========================================================================
// Where my money is: net worth by type, bank or currency
// ===========================================================================

enum _Split { type, bank, currency }

class AllocationTab extends StatefulWidget {
  const AllocationTab({super.key});

  @override
  State<AllocationTab> createState() => _AllocationTabState();
}

class _Group {
  final String name;
  final List<(Account, double)> accounts = [];
  double total = 0;

  /// Sum in the group's own currency (currency view only).
  double native = 0;
  _Group(this.name);
}

class _AllocationTabState extends State<AllocationTab> {
  _Split _split = _Split.type;

  String _groupOf(Account a) {
    switch (_split) {
      case _Split.type:
        return a.type.family.label;
      case _Split.bank:
        if (a.bank.isNotEmpty) return a.bank;
        return a.type.family == AccountFamily.cash ? 'Cash' : 'No bank';
      case _Split.currency:
        return a.currency;
    }
  }

  List<_Group> _groups(AppState state, bool positive) {
    final map = <String, _Group>{};
    for (final a in state.countedAccounts) {
      final v = state.toBase(a.balance, a.currency);
      if (v.abs() < 0.005 || (v > 0) != positive) continue;
      final g = map.putIfAbsent(_groupOf(a), () => _Group(_groupOf(a)));
      g.accounts.add((a, v));
      g.total += v;
      g.native += a.balance;
    }
    final list = map.values.toList()
      ..sort((x, y) => y.total.abs().compareTo(x.total.abs()));
    for (final g in list) {
      g.accounts.sort((x, y) => y.$2.abs().compareTo(x.$2.abs()));
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final cur = state.baseCurrency;
    final assets = _groups(state, true);
    final debts = _groups(state, false);
    final totalA = assets.fold<double>(0, (t, g) => t + g.total);
    final totalD = debts.fold<double>(0, (t, g) => t - g.total);
    final small = Theme.of(context).textTheme.bodySmall;

    Widget group(_Group g, double whole, Color? color) {
      final share = whole <= 0 ? 0 : g.total.abs() / whole * 100;
      final native = _split == _Split.currency && g.name != cur
          ? ' · ${fmtMoney(g.native.abs(), g.name)}'
          : '';
      return Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: EdgeInsets.zero,
          childrenPadding: EdgeInsets.zero,
          title: _ShareRow(
            label: _split == _Split.currency ? currencyName(g.name) : g.name,
            value: g.total.abs(),
            max: whole,
            color: color,
            caption:
                '${share.toStringAsFixed(1)}% · ${g.accounts.length} account${g.accounts.length == 1 ? '' : 's'}$native',
          ),
          children: [
            for (final (a, v) in g.accounts)
              ListTile(
                dense: true,
                contentPadding: const EdgeInsets.only(left: 32, right: 16),
                title: Text(a.fullName),
                subtitle: a.currency == cur
                    ? null
                    : Text(fmtMoney(a.balance, a.currency)),
                trailing: Text(fmtAmount(v.abs())),
              ),
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.only(bottom: 32),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: SegmentedButton<_Split>(
            segments: const [
              ButtonSegment(value: _Split.type, label: Text('Type')),
              ButtonSegment(value: _Split.bank, label: Text('Bank')),
              ButtonSegment(value: _Split.currency, label: Text('Currency')),
            ],
            selected: {_split},
            onSelectionChanged: (s) => setState(() => _split = s.first),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Net Worth', style: small),
              Text(fmtMoney(totalA - totalD, cur),
                  style: Theme.of(context)
                      .textTheme
                      .headlineSmall
                      ?.copyWith(fontWeight: FontWeight.bold)),
              Text('Own ${fmtAmount(totalA)} · owe ${fmtAmount(totalD)}',
                  style: small),
            ],
          ),
        ),
        _heading(context, 'What You Own', sub: '$cur · tap to see accounts'),
        for (final g in assets) group(g, totalA, null),
        if (debts.isNotEmpty) ...[
          _heading(context, 'What You Owe', sub: cur),
          for (final g in debts) group(g, totalD, kExpenseColor),
        ],
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Text(
            'Current balances of accounts counted in net worth, in $cur at '
            'today\'s rates. Archived and excluded accounts are left out.',
            style: small,
          ),
        ),
      ],
    );
  }
}

// ===========================================================================
// Compare months and top payees
// ===========================================================================

class CompareTab extends StatefulWidget {
  const CompareTab({super.key});

  @override
  State<CompareTab> createState() => _CompareTabState();
}

class _Cmp {
  final String key;
  final String name;
  final Category? category;
  double now = 0, prev = 0, avg = 0;
  _Cmp(this.key, this.name, this.category);
}

class _CmpData {
  final Map<String, _Cmp> groups;
  final Map<String, Map<String, _Cmp>> cats; // group -> category key -> row
  _CmpData(this.groups, this.cats);
}

enum _PPeriod { thisMonth, lastMonth, thisYear, last12, all }

class _CompareTabState extends State<CompareTab> {
  bool _payees = false;

  // Compare
  late DateTime _month;
  Future<_CmpData>? _cmp;
  String _cmpKey = '';

  // Payees
  _PPeriod _period = _PPeriod.last12;
  TxType _type = TxType.expense;
  Future<List<(String, double, int)>>? _pay;
  String _payKey = '';

  @override
  void initState() {
    super.initState();
    final n = DateTime.now();
    _month = DateTime(n.year, n.month);
  }

  String _groupName(Category? c) {
    if (c == null) return 'Uncategorized';
    return c.group.isEmpty ? 'Other' : c.group;
  }

  Future<_CmpData> _loadCmp(AppState state) async {
    final from = DateTime(_month.year, _month.month - 12);
    final rows = await state.db
        .expensesByMonthCategory(from, DateTime(_month.year, _month.month + 1));
    String ym(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}';
    final nowKey = ym(_month);
    final prevKey = ym(DateTime(_month.year, _month.month - 1));
    final groups = <String, _Cmp>{};
    final cats = <String, Map<String, _Cmp>>{};
    for (final r in rows) {
      final id = r['cat'] as int?;
      final c = state.categoryById(id);
      final g = _groupName(c);
      final v = state.toBase((r['total'] as num).toDouble(),
          (r['cur'] as String?) ?? state.baseCurrency);
      final gr = groups.putIfAbsent(g, () => _Cmp(g, g, null));
      final cr = cats
          .putIfAbsent(g, () => {})
          .putIfAbsent('$id', () => _Cmp('$id', c?.name ?? 'No category', c));
      final k = r['ym'] as String;
      for (final x in [gr, cr]) {
        if (k == nowKey) {
          x.now += v;
        } else {
          // The 12 months before the selected one.
          x.avg += v / 12;
          if (k == prevKey) x.prev += v;
        }
      }
    }
    return _CmpData(groups, cats);
  }

  (DateTime, DateTime) get _payRange {
    final n = DateTime.now();
    switch (_period) {
      case _PPeriod.thisMonth:
        return (DateTime(n.year, n.month), DateTime(n.year, n.month + 1));
      case _PPeriod.lastMonth:
        return (DateTime(n.year, n.month - 1), DateTime(n.year, n.month));
      case _PPeriod.thisYear:
        return (DateTime(n.year), DateTime(n.year + 1));
      case _PPeriod.last12:
        return (DateTime(n.year, n.month - 11), DateTime(n.year, n.month + 1));
      case _PPeriod.all:
        return (DateTime(1970), DateTime(2200));
    }
  }

  Future<List<(String, double, int)>> _loadPayees(AppState state) async {
    final (from, to) = _payRange;
    final rows = await state.db.payeeTotals(_type, from, to);
    final map = <String, (String, double, int)>{};
    for (final r in rows) {
      final name = r['payee'] as String;
      final k = name.toLowerCase();
      final v = state.toBase((r['total'] as num).toDouble(),
          (r['cur'] as String?) ?? state.baseCurrency);
      final old = map[k];
      map[k] = (old?.$1 ?? name, (old?.$2 ?? 0) + v, (old?.$3 ?? 0) + (r['n'] as int));
    }
    return map.values.toList()..sort((a, b) => b.$2.compareTo(a.$2));
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    return ListView(
      padding: const EdgeInsets.only(bottom: 32),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: false, label: Text('Compare Months')),
              ButtonSegment(value: true, label: Text('Payees')),
            ],
            selected: {_payees},
            onSelectionChanged: (s) => setState(() => _payees = s.first),
          ),
        ),
        ...(_payees ? _payeeView(context, state) : _compareView(context, state)),
      ],
    );
  }

  // ----- Compare months -----

  List<Widget> _compareView(BuildContext context, AppState state) {
    final key = '${state.version}-$_month';
    if (key != _cmpKey) {
      _cmpKey = key;
      _cmp = _loadCmp(state);
    }
    final now = DateTime.now();
    final partial = now.year == _month.year && now.month == _month.month;
    return [
      Row(
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            onPressed: () =>
                setState(() => _month = DateTime(_month.year, _month.month - 1)),
          ),
          Expanded(
            child: Center(
              child: Text(monthFmt.format(_month),
                  style: Theme.of(context).textTheme.titleMedium),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            onPressed: () =>
                setState(() => _month = DateTime(_month.year, _month.month + 1)),
          ),
        ],
      ),
      FutureBuilder<_CmpData>(
        future: _cmp,
        builder: (context, snap) {
          final d = snap.data;
          if (d == null) {
            return const Padding(
                padding: EdgeInsets.all(40),
                child: Center(child: CircularProgressIndicator()));
          }
          final rows = d.groups.values.toList();
          final total = _Cmp('', 'All Spending', null);
          for (final r in rows) {
            total.now += r.now;
            total.prev += r.prev;
            total.avg += r.avg;
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _CmpTile(row: total, bold: true),
              if (partial)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    'This month is still running (day ${now.day} of ${DateTime(now.year, now.month + 1, 0).day}).',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              const Divider(),
              _CmpList(
                rows: rows,
                onTap: (r) => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => Scaffold(
                      appBar: AppBar(
                          title: Text('${r.name} · ${DateFormat('MMM yyyy').format(_month)}')),
                      body: ListView(
                        padding: const EdgeInsets.only(bottom: 32),
                        children: [
                          _CmpTile(row: r, bold: true),
                          const Divider(),
                          _CmpList(rows: (d.cats[r.key] ?? const {}).values.toList()),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    ];
  }

  // ----- Payees -----

  List<Widget> _payeeView(BuildContext context, AppState state) {
    final key = '${state.version}-$_period-$_type';
    if (key != _payKey) {
      _payKey = key;
      _pay = _loadPayees(state);
    }
    final cur = state.baseCurrency;
    const labels = {
      _PPeriod.thisMonth: 'This Month',
      _PPeriod.lastMonth: 'Last Month',
      _PPeriod.thisYear: 'This Year',
      _PPeriod.last12: 'Last 12 Months',
      _PPeriod.all: 'All Time',
    };
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            SegmentedButton<TxType>(
              segments: const [
                ButtonSegment(value: TxType.expense, label: Text('Paid to')),
                ButtonSegment(value: TxType.income, label: Text('Received from')),
              ],
              selected: {_type},
              onSelectionChanged: (s) => setState(() => _type = s.first),
            ),
            PopupMenuButton<_PPeriod>(
              initialValue: _period,
              onSelected: (p) => setState(() => _period = p),
              itemBuilder: (_) => [
                for (final e in labels.entries)
                  PopupMenuItem(value: e.key, child: Text(e.value)),
              ],
              child: Chip(
                avatar: const Icon(Icons.date_range, size: 18),
                label: Text(labels[_period]!),
              ),
            ),
          ],
        ),
      ),
      FutureBuilder<List<(String, double, int)>>(
        future: _pay,
        builder: (context, snap) {
          final list = snap.data;
          if (list == null) {
            return const Padding(
                padding: EdgeInsets.all(40),
                child: Center(child: CircularProgressIndicator()));
          }
          if (list.isEmpty) {
            return const Padding(
              padding: EdgeInsets.all(40),
              child: Center(
                  child: Text('No transactions with a payee in this period')),
            );
          }
          final top = list.take(40).toList();
          final total = list.fold<double>(0, (t, p) => t + p.$2);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _heading(context, '${list.length} payees · ${fmtMoney(total, cur)}',
                  sub: list.length > 40 ? 'Top 40 shown · tap for transactions' : 'Tap for transactions'),
              for (final p in top)
                _ShareRow(
                  label: p.$1,
                  value: p.$2,
                  max: top.first.$2,
                  color: _type == TxType.income ? kIncomeColor : null,
                  caption:
                      '${p.$3} transaction${p.$3 == 1 ? '' : 's'} · average ${fmtAmount(p.$2 / p.$3)}'
                      '${total > 0 ? ' · ${(p.$2 / total * 100).toStringAsFixed(1)}%' : ''}',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          SearchScreen(initialQuery: p.$1, initialType: _type),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    ];
  }
}

String _change(double now, double base) {
  if (base.abs() < 0.01) return now.abs() < 0.01 ? '—' : 'new';
  final p = (now - base) / base.abs() * 100;
  return '${p >= 0 ? '▲' : '▼'} ${p.abs().toStringAsFixed(0)}%';
}

Color? _changeColor(double now, double base) {
  if (base.abs() < 0.01) return null;
  final p = (now - base) / base.abs();
  if (p > 0.1) return kExpenseColor;
  if (p < -0.1) return kIncomeColor;
  return null;
}

class _CmpTile extends StatelessWidget {
  const _CmpTile({required this.row, this.bold = false, this.onTap});

  final _Cmp row;
  final bool bold;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final small = Theme.of(context).textTheme.bodySmall;
    Widget cell(String label, double base) => Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: small),
              Text(fmtAmount(base), style: const TextStyle(fontSize: 13)),
              Text(_change(row.now, base),
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: _changeColor(row.now, base))),
            ],
          ),
        );
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        child: Row(
          children: [
            Expanded(
              flex: 5,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    if (row.category != null) ...[
                      SizedBox(
                          width: 24,
                          height: 24,
                          child: FittedBox(
                              child: CategoryAvatar(category: row.category))),
                      const SizedBox(width: 8),
                    ],
                    Expanded(
                      child: Text(row.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontWeight: bold ? FontWeight.bold : FontWeight.w500)),
                    ),
                  ]),
                  Text(fmtAmount(row.now),
                      style: TextStyle(
                          fontSize: bold ? 20 : 16, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
            cell('Last Month', row.prev),
            cell('12-Mo Avg', row.avg),
            if (onTap != null) const Icon(Icons.chevron_right),
          ],
        ),
      ),
    );
  }
}

/// Rows sorted by how far this month is above its 12-month average.
class _CmpList extends StatelessWidget {
  const _CmpList({required this.rows, this.onTap});

  final List<_Cmp> rows;
  final ValueChanged<_Cmp>? onTap;

  @override
  Widget build(BuildContext context) {
    final list = rows
        .where((r) => r.now.abs() >= 0.01 || r.prev.abs() >= 0.01 || r.avg.abs() >= 0.01)
        .toList()
      ..sort((a, b) => (b.now - b.avg).compareTo(a.now - a.avg));
    if (list.isEmpty) {
      return const Padding(
          padding: EdgeInsets.all(32),
          child: Center(child: Text('No spending to compare')));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
          child: Text('Biggest increase over the average first',
              style: Theme.of(context).textTheme.bodySmall),
        ),
        for (final r in list)
          _CmpTile(row: r, onTap: onTap == null ? null : () => onTap!(r)),
      ],
    );
  }
}

// ===========================================================================
// Loans overview
// ===========================================================================

class LoansTab extends StatelessWidget {
  const LoansTab({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final base = state.baseCurrency;
    final loans = state.accounts
        .where((a) => !a.archived && a.type == AccountType.loan)
        .toList()
      ..sort((a, b) => a.balance.compareTo(b.balance));
    if (loans.isEmpty) {
      return const Center(child: Text('No loans'));
    }
    var owed = 0.0, monthly = 0.0, interestLeft = 0.0;
    final now = DateTime.now();
    for (final a in loans) {
      if (a.balance < 0) owed += state.toBase(-a.balance, a.currency);
      final t = a.loan;
      if (t == null) continue;
      final rows = t.schedule().skip(t.nextIndex).toList();
      if (rows.isNotEmpty) monthly += state.toBase(rows.first.payment, a.currency);
      interestLeft += state.toBase(
          rows.fold<double>(0, (s, r) => s + r.interest), a.currency);
    }
    final small = Theme.of(context).textTheme.bodySmall;
    return ListView(
      padding: const EdgeInsets.only(bottom: 32),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _stat(context, 'Total Owed', fmtMoney(owed, base)),
              _stat(context, 'Monthly Installments', fmtMoney(monthly, base)),
              if (interestLeft > 0)
                _stat(context, 'Interest Still to Pay', fmtMoney(interestLeft, base)),
            ],
          ),
        ),
        _heading(context, 'Your Loans', sub: 'Tap a loan for its schedule'),
        for (final a in loans)
          () {
            final t = a.loan;
            final rows = t?.schedule();
            final paid = t == null ? 0 : t.nextIndex.clamp(0, rows!.length);
            final next = t == null || paid >= rows!.length ? null : rows[paid];
            final frac = t == null || t.months == 0 ? null : paid / t.months;
            final overdue = next != null &&
                next.date.isBefore(DateTime(now.year, now.month, now.day + 1));
            return InkWell(
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => AccountDetailScreen(accountId: a.id!)),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Expanded(
                          child: Text(a.fullName,
                              style: const TextStyle(fontWeight: FontWeight.w600))),
                      Text(fmtMoney(-a.balance, a.currency),
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                    ]),
                    if (frac != null) ...[
                      const SizedBox(height: 6),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: frac.clamp(0.0, 1.0),
                          minHeight: 8,
                          backgroundColor:
                              Theme.of(context).colorScheme.surfaceContainerHighest,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '$paid of ${t!.months} paid · ends ${shortDateFmt.format(rows!.last.date)}'
                        '${next == null ? '' : ' · ${overdue ? 'due' : 'next'} ${fmtAmount(next.payment)} on ${shortDateFmt.format(next.date)}'}'
                        '${a.excludeTotal ? ' · not in net worth' : ''}',
                        style: small?.copyWith(color: overdue ? kExpenseColor : null),
                      ),
                    ] else
                      Text(
                          'No repayment plan (balance only)${a.excludeTotal ? ' · not in net worth' : ''}',
                          style: small),
                  ],
                ),
              ),
            );
          }(),
      ],
    );
  }

  Widget _stat(BuildContext context, String label, String value) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: Theme.of(context).textTheme.bodySmall),
            Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
          ],
        ),
      );
}
