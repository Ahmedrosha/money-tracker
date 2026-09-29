import 'package:flutter/material.dart';

import '../data/models.dart';
import '../state/app_state.dart';
import '../util/format.dart';
import 'transaction_edit.dart';
import 'widgets.dart';

/// One card cycle: from the day after [prevClose] up to [close].
/// [open] = the cycle hasn't closed yet.
class StatementDetailScreen extends StatelessWidget {
  const StatementDetailScreen({
    super.key,
    required this.card,
    required this.close,
    this.open = false,
  });

  final Account card;
  final DateTime close;
  final bool open;

  DateTime get prevClose =>
      cycleCloseIn(close.year, close.month - 1, card.statementDay!);

  DateTime get nextClose =>
      cycleCloseIn(close.year, close.month + 1, card.statementDay!);

  /// Noon on the given day: safely inside that day's cycle.
  static DateTime _noon(DateTime d) => DateTime(d.year, d.month, d.day, 12);

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final cur = card.currency;
    return Scaffold(
      appBar: AppBar(
        title: Text(open ? 'Current Cycle' : 'Statement ${shortDateFmt.format(close)}'),
      ),
      body: FutureBuilder<_Data>(
        key: ValueKey('${state.version}-$close'),
        future: _load(state),
        builder: (context, snap) {
          final d = snap.data;
          if (d == null) return const Center(child: CircularProgressIndicator());
          final small = Theme.of(context).textTheme.bodySmall;
          final charges = d.txns.where((t) => _effect(t) < 0).toList();
          final credits = d.txns.where((t) => _effect(t) >= 0).toList();
          return ListView(
            padding: const EdgeInsets.only(bottom: 32),
            children: [
              Card(
                margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                          '${shortDateFmt.format(prevClose.add(const Duration(days: 1)))} – ${shortDateFmt.format(close)}',
                          style: Theme.of(context).textTheme.titleSmall),
                      Text(
                          open
                              ? 'Closes ${dayFmt.format(close)} · due ${shortDateFmt.format(dueDateAfter(close, card.dueDay!))}'
                              : 'Due ${dayFmt.format(dueDateAfter(close, card.dueDay!))}',
                          style: small),
                      const SizedBox(height: 12),
                      _row('Previous Balance', fmtMoney(d.previous, cur)),
                      _row('New Charges', '+ ${fmtMoney(d.charges, cur)}'),
                      _row('Payments & Credits', '− ${fmtMoney(d.credits, cur)}'),
                      const Divider(),
                      _row(open ? 'Owed So Far' : 'Statement Amount',
                          fmtMoney(d.closing, cur),
                          bold: true),
                      if (!open) ...[
                        _row('Paid After Closing', fmtMoney(d.paidAfter, cur)),
                        _row('Remaining',
                            fmtMoney((d.closing - d.paidAfter).clamp(0, double.infinity), cur)),
                      ],
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                child: Text(
                    'Tap a transaction to move it to the previous or next statement if the bank counted it there.',
                    style: small),
              ),
              _header(context, state, 'Charges', charges.length, d.charges, cur),
              if (!state.isCollapsed('stmt:Charges'))
                for (final t in charges) _tile(context, state, t),
              _header(context, state, 'Payments & Credits', credits.length, d.credits, cur),
              if (!state.isCollapsed('stmt:Payments & Credits'))
                for (final t in credits) _tile(context, state, t),
            ],
          );
        },
      ),
    );
  }

  Future<_Data> _load(AppState state) async {
    final txns = await state.db.statementTxns(card.id!, prevClose, close);
    final prevBal = await state.db.balanceAsOf(card.id!, prevClose);
    final closeBal = await state.db.balanceAsOf(card.id!, close);
    var charges = 0.0, credits = 0.0;
    for (final t in txns) {
      final e = _effect(t);
      if (e < 0) {
        charges -= e;
      } else {
        credits += e;
      }
    }
    var paidAfter = 0.0;
    if (!open) {
      final now = DateTime.now();
      final until = nextClose.isAfter(now) ? now : nextClose;
      paidAfter = await state.db.creditsBetween(card.id!, close, until);
    }
    return _Data(txns, -prevBal, charges, credits, -closeBal, paidAfter);
  }

  /// Effect on the card: negative = charge, positive = payment / credit.
  double _effect(Txn t) {
    if (t.type == TxType.transfer && t.toAccountId == card.id) {
      return t.toAmount ?? t.amount;
    }
    if (t.type == TxType.income) return t.amount;
    return -t.amount;
  }

  DateTime _countsOn(Txn t) =>
      t.type == TxType.transfer && t.toAccountId == card.id
          ? (t.toPostDate ?? t.date)
          : t.effectivePostDate;

  Widget _header(BuildContext context, AppState state, String title, int n,
          double sum, String cur) =>
      InkWell(
        onTap: () => state.toggleCollapsed('stmt:$title'),
        child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 16, 16, 4),
        child: Row(
          children: [
            CollapseArrow(collapsed: state.isCollapsed('stmt:$title')),
            const SizedBox(width: 4),
            Expanded(
              child: Text('$title · $n',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.bold)),
            ),
            Text(fmtMoney(sum, cur),
                style: const TextStyle(fontWeight: FontWeight.w600)),
          ],
        ),
      ),
      );

  Widget _tile(BuildContext context, AppState state, Txn t) {
    final e = _effect(t);
    final other = t.type == TxType.transfer
        ? state.accountById(t.toAccountId == card.id ? t.accountId : t.toAccountId)
        : null;
    final cat = state.categoryById(t.categoryId);
    final title = t.type == TxType.transfer
        ? (t.toAccountId == card.id
            ? 'Payment from ${other?.name ?? '?'}'
            : 'Transfer to ${other?.name ?? '?'}')
        : (t.payee.isNotEmpty ? t.payee : (cat?.name ?? t.type.label));
    final on = _countsOn(t);
    final moved = on.year != t.date.year || on.month != t.date.month || on.day != t.date.day;
    return ListTile(
      leading: SizedBox(
        width: 36,
        height: 36,
        child: FittedBox(
          child: CategoryAvatar(
              category: cat, transfer: t.type == TxType.transfer),
        ),
      ),
      title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        '${shortDateFmt.format(t.date)}'
        '${moved ? ' · counts on ${shortDateFmt.format(on)}' : ''}'
        '${t.planIndex != null ? ' · installment ${t.planIndex}' : ''}',
      ),
      trailing: Text(
        '${e >= 0 ? '+' : '−'}${fmtAmount(e.abs())}',
        style: TextStyle(
            fontWeight: FontWeight.w600,
            color: e >= 0 ? kIncomeColor : kExpenseColor),
      ),
      onTap: () => _actions(context, state, t, title),
    );
  }

  Future<void> _actions(
      BuildContext context, AppState state, Txn t, String title) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(title, style: Theme.of(ctx).textTheme.titleMedium),
            ),
            ListTile(
              leading: const Icon(Icons.arrow_back),
              title: const Text('Move to Previous Statement'),
              subtitle: Text('Counts on ${shortDateFmt.format(prevClose)}'),
              onTap: () => Navigator.pop(ctx, 'prev'),
            ),
            ListTile(
              leading: const Icon(Icons.arrow_forward),
              title: Text(open ? 'Move to Next Cycle' : 'Move to Next Statement'),
              subtitle: Text(
                  'Counts on ${shortDateFmt.format(close.add(const Duration(days: 1)))}'),
              onTap: () => Navigator.pop(ctx, 'next'),
            ),
            if (_movedAway(t))
              ListTile(
                leading: const Icon(Icons.undo),
                title: const Text('Back to Its Own Date'),
                subtitle: Text(shortDateFmt.format(t.date)),
                onTap: () => Navigator.pop(ctx, 'reset'),
              ),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Edit Transaction'),
              onTap: () => Navigator.pop(ctx, 'edit'),
            ),
          ],
        ),
      ),
    );
    if (choice == null || !context.mounted) return;
    switch (choice) {
      case 'prev':
        await state.moveToStatement(t, card, _noon(prevClose));
        if (context.mounted) showSnack(context, 'Moved to the statement of ${shortDateFmt.format(prevClose)}');
      case 'next':
        await state.moveToStatement(t, card, _noon(close.add(const Duration(days: 1))));
        if (context.mounted) {
          showSnack(context,
              'Moved to the statement of ${shortDateFmt.format(nextClose)}');
        }
      case 'reset':
        await state.moveToStatement(t, card, t.date);
      case 'edit':
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => TransactionEditScreen(txn: t)),
        );
    }
  }

  bool _movedAway(Txn t) {
    final on = _countsOn(t);
    return on.year != t.date.year || on.month != t.date.month || on.day != t.date.day;
  }

  Widget _row(String label, String value, {bool bold = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            Expanded(child: Text(label)),
            Text(value,
                style: TextStyle(fontWeight: bold ? FontWeight.bold : FontWeight.normal)),
          ],
        ),
      );
}

class _Data {
  final List<Txn> txns;
  final double previous, charges, credits, closing, paidAfter;
  _Data(this.txns, this.previous, this.charges, this.credits, this.closing,
      this.paidAfter);
}
