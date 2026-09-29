import 'package:flutter/material.dart';

import '../data/models.dart';
import '../state/app_state.dart';
import '../util/format.dart';
import 'widgets.dart';

const Color kWarnColor = Color(0xFFEF8F00);

Color budgetColor(BuildContext context, BudgetStatus s) {
  if (s.over) return kExpenseColor;
  if (s.fraction >= 0.8) return kWarnColor;
  return Theme.of(context).colorScheme.primary;
}

/// One budget: name, progress bar and what's left.
class BudgetRow extends StatelessWidget {
  const BudgetRow({super.key, required this.status, this.onTap, this.month});

  final BudgetStatus status;
  final VoidCallback? onTap;

  /// When set, a marker shows how far through the month today is.
  final DateTime? month;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final cur = state.baseCurrency;
    final scheme = Theme.of(context).colorScheme;
    final s = status;
    final color = budgetColor(context, s);
    final now = DateTime.now();
    double? todayFrac;
    final m = month;
    if (m != null && m.year == now.year && m.month == now.month) {
      final days = DateTime(m.year, m.month + 1, 0).day;
      todayFrac = now.day / days;
    }
    final small = Theme.of(context).textTheme.bodySmall;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(s.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                ),
                Text(
                  s.over
                      ? '${fmtAmount(-s.left)} over'
                      : '${fmtAmount(s.left)} left',
                  style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: s.over ? kExpenseColor : null),
                ),
              ],
            ),
            const SizedBox(height: 6),
            LayoutBuilder(builder: (context, c) {
              return SizedBox(
                height: 10,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(5),
                      ),
                    ),
                    FractionallySizedBox(
                      widthFactor: s.fraction.clamp(0.0, 1.0),
                      child: Container(
                        decoration: BoxDecoration(
                          color: color,
                          borderRadius: BorderRadius.circular(5),
                        ),
                      ),
                    ),
                    if (todayFrac != null)
                      Positioned(
                        left: c.maxWidth * todayFrac - 1,
                        top: -3,
                        bottom: -3,
                        child: Container(width: 2, color: scheme.onSurface),
                      ),
                  ],
                ),
              );
            }),
            const SizedBox(height: 4),
            Text(
              '${fmtAmount(s.spent)} of ${fmtMoney(s.limit, cur)} · ${(s.fraction * 100).toStringAsFixed(0)}%'
              '${s.budget.rollover && s.carried.abs() >= 0.01 ? ' · ${s.carried >= 0 ? '+' : ''}${fmtAmount(s.carried)} carried' : ''}',
              style: small,
            ),
          ],
        ),
      ),
    );
  }
}

/// Bottom tab: all budgets for a month.
class BudgetsScreen extends StatelessWidget {
  const BudgetsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Budgets')),
      body: const BudgetsTab(),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Add budget',
        onPressed: () => editBudget(context, null),
        child: const Icon(Icons.add),
      ),
    );
  }
}

/// All budgets for a month.
class BudgetsTab extends StatefulWidget {
  const BudgetsTab({super.key});

  @override
  State<BudgetsTab> createState() => _BudgetsTabState();
}

class _BudgetsTabState extends State<BudgetsTab> {
  late DateTime _month;
  Future<List<BudgetStatus>>? _future;
  String _key = '';

  @override
  void initState() {
    super.initState();
    final n = DateTime.now();
    _month = DateTime(n.year, n.month);
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final key = '${state.version}-$_month';
    if (key != _key) {
      _key = key;
      _future = state.budgetStatus(_month);
    }
    final cur = state.baseCurrency;
    final now = DateTime.now();
    final isCurrent = now.year == _month.year && now.month == _month.month;

    return FutureBuilder<List<BudgetStatus>>(
      future: _future,
      builder: (context, snap) {
        final list = snap.data ?? const <BudgetStatus>[];
        final total = list.where((s) => s.budget.scope == BudgetScope.total);
        final others = list.where((s) => s.budget.scope != BudgetScope.total).toList()
          ..sort((a, b) => b.fraction.compareTo(a.fraction));
        final sumLimit = others.fold<double>(0, (t, s) => t + s.limit);
        final sumSpent = others.fold<double>(0, (t, s) => t + s.spent);
        final overCount = list.where((s) => s.over).length;
        return ListView(
          padding: const EdgeInsets.only(bottom: 96),
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
            if (snap.connectionState != ConnectionState.done)
              const Padding(
                padding: EdgeInsets.all(40),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (list.isEmpty)
              Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  children: [
                    Icon(Icons.savings_outlined,
                        size: 48,
                        color: Theme.of(context).colorScheme.onSurfaceVariant),
                    const SizedBox(height: 12),
                    const Text(
                      'Set a monthly limit for all spending, a category group or a single category.',
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              )
            else ...[
              if (others.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                  child: Text(
                    '${others.length} budget${others.length == 1 ? '' : 's'} · '
                    '${fmtAmount(sumSpent)} of ${fmtMoney(sumLimit, cur)}'
                    '${overCount > 0 ? ' · $overCount over' : ''}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              for (final s in total)
                BudgetRow(
                    status: s,
                    month: _month,
                    onTap: () => editBudget(context, s.budget)),
              if (total.isNotEmpty && others.isNotEmpty) const Divider(),
              for (final s in others)
                BudgetRow(
                    status: s,
                    month: _month,
                    onTap: () => editBudget(context, s.budget)),
              if (isCurrent)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Text(
                    'The line on each bar marks today, so you can see whether spending is ahead of the month.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
            ],
            if (list.isEmpty && snap.connectionState == ConnectionState.done)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: FilledButton.tonalIcon(
                icon: const Icon(Icons.add),
                label: const Text('Add budget'),
                onPressed: () => editBudget(context, null),
              ),
            ),
          ],
        );
      },
    );
  }
}

Future<void> editBudget(BuildContext context, Budget? b) => Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => BudgetEditScreen(budget: b)),
    );

class BudgetEditScreen extends StatefulWidget {
  const BudgetEditScreen({super.key, this.budget});

  final Budget? budget;

  @override
  State<BudgetEditScreen> createState() => _BudgetEditScreenState();
}

class _BudgetEditScreenState extends State<BudgetEditScreen> {
  late BudgetScope _scope;
  String _target = '';
  late bool _rollover;
  late DateTime _start;
  final _amount = TextEditingController();
  Future<double>? _avg;
  String _avgKey = '';

  @override
  void initState() {
    super.initState();
    final b = widget.budget;
    final n = DateTime.now();
    _scope = b?.scope ?? BudgetScope.category;
    _target = b?.target ?? '';
    _rollover = b?.rollover ?? false;
    _start = b?.start ?? DateTime(n.year, n.month);
    if (b != null) _amount.text = fmtAmount(b.amount).replaceAll(',', '');
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  /// Average monthly spending over the last 3 full months, as a guide.
  Future<double> _average(AppState state) async {
    final n = DateTime.now();
    final probe = Budget(
        scope: _scope, target: _target, amount: 0, start: DateTime(n.year, n.month - 3));
    var sum = 0.0;
    for (var i = 1; i <= 3; i++) {
      final st = await state.budgetStatusFor(probe, DateTime(n.year, n.month - i));
      sum += st.spent;
    }
    return sum / 3;
  }

  String _targetLabel(AppState state) {
    switch (_scope) {
      case BudgetScope.total:
        return 'All spending';
      case BudgetScope.group:
        return _target.isEmpty ? 'Choose a group' : _target;
      case BudgetScope.category:
        final c = state.categoryById(int.tryParse(_target));
        if (c == null) return 'Choose a category';
        return c.group.isEmpty ? c.name : '${c.group} › ${c.name}';
    }
  }

  Future<void> _pickTarget(AppState state) async {
    if (_scope == BudgetScope.category) {
      final id = await pickCategory(context,
          kind: TxType.expense, current: int.tryParse(_target));
      if (id != null && id != -1) setState(() => _target = '$id');
    } else if (_scope == BudgetScope.group) {
      final groups = state
          .categoriesOf(TxType.expense)
          .map((c) => c.group)
          .where((g) => g.isNotEmpty)
          .toSet()
          .toList()
        ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
      final g = await showModalBottomSheet<String>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (ctx) => SizedBox(
          height: MediaQuery.of(ctx).size.height * 0.7,
          child: groups.isEmpty
              ? const Center(
                  child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('No category groups yet. Set groups in Settings → Categories.'),
                ))
              : ListView(
                  children: [
                    for (final g in groups)
                      ListTile(
                        title: Text(g),
                        selected: g == _target,
                        onTap: () => Navigator.pop(ctx, g),
                      ),
                  ],
                ),
        ),
      );
      if (g != null) setState(() => _target = g);
    }
  }

  Future<void> _save(AppState state) async {
    final amount = parseAmount(_amount.text);
    if (_scope != BudgetScope.total && _target.isEmpty) {
      showSnack(context,
          _scope == BudgetScope.group ? 'Choose a group' : 'Choose a category');
      return;
    }
    if (amount == null || amount <= 0) {
      showSnack(context, 'Enter a monthly amount');
      return;
    }
    final dup = state.budgets.any((b) =>
        b.id != widget.budget?.id &&
        b.scope == _scope &&
        (b.scope == BudgetScope.total || b.target == _target));
    if (dup) {
      showSnack(context, 'There is already a budget for this');
      return;
    }
    final old = widget.budget;
    await state.saveBudget(Budget(
      id: old?.id,
      scope: _scope,
      target: _scope == BudgetScope.total ? '' : _target,
      amount: amount,
      rollover: _rollover,
      start: _start,
      sortOrder: old?.sortOrder ?? 0,
    ));
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final cur = state.baseCurrency;
    final ready = _scope == BudgetScope.total || _target.isNotEmpty;
    final avgKey = '${state.version}-$_scope-$_target';
    if (ready && avgKey != _avgKey) {
      _avgKey = avgKey;
      _avg = _average(state);
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.budget == null ? 'New budget' : 'Edit budget'),
        actions: [
          if (widget.budget != null)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Delete',
              onPressed: () async {
                final ok = await confirmDialog(context,
                    title: 'Delete this budget?',
                    message: 'Your transactions are not affected.');
                if (ok && context.mounted) {
                  await state.deleteBudget(widget.budget!.id!);
                  if (context.mounted) Navigator.pop(context);
                }
              },
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SegmentedButton<BudgetScope>(
            segments: const [
              ButtonSegment(value: BudgetScope.category, label: Text('Category')),
              ButtonSegment(value: BudgetScope.group, label: Text('Group')),
              ButtonSegment(value: BudgetScope.total, label: Text('All spending')),
            ],
            selected: {_scope},
            onSelectionChanged: widget.budget != null
                ? null
                : (s) => setState(() {
                      _scope = s.first;
                      _target = '';
                    }),
          ),
          const SizedBox(height: 16),
          if (_scope != BudgetScope.total)
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.all(16)),
              icon: Icon(_scope == BudgetScope.group
                  ? Icons.folder_outlined
                  : Icons.category_outlined),
              label: Text(_targetLabel(state)),
              onPressed: widget.budget != null ? null : () => _pickTarget(state),
            ),
          if (_scope != BudgetScope.total) const SizedBox(height: 16),
          TextField(
            controller: _amount,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: 'Monthly limit',
              suffixText: cur,
              border: const OutlineInputBorder(),
            ),
          ),
          if (ready)
            FutureBuilder<double>(
              future: _avg,
              builder: (context, snap) {
                final v = snap.data;
                if (v == null) return const SizedBox(height: 8);
                return Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: v > 0
                        ? () => _amount.text = v.ceilToDouble().toStringAsFixed(0)
                        : null,
                    child: Text(v > 0
                        ? 'Last 3 months average: ${fmtMoney(v, cur)} — use it'
                        : 'No spending here in the last 3 months'),
                  ),
                );
              },
            ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Roll over'),
            subtitle: const Text(
                'What\'s left at month end adds to next month; overspending takes from it'),
            value: _rollover,
            onChanged: (v) => setState(() => _rollover = v),
          ),
          if (_rollover)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event),
              title: const Text('Counting from'),
              subtitle: Text(monthFmt.format(_start)),
              onTap: () async {
                final d = await showDatePicker(
                  context: context,
                  initialDate: _start,
                  firstDate: DateTime(2000),
                  lastDate: DateTime(2100),
                  helpText: 'Any day in the first month',
                );
                if (d != null) setState(() => _start = DateTime(d.year, d.month));
              },
            ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: () => _save(state),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}
