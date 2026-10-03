import 'package:flutter/material.dart';

import '../data/models.dart';
import '../l10n/l10n.dart';
import '../state/app_state.dart';
import '../util/format.dart';
import 'month_summary_screen.dart' show shareAsPdf;
import 'widgets.dart';

class _Year {
  double income = 0, spent = 0, prevIncome = 0, prevSpent = 0;
  double startNw = 0, endNw = 0;
  double subscriptions = 0, loanInterest = 0;
  final months = List<(double, double)>.filled(12, (0.0, 0.0)); // income, spent
  List<(String, double)> topCats = [];
  List<Txn> biggest = [];
  List<(String, double)> tags = [];
  double get saved => income - spent;
}

/// The year in short: totals, each month, best and worst months, top
/// categories, biggest expenses, net worth, subscriptions, loan interest
/// and trips (tags).
class YearReviewScreen extends StatefulWidget {
  const YearReviewScreen({super.key, required this.year});
  final int year;

  @override
  State<YearReviewScreen> createState() => _YearReviewScreenState();
}

class _YearReviewScreenState extends State<YearReviewScreen> {
  late int _year = widget.year;
  Future<_Year>? _future;
  String _key = '';
  final _shot = GlobalKey();
  bool _sharing = false;

  Future<_Year> _load(AppState state) async {
    final y = _Year();
    final from = DateTime(_year, 1, 1);
    final to = DateTime(_year + 1, 1, 1);
    final prev = DateTime(_year - 1, 1, 1);
    String cur(Map r) => r['cur'] as String? ?? state.baseCurrency;
    for (final r in await state.db.monthlyTotals(prev, to)) {
      final v = state.toBase((r['total'] as num).toDouble(), cur(r));
      final ym = r['ym'] as String;
      final inYear = ym.startsWith('$_year-');
      final inc = r['type'] == 'income';
      if (inYear) {
        final m = int.parse(ym.substring(5)) - 1;
        final old = y.months[m];
        y.months[m] = inc ? (old.$1 + v, old.$2) : (old.$1, old.$2 + v);
        if (inc) {
          y.income += v;
        } else {
          y.spent += v;
        }
      } else {
        if (inc) {
          y.prevIncome += v;
        } else {
          y.prevSpent += v;
        }
      }
    }
    final byCat = <int?, double>{};
    for (final r in await state.db.categoryTotals(TxType.expense, from, to)) {
      final c = r['cat'] as int?;
      byCat[c] = (byCat[c] ?? 0) + state.toBase((r['total'] as num).toDouble(), cur(r));
    }
    final cats = byCat.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    y.topCats = [
      for (final e in cats.take(6)) (state.categoryById(e.key)?.name ?? tr('No category'), e.value),
    ];
    for (final e in cats) {
      if ((state.categoryById(e.key)?.name ?? '').toLowerCase() == 'loan interest') y.loanInterest += e.value;
    }
    double base(Txn t) =>
        state.toBase(t.amount, state.accountById(t.accountId)?.currency ?? state.baseCurrency);
    final txns = await state.db.transactions(from: from, to: to);
    final subIds = {for (final r in state.rules) if (r.subscription) r.id};
    for (final t in txns) {
      if (t.type == TxType.expense && subIds.contains(t.recurringId)) y.subscriptions += base(t);
    }
    y.biggest = (txns.where((t) => t.type == TxType.expense).toList()
          ..sort((a, b) => base(b).compareTo(base(a))))
        .take(5)
        .toList();
    // Net worth at the start and end of the year (counted accounts).
    final counted = {for (final a in state.accounts) if (!a.excludeTotal) a.id!: a};
    var opening = 0.0;
    for (final a in counted.values) {
      opening += state.toBase(a.openingBalance, a.currency);
    }
    var before = opening, upTo = opening;
    for (final r in await state.db.monthlyAccountChanges(to.subtract(const Duration(milliseconds: 1)))) {
      final a = counted[r['acc'] as int?];
      if (a == null) continue;
      final v = state.toBase((r['delta'] as num).toDouble(), a.currency);
      final ym = r['ym'] as String;
      if (ym.compareTo('$_year-01') < 0) before += v;
      upTo += v;
    }
    y.startNw = before;
    y.endNw = upTo;
    // Trips and other tags of the year.
    final tagSums = <(String, double)>[];
    for (final tag in state.allTags) {
      var s = 0.0;
      for (final t in await state.db.txnsWithTag(tag)) {
        if (t.type != TxType.expense || t.date.isBefore(from) || !t.date.isBefore(to)) continue;
        s += base(t);
      }
      if (s > 0.004) tagSums.add((tag, s));
    }
    tagSums.sort((a, b) => b.$2.compareTo(a.$2));
    y.tags = tagSums.take(5).toList();
    return y;
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final key = '${state.version}-$_year';
    if (key != _key) {
      _key = key;
      _future = _load(state);
    }
    final theme = Theme.of(context);
    final cur = state.baseCurrency;
    return Scaffold(
      appBar: AppBar(
        title: Text(tr('Year in Review')),
        actions: [
          _sharing
              ? const Padding(
                  padding: EdgeInsets.all(16),
                  child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)))
              : IconButton(
                  tooltip: tr('Share as PDF'),
                  icon: const Icon(Icons.ios_share),
                  onPressed: () async {
                    setState(() => _sharing = true);
                    await shareAsPdf(context, _shot, 'Year $_year', tr('$_year in review'));
                    if (mounted) setState(() => _sharing = false);
                  },
                ),
        ],
      ),
      body: FutureBuilder<_Year>(
        future: _future,
        builder: (context, snap) {
          final y = snap.data;
          return SingleChildScrollView(
            padding: const EdgeInsets.only(bottom: 32),
            child: Column(
              children: [
                Row(
                  children: [
                    IconButton(icon: const Icon(Icons.chevron_left), onPressed: () => setState(() => _year--)),
                    Expanded(child: Center(child: Text('$_year', style: theme.textTheme.titleMedium))),
                    IconButton(icon: const Icon(Icons.chevron_right), onPressed: () => setState(() => _year++)),
                  ],
                ),
                if (y == null)
                  const Padding(padding: EdgeInsets.all(40), child: CircularProgressIndicator())
                else
                  RepaintBoundary(
                    key: _shot,
                    child: Container(
                      color: theme.scaffoldBackgroundColor,
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                      child: _content(context, state, y, cur),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _content(BuildContext context, AppState state, _Year y, String cur) {
    final theme = Theme.of(context);
    final small = theme.textTheme.bodySmall;
    String vs(double now, double before) {
      if (before.abs() < 0.005) return '';
      final p = (now - before) / before.abs() * 100;
      return tr('${p >= 0 ? '+' : ''}${p.toStringAsFixed(0)}% vs year before');
    }

    Widget big(String label, double v, double before, Color color) => Expanded(
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: color.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(10)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: small),
              FittedBox(child: Text(fmtMoney(v, cur), style: TextStyle(fontWeight: FontWeight.bold, color: color, fontSize: 16))),
              Text(vs(v, before), style: small),
            ]),
          ),
        );
    Widget heading(String t) => Padding(
          padding: const EdgeInsets.only(top: 18, bottom: 6),
          child: Text(t, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
        );
    Widget row(String l, String v, {Color? color}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(children: [
            Expanded(child: Text(l, maxLines: 1, overflow: TextOverflow.ellipsis)),
            Text(v, style: TextStyle(fontWeight: FontWeight.w600, color: color)),
          ]),
        );

    // Months with any money moving.
    final active = [for (var i = 0; i < 12; i++) if (y.months[i].$1 > 0 || y.months[i].$2 > 0) i];
    int? best, worst;
    for (final i in active) {
      final s = y.months[i].$1 - y.months[i].$2;
      if (best == null || s > y.months[best].$1 - y.months[best].$2) best = i;
      if (worst == null || s < y.months[worst].$1 - y.months[worst].$2) worst = i;
    }
    final maxV = y.months.fold<double>(0, (m, e) => [m, e.$1, e.$2].reduce((a, b) => a > b ? a : b));
    String mName(int i) => monthFmt.format(DateTime(_year, i + 1)).split(' ').first;
    final nwChange = y.endNw - y.startNw;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(tr('$_year in review'), style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        Row(children: [
          big(tr('Income'), y.income, y.prevIncome, kIncomeColor),
          const SizedBox(width: 8),
          big(tr('Spent'), y.spent, y.prevSpent, kExpenseColor),
        ]),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: theme.colorScheme.primaryContainer, borderRadius: BorderRadius.circular(10)),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(y.saved >= 0 ? tr('Saved') : tr('Overspent'), style: small),
                Text(fmtMoney(y.saved.abs(), cur), style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
              ]),
            ),
            if (y.income > 0 && y.saved > 0)
              Text(tr('${(y.saved / y.income * 100).toStringAsFixed(0)}% of income'),
                  style: const TextStyle(fontWeight: FontWeight.w600)),
          ]),
        ),
        heading(tr('Month by Month')),
        SizedBox(
          height: 120,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (var i = 0; i < 12; i++)
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Container(width: 6, height: maxV == 0 ? 0 : 90 * y.months[i].$1 / maxV, color: kIncomeColor),
                          const SizedBox(width: 1),
                          Container(width: 6, height: maxV == 0 ? 0 : 90 * y.months[i].$2 / maxV, color: kExpenseColor),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(mName(i).substring(0, mName(i).length < 3 ? mName(i).length : 3),
                          style: small?.copyWith(fontSize: 10)),
                    ],
                  ),
                ),
            ],
          ),
        ),
        if (best != null) ...[
          const SizedBox(height: 8),
          row(tr('Best month: ${mName(best)}'), fmtMoney(y.months[best].$1 - y.months[best].$2, cur), color: kIncomeColor),
          if (worst != null && worst != best)
            row(tr('Hardest month: ${mName(worst)}'), fmtMoney(y.months[worst].$1 - y.months[worst].$2, cur),
                color: kExpenseColor),
        ],
        heading(tr('Net Worth')),
        row(tr('Start of $_year'), fmtMoney(y.startNw, cur)),
        row(tr('End of $_year'), fmtMoney(y.endNw, cur)),
        row(tr('Change'), '${nwChange >= 0 ? '+' : ''}${fmtMoney(nwChange, cur)}',
            color: nwChange >= 0 ? kIncomeColor : kExpenseColor),
        if (y.subscriptions > 0.004) row(tr('Subscriptions'), fmtMoney(y.subscriptions, cur)),
        if (y.loanInterest > 0.004) row(tr('Loan interest'), fmtMoney(y.loanInterest, cur)),
        if (y.topCats.isNotEmpty) ...[
          heading(tr('Top Categories')),
          for (final (n, v) in y.topCats)
            row(n, '${fmtMoney(v, cur)}${y.spent > 0 ? '  ·  ${(v / y.spent * 100).toStringAsFixed(0)}%' : ''}'),
        ],
        if (y.tags.isNotEmpty) ...[
          heading(tr('Trips & Tags')),
          for (final (n, v) in y.tags) row('#$n', fmtMoney(v, cur)),
        ],
        if (y.biggest.isNotEmpty) ...[
          heading(tr('Biggest Expenses')),
          for (final t in y.biggest)
            row(
              '${t.payee.isNotEmpty ? t.payee : (state.categoryById(t.categoryId)?.name ?? tr('Expense'))} · ${shortDateFmt.format(t.date)}',
              fmtMoney(t.amount, state.accountById(t.accountId)?.currency ?? cur),
            ),
        ],
        const SizedBox(height: 12),
        Text('Expense & Wealth Tracker', style: small, textAlign: TextAlign.center),
      ],
    );
  }
}
