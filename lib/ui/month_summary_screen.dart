import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import '../data/models.dart';
import '../l10n/l10n.dart';
import '../state/app_state.dart';
import '../util/format.dart';
import 'widgets.dart';

class _Summary {
  double income = 0, spent = 0, prevIncome = 0, prevSpent = 0;
  double netWorthChange = 0;

  /// Money moved into counted accounts from accounts left out of totals
  /// (minus what went the other way), per account name.
  Map<String, double> movedIn = {};

  /// Income minus spending on accounts left out of totals (in "saved" but
  /// not in net worth).
  double uncountedSaved = 0;
  double loanInterest = 0, subscriptions = 0;
  List<(String, double)> topCats = [];
  List<Txn> biggest = [];
  List<BudgetStatus> budgets = [];
  double get saved => income - spent;
  double get prevSaved => prevIncome - prevSpent;
}

/// Last month in short: income, spending, saved, top categories, biggest
/// expenses, net worth change, budgets, subscriptions and loan interest.
class MonthSummaryScreen extends StatefulWidget {
  const MonthSummaryScreen({super.key, required this.month});
  final DateTime month;

  @override
  State<MonthSummaryScreen> createState() => _MonthSummaryScreenState();
}

class _MonthSummaryScreenState extends State<MonthSummaryScreen> {
  late DateTime _month = DateTime(widget.month.year, widget.month.month);
  Future<_Summary>? _future;
  String _key = '';
  final _shot = GlobalKey();
  bool _sharing = false;

  String _ym(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}';

  Future<_Summary> _load(AppState state) async {
    final s = _Summary();
    final from = _month;
    final to = DateTime(_month.year, _month.month + 1, 1);
    final prev = DateTime(_month.year, _month.month - 1, 1);
    for (final r in await state.db.monthlyTotals(prev, to)) {
      final v = state.toBase((r['total'] as num).toDouble(), r['cur'] as String? ?? state.baseCurrency);
      final cur = r['ym'] == _ym(from);
      if (r['type'] == 'income') {
        if (cur) {
          s.income += v;
        } else {
          s.prevIncome += v;
        }
      } else {
        if (cur) {
          s.spent += v;
        } else {
          s.prevSpent += v;
        }
      }
    }
    final byCat = <int?, double>{};
    for (final r in await state.db.categoryTotals(TxType.expense, from, to)) {
      final cat = r['cat'] as int?;
      byCat[cat] = (byCat[cat] ?? 0) +
          state.toBase((r['total'] as num).toDouble(), r['cur'] as String? ?? state.baseCurrency);
    }
    final cats = byCat.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    s.topCats = [
      for (final e in cats.take(5))
        (state.categoryById(e.key)?.name ?? tr('No category'), e.value),
    ];
    for (final e in cats) {
      if ((state.categoryById(e.key)?.name ?? '').toLowerCase() == 'loan interest') {
        s.loanInterest += e.value;
      }
    }
    double base(Txn t) =>
        state.toBase(t.amount, state.accountById(t.accountId)?.currency ?? state.baseCurrency);
    final txns = await state.db.transactions(from: from, to: to);
    final subIds = {for (final r in state.rules) if (r.subscription) r.id};
    for (final t in txns) {
      if (t.type == TxType.expense && subIds.contains(t.recurringId)) s.subscriptions += base(t);
    }
    s.biggest = txns.where((t) => t.type == TxType.expense).toList()
      ..sort((a, b) => base(b).compareTo(base(a)));
    s.biggest = s.biggest.take(5).toList();
    // Net worth change: money in and out of the counted accounts.
    final counted = {
      for (final a in state.accounts)
        if (!a.excludeTotal) a.id!: a,
    };
    for (final r in await state.db.monthlyAccountChanges(to.subtract(const Duration(milliseconds: 1)))) {
      if (r['ym'] != _ym(from)) continue;
      final a = counted[r['acc'] as int?];
      if (a == null) continue;
      s.netWorthChange += state.toBase((r['delta'] as num).toDouble(), a.currency);
    }
    // Why net worth changed differently from what was saved.
    for (final t in txns) {
      final fromIn = counted.containsKey(t.accountId);
      if (t.type == TxType.transfer) {
        final toIn = counted.containsKey(t.toAccountId);
        if (fromIn == toIn) continue;
        final other = state.accountById(fromIn ? t.toAccountId : t.accountId);
        final name = other?.name ?? tr('Deleted account');
        final toAcc = state.accountById(t.toAccountId);
        final v = fromIn
            ? -base(t)
            : state.toBase(t.toAmount ?? t.amount, toAcc?.currency ?? state.baseCurrency);
        s.movedIn[name] = (s.movedIn[name] ?? 0) + v;
      } else if (!fromIn) {
        s.uncountedSaved += t.type == TxType.income ? base(t) : -base(t);
      }
    }
    s.movedIn.removeWhere((_, v) => v.abs() < 0.5);
    s.budgets = [...await state.budgetStatus(from)];
    return s;
  }

  Future<void> _share() async {
    setState(() => _sharing = true);
    try {
      final boundary = _shot.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return;
      final image = await boundary.toImage(pixelRatio: 2.5);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) return;
      final png = data.buffer.asUint8List();
      // One PDF page the shape of the summary.
      const width = 420.0;
      final height = width * image.height / image.width;
      final doc = pw.Document();
      doc.addPage(pw.Page(
        pageFormat: PdfPageFormat(width, height, marginAll: 0),
        build: (_) => pw.Image(pw.MemoryImage(png), fit: pw.BoxFit.contain),
      ));
      final dir = await getTemporaryDirectory();
      final name = 'Summary ${_ym(_month)}.pdf';
      final f = File('${dir.path}/$name');
      await f.writeAsBytes(await doc.save());
      if (!mounted) return;
      await Share.shareXFiles([XFile(f.path)],
          subject: tr('${monthFmt.format(_month)} summary'),
          sharePositionOrigin: shareOrigin(context));
    } catch (e) {
      if (mounted) showSnack(context, tr('Could not share: $e'));
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final key = '${state.version}-$_month';
    if (key != _key) {
      _key = key;
      _future = _load(state);
    }
    final theme = Theme.of(context);
    final cur = state.baseCurrency;
    return Scaffold(
      appBar: AppBar(
        title: Text(tr('Month Summary')),
        actions: [
          _sharing
              ? const Padding(
                  padding: EdgeInsets.all(16),
                  child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                )
              : IconButton(
                  tooltip: tr('Share as PDF'),
                  icon: const Icon(Icons.ios_share),
                  onPressed: _share,
                ),
        ],
      ),
      body: FutureBuilder<_Summary>(
        future: _future,
        builder: (context, snap) {
          final s = snap.data;
          return SingleChildScrollView(
            padding: const EdgeInsets.only(bottom: 32),
            child: Column(
              children: [
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.chevron_left),
                      onPressed: () => setState(() => _month = DateTime(_month.year, _month.month - 1)),
                    ),
                    Expanded(
                      child: Center(
                        child: Text(monthFmt.format(_month), style: theme.textTheme.titleMedium),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.chevron_right),
                      onPressed: () => setState(() => _month = DateTime(_month.year, _month.month + 1)),
                    ),
                  ],
                ),
                if (s == null)
                  const Padding(padding: EdgeInsets.all(40), child: CircularProgressIndicator())
                else
                  RepaintBoundary(
                    key: _shot,
                    child: Container(
                      color: theme.scaffoldBackgroundColor,
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                      child: _content(context, state, s, cur),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  /// Explains a net worth change that differs from what was saved: money
  /// moved from or to accounts left out of totals (e.g. a loan or an
  /// excluded account).
  List<Widget> _netWorthWhy(BuildContext context, _Summary s, String cur) {
    final moved = s.movedIn.values.fold<double>(0, (a, b) => a + b);
    // Income and spending on accounts left out of totals are in "saved" but
    // not in net worth.
    final outside = -s.uncountedSaved;
    if ((s.netWorthChange - s.saved).abs() < 1) return const [];
    final other = s.netWorthChange - s.saved - outside - moved;
    final theme = Theme.of(context);
    // Same size as the other lines, in a softer colour.
    final style = theme.textTheme.bodyMedium?.copyWith(
        color: theme.colorScheme.onSurfaceVariant);
    String sign(double v) => '${v >= 0 ? '+' : ''}${fmtMoney(v, cur)}';
    Widget line(String l, double v) => Padding(
          padding: const EdgeInsetsDirectional.only(start: 14, top: 3, bottom: 3),
          child: Row(children: [
            Expanded(child: Text(l, style: style, maxLines: 1, overflow: TextOverflow.ellipsis)),
            const SizedBox(width: 8),
            Text(sign(v), style: style),
          ]),
        );
    final names = s.movedIn.entries.toList()
      ..sort((a, b) => b.value.abs().compareTo(a.value.abs()));
    return [
      line(tr('What you saved'), s.saved),
      if (outside.abs() >= 1)
        line(outside >= 0
            ? tr('Spent from accounts not in totals')
            : tr('Earned in accounts not in totals'), outside),
      for (final e in names.take(3))
        line(e.value >= 0
            ? tr('Moved in from ${e.key} (not in totals)')
            : tr('Moved out to ${e.key} (not in totals)'), e.value),
      if (names.length > 3)
        line(tr('Other accounts not in totals'),
            names.skip(3).fold<double>(0, (a, e) => a + e.value)),
      if (other.abs() >= 1) line(tr('Other (entry dates, exchange rates)'), other),
    ];
  }

  Widget _content(BuildContext context, AppState state, _Summary s, String cur) {
    final theme = Theme.of(context);
    final small = theme.textTheme.bodySmall;
    String vs(double now, double before) {
      if (before.abs() < 0.005) return '';
      final p = (now - before) / before.abs() * 100;
      return tr('${p >= 0 ? '+' : ''}${p.toStringAsFixed(0)}% vs month before');
    }

    Widget big(String label, double v, double before, Color color) => Expanded(
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: small),
                FittedBox(
                  child: Text(fmtMoney(v, cur),
                      style: TextStyle(fontWeight: FontWeight.bold, color: color, fontSize: 16)),
                ),
                Text(vs(v, before), style: small),
              ],
            ),
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

    final rate = s.income > 0 ? (s.saved / s.income * 100).toStringAsFixed(0) : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(tr('${monthFmt.format(_month)} in short'),
            style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        Row(children: [
          big(tr('Income'), s.income, s.prevIncome, kIncomeColor),
          const SizedBox(width: 8),
          big(tr('Spent'), s.spent, s.prevSpent, kExpenseColor),
        ]),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: theme.colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(s.saved >= 0 ? tr('Saved') : tr('Overspent'), style: small),
                    Text(fmtMoney(s.saved.abs(), cur),
                        style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
              if (rate != null && s.saved > 0)
                Text(tr('$rate% of income'), style: const TextStyle(fontWeight: FontWeight.w600)),
            ],
          ),
        ),
        const SizedBox(height: 8),
        row(tr('Net worth change'), '${s.netWorthChange >= 0 ? '+' : ''}${fmtMoney(s.netWorthChange, cur)}',
            color: s.netWorthChange >= 0 ? kIncomeColor : kExpenseColor),
        ..._netWorthWhy(context, s, cur),
        if (s.subscriptions > 0.004) row(tr('Subscriptions'), fmtMoney(s.subscriptions, cur)),
        if (s.loanInterest > 0.004) row(tr('Loan interest'), fmtMoney(s.loanInterest, cur)),
        if (s.topCats.isNotEmpty) ...[
          heading(tr('Top Categories')),
          for (final (name, v) in s.topCats)
            row(name, '${fmtMoney(v, cur)}${s.spent > 0 ? '  ·  ${(v / s.spent * 100).toStringAsFixed(0)}%' : ''}'),
        ],
        if (s.biggest.isNotEmpty) ...[
          heading(tr('Biggest Expenses')),
          for (final t in s.biggest)
            row(
              '${t.payee.isNotEmpty ? t.payee : (state.categoryById(t.categoryId)?.name ?? tr('Expense'))} · ${shortDateFmt.format(t.date)}',
              fmtMoney(t.amount, state.accountById(t.accountId)?.currency ?? cur),
            ),
        ],
        if (s.budgets.isNotEmpty) ...[
          heading(tr('Budgets')),
          for (final b in s.budgets)
            row(
              b.name,
              b.spent > b.limit
                  ? tr('Over by ${fmtMoney(b.spent - b.limit, cur)}')
                  : tr('${fmtMoney(b.limit - b.spent, cur)} left'),
              color: b.spent > b.limit ? kExpenseColor : kIncomeColor,
            ),
        ],
        const SizedBox(height: 12),
        Text(tr('Expense & Wealth Tracker'), style: small, textAlign: TextAlign.center),
      ],
    );
  }
}
