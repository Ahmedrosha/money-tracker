import 'package:flutter/material.dart';

import '../data/models.dart';
import '../state/app_state.dart';
import '../util/format.dart';
import 'account_edit.dart';
import 'pay_card.dart';
import 'statement_detail.dart';
import 'widgets.dart';

/// Credit card block on the account screen: limit, statement, pay.
class CardPanel extends StatelessWidget {
  const CardPanel({super.key, required this.summary});

  final CardSummary summary;

  @override
  Widget build(BuildContext context) {
    final a = summary.card;
    final cur = a.currency;
    final scheme = Theme.of(context).colorScheme;
    final last = summary.last;
    final limit = a.creditLimit;
    final small = Theme.of(context).textTheme.bodySmall;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (limit != null && limit > 0)
          Card(
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text('Available Limit',
                            style: Theme.of(context).textTheme.titleSmall),
                      ),
                      Text(fmtMoney(summary.available!, cur),
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: summary.available! < 0
                                  ? kExpenseColor
                                  : kIncomeColor)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: (summary.used / limit).clamp(0.0, 1.0),
                      minHeight: 10,
                      backgroundColor: scheme.surfaceContainerHighest,
                      color: summary.used > limit * 0.8
                          ? kExpenseColor
                          : scheme.primary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Limit ${fmtAmount(limit)} · owed ${fmtAmount(summary.owedNow)}'
                    '${summary.futureInstallments > 0 ? ' · future installments ${fmtAmount(summary.futureInstallments)}' : ''}',
                    style: small,
                  ),
                ],
              ),
            ),
          ),
        if (!a.hasCycle)
          Card(
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('Set the statement closing and due days'),
              subtitle: const Text('to see statements and amounts due'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => AccountEditScreen(account: a)),
              ),
            ),
          ),
        if (last != null)
          Card(
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            color: last.overdue
                ? scheme.errorContainer
                : (last.settled ? null : scheme.secondaryContainer),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Statement ${shortDateFmt.format(last.closeDate)}',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                      ),
                      if (last.settled)
                        TagChip('Paid', color: kIncomeColor)
                      else if (last.overdue)
                        TagChip('Overdue', color: scheme.error)
                      else
                        TagChip('Due ${shortDateFmt.format(last.dueDate)}',
                            color: scheme.secondary),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _row('Statement Amount', fmtMoney(last.amount, cur)),
                  _row('Paid Since Closing', fmtMoney(last.paid, cur)),
                  _row('Remaining Due', fmtMoney(last.remaining, cur),
                      bold: true),
                  _row('Minimum Due', fmtMoney(last.minimumDue, cur)),
                  _row('Due Date', dayFmt.format(last.dueDate)),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      TextButton(
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => StatementDetailScreen(
                                  card: a, close: last.closeDate)),
                        ),
                        child: const Text('Details'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => StatementsScreen(card: a)),
                        ),
                        child: const Text('All Statements'),
                      ),
                      const Spacer(),
                      FilledButton.icon(
                        onPressed: () => showPayCard(context, summary),
                        icon: const Icon(Icons.payments_outlined),
                        label: const Text('Pay'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        if (summary.nextClose != null)
          Card(
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: ListTile(
              leading: const Icon(Icons.autorenew),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => StatementDetailScreen(
                      card: a, close: summary.nextClose!, open: true),
                ),
              ),
              title: Text(
                  'Current Cycle: ${fmtMoney(summary.cycleSpent, cur)} spent'),
              subtitle: Text(
                  'Closes ${dayFmt.format(summary.nextClose!)} · due '
                  '${shortDateFmt.format(dueDateAfter(summary.nextClose!, a.dueDay!))}'),
            ),
          ),
      ],
    );
  }

  Widget _row(String label, String value, {bool bold = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            Expanded(child: Text(label)),
            Text(value,
                style: TextStyle(
                    fontWeight: bold ? FontWeight.bold : FontWeight.normal)),
          ],
        ),
      );
}

/// Last 12 statements of a card.
class StatementsScreen extends StatelessWidget {
  const StatementsScreen({super.key, required this.card});

  final Account card;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    return Scaffold(
      appBar: AppBar(title: Text('${card.name} statements')),
      body: FutureBuilder<List<CardStatement>>(
        // Rebuilds when data changes because AppScope.of subscribes.
        key: ValueKey(state.version),
        future: state.statementHistory(card),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final list = snap.data!;
          return ListView.separated(
            itemCount: list.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final st = list[i];
              final status = st.amount <= 0
                  ? 'Nothing due'
                  : st.settled
                      ? 'Paid'
                      : (st.overdue
                          ? 'Unpaid · ${fmtAmount(st.remaining)} left'
                          : 'Due ${shortDateFmt.format(st.dueDate)} · ${fmtAmount(st.remaining)} left');
              return ListTile(
                title: Text('Closed ${shortDateFmt.format(st.closeDate)}'),
                subtitle: Text(
                    '$status\nPaid in cycle after closing: ${fmtAmount(st.paid)}'),
                isThreeLine: true,
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(fmtMoney(st.amount, card.currency),
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    const Icon(Icons.chevron_right),
                  ],
                ),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        StatementDetailScreen(card: card, close: st.closeDate),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
