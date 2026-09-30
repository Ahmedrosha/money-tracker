import 'package:flutter/material.dart';

import '../data/models.dart';
import '../state/app_state.dart';
import '../util/format.dart';
import 'transaction_edit.dart';
import 'widgets.dart';
import '../l10n/l10n.dart';

class RecurringScreen extends StatelessWidget {
  const RecurringScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final active = state.rules.where((r) => !r.finished).toList()
      ..sort((a, b) =>
          a.occurrence(a.nextIndex).compareTo(b.occurrence(b.nextIndex)));
    final ended = state.rules.where((r) => r.finished).toList();

    return Scaffold(
      appBar: AppBar(title: Text(tr('Recurring Items'))),
      body: state.rules.isEmpty
          ? Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  tr('No recurring items yet.\nTurn on "Repeat" when adding a transaction.'),
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : ListView(
              children: [
                for (final r in active) _tile(context, state, r),
                if (ended.isNotEmpty)
                  ExpansionTile(
                    title: Text(tr('Ended (${ended.length})')),
                    children: [for (final r in ended) _tile(context, state, r)],
                  ),
              ],
            ),
    );
  }

  Widget _tile(BuildContext context, AppState state, RecurringRule r) {
    final account = state.accountById(r.accountId);
    final category = state.categoryById(r.categoryId);
    final title = r.type == TxType.transfer
        ? tr('Transfer → ${state.accountById(r.toAccountId)?.fullName ?? '?'}')
        : (r.payee.isNotEmpty ? r.payee : (category?.name ?? r.type.label));
    final signed = r.type == TxType.expense ? -r.amount : r.amount;
    return ListTile(
      leading: CategoryAvatar(
          category: category, transfer: r.type == TxType.transfer),
      title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        '${r.scheduleLabel}\n'
        '${r.finished ? tr('Ended') : tr('Next: ${shortDateFmt.format(r.occurrence(r.nextIndex))}')}'
        ' · ${account?.fullName ?? '?'}',
      ),
      isThreeLine: true,
      trailing: Text(
        '${fmtAmount(signed)} ${account?.currency ?? ''}',
        style: TextStyle(
            fontWeight: FontWeight.w600,
            color: r.type == TxType.transfer
                ? null
                : amountColor(context, signed)),
      ),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => TransactionEditScreen(rule: r)),
      ),
    );
  }
}
