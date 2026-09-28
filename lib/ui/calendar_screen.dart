import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../data/models.dart';
import '../state/app_state.dart';
import '../util/format.dart';
import 'transaction_edit.dart';
import 'widgets.dart';

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _DayInfo {
  double expense = 0;
  double income = 0;
  bool hasUpcoming = false;
  bool hasDue = false;
  final List<Txn> txns = [];
  final List<Occurrence> pending = [];
}

class _CalendarScreenState extends State<CalendarScreen> {
  late DateTime _month;
  late DateTime _selected;
  Future<List<Txn>>? _future;
  String _loadedKey = '';

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _month = DateTime(now.year, now.month);
    _selected = DateTime(now.year, now.month, now.day);
  }

  void _shift(int delta) {
    setState(() {
      _month = DateTime(_month.year, _month.month + delta);
      final now = DateTime.now();
      _selected = (_month.year == now.year && _month.month == now.month)
          ? DateTime(now.year, now.month, now.day)
          : _month;
    });
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
        title: const Text('Calendar'),
        actions: [
          IconButton(
            tooltip: 'Today',
            icon: const Icon(Icons.today),
            onPressed: () {
              final now = DateTime.now();
              setState(() {
                _month = DateTime(now.year, now.month);
                _selected = DateTime(now.year, now.month, now.day);
              });
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Add on selected day',
        onPressed: () {
          final now = DateTime.now();
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => TransactionEditScreen(
                initialDate: DateTime(_selected.year, _selected.month,
                    _selected.day, now.hour, now.minute),
              ),
            ),
          );
        },
        child: const Icon(Icons.add),
      ),
      body: FutureBuilder<List<Txn>>(
        future: _future,
        builder: (context, snap) {
          final days = <int, _DayInfo>{};
          _DayInfo info(int d) => days.putIfAbsent(d, () => _DayInfo());
          for (final t in snap.data ?? const <Txn>[]) {
            final i = info(t.date.day);
            i.txns.add(t);
            final cur = state.accountById(t.accountId)?.currency ??
                state.baseCurrency;
            if (t.type == TxType.expense) i.expense += state.toBase(t.amount, cur);
            if (t.type == TxType.income) i.income += state.toBase(t.amount, cur);
            if (t.isFuture) i.hasUpcoming = true;
          }
          for (final o in state.pendingOccurrences(
              _month, DateTime(_month.year, _month.month + 1))) {
            final i = info(o.date.day);
            i.pending.add(o);
            if (o.isDue) {
              i.hasDue = true;
            } else {
              i.hasUpcoming = true;
            }
          }

          final sel = _selected.month == _month.month &&
                  _selected.year == _month.year
              ? days[_selected.day]
              : null;
          final selItems = <(DateTime, Object)>[
            for (final t in sel?.txns ?? const <Txn>[]) (t.date, t),
            for (final o in sel?.pending ?? const <Occurrence>[]) (o.date, o),
          ]..sort((a, b) => a.$1.compareTo(b.$1));

          return ListView(
            padding: const EdgeInsets.only(bottom: 96),
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  children: [
                    IconButton(
                        onPressed: () => _shift(-1),
                        icon: const Icon(Icons.chevron_left)),
                    Expanded(
                      child: Center(
                        child: Text(monthFmt.format(_month),
                            style: Theme.of(context).textTheme.titleMedium),
                      ),
                    ),
                    IconButton(
                        onPressed: () => _shift(1),
                        icon: const Icon(Icons.chevron_right)),
                  ],
                ),
              ),
              _Grid(
                month: _month,
                weekStart: state.weekStart,
                selected: _selected,
                days: days,
                onTap: (d) => setState(() => _selected = d),
              ),
              const Divider(height: 24),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(dayFmt.format(_selected),
                          style: Theme.of(context).textTheme.titleSmall),
                    ),
                    if (sel != null && sel.expense > 0)
                      Text('-${fmtAmount(sel.expense)}',
                          style: const TextStyle(
                              color: kExpenseColor,
                              fontWeight: FontWeight.w600)),
                    if (sel != null && sel.income > 0) ...[
                      const SizedBox(width: 12),
                      Text('+${fmtAmount(sel.income)}',
                          style: const TextStyle(
                              color: kIncomeColor,
                              fontWeight: FontWeight.w600)),
                    ],
                  ],
                ),
              ),
              if (selItems.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: Text('Nothing on this day')),
                ),
              for (final (_, item) in selItems)
                if (item is Txn)
                  TxnTile(
                    txn: item,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => TransactionEditScreen(txn: item)),
                    ),
                  )
                else if (item is Occurrence)
                  OccurrenceTile(occurrence: item),
            ],
          );
        },
      ),
    );
  }
}

class _Grid extends StatelessWidget {
  const _Grid({
    required this.month,
    required this.weekStart,
    required this.selected,
    required this.days,
    required this.onTap,
  });

  final DateTime month;
  final int weekStart;
  final DateTime selected;
  final Map<int, _DayInfo> days;
  final ValueChanged<DateTime> onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final lead = (month.weekday - weekStart + 7) % 7;
    final cells = lead + daysInMonth;
    final rows = (cells / 7).ceil();
    final today = DateTime.now();
    final wdFmt = DateFormat.E();

    // Weekday labels starting at weekStart. 2024-01-01 was a Monday.
    final labels = [
      for (var i = 0; i < 7; i++)
        wdFmt.format(DateTime(2024, 1, 1 + (weekStart - 1 + i) % 7)),
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Column(
        children: [
          Row(
            children: [
              for (final l in labels)
                Expanded(
                  child: Center(
                    child: Text(l,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: scheme.onSurfaceVariant)),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          for (var r = 0; r < rows; r++)
            Row(
              children: [
                for (var c = 0; c < 7; c++)
                  Expanded(
                    child: _cell(context, r * 7 + c - lead + 1, daysInMonth,
                        today, scheme),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _cell(BuildContext context, int day, int daysInMonth, DateTime today,
      ColorScheme scheme) {
    if (day < 1 || day > daysInMonth) return const SizedBox(height: 64);
    final date = DateTime(month.year, month.month, day);
    final info = days[day];
    final isSel = selected == date;
    final isToday = today.year == date.year &&
        today.month == date.month &&
        today.day == date.day;
    return GestureDetector(
      onTap: () => onTap(date),
      child: Container(
        height: 64,
        margin: const EdgeInsets.all(1.5),
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 3),
        decoration: BoxDecoration(
          color: isSel
              ? scheme.primaryContainer
              : scheme.surfaceContainerHighest.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(8),
          border: isToday ? Border.all(color: scheme.primary, width: 1.5) : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text('$day',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: isToday ? FontWeight.bold : FontWeight.w500)),
                const Spacer(),
                if (info?.hasDue ?? false) _dot(scheme.error),
                if (info?.hasUpcoming ?? false) _dot(scheme.tertiary),
              ],
            ),
            const Spacer(),
            if ((info?.expense ?? 0) > 0)
              _amt('-${_compact(info!.expense)}', kExpenseColor),
            if ((info?.income ?? 0) > 0)
              _amt('+${_compact(info!.income)}', kIncomeColor),
          ],
        ),
      ),
    );
  }

  Widget _dot(Color c) => Container(
        width: 6,
        height: 6,
        margin: const EdgeInsets.only(left: 2),
        decoration: BoxDecoration(color: c, shape: BoxShape.circle),
      );

  Widget _amt(String s, Color c) => FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerRight,
        child: Text(s,
            style: TextStyle(
                fontSize: 10, color: c, fontWeight: FontWeight.w600)),
      );

  static String _compact(double v) {
    if (v >= 1e6) return '${(v / 1e6).toStringAsFixed(v >= 1e7 ? 0 : 1)}M';
    if (v >= 1e3) return '${(v / 1e3).toStringAsFixed(v >= 1e4 ? 0 : 1)}k';
    return v.toStringAsFixed(0);
  }
}
