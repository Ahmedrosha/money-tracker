import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../data/models.dart';
import '../state/app_state.dart';
import '../util/format.dart';
import 'widgets.dart';

String _short(double v) {
  if (amountsHidden) return '•';
  final a = v.abs();
  final sign = v < 0 ? '-' : '';
  if (a >= 1e6) return '$sign${(a / 1e6).toStringAsFixed(a >= 1e7 ? 0 : 1)}M';
  if (a >= 1e3) return '$sign${(a / 1e3).toStringAsFixed(a >= 1e4 ? 0 : 1)}k';
  return '$sign${a.toStringAsFixed(0)}';
}

String _ym(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}';

Widget _title(BuildContext context, String t, {String? sub}) => Padding(
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

Widget _legendDot(BuildContext context, Color c, String label) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(3))),
        const SizedBox(width: 6),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );

// ===========================================================================
// Trend: income vs spending per month / year, and one category over time
// ===========================================================================

class TrendTab extends StatefulWidget {
  const TrendTab({super.key});

  @override
  State<TrendTab> createState() => _TrendTabState();
}

class _Bucket {
  final DateTime start;
  final String label;
  final String longLabel;
  double income = 0;
  double spent = 0;
  _Bucket(this.start, this.label, this.longLabel);
  double get net => income - spent;
}

class _TrendTabState extends State<TrendTab> {
  bool _years = false;
  bool _cumulative = false;
  int? _selected;
  int? _categoryId;
  Future<List<_Bucket>>? _future;
  Future<List<_Bucket>>? _catFuture;
  String _key = '';

  Future<(DateTime, List<DateTime>)> _range(AppState state) async {
    final now = DateTime.now();
    if (!_years) {
      final starts = [for (var i = 11; i >= 0; i--) DateTime(now.year, now.month - i)];
      return (starts.first, starts);
    }
    final first = await state.db.firstTransactionDate() ?? now;
    final starts = [for (var y = first.year; y <= now.year; y++) DateTime(y)];
    return (starts.first, starts);
  }

  Future<List<_Bucket>> _load(AppState state) async {
    final (from, starts) = await _range(state);
    final now = DateTime.now();
    final end = _years ? DateTime(now.year + 1) : DateTime(now.year, now.month + 1);
    final rows = await state.db.monthlyTotals(from, end);
    final buckets = {
      for (final s in starts)
        (_years ? '${s.year}' : _ym(s)): _Bucket(
            s,
            _years ? "'${s.year % 100}" : DateFormat('MMM').format(s),
            _years ? '${s.year}' : monthFmt.format(s)),
    };
    for (final r in rows) {
      final ym = r['ym'] as String;
      final b = buckets[_years ? ym.substring(0, 4) : ym];
      if (b == null) continue;
      final v = state.toBase((r['total'] as num).toDouble(),
          (r['cur'] as String?) ?? state.baseCurrency);
      if (r['type'] == 'income') {
        b.income += v;
      } else {
        b.spent += v;
      }
    }
    return buckets.values.toList();
  }

  Future<List<_Bucket>> _loadCategory(AppState state, int catId) async {
    final (from, starts) = await _range(state);
    final now = DateTime.now();
    final end = _years ? DateTime(now.year + 1) : DateTime(now.year, now.month + 1);
    final rows = await state.db.categoryMonthly(catId, from, end);
    final buckets = {
      for (final s in starts)
        (_years ? '${s.year}' : _ym(s)): _Bucket(
            s,
            _years ? "'${s.year % 100}" : DateFormat('MMM').format(s),
            _years ? '${s.year}' : monthFmt.format(s)),
    };
    for (final r in rows) {
      final ym = r['ym'] as String;
      final b = buckets[_years ? ym.substring(0, 4) : ym];
      if (b == null) continue;
      b.spent += state.toBase((r['total'] as num).toDouble(),
          (r['cur'] as String?) ?? state.baseCurrency);
    }
    return buckets.values.toList();
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final key = '${state.version}-$_years-$_categoryId';
    if (key != _key) {
      _key = key;
      _selected = null;
      _future = _load(state);
      _catFuture = _categoryId == null ? null : _loadCategory(state, _categoryId!);
    }
    final cur = state.baseCurrency;
    final cat = state.categoryById(_categoryId);

    return ListView(
      padding: const EdgeInsets.only(bottom: 32),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: false, label: Text('Last 12 Months')),
              ButtonSegment(value: true, label: Text('By Year')),
            ],
            selected: {_years},
            onSelectionChanged: (s) => setState(() => _years = s.first),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: false, label: Text('Trend')),
              ButtonSegment(value: true, label: Text('Cumulative')),
            ],
            selected: {_cumulative},
            onSelectionChanged: (s) => setState(() => _cumulative = s.first),
          ),
        ),
        _title(
            context,
            _cumulative ? 'Saved Over Time' : 'Income vs Spending',
            sub: _cumulative
                ? '$cur · running total of income minus spending'
                : '$cur · tap a bar for details'),
        FutureBuilder<List<_Bucket>>(
          future: _future,
          builder: (context, snap) {
            if (!snap.hasData) {
              return const Padding(
                  padding: EdgeInsets.all(40),
                  child: Center(child: CircularProgressIndicator()));
            }
            final b = snap.data!;
            final sel = _selected == null || _selected! >= b.length
                ? b.length - 1
                : _selected!;
            final s = b[sel];
            final avgSpent = b.fold<double>(0, (t, x) => t + x.spent) / b.length;
            if (_cumulative) return _cumulativeView(context, b, sel, cur);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                  child: Wrap(spacing: 16, children: [
                    _legendDot(context, kIncomeColor, 'Income'),
                    _legendDot(context, kExpenseColor, 'Spending'),
                  ]),
                ),
                _PairBars(
                  buckets: b,
                  selected: sel,
                  onSelect: (i) => setState(() => _selected = i),
                ),
                Card(
                  margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(s.longLabel,
                            style: const TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 4),
                        Text('Income ${fmtMoney(s.income, cur)}'),
                        Text('Spending ${fmtMoney(s.spent, cur)}'),
                        Text('Net ${fmtMoney(s.income - s.spent, cur)}',
                            style: TextStyle(
                                color: amountColor(context, s.income - s.spent),
                                fontWeight: FontWeight.w600)),
                        const SizedBox(height: 4),
                        Text(
                            'Average spending per ${_years ? 'year' : 'month'}: ${fmtMoney(avgSpent, cur)}',
                            style: Theme.of(context).textTheme.bodySmall),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
        _title(context, 'One Category Over Time'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: OutlinedButton.icon(
            icon: const Icon(Icons.category_outlined),
            label: Text(cat == null
                ? 'Choose a Category'
                : (cat.group.isEmpty ? cat.name : '${cat.group} › ${cat.name}')),
            onPressed: () async {
              final id = await pickCategory(context,
                  kind: cat?.kind ?? TxType.expense, current: _categoryId);
              if (id != null && id != -1) setState(() => _categoryId = id);
            },
          ),
        ),
        if (_catFuture != null)
          FutureBuilder<List<_Bucket>>(
            future: _catFuture,
            builder: (context, snap) {
              if (!snap.hasData) {
                return const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: CircularProgressIndicator()));
              }
              final b = snap.data!;
              final total = b.fold<double>(0, (t, x) => t + x.spent);
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _SingleBars(
                      values: [for (final x in b) x.spent],
                      labels: [for (final x in b) x.label]),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                    child: Text(
                      'Total ${fmtMoney(total, cur)} · average ${fmtMoney(total / b.length, cur)} per ${_years ? 'year' : 'month'}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ],
              );
            },
          ),
      ],
    );
  }

  Widget _cumulativeView(
      BuildContext context, List<_Bucket> b, int sel, String cur) {
    var run = 0.0;
    final pts = <(DateTime, double)>[];
    for (final x in b) {
      run += x.net;
      pts.add((x.start, run));
    }
    final income = b.fold<double>(0, (t, x) => t + x.income);
    final spent = b.fold<double>(0, (t, x) => t + x.spent);
    final saved = income - spent;
    final labels = _years
        ? [for (final x in b) x.label]
        : monthAxisLabels([for (final x in b) x.start]);
    final small = Theme.of(context).textTheme.bodySmall;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('By the end of ${b[sel].longLabel}', style: small),
              Text(fmtMoney(pts[sel].$2, cur),
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: amountColor(context, pts[sel].$2))),
              Text(
                  '${b[sel].longLabel} alone: ${b[sel].net >= 0 ? '+' : ''}${fmtMoney(b[sel].net, cur)}',
                  style: small),
            ],
          ),
        ),
        LineChart(
          points: pts,
          selected: sel,
          xLabels: labels,
          height: 200,
          onSelect: (i) => setState(() => _selected = i),
        ),
        Card(
          margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_years ? 'All Years' : 'Last 12 Months',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text('Income ${fmtMoney(income, cur)}'),
                Text('Spending ${fmtMoney(spent, cur)}'),
                Text(
                    'Saved ${fmtMoney(saved, cur)}'
                    '${income > 0 ? ' · ${(saved / income * 100).toStringAsFixed(0)}% of income' : ''}',
                    style: TextStyle(
                        color: amountColor(context, saved),
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text(
                    '${b.where((x) => x.net >= 0).length} of ${b.length} ${_years ? 'years' : 'months'} saved money',
                    style: small),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Two bars (income, spending) per period; tap to select.
class _PairBars extends StatelessWidget {
  const _PairBars(
      {required this.buckets, required this.selected, required this.onSelect});

  final List<_Bucket> buckets;
  final int selected;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    var maxV = 0.0;
    for (final b in buckets) {
      if (b.income > maxV) maxV = b.income;
      if (b.spent > maxV) maxV = b.spent;
    }
    double h(double v) => maxV <= 0 ? 0 : (130 * v / maxV).clamp(0, 130).toDouble();
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: SizedBox(
        height: 170,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (var i = 0; i < buckets.length; i++)
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onSelect(i),
                  child: Container(
                    decoration: BoxDecoration(
                      color: i == selected
                          ? scheme.primary.withValues(alpha: 0.08)
                          : null,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 1),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            _bar(h(buckets[i].income), kIncomeColor),
                            const SizedBox(width: 2),
                            _bar(h(buckets[i].spent), kExpenseColor),
                          ],
                        ),
                        const SizedBox(height: 6),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(buckets[i].label,
                              style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: i == selected
                                      ? FontWeight.bold
                                      : FontWeight.normal)),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _bar(double h, Color c) => Flexible(
        child: Container(
          width: 8,
          height: h < 2 ? 2 : h,
          decoration: BoxDecoration(
            color: c,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
          ),
        ),
      );
}

/// One series of bars with short value labels on top.
class _SingleBars extends StatelessWidget {
  const _SingleBars({required this.values, required this.labels});

  final List<double> values;
  final List<String> labels;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final maxV = values.fold<double>(0, (m, v) => v > m ? v : m);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: SizedBox(
        height: 160,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (var i = 0; i < values.length; i++)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(values[i] == 0 ? '' : _short(values[i]),
                            style: const TextStyle(fontSize: 10)),
                      ),
                      const SizedBox(height: 2),
                      Container(
                        height: maxV <= 0
                            ? 2
                            : (110 * values[i] / maxV).clamp(2, 110).toDouble(),
                        decoration: BoxDecoration(
                          color: scheme.primary,
                          borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(4)),
                        ),
                      ),
                      const SizedBox(height: 6),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(labels[i], style: const TextStyle(fontSize: 11)),
                      ),
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

// ===========================================================================
// Net worth over time
// ===========================================================================

class NetWorthTab extends StatefulWidget {
  const NetWorthTab({super.key});

  @override
  State<NetWorthTab> createState() => _NetWorthTabState();
}

class _NetWorthTabState extends State<NetWorthTab> {
  Future<List<(DateTime, double)>>? _future;
  String _key = '';
  int? _sel;
  int _years = 0; // 0 = all

  /// End-of-month net worth for every month since the first transaction,
  /// using today's exchange rates. Excluded accounts are left out; archived
  /// accounts are kept, since they held money at the time.
  Future<List<(DateTime, double)>> _load(AppState state) async {
    final now = DateTime.now();
    final first = await state.db.firstTransactionDate();
    if (first == null) return const [];
    final rows = await state.db.monthlyAccountChanges(now);
    final counted = {
      for (final a in state.accounts)
        if (!a.excludeTotal) a.id!: a,
    };
    // month -> total change in base currency
    final change = <String, double>{};
    for (final r in rows) {
      final a = counted[r['acc'] as int?];
      if (a == null) continue;
      final ym = r['ym'] as String;
      change[ym] = (change[ym] ?? 0) +
          state.toBase((r['delta'] as num).toDouble(), a.currency);
    }
    var running = 0.0;
    for (final a in counted.values) {
      running += state.toBase(a.openingBalance, a.currency);
    }
    final out = <(DateTime, double)>[];
    var m = DateTime(first.year, first.month);
    final last = DateTime(now.year, now.month);
    while (!m.isAfter(last)) {
      running += change[_ym(m)] ?? 0;
      out.add((m, running));
      m = DateTime(m.year, m.month + 1);
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final key = '${state.version}';
    if (key != _key) {
      _key = key;
      _sel = null;
      _future = _load(state);
    }
    final cur = state.baseCurrency;
    return FutureBuilder<List<(DateTime, double)>>(
      future: _future,
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        var pts = snap.data!;
        if (pts.isEmpty) return const Center(child: Text('No data yet'));
        if (_years > 0 && pts.length > _years * 12) {
          pts = pts.sublist(pts.length - _years * 12);
        }
        final sel = _sel == null || _sel! >= pts.length ? pts.length - 1 : _sel!;
        final nowV = pts.last.$2;
        final yearAgo = pts.length > 12 ? pts[pts.length - 13].$2 : pts.first.$2;
        final peak = pts.reduce((a, b) => b.$2 > a.$2 ? b : a);
        return ListView(
          padding: const EdgeInsets.only(bottom: 32),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: SegmentedButton<int>(
                segments: const [
                  ButtonSegment(value: 1, label: Text('1Y')),
                  ButtonSegment(value: 3, label: Text('3Y')),
                  ButtonSegment(value: 5, label: Text('5Y')),
                  ButtonSegment(value: 0, label: Text('All')),
                ],
                selected: {_years},
                onSelectionChanged: (s) => setState(() {
                  _years = s.first;
                  _sel = null;
                }),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(monthFmt.format(pts[sel].$1),
                      style: Theme.of(context).textTheme.bodySmall),
                  Text(fmtMoney(pts[sel].$2, cur),
                      style: Theme.of(context)
                          .textTheme
                          .headlineSmall
                          ?.copyWith(fontWeight: FontWeight.bold)),
                  Text('Drag across the chart to see any month',
                      style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
            LineChart(
              points: pts,
              selected: sel,
              xLabels: monthAxisLabels([for (final p in pts) p.$1]),
              onSelect: (i) => setState(() => _sel = i),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _chip(context, 'Now', fmtMoney(nowV, cur)),
                  _chip(context, 'Change Over 12 Months',
                      '${nowV - yearAgo >= 0 ? '+' : ''}${fmtMoney(nowV - yearAgo, cur)}'),
                  _chip(context, 'Highest',
                      '${fmtMoney(peak.$2, cur)} · ${DateFormat('MMM yyyy').format(peak.$1)}'),
                ],
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Text(
                'Month-end totals of all accounts counted in net worth (archived '
                'ones included for the months they held money). Foreign-currency '
                'balances use today\'s exchange rates.',
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _chip(BuildContext context, String label, String value) => Container(
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

/// Axis labels for monthly points: month names for short spans, years
/// (at January) for long ones. Thinned to about six.
List<String?> monthAxisLabels(List<DateTime> ds) {
  final out = List<String?>.filled(ds.length, null);
  if (ds.length <= 24) {
    final step = (ds.length / 6).ceil().clamp(1, 100);
    final fmt = DateFormat(ds.length <= 12 ? 'MMM' : "MMM ''yy");
    for (var i = 0; i < ds.length; i += step) {
      out[i] = fmt.format(ds[i]);
    }
    return out;
  }
  final years = [
    for (var i = 0; i < ds.length; i++)
      if (ds[i].month == 1) i
  ];
  final step = (years.length / 6).ceil().clamp(1, 100);
  for (var k = 0; k < years.length; k += step) {
    out[years[k]] = '${ds[years[k]].year}';
  }
  return out;
}

class LineChart extends StatelessWidget {
  const LineChart({
    super.key,
    required this.points,
    required this.selected,
    required this.onSelect,
    required this.xLabels,
    this.color,
    this.height = 220,
  });

  final List<(DateTime, double)> points;
  final int selected;
  final ValueChanged<int> onSelect;
  final List<String?> xLabels;
  final Color? color;
  final double height;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 12, 16, 0),
      child: LayoutBuilder(builder: (context, c) {
        const left = 44.0;
        final w = c.maxWidth - left;
        void pick(double x) {
          if (points.length < 2) return;
          final i = ((x - left) / w * (points.length - 1)).round();
          onSelect(i.clamp(0, points.length - 1));
        }

        return GestureDetector(
          onTapDown: (d) => pick(d.localPosition.dx),
          onHorizontalDragUpdate: (d) => pick(d.localPosition.dx),
          child: CustomPaint(
            size: Size(c.maxWidth, height),
            painter: _LinePainter(
              points: points,
              selected: selected,
              xLabels: xLabels,
              line: color ?? scheme.primary,
              grid: scheme.outlineVariant,
              text: scheme.onSurfaceVariant,
              left: left,
            ),
          ),
        );
      }),
    );
  }
}

class _LinePainter extends CustomPainter {
  _LinePainter({
    required this.points,
    required this.selected,
    required this.xLabels,
    required this.line,
    required this.grid,
    required this.text,
    required this.left,
  });

  final List<(DateTime, double)> points;
  final int selected;
  final List<String?> xLabels;
  final Color line, grid, text;
  final double left;

  @override
  void paint(Canvas canvas, Size size) {
    const bottom = 20.0;
    final h = size.height - bottom;
    final w = size.width - left;
    var minV = points.map((p) => p.$2).reduce((a, b) => a < b ? a : b);
    var maxV = points.map((p) => p.$2).reduce((a, b) => a > b ? a : b);
    if (minV > 0) minV = 0; // anchor at zero when all positive
    if (maxV == minV) maxV = minV + 1;
    double y(double v) => h - (v - minV) / (maxV - minV) * (h - 8);
    double x(int i) =>
        left + (points.length == 1 ? w / 2 : i / (points.length - 1) * w);

    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;
    void label(String s, Offset o, {TextAlign align = TextAlign.left}) {
      final tp = TextPainter(
        text: TextSpan(text: s, style: TextStyle(color: text, fontSize: 10)),
        textDirection: TextDirection.ltr,
      )..layout();
      var dx = align == TextAlign.right
          ? o.dx - tp.width
          : align == TextAlign.center
              ? o.dx - tp.width / 2
              : o.dx;
      if (align == TextAlign.center) {
        dx = dx.clamp(left - 4, size.width - tp.width).toDouble();
      }
      tp.paint(canvas, Offset(dx, o.dy - tp.height / 2));
    }

    // Three recessive gridlines with short labels.
    for (var k = 0; k <= 2; k++) {
      final v = minV + (maxV - minV) * k / 2;
      final yy = y(v);
      canvas.drawLine(Offset(left, yy), Offset(size.width, yy), gridPaint);
      label(_short(v), Offset(left - 6, yy), align: TextAlign.right);
    }
    // Zero line when the range crosses it.
    if (minV < 0 && maxV > 0) {
      canvas.drawLine(Offset(left, y(0)), Offset(size.width, y(0)),
          gridPaint..strokeWidth = 1.5);
    }

    // X axis labels.
    for (var i = 0; i < points.length && i < xLabels.length; i++) {
      final l = xLabels[i];
      if (l != null) {
        label(l, Offset(x(i), size.height - 8), align: TextAlign.center);
      }
    }

    // The line.
    final path = Path()..moveTo(x(0), y(points[0].$2));
    for (var i = 1; i < points.length; i++) {
      path.lineTo(x(i), y(points[i].$2));
    }
    canvas.drawPath(
        path,
        Paint()
          ..color = line
          ..strokeWidth = 2
          ..style = PaintingStyle.stroke
          ..strokeJoin = StrokeJoin.round);

    // Crosshair on the selected month.
    final sx = x(selected);
    final sy = y(points[selected].$2);
    canvas.drawLine(Offset(sx, 0), Offset(sx, h),
        Paint()
          ..color = text.withValues(alpha: 0.5)
          ..strokeWidth = 1);
    canvas.drawCircle(Offset(sx, sy), 6, Paint()..color = line.withValues(alpha: 0.25));
    canvas.drawCircle(Offset(sx, sy), 4, Paint()..color = line);
  }

  @override
  bool shouldRepaint(covariant _LinePainter old) =>
      old.selected != selected || old.points != points || old.line != line;
}

// ===========================================================================
// Credit cards: limit use and statements
// ===========================================================================

class CardsTab extends StatelessWidget {
  const CardsTab({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final cards = state.cards.values.where((c) => !c.card.archived).toList()
      ..sort((a, b) => b.used.compareTo(a.used));
    if (cards.isEmpty) {
      return const Center(child: Text('No credit cards'));
    }
    return ListView(
      padding: const EdgeInsets.only(bottom: 32),
      children: [for (final c in cards) _CardReport(summary: c)],
    );
  }
}

class _CardReport extends StatelessWidget {
  const _CardReport({required this.summary});

  final CardSummary summary;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final a = summary.card;
    final cur = a.currency;
    final scheme = Theme.of(context).colorScheme;
    final limit = a.creditLimit;
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(a.fullName,
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            if (limit != null && limit > 0) ...[
              Row(
                children: [
                  Expanded(
                      child: Text(
                          'Using ${(summary.used / limit * 100).toStringAsFixed(0)}% of ${fmtMoney(limit, cur)}')),
                  Text('Available ${fmtAmount(summary.available!)}',
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                ],
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: (summary.used / limit).clamp(0.0, 1.0),
                  minHeight: 8,
                  backgroundColor: scheme.surfaceContainerHighest,
                  color: summary.used > limit * 0.8 ? kExpenseColor : scheme.primary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                  'Owed ${fmtAmount(summary.owedNow)}'
                  '${summary.futureInstallments > 0 ? ' · future installments ${fmtAmount(summary.futureInstallments)}' : ''}',
                  style: Theme.of(context).textTheme.bodySmall),
            ] else
              Text('Owed ${fmtMoney(summary.owedNow, cur)} · no limit set',
                  style: Theme.of(context).textTheme.bodySmall),
            if (a.hasCycle)
              FutureBuilder<List<CardStatement>>(
                key: ValueKey(state.version),
                future: state.statementHistory(a),
                builder: (context, snap) {
                  if (!snap.hasData) {
                    return const Padding(
                        padding: EdgeInsets.all(16),
                        child: Center(child: CircularProgressIndicator()));
                  }
                  final list = snap.data!.reversed.toList(); // oldest first
                  final amounts = [for (final s in list) s.amount];
                  final nonZero = amounts.where((v) => v > 0).toList();
                  final avg = nonZero.isEmpty
                      ? 0.0
                      : nonZero.reduce((a, b) => a + b) / nonZero.length;
                  final unpaid = list.where((s) => !s.settled && s.amount > 0).length;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 12),
                      Text('Statements, last 12 cycles',
                          style: Theme.of(context).textTheme.labelLarge),
                      _SingleBars(
                        values: amounts,
                        labels: [
                          for (final s in list) DateFormat('MMM').format(s.closeDate)
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Average ${fmtMoney(avg, cur)} · highest ${fmtMoney(amounts.fold(0.0, (m, v) => v > m ? v : m), cur)}'
                        '${unpaid > 0 ? ' · $unpaid not fully paid' : ''}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  );
                },
              )
            else
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                    'Set the statement closing and due days on this card to see its statements.',
                    style: Theme.of(context).textTheme.bodySmall),
              ),
          ],
        ),
      ),
    );
  }
}
