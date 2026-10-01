import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../data/models.dart';
import '../l10n/l10n.dart';
import '../state/app_state.dart';
import '../util/format.dart';
import 'budgets_screen.dart';
import 'reports_screen.dart' show loadCategoryTotals;
import 'widgets.dart';

/// Budget vs Actual: each budget against what was spent, the month's
/// totals, unbudgeted spending, pace for the current month and the last
/// 6 months.
class BudgetVsActualTab extends StatefulWidget {
  const BudgetVsActualTab({super.key});

  @override
  State<BudgetVsActualTab> createState() => _BudgetVsActualTabState();
}

class _BvaData {
  _BvaData(this.statuses, this.unbudgeted, this.history);
  final List<BudgetStatus> statuses;
  final double unbudgeted;

  /// Last 6 months: (month, budgeted, spent, budgets kept, budgets total).
  final List<(DateTime, double, double, int, int)> history;
}

class _BudgetVsActualTabState extends State<BudgetVsActualTab> {
  late DateTime _month;
  Future<_BvaData>? _future;
  String _key = '';

  @override
  void initState() {
    super.initState();
    final n = DateTime.now();
    _month = DateTime(n.year, n.month);
  }

  Future<_BvaData> _load(AppState state) async {
    final statuses = await state.budgetStatus(_month);
    // Spending in categories no budget covers (a total budget doesn't
    // count, since it covers everything).
    final cats = await loadCategoryTotals(
        state, TxType.expense, _month, DateTime(_month.year, _month.month + 1));
    final catIds = <int>{};
    final groups = <String>{};
    for (final b in state.budgets) {
      if (b.scope == BudgetScope.category && b.categoryId != null) {
        catIds.add(b.categoryId!);
      } else if (b.scope == BudgetScope.group) {
        groups.add(b.target);
      }
    }
    var unbudgeted = 0.0;
    for (final c in cats) {
      final covered = (c.id != null && catIds.contains(c.id)) ||
          (c.category != null && groups.contains(c.category!.group));
      if (!covered) unbudgeted += c.total;
    }
    final history = <(DateTime, double, double, int, int)>[];
    for (var i = 5; i >= 0; i--) {
      final m = DateTime(_month.year, _month.month - i);
      final list = (await state.budgetStatus(m))
          .where((s) => !s.budget.start.isAfter(m))
          .toList();
      // A total budget already includes everything; avoid counting twice.
      final total = list.where((s) => s.budget.scope == BudgetScope.total);
      final use = total.isNotEmpty ? total.toList() : list;
      history.add((
        m,
        use.fold(0.0, (t, s) => t + s.limit),
        use.fold(0.0, (t, s) => t + s.spent),
        list.where((s) => !s.over).length,
        list.length,
      ));
    }
    return _BvaData(statuses, unbudgeted, history);
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
    final theme = Theme.of(context);
    final small = theme.textTheme.bodySmall;

    if (state.budgets.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.savings_outlined, size: 48),
              const SizedBox(height: 12),
              Text(tr('No budgets yet'), style: theme.textTheme.titleMedium),
              const SizedBox(height: 6),
              Text(
                tr('Set a monthly limit for all spending, a category group or a single category.'),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                icon: const Icon(Icons.add),
                label: Text(tr('New Budget')),
                onPressed: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const BudgetEditScreen())),
              ),
            ],
          ),
        ),
      );
    }

    final now = DateTime.now();
    final isCurrent = _month.year == now.year && _month.month == now.month;
    final daysInMonth = DateTime(_month.year, _month.month + 1, 0).day;

    return FutureBuilder<_BvaData>(
      future: _future,
      builder: (context, snap) {
        final d = snap.data;
        return ListView(
          padding: const EdgeInsets.only(bottom: 32),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.chevron_left),
                    onPressed: () => setState(() =>
                        _month = DateTime(_month.year, _month.month - 1)),
                  ),
                  Expanded(
                    child: Text(monthFmt.format(_month),
                        textAlign: TextAlign.center,
                        style: theme.textTheme.titleMedium),
                  ),
                  IconButton(
                    icon: const Icon(Icons.chevron_right),
                    onPressed: isCurrent
                        ? null
                        : () => setState(() =>
                            _month = DateTime(_month.year, _month.month + 1)),
                  ),
                ],
              ),
            ),
            if (d == null)
              const Padding(
                padding: EdgeInsets.all(40),
                child: Center(child: CircularProgressIndicator()),
              )
            else ...[
              _summary(context, d, cur, isCurrent, now.day, daysInMonth),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Row(
                  children: [
                    Expanded(child: Text(tr('Budget'), style: small)),
                    _legend(context, theme.colorScheme.outlineVariant, tr('Budget')),
                    const SizedBox(width: 12),
                    _legend(context, theme.colorScheme.primary, tr('Spent')),
                  ],
                ),
              ),
              for (final st in d.statuses)
                _BudgetRow(
                    st: st,
                    currency: cur,
                    paceFrac: isCurrent ? now.day / daysInMonth : null),
              if (d.unbudgeted > 0.004)
                ListTile(
                  leading: const Icon(Icons.help_outline),
                  title: Text(tr('Unbudgeted Spending')),
                  subtitle: Text(tr('Categories with no budget of their own')),
                  trailing: Text(fmtMoney(d.unbudgeted, cur),
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
                child: Text(tr('Last 6 Months'),
                    style: theme.textTheme.titleSmall
                        ?.copyWith(color: theme.colorScheme.primary)),
              ),
              _HistoryBars(history: d.history),
              for (final h in d.history.reversed)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 2, 16, 2),
                  child: Row(
                    children: [
                      Expanded(child: Text(monthFmt.format(h.$1), style: small)),
                      Text(
                        tr('${fmtAmount(h.$3)} of ${fmtAmount(h.$2)}'),
                        style: small?.copyWith(
                            color: h.$3 > h.$2 + 0.004
                                ? kExpenseColor
                                : theme.colorScheme.onSurfaceVariant),
                      ),
                      const SizedBox(width: 10),
                      Text(tr('${h.$4}/${h.$5} kept'), style: small),
                    ],
                  ),
                ),
            ],
          ],
        );
      },
    );
  }

  Widget _legend(BuildContext context, Color c, String label) => Row(
        children: [
          Container(
              width: 10,
              height: 10,
              decoration:
                  BoxDecoration(color: c, borderRadius: BorderRadius.circular(3))),
          const SizedBox(width: 4),
          Text(label, style: Theme.of(context).textTheme.bodySmall),
        ],
      );

  Widget _summary(BuildContext context, _BvaData d, String cur, bool isCurrent,
      int day, int days) {
    final theme = Theme.of(context);
    final st = d.statuses;
    final total = st.where((s) => s.budget.scope == BudgetScope.total).toList();
    final use = total.isNotEmpty ? total : st;
    final budgeted = use.fold<double>(0, (t, s) => t + s.limit);
    final spent = use.fold<double>(0, (t, s) => t + s.spent);
    final diff = budgeted - spent;
    final over = diff < -0.004;
    final kept = st.where((s) => !s.over).length;
    final pace = isCurrent && day > 0 ? spent / day * days : null;

    Widget cell(String label, String value, {Color? color}) => Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: theme.textTheme.bodySmall),
              const SizedBox(height: 2),
              Text(value,
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700, color: color)),
            ],
          ),
        );

    return Card(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                cell(tr('Budgeted'), fmtAmount(budgeted)),
                cell(tr('Spent'), fmtAmount(spent)),
                cell(over ? tr('Over') : tr('Left'), fmtAmount(diff.abs()),
                    color: over ? kExpenseColor : kIncomeColor),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              tr('$kept of ${st.length} budgets kept · $cur'),
              style: theme.textTheme.bodySmall,
            ),
            if (pace != null && budgeted > 0)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  tr('At this pace the month ends at ${fmtAmount(pace)} of ${fmtAmount(budgeted)}'),
                  style: theme.textTheme.bodySmall?.copyWith(
                      color: pace > budgeted ? kExpenseColor : kIncomeColor,
                      fontWeight: FontWeight.w600),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// One budget: name, two bars (budget and spent) and the difference.
class _BudgetRow extends StatelessWidget {
  const _BudgetRow({required this.st, required this.currency, this.paceFrac});

  final BudgetStatus st;
  final String currency;
  final double? paceFrac;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final maxV = [st.limit, st.spent, 1.0].reduce((a, b) => a > b ? a : b);
    final diff = st.limit - st.spent;
    final color = st.over
        ? kExpenseColor
        : (st.fraction >= 0.8 ? const Color(0xFFE6A23C) : theme.colorScheme.primary);

    Widget bar(double v, Color c) => LayoutBuilder(
          builder: (context, box) => Stack(
            children: [
              Container(
                  height: 8,
                  decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(4))),
              Container(
                  height: 8,
                  width: box.maxWidth * (v / maxV).clamp(0.0, 1.0),
                  decoration: BoxDecoration(
                      color: c, borderRadius: BorderRadius.circular(4))),
            ],
          ),
        );

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                  child: Text(st.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w500))),
              Text(
                diff < -0.004
                    ? tr('${fmtAmount(-diff)} over')
                    : tr('${fmtAmount(diff)} left'),
                style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: diff < -0.004 ? kExpenseColor : kIncomeColor),
              ),
            ],
          ),
          const SizedBox(height: 6),
          bar(st.limit, theme.colorScheme.outlineVariant),
          const SizedBox(height: 4),
          bar(st.spent, color),
          const SizedBox(height: 4),
          Text(
            [
              tr('Spent ${fmtAmount(st.spent)} of ${fmtAmount(st.limit)}'),
              if (st.carried.abs() > 0.004)
                tr('${fmtAmount(st.carried)} carried in'),
              if (paceFrac != null && paceFrac! > 0 && st.limit > 0)
                tr('pace ${fmtAmount(st.spent / paceFrac!)}'),
            ].join(' · '),
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

/// Budget (outline) and actual (filled) side by side for each month.
class _HistoryBars extends StatelessWidget {
  const _HistoryBars({required this.history});

  final List<(DateTime, double, double, int, int)> history;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final maxV = history.fold<double>(
        1, (m, h) => [m, h.$2, h.$3].reduce((a, b) => a > b ? a : b));
    const h = 120.0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: SizedBox(
        height: h + 22,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (final m in history)
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Container(
                          width: 12,
                          height: (m.$2 / maxV * h).clamp(2.0, h),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.outlineVariant,
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                        const SizedBox(width: 3),
                        Container(
                          width: 12,
                          height: (m.$3 / maxV * h).clamp(2.0, h),
                          decoration: BoxDecoration(
                            color: m.$3 > m.$2 + 0.004
                                ? kExpenseColor
                                : theme.colorScheme.primary,
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      DateFormat('MMM').format(m.$1),
                      style: theme.textTheme.labelSmall,
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
