import 'package:flutter/material.dart';

import '../data/models.dart';
import '../state/app_state.dart';
import '../util/format.dart';
import 'transaction_edit.dart';

/// Asks how much to pay, then opens a prefilled transfer into the card.
Future<void> showPayCard(BuildContext context, CardSummary c) async {
  final cur = c.card.currency;
  final last = c.last;
  final options = <(String, String, double)>[
    if (last != null && last.remaining > 0)
      ('Statement balance', 'Pay the full statement, no interest',
          last.remaining),
    if (last != null && last.minimumDue > 0)
      ('Minimum due', '${fmtAmount(last.minPct)}% of statement',
          last.minimumDue),
    if (c.owedNow > 0)
      ('Current balance', 'Everything spent so far, incl. this cycle',
          c.owedNow),
  ];

  final choice = await showModalBottomSheet<double>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            title: Text('Pay ${c.card.fullName}'),
            subtitle: last == null
                ? null
                : Text('Due ${shortDateFmt.format(last.dueDate)}'),
          ),
          for (final (title, sub, amount) in options)
            ListTile(
              leading: const Icon(Icons.payments_outlined),
              title: Text(title),
              subtitle: Text(sub),
              trailing: Text(fmtMoney(amount, cur),
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              onTap: () => Navigator.pop(ctx, amount),
            ),
          ListTile(
            leading: const Icon(Icons.edit_outlined),
            title: const Text('Other amount'),
            onTap: () => Navigator.pop(ctx, 0.0),
          ),
        ],
      ),
    ),
  );
  if (choice == null || !context.mounted) return;

  final state = AppScope.read(context);
  // Default source: a non-credit account in the same currency, if any.
  final sources =
      state.activeAccounts.where((a) => !a.type.isLiability && a.id != c.card.id);
  final from = sources.where((a) => a.currency == cur).firstOrNull ??
      sources.firstOrNull;

  await Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => TransactionEditScreen(
        initialType: TxType.transfer,
        initialAccountId: from?.id,
        initialToAccountId: c.card.id,
        initialAmount: choice > 0 ? choice : null,
        initialNote: 'Card payment',
      ),
    ),
  );
}
