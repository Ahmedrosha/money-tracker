import 'package:flutter/material.dart';

import '../data/models.dart';
import '../state/app_state.dart';
import '../util/currencies.dart';
import '../util/format.dart';
import '../util/icons.dart';

const Color kIncomeColor = Color(0xFF2E7D32);
const Color kExpenseColor = Color(0xFFC62828);

Color amountColor(BuildContext context, double v) {
  if (v > 0.004) return kIncomeColor;
  if (v < -0.004) return kExpenseColor;
  return Theme.of(context).colorScheme.onSurfaceVariant;
}

/// A labelled dropdown that looks like a text field.
class LabeledDropdown<T> extends StatelessWidget {
  const LabeledDropdown({
    super.key,
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
    this.hint,
  });

  final String label;
  final T? value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?>? onChanged;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final hasValue = value != null && items.any((i) => i.value == value);
    return InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: hasValue ? value : null,
          isExpanded: true,
          hint: hint == null ? null : Text(hint!),
          items: items,
          onChanged: onChanged,
        ),
      ),
    );
  }
}

class CategoryAvatar extends StatelessWidget {
  const CategoryAvatar({super.key, this.category, this.transfer = false});

  final Category? category;
  final bool transfer;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (transfer) {
      return CircleAvatar(
        backgroundColor: scheme.secondaryContainer,
        foregroundColor: scheme.onSecondaryContainer,
        child: const Icon(Icons.swap_horiz),
      );
    }
    final color = Color(category?.color ?? 0xFF607D8B);
    return CircleAvatar(
      backgroundColor: color.withValues(alpha: 0.18),
      foregroundColor: color,
      child: Icon(categoryIcon(category?.icon ?? 'other')),
    );
  }
}

/// One transaction row. When [perspectiveAccountId] is set, transfers are
/// shown as positive or negative for that account.
class TxnTile extends StatelessWidget {
  const TxnTile({
    super.key,
    required this.txn,
    this.perspectiveAccountId,
    this.onTap,
  });

  final Txn txn;
  final int? perspectiveAccountId;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final account = state.accountById(txn.accountId);
    final toAccount = state.accountById(txn.toAccountId);
    final category = state.categoryById(txn.categoryId);

    String title;
    String subtitle;
    double signed;
    String currency = account?.currency ?? '';

    switch (txn.type) {
      case TxType.expense:
        title = txn.payee.isNotEmpty
            ? txn.payee
            : (category?.name ?? 'Expense');
        subtitle = [
          if (txn.payee.isNotEmpty && category != null) category.name,
          account?.name ?? '?',
        ].join(' · ');
        signed = -txn.amount;
        break;
      case TxType.income:
        title = txn.payee.isNotEmpty
            ? txn.payee
            : (category?.name ?? 'Income');
        subtitle = [
          if (txn.payee.isNotEmpty && category != null) category.name,
          account?.name ?? '?',
        ].join(' · ');
        signed = txn.amount;
        break;
      case TxType.transfer:
        title = 'Transfer';
        subtitle = '${account?.name ?? '?'} → ${toAccount?.name ?? '?'}';
        if (perspectiveAccountId != null &&
            perspectiveAccountId == txn.toAccountId) {
          signed = txn.toAmount ?? txn.amount;
          currency = toAccount?.currency ?? currency;
        } else if (perspectiveAccountId != null) {
          signed = -txn.amount;
        } else {
          signed = txn.amount;
        }
        break;
    }
    if (txn.note.isNotEmpty) subtitle = '$subtitle · ${txn.note}';

    final isNeutralTransfer =
        txn.type == TxType.transfer && perspectiveAccountId == null;

    return ListTile(
      onTap: onTap,
      leading: CategoryAvatar(
          category: category, transfer: txn.type == TxType.transfer),
      title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: Text(
        '${signed > 0 && !isNeutralTransfer ? '+' : ''}${fmtAmount(signed)} $currency',
        style: TextStyle(
          fontWeight: FontWeight.w600,
          color: isNeutralTransfer
              ? Theme.of(context).colorScheme.onSurfaceVariant
              : amountColor(context, signed),
        ),
      ),
    );
  }
}

/// Searchable currency picker. Returns the selected code.
Future<String?> pickCurrency(BuildContext context, {String? current}) {
  final state = AppScope.read(context);
  final codes = <String>{...kCurrencyNames.keys, ...state.rates.keys}.toList()
    ..sort();
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => _CurrencySheet(codes: codes, current: current),
  );
}

class _CurrencySheet extends StatefulWidget {
  const _CurrencySheet({required this.codes, this.current});

  final List<String> codes;
  final String? current;

  @override
  State<_CurrencySheet> createState() => _CurrencySheetState();
}

class _CurrencySheetState extends State<_CurrencySheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final q = _query.trim().toUpperCase();
    final list = widget.codes.where((c) {
      if (q.isEmpty) return true;
      return c.contains(q) || currencyName(c).toUpperCase().contains(q);
    }).toList();
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.75,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              autofocus: false,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Search currency',
                border: OutlineInputBorder(),
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: list.length,
              itemBuilder: (ctx, i) {
                final c = list[i];
                return ListTile(
                  title: Text(c),
                  subtitle: Text(currencyName(c)),
                  trailing: c == widget.current
                      ? const Icon(Icons.check)
                      : null,
                  onTap: () => Navigator.pop(context, c),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

Future<bool> confirmDialog(BuildContext context,
    {required String title, required String message, String ok = 'Delete'}) async {
  final res = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel')),
        FilledButton(
            onPressed: () => Navigator.pop(ctx, true), child: Text(ok)),
      ],
    ),
  );
  return res ?? false;
}

void showSnack(BuildContext context, String msg) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(msg)));
}
