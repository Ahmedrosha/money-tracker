import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../data/models.dart';
import '../state/app_state.dart';
import '../util/format.dart';
import 'pay_card.dart';
import 'transaction_edit.dart';
import 'widgets.dart';

/// Calendar tab: all accounts, or one picked from the filter.
class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  int? _accountId;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final account = state.accountById(_accountId);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Calendar'),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.filter_list),
            label: Text(account?.name ?? 'All Accounts',
                overflow: TextOverflow.ellipsis),
            onPressed: () async {
              final id = await pickAccount(context,
                  current: _accountId,
                  title: 'Show Calendar for',
                  allowAll: true);
              if (id == null) return;
              setState(() => _accountId = id == -1 ? null : id);
            },
          ),
        ],
      ),
      body: CalendarView(key: ValueKey(_accountId), accountId: _accountId),
    );
  }
}

class _DayInfo {
  double outflow = 0;
  double inflow = 0;
  bool hasUpcoming = false;
  bool hasDue = false;
  bool hasCard = false;
  final List<Txn> txns = [];
  final List<Occurrence> pending = [];
  final List<_CardEvent> cardEvents = [];
}

class _CardEvent {
  final CardSummary card;
  final String label;
  final double? amount;
  final bool payable;
  _CardEvent(this.card, this.label, this.amount, {this.payable = false});
}

/// Month grid + list for the selected day. When [accountId] is set, only
/// that account is shown and transfers count as money in / out of it.
class CalendarView extends StatefulWidget {
  const CalendarView({super.key, this.accountId, this.shrinkWrap = false});

  final int? accountId;

  /// Use inside another scrollable.
  final bool shrinkWrap;

  @override
  State<CalendarView> createState() => _CalendarViewState();
}

class _CalendarViewState extends State<CalendarView> {
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

  bool _touches(int? a, int? b) =>
      widget.accountId == null || a == widget.accountId || b == widget.accountId;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final key = '${state.version}-${_month.year}-${_month.month}';
    if (key != _loadedKey) {
      _loadedKey = key;
      _future = state.db.transactions(
        from: _month,
        to: DateTime(_month.year, _month.month + 1),
        accountId: widget.accountId,
      );
    }
    final monthEnd = DateTime(_month.year, _month.month + 1);

    return FutureBuilder<List<Txn>>(
      future: _future,
      builder: (context, snap) {
        final days = <int, _DayInfo>{};
        _DayInfo info(int d) => days.putIfAbsent(d, () => _DayInfo());

        for (final t in snap.data ?? const <Txn>[]) {
          final i = info(t.date.day);
          i.txns.add(t);
          if (t.isFuture) i.hasUpcoming = true;
          if (widget.accountId == null) {
            final cur = state.accountById(t.accountId)?.currency ??
                state.baseCurrency;
            if (t.type == TxType.expense) i.outflow += state.toBase(t.amount, cur);
            if (t.type == TxType.income) i.inflow += state.toBase(t.amount, cur);
          } else {
            final id = widget.accountId!;
            if (t.type == TxType.income) {
              i.inflow += t.amount;
            } else if (t.type == TxType.expense) {
              i.outflow += t.amount;
            } else if (t.toAccountId == id && t.accountId != id) {
              i.inflow += t.toAmount ?? t.amount;
            } else if (t.accountId == id && t.toAccountId != id) {
              i.outflow += t.amount;
            }
          }
        }

        for (final o in state.pendingOccurrences(_month, monthEnd)) {
          if (!_touches(o.rule.accountId, o.rule.toAccountId)) continue;
          final i = info(o.date.day);
          i.pending.add(o);
          if (o.isDue) {
            i.hasDue = true;
          } else {
            i.hasUpcoming = true;
          }
        }

        // Credit card closing and due dates.
        for (final c in state.cards.values) {
          final a = c.card;
          if (a.archived || !a.hasCycle) continue;
          if (widget.accountId != null && a.id != widget.accountId) continue;
          void add(DateTime d, _CardEvent e) {
            if (d.isBefore(_month) || !d.isBefore(monthEnd)) return;
            final i = info(d.day);
            i.cardEvents.add(e);
            i.hasCard = true;
          }

          final last = c.last;
          if (last != null) {
            add(last.closeDate,
                _CardEvent(c, 'Statement Closed', last.amount));
            add(
                last.dueDate,
                _CardEvent(
                    c,
                    last.settled ? 'Statement paid' : 'Payment due',
                    last.settled ? last.amount : last.remaining,
                    payable: !last.settled));
          }
          if (c.nextClose != null) {
            add(c.nextClose!, _CardEvent(c, 'Statement closes', null));
            add(dueDateAfter(c.nextClose!, a.dueDay!),
                _CardEvent(c, 'Next payment due', null));
          }
          // Show the cycle days for months further away as well.
          final close = cycleCloseIn(_month.year, _month.month, a.statementDay!);
          if (c.nextClose != null && close.isAfter(c.nextClose!)) {
            add(close, _CardEvent(c, 'Statement closes', null));
            final due = dueDateAfter(
                cycleCloseIn(_month.year, _month.month - 1, a.statementDay!),
                a.dueDay!);
            if (due.isAfter(dueDateAfter(c.nextClose!, a.dueDay!))) {
              add(due, _CardEvent(c, 'Payment due', null));
            }
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
        final currency = widget.accountId == null
            ? state.baseCurrency
            : (state.accountById(widget.accountId)?.currency ?? '');

        final children = <Widget>[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                IconButton(
                    onPressed: () => _shift(-1),
                    icon: const Icon(Icons.chevron_left)),
                Expanded(
                  child: Center(
                    child: TextButton(
                      onPressed: () {
                        final now = DateTime.now();
                        setState(() {
                          _month = DateTime(now.year, now.month);
                          _selected = DateTime(now.year, now.month, now.day);
                        });
                      },
                      child: Text(monthFmt.format(_month),
                          style: Theme.of(context).textTheme.titleMedium),
                    ),
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
            padding: const EdgeInsets.fromLTRB(16, 0, 8, 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(dayFmt.format(_selected),
                      style: Theme.of(context).textTheme.titleSmall),
                ),
                if (sel != null && sel.outflow > 0)
                  Text('-${fmtAmount(sel.outflow)}',
                      style: const TextStyle(
                          color: kExpenseColor, fontWeight: FontWeight.w600)),
                if (sel != null && sel.inflow > 0) ...[
                  const SizedBox(width: 12),
                  Text('+${fmtAmount(sel.inflow)}',
                      style: const TextStyle(
                          color: kIncomeColor, fontWeight: FontWeight.w600)),
                ],
                IconButton(
                  tooltip: 'Add on This Day',
                  icon: const Icon(Icons.add_circle_outline),
                  onPressed: () {
                    final now = DateTime.now();
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => TransactionEditScreen(
                          initialAccountId: widget.accountId,
                          initialDate: DateTime(_selected.year,
                              _selected.month, _selected.day, now.hour,
                              now.minute),
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          if (widget.accountId != null && currency.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
              child: Text('Amounts in $currency',
                  style: Theme.of(context).textTheme.bodySmall),
            ),
          for (final e in sel?.cardEvents ?? const <_CardEvent>[])
            Card(
              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: ListTile(
                leading: const Icon(Icons.credit_card),
                title: Text('${e.label} · ${e.card.card.name}'),
                subtitle: e.amount == null
                    ? null
                    : Text(fmtMoney(e.amount!, e.card.card.currency)),
                trailing: e.payable
                    ? FilledButton.tonal(
                        onPressed: () => showPayCard(context, e.card),
                        child: const Text('Pay'),
                      )
                    : null,
              ),
            ),
          if (selItems.isEmpty && (sel?.cardEvents.isEmpty ?? true))
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: Text('Nothing on this day')),
            ),
          for (final (_, item) in selItems)
            if (item is Txn)
              TxnTile(
                txn: item,
                perspectiveAccountId: widget.accountId,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => TransactionEditScreen(txn: item)),
                ),
              )
            else if (item is Occurrence)
              OccurrenceTile(occurrence: item),
        ];

        if (widget.shrinkWrap) {
          return Column(children: children);
        }
        return ListView(
          padding: const EdgeInsets.only(bottom: 96),
          children: children,
        );
      },
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
                if (info?.hasCard ?? false) _dot(scheme.secondary),
                if (info?.hasDue ?? false) _dot(scheme.error),
                if (info?.hasUpcoming ?? false) _dot(scheme.tertiary),
              ],
            ),
            const Spacer(),
            if ((info?.outflow ?? 0) > 0)
              _amt('-${_compact(info!.outflow)}', kExpenseColor),
            if ((info?.inflow ?? 0) > 0)
              _amt('+${_compact(info!.inflow)}', kIncomeColor),
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
    if (amountsHidden) return '•';
    if (v >= 1e6) return '${(v / 1e6).toStringAsFixed(v >= 1e7 ? 0 : 1)}M';
    if (v >= 1e3) return '${(v / 1e3).toStringAsFixed(v >= 1e4 ? 0 : 1)}k';
    return v.toStringAsFixed(0);
  }
}
