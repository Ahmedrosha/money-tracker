import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../data/db.dart';
import '../data/models.dart';
import '../state/app_state.dart';
import '../util/format.dart';
import 'pay_card.dart';
import 'reports_more.dart';
import 'transaction_edit.dart';
import 'widgets.dart';

/// Totals per category in the main currency.
class CatTotal {
  final Category? category;
  final int? id;
  final TxType kind;
  double total = 0;
  int count = 0;
  CatTotal(this.id, this.category, this.kind);
  String get name => category?.name ?? 'No category';
  String get group {
    if (category == null) return 'Uncategorized';
    return category!.group.isEmpty ? 'Other' : category!.group;
  }
}

Future<List<CatTotal>> loadCategoryTotals(
    AppState state, TxType type, DateTime from, DateTime to) async {
  final rows = await state.db.categoryTotals(type, from, to);
  final map = <int?, CatTotal>{};
  for (final r in rows) {
    final id = r['cat'] as int?;
    final t =
        map.putIfAbsent(id, () => CatTotal(id, state.categoryById(id), type));
    t.total += state.toBase((r['total'] as num).toDouble(),
        (r['cur'] as String?) ?? state.baseCurrency);
    t.count += r['n'] as int;
  }
  return map.values.toList()..sort((a, b) => b.total.compareTo(a.total));
}

class ReportsScreen extends StatelessWidget {
  const ReportsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 5,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Reports'),
          bottom: const TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              Tab(text: 'Dashboard'),
              Tab(text: 'By category'),
              Tab(text: 'Trend'),
              Tab(text: 'Net worth'),
              Tab(text: 'Cards'),
            ],
          ),
        ),
        body: const TabBarView(children: [
          _Dashboard(),
          _ByCategory(),
          TrendTab(),
          NetWorthTab(),
          CardsTab(),
        ]),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared pieces
// ---------------------------------------------------------------------------

/// A labelled horizontal bar: name, value and a bar scaled to [max].
class _BarRow extends StatelessWidget {
  const _BarRow({
    required this.label,
    required this.value,
    required this.max,
    required this.currency,
    this.caption,
    this.leading,
    this.onTap,
  });

  final String label;
  final double value;
  final double max;
  final String currency;
  final String? caption;
  final Widget? leading;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final frac = max <= 0 ? 0.0 : (value / max).clamp(0.0, 1.0);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            if (leading != null) ...[leading!, const SizedBox(width: 12)],
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
                      Text(fmtMoney(value, currency),
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
                          child: Container(height: 8, color: scheme.primary),
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

class _Tile extends StatelessWidget {
  const _Tile({required this.label, required this.value, this.note, this.color});

  final String label;
  final String value;
  final String? note;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value,
                style: TextStyle(
                    fontSize: 20, fontWeight: FontWeight.bold, color: color)),
          ),
          if (note != null)
            Text(note!,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}

Widget _sectionTitle(BuildContext context, String t, {String? sub}) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(t,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold)),
          if (sub != null)
            Text(sub, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );

String _pct(double now, double before) {
  if (before.abs() < 0.01) return '';
  final p = (now - before) / before.abs() * 100;
  return '${p >= 0 ? '▲' : '▼'} ${p.abs().toStringAsFixed(0)}% vs last month';
}

// ---------------------------------------------------------------------------
// Dashboard
// ---------------------------------------------------------------------------

class _Dashboard extends StatefulWidget {
  const _Dashboard();

  @override
  State<_Dashboard> createState() => _DashboardState();
}

class _DashData {
  final double spent, income, prevSpent, prevIncome, prevToDate;
  final List<CatTotal> top;
  final Map<String, double> prevByCat;
  final List<(String, double)> months; // last 6 months spending
  _DashData(this.spent, this.income, this.prevSpent, this.prevIncome,
      this.prevToDate, this.top, this.prevByCat, this.months);
}

class _DashboardState extends State<_Dashboard> {
  late DateTime _month;
  Future<_DashData>? _future;
  String _key = '';

  @override
  void initState() {
    super.initState();
    final n = DateTime.now();
    _month = DateTime(n.year, n.month);
  }

  Future<_DashData> _load(AppState state) async {
    final start = _month;
    final end = DateTime(_month.year, _month.month + 1);
    final prev = DateTime(_month.year, _month.month - 1);
    double sum(List<CatTotal> l) => l.fold(0.0, (s, c) => s + c.total);

    final exp = await loadCategoryTotals(state, TxType.expense, start, end);
    final inc = await loadCategoryTotals(state, TxType.income, start, end);
    final pexp = await loadCategoryTotals(state, TxType.expense, prev, start);
    final pinc = await loadCategoryTotals(state, TxType.income, prev, start);

    // Last month up to the same day, for a fair "so far" comparison.
    final now = DateTime.now();
    final isCurrent = now.year == _month.year && now.month == _month.month;
    var prevToDate = sum(pexp);
    if (isCurrent) {
      final cut = DateTime(prev.year, prev.month, now.day + 1);
      final p = await loadCategoryTotals(
          state, TxType.expense, prev, cut.isBefore(start) ? cut : start);
      prevToDate = sum(p);
    }

    // Spending for the 6 months ending with the selected one.
    final from6 = DateTime(_month.year, _month.month - 5);
    final rows = await state.db.monthlyTotals(from6, end);
    final byMonth = <String, double>{};
    for (final r in rows) {
      if (r['type'] != 'expense') continue;
      final ym = r['ym'] as String;
      byMonth[ym] = (byMonth[ym] ?? 0) +
          state.toBase((r['total'] as num).toDouble(),
              (r['cur'] as String?) ?? state.baseCurrency);
    }
    final months = <(String, double)>[
      for (var i = 0; i < 6; i++)
        () {
          final d = DateTime(from6.year, from6.month + i);
          final key = '${d.year}-${d.month.toString().padLeft(2, '0')}';
          return (DateFormat('MMM').format(d), byMonth[key] ?? 0.0);
        }(),
    ];

    return _DashData(sum(exp), sum(inc), sum(pexp), sum(pinc), prevToDate,
        exp.take(5).toList(), {for (final c in pexp) '${c.id}': c.total}, months);
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final key = '${state.version}-$_month';
    if (key != _key) {
      _key = key;
      _future = _load(state);
    }
    final cur = state.baseCurrency;
    final now = DateTime.now();
    final isCurrent = now.year == _month.year && now.month == _month.month;

    return FutureBuilder<_DashData>(
      future: _future,
      builder: (context, snap) {
        final d = snap.data;
        return ListView(
          padding: const EdgeInsets.only(bottom: 32),
          children: [
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left),
                  onPressed: () => setState(
                      () => _month = DateTime(_month.year, _month.month - 1)),
                ),
                Expanded(
                  child: Center(
                    child: Text(monthFmt.format(_month),
                        style: Theme.of(context).textTheme.titleMedium),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right),
                  onPressed: () => setState(
                      () => _month = DateTime(_month.year, _month.month + 1)),
                ),
              ],
            ),
            if (d == null)
              const Padding(
                padding: EdgeInsets.all(40),
                child: Center(child: CircularProgressIndicator()),
              )
            else ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  childAspectRatio: 1.9,
                  children: [
                    _Tile(
                      label: 'Spent',
                      value: fmtMoney(d.spent, cur),
                      color: kExpenseColor,
                      note: isCurrent
                          ? _pct(d.spent, d.prevToDate).replaceFirst(
                              'vs last month', 'vs same day last month')
                          : _pct(d.spent, d.prevSpent),
                    ),
                    _Tile(
                      label: 'Income',
                      value: fmtMoney(d.income, cur),
                      color: kIncomeColor,
                      note: _pct(d.income, d.prevIncome),
                    ),
                    _Tile(
                      label: 'Net',
                      value: fmtMoney(d.income - d.spent, cur),
                      color: amountColor(context, d.income - d.spent),
                    ),
                    _Tile(
                      label: 'Saved of income',
                      value: d.income > 0
                          ? '${((d.income - d.spent) / d.income * 100).toStringAsFixed(0)}%'
                          : '—',
                      note: 'Net worth ${fmtAmount(state.netWorth)}',
                    ),
                  ],
                ),
              ),
              _sectionTitle(context, 'Spending, last 6 months', sub: cur),
              _MonthBars(months: d.months, currency: cur),
              _sectionTitle(context, 'Top categories',
                  sub: d.top.isEmpty ? 'No spending this month' : null),
              for (final c in d.top)
                _BarRow(
                  label: c.name,
                  value: c.total,
                  max: d.top.first.total,
                  currency: cur,
                  leading: SizedBox(
                      width: 32,
                      height: 32,
                      child: FittedBox(child: CategoryAvatar(category: c.category))),
                  caption: () {
                    final p = d.prevByCat['${c.id}'] ?? 0;
                    final t = _pct(c.total, p);
                    return '${c.count} transactions${t.isEmpty ? '' : ' · $t'}';
                  }(),
                  onTap: () => _openCategory(context, c, _month,
                      DateTime(_month.year, _month.month + 1)),
                ),
              _sectionTitle(context, 'Coming up (next 14 days)'),
              ..._upcoming(context, state),
            ],
          ],
        );
      },
    );
  }

  List<Widget> _upcoming(BuildContext context, AppState state) {
    final now = DateTime.now();
    final until = now.add(const Duration(days: 14));
    final items = <(DateTime, Widget)>[];
    for (final c in state.cardsDue) {
      final due = c.last!.dueDate;
      if (due.isAfter(until)) continue;
      items.add((
        due,
        ListTile(
          leading: const Icon(Icons.credit_card),
          title: Text(c.card.fullName),
          subtitle: Text(
              '${c.last!.overdue ? 'Overdue since' : 'Due'} ${shortDateFmt.format(due)}'),
          trailing: Text(fmtMoney(c.last!.remaining, c.card.currency),
              style: const TextStyle(fontWeight: FontWeight.w600)),
          onTap: () => showPayCard(context, c),
        )
      ));
    }
    for (final o in state.pendingOccurrences(DateTime(1970), until)) {
      items.add((o.date, OccurrenceTile(occurrence: o, showDate: true)));
    }
    items.sort((a, b) => a.$1.compareTo(b.$1));
    if (items.isEmpty) {
      return const [
        Padding(
          padding: EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Text('Nothing due in the next two weeks'),
        )
      ];
    }
    return items.map((e) => e.$2).toList();
  }
}

/// Six vertical bars, one per month, each labelled with its value.
class _MonthBars extends StatelessWidget {
  const _MonthBars({required this.months, required this.currency});

  final List<(String, double)> months;
  final String currency;

  static String _short(double v) {
    if (v >= 1e6) return '${(v / 1e6).toStringAsFixed(1)}M';
    if (v >= 1e3) return '${(v / 1e3).toStringAsFixed(v >= 1e4 ? 0 : 1)}k';
    return v.toStringAsFixed(0);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final maxV = months.fold<double>(0, (m, e) => e.$2 > m ? e.$2 : m);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: SizedBox(
        height: 150,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (var i = 0; i < months.length; i++)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text(_short(months[i].$2),
                          style: Theme.of(context).textTheme.labelSmall),
                      const SizedBox(height: 4),
                      Container(
                        height: maxV <= 0
                            ? 2
                            : (100 * months[i].$2 / maxV).clamp(2, 100).toDouble(),
                        decoration: BoxDecoration(
                          // Selected (last) month solid, earlier ones lighter.
                          color: i == months.length - 1
                              ? scheme.primary
                              : scheme.primary.withValues(alpha: 0.45),
                          borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(4)),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(months[i].$1,
                          style: Theme.of(context).textTheme.labelSmall),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// By category
// ---------------------------------------------------------------------------

enum _Period { thisMonth, lastMonth, thisYear, last12, custom }

class _ByCategory extends StatefulWidget {
  const _ByCategory();

  @override
  State<_ByCategory> createState() => _ByCategoryState();
}

class _ByCategoryState extends State<_ByCategory> {
  _Period _period = _Period.thisMonth;
  DateTimeRange? _custom;
  TxType _type = TxType.expense;
  Future<List<CatTotal>>? _future;
  String _key = '';

  (DateTime, DateTime) get _range {
    final n = DateTime.now();
    switch (_period) {
      case _Period.thisMonth:
        return (DateTime(n.year, n.month), DateTime(n.year, n.month + 1));
      case _Period.lastMonth:
        return (DateTime(n.year, n.month - 1), DateTime(n.year, n.month));
      case _Period.thisYear:
        return (DateTime(n.year), DateTime(n.year + 1));
      case _Period.last12:
        return (DateTime(n.year, n.month - 11), DateTime(n.year, n.month + 1));
      case _Period.custom:
        final r = _custom!;
        return (r.start, DateTime(r.end.year, r.end.month, r.end.day + 1));
    }
  }

  String get _label {
    switch (_period) {
      case _Period.thisMonth:
        return 'This month';
      case _Period.lastMonth:
        return 'Last month';
      case _Period.thisYear:
        return 'This year';
      case _Period.last12:
        return 'Last 12 months';
      case _Period.custom:
        return '${shortDateFmt.format(_custom!.start)} – ${shortDateFmt.format(_custom!.end)}';
    }
  }

  Future<void> _pickPeriod() async {
    final p = await showModalBottomSheet<_Period>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final (v, l) in const [
              (_Period.thisMonth, 'This month'),
              (_Period.lastMonth, 'Last month'),
              (_Period.thisYear, 'This year'),
              (_Period.last12, 'Last 12 months'),
              (_Period.custom, 'Choose dates…'),
            ])
              ListTile(
                title: Text(l),
                trailing: v == _period ? const Icon(Icons.check) : null,
                onTap: () => Navigator.pop(ctx, v),
              ),
          ],
        ),
      ),
    );
    if (p == null || !mounted) return;
    if (p == _Period.custom) {
      final r = await showDateRangePicker(
          context: context,
          firstDate: DateTime(2000),
          lastDate: DateTime(2100),
          initialDateRange: _custom);
      if (r == null) return;
      setState(() {
        _custom = r;
        _period = p;
      });
    } else {
      setState(() => _period = p);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final (from, to) = _range;
    final key = '${state.version}-$_type-$from-$to';
    if (key != _key) {
      _key = key;
      _future = loadCategoryTotals(state, _type, from, to);
    }
    final cur = state.baseCurrency;

    return FutureBuilder<List<CatTotal>>(
      future: _future,
      builder: (context, snap) {
        final cats = snap.data ?? const <CatTotal>[];
        // Roll categories up into their groups.
        final groups = <String, List<CatTotal>>{};
        for (final c in cats) {
          groups.putIfAbsent(c.group, () => []).add(c);
        }
        double sum(List<CatTotal> l) => l.fold(0.0, (s, c) => s + c.total);
        final ranked = groups.entries.toList()
          ..sort((a, b) => sum(b.value).compareTo(sum(a.value)));
        final total = sum(cats);
        final maxG = ranked.isEmpty ? 0.0 : sum(ranked.first.value);

        return ListView(
          padding: const EdgeInsets.only(bottom: 32),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  SegmentedButton<TxType>(
                    segments: const [
                      ButtonSegment(value: TxType.expense, label: Text('Spending')),
                      ButtonSegment(value: TxType.income, label: Text('Income')),
                    ],
                    selected: {_type},
                    onSelectionChanged: (s) => setState(() => _type = s.first),
                  ),
                  ActionChip(
                    avatar: const Icon(Icons.date_range, size: 18),
                    label: Text(_label),
                    onPressed: _pickPeriod,
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_type == TxType.expense ? 'Total spent' : 'Total income',
                      style: Theme.of(context).textTheme.bodySmall),
                  Text(fmtMoney(total, cur),
                      style: Theme.of(context)
                          .textTheme
                          .headlineSmall
                          ?.copyWith(fontWeight: FontWeight.bold)),
                ],
              ),
            ),
            if (snap.connectionState != ConnectionState.done)
              const Padding(
                padding: EdgeInsets.all(40),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (cats.isEmpty)
              const Padding(
                padding: EdgeInsets.all(40),
                child: Center(child: Text('Nothing in this period')),
              ),
            for (final g in ranked)
              _BarRow(
                label: g.key,
                value: sum(g.value),
                max: maxG,
                currency: cur,
                caption:
                    '${total > 0 ? (sum(g.value) / total * 100).toStringAsFixed(1) : '0'}% · '
                    '${g.value.fold<int>(0, (n, c) => n + c.count)} transactions · '
                    '${g.value.length} categor${g.value.length == 1 ? 'y' : 'ies'}',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => _GroupScreen(
                        title: g.key, cats: g.value, from: from, to: to,
                        periodLabel: _label),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _GroupScreen extends StatelessWidget {
  const _GroupScreen({
    required this.title,
    required this.cats,
    required this.from,
    required this.to,
    required this.periodLabel,
  });

  final String title;
  final List<CatTotal> cats;
  final DateTime from, to;
  final String periodLabel;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final cur = state.baseCurrency;
    final total = cats.fold<double>(0, (s, c) => s + c.total);
    final max = cats.isEmpty ? 0.0 : cats.first.total;
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text('$periodLabel · ${fmtMoney(total, cur)}',
                style: Theme.of(context).textTheme.titleMedium),
          ),
          for (final c in cats)
            _BarRow(
              label: c.name,
              value: c.total,
              max: max,
              currency: cur,
              leading: SizedBox(
                  width: 32,
                  height: 32,
                  child: FittedBox(child: CategoryAvatar(category: c.category))),
              caption:
                  '${total > 0 ? (c.total / total * 100).toStringAsFixed(1) : '0'}% · ${c.count} transactions',
              onTap: () => _openCategory(context, c, from, to),
            ),
        ],
      ),
    );
  }
}

void _openCategory(BuildContext context, CatTotal c, DateTime from, DateTime to) {
  Navigator.push(
    context,
    MaterialPageRoute(
        builder: (_) => _CategoryTxnsScreen(cat: c, from: from, to: to)),
  );
}

class _CategoryTxnsScreen extends StatelessWidget {
  const _CategoryTxnsScreen(
      {required this.cat, required this.from, required this.to});

  final CatTotal cat;
  final DateTime from, to;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(cat.name)),
      body: FutureBuilder<SearchResult>(
        key: ValueKey(state.version),
        future: state.db.search(
          categoryId: cat.id,
          from: from,
          to: to,
          type: cat.kind,
          limit: 2000,
        ),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final list = snap.data!.txns;
          if (cat.id == null) {
            // "No category": search can't filter on null, so filter here.
            list.retainWhere((t) => t.categoryId == null);
          }
          return ListView.builder(
            itemCount: list.length,
            itemBuilder: (context, i) {
              final t = list[i];
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TxnTile(
                    txn: t,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => TransactionEditScreen(txn: t)),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(72, 0, 16, 6),
                    child: Text(dayFmt.format(t.date),
                        style: Theme.of(context).textTheme.bodySmall),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}
