import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../data/models.dart';
import '../state/app_state.dart';
import '../util/currencies.dart';
import '../util/format.dart';
import '../util/icons.dart';
import 'transaction_edit.dart';

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
          account?.fullName ?? '?',
        ].join(' · ');
        signed = -txn.amount;
        break;
      case TxType.income:
        title = txn.payee.isNotEmpty
            ? txn.payee
            : (category?.name ?? 'Income');
        subtitle = [
          if (txn.payee.isNotEmpty && category != null) category.name,
          account?.fullName ?? '?',
        ].join(' · ');
        signed = txn.amount;
        break;
      case TxType.transfer:
        title = 'Transfer';
        subtitle = '${account?.fullName ?? '?'} → ${toAccount?.fullName ?? '?'}';
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
    if (txn.postedLater) {
      subtitle = '$subtitle · Posted ${DateFormat('d MMM').format(txn.postDate!)}';
    }
    if (txn.note.isNotEmpty) subtitle = '$subtitle · ${txn.note}';

    final isNeutralTransfer =
        txn.type == TxType.transfer && perspectiveAccountId == null;
    final plan = state.plans[txn.planId];
    final future = txn.isFuture;

    return Opacity(
      opacity: future ? 0.7 : 1,
      child: ListTile(
      onTap: onTap,
      leading: CategoryAvatar(
          category: category, transfer: txn.type == TxType.transfer),
      title: Row(
        children: [
          Flexible(
              child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis)),
          if (txn.planIndex != null)
            TagChip('${txn.planIndex}/${plan?.months ?? '?'}'),
          if (txn.recurringId != null)
            const Padding(
              padding: EdgeInsets.only(left: 6),
              child: Icon(Icons.repeat, size: 14),
            ),
          if (future)
            TagChip('Upcoming',
                color: Theme.of(context).colorScheme.tertiary)
          else if (txn.isPending)
            TagChip('Pending', color: Theme.of(context).colorScheme.secondary),
        ],
      ),
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
      ),
    );
  }
}

/// A recurring item that has not been confirmed yet.
class OccurrenceTile extends StatelessWidget {
  const OccurrenceTile({super.key, required this.occurrence, this.showDate = false});

  final Occurrence occurrence;
  final bool showDate;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final r = occurrence.rule;
    final account = state.accountById(r.accountId);
    final toAccount = state.accountById(r.toAccountId);
    final category = state.categoryById(r.categoryId);
    final due = occurrence.isDue;
    final canAct = state.isNextOccurrence(occurrence);

    final title = r.type == TxType.transfer
        ? 'Transfer'
        : (r.payee.isNotEmpty ? r.payee : (category?.name ?? r.type.label));
    final sub = r.type == TxType.transfer
        ? '${account?.fullName ?? '?'} → ${toAccount?.fullName ?? '?'}'
        : (account?.fullName ?? '?');
    final signed = r.type == TxType.income
        ? r.amount
        : (r.type == TxType.expense ? -r.amount : r.amount);
    final scheme = Theme.of(context).colorScheme;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      color: due ? scheme.tertiaryContainer.withValues(alpha: 0.5) : null,
      child: ListTile(
        onTap: () => openOccurrence(context, occurrence),
        leading: CategoryAvatar(
            category: category, transfer: r.type == TxType.transfer),
        title: Row(
          children: [
            Flexible(
                child:
                    Text(title, maxLines: 1, overflow: TextOverflow.ellipsis)),
            TagChip(due ? 'Due' : 'Upcoming',
                color: due ? scheme.error : scheme.tertiary),
          ],
        ),
        subtitle: Text(
          [
            if (showDate) shortDateFmt.format(occurrence.date),
            sub,
          ].join(' · '),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              '${signed > 0 && r.type != TxType.transfer ? '+' : ''}${fmtAmount(signed)} ${account?.currency ?? ''}',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: r.type == TxType.transfer
                    ? scheme.onSurfaceVariant
                    : amountColor(context, signed),
              ),
            ),
            if (canAct)
              Text('Tap to confirm',
                  style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

/// Bottom sheet with Confirm / Edit & confirm / Skip / Edit rule.
Future<void> openOccurrence(BuildContext context, Occurrence o) async {
  final state = AppScope.read(context);
  final canAct = state.isNextOccurrence(o);
  final choice = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            title: Text(dayFmt.format(o.date)),
            subtitle: Text(o.rule.scheduleLabel),
          ),
          if (!canAct)
            const ListTile(
              leading: Icon(Icons.info_outline),
              title: Text('Confirm or skip the earlier ones of this item first'),
            ),
          if (canAct) ...[
            ListTile(
              leading: const Icon(Icons.check_circle_outline),
              title: const Text('Confirm as is'),
              onTap: () => Navigator.pop(ctx, 'confirm'),
            ),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Edit amount / details, then confirm'),
              onTap: () => Navigator.pop(ctx, 'edit'),
            ),
            ListTile(
              leading: const Icon(Icons.skip_next_outlined),
              title: const Text('Skip this time'),
              onTap: () => Navigator.pop(ctx, 'skip'),
            ),
          ],
          ListTile(
            leading: const Icon(Icons.repeat),
            title: const Text('Edit recurring item (all future)'),
            onTap: () => Navigator.pop(ctx, 'rule'),
          ),
        ],
      ),
    ),
  );
  if (choice == null || !context.mounted) return;
  switch (choice) {
    case 'confirm':
      await state.confirmOccurrence(o);
      if (context.mounted) showSnack(context, 'Recorded');
      break;
    case 'skip':
      await state.skipOccurrence(o);
      break;
    case 'edit':
      await Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => TransactionEditScreen(occurrence: o)));
      break;
    case 'rule':
      await Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => TransactionEditScreen(rule: o.rule)));
      break;
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

IconData accountTypeIcon(AccountType t) {
  switch (t) {
    case AccountType.cash:
      return Icons.payments;
    case AccountType.ewallet:
      return Icons.phone_iphone;
    case AccountType.bank:
      return Icons.account_balance;
    case AccountType.savings:
      return Icons.savings;
    case AccountType.certificate:
      return Icons.workspace_premium;
    case AccountType.debitCard:
      return Icons.credit_card_outlined;
    case AccountType.creditCard:
      return Icons.credit_card;
    case AccountType.loan:
      return Icons.request_quote;
    case AccountType.investment:
      return Icons.show_chart;
    case AccountType.funds:
      return Icons.pie_chart_outline;
    case AccountType.crypto:
      return Icons.currency_bitcoin;
    case AccountType.gold:
      return Icons.diamond_outlined;
    case AccountType.property:
      return Icons.home_work_outlined;
    case AccountType.car:
      return Icons.directions_car;
    case AccountType.otherAsset:
      return Icons.inventory_2_outlined;
    case AccountType.receivable:
      return Icons.handshake_outlined;
    case AccountType.other:
      return Icons.wallet;
  }
}

/// Groups accounts by bank; accounts without a bank go last under "Other".
List<MapEntry<String, List<Account>>> groupByBank(List<Account> list) {
  final map = <String, List<Account>>{};
  for (final a in list) {
    map.putIfAbsent(a.bank.trim(), () => []).add(a);
  }
  final keys = map.keys.where((k) => k.isNotEmpty).toList()
    ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  return [
    for (final k in keys) MapEntry(k, map[k]!),
    if (map.containsKey('')) MapEntry('Other', map['']!),
  ];
}

/// A form field that opens an account picker grouped by bank.
class AccountField extends StatelessWidget {
  const AccountField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.keepId,
    this.errorText,
  });

  final String label;
  final int? value;
  final ValueChanged<int> onChanged;

  /// An archived account to still offer (e.g. when editing an old entry).
  final int? keepId;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final a = state.accountById(value);
    return InkWell(
      borderRadius: BorderRadius.circular(4),
      onTap: () async {
        final id = await pickAccount(context,
            current: value, keepId: keepId ?? value, title: label);
        if (id != null) onChanged(id);
      },
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          errorText: errorText,
          border: const OutlineInputBorder(),
          suffixIcon: const Icon(Icons.arrow_drop_down),
          prefixIcon: a == null ? null : Icon(accountTypeIcon(a.type)),
        ),
        child: a == null
            ? Text('Select',
                style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant))
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (a.bank.isNotEmpty)
                    Text(a.bank,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.primary)),
                  Text('${a.name} · ${a.currency}',
                      overflow: TextOverflow.ellipsis),
                ],
              ),
      ),
    );
  }
}

/// Returns the chosen account id, or -1 for "All accounts" when
/// [allowAll] is set.
Future<int?> pickAccount(BuildContext context,
    {int? current,
    int? keepId,
    String title = 'Account',
    bool allowAll = false,
    bool includeArchived = false}) {
  final state = AppScope.read(context);
  final list = state.accounts
      .where((a) => includeArchived || !a.archived || a.id == keepId)
      .toList();
  return showModalBottomSheet<int>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => _AccountSheet(
      accounts: list,
      current: current,
      title: title,
      allowAll: allowAll,
    ),
  );
}

/// Account list grouped by bank, with a search box on top.
class _AccountSheet extends StatefulWidget {
  const _AccountSheet({
    required this.accounts,
    required this.current,
    required this.title,
    required this.allowAll,
  });

  final List<Account> accounts;
  final int? current;
  final String title;
  final bool allowAll;

  @override
  State<_AccountSheet> createState() => _AccountSheetState();
}

class _AccountSheetState extends State<_AccountSheet> {
  String _q = '';
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  bool _matches(Account a, List<String> words) {
    final hay = '${a.name} ${a.bank} ${a.type.label} ${a.type.family.label} '
            '${a.currency}'
        .toLowerCase();
    return words.every(hay.contains);
  }

  @override
  Widget build(BuildContext context) {
    final words = _q.trim().toLowerCase().split(RegExp(r'\s+'))
      ..removeWhere((w) => w.isEmpty);
    final filtered = words.isEmpty
        ? widget.accounts
        : widget.accounts.where((a) => _matches(a, words)).toList();
    final groups = groupByBank(filtered);
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      // Keep the list above the keyboard while typing.
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.75,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(widget.title,
                  style: Theme.of(context).textTheme.titleMedium),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: TextField(
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search),
                  hintText: 'Search account, bank, type',
                  border: const OutlineInputBorder(),
                  isDense: true,
                  suffixIcon: _q.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () => setState(() {
                            _ctrl.clear();
                            _q = '';
                          }),
                        ),
                ),
                controller: _ctrl,
                onChanged: (v) => setState(() => _q = v),
              ),
            ),
            Expanded(
              child: ListView(
                children: [
                  if (widget.allowAll && words.isEmpty)
                    ListTile(
                      leading: const Icon(Icons.select_all),
                      title: const Text('All accounts'),
                      selected: widget.current == null,
                      onTap: () => Navigator.pop(context, -1),
                    ),
                  if (filtered.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(child: Text('No matching accounts')),
                    ),
                  for (final g in groups) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                      child: Text(
                        g.key,
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                            color: scheme.primary, fontWeight: FontWeight.bold),
                      ),
                    ),
                    for (final a in g.value)
                      ListTile(
                        leading: Icon(accountTypeIcon(a.type)),
                        title: Text(a.name),
                        subtitle: Text(
                            a.archived ? '${a.type.label} · archived' : a.type.label),
                        selected: a.id == widget.current,
                        trailing: Text(fmtMoney(a.balance, a.currency),
                            style:
                                TextStyle(color: amountColor(context, a.balance))),
                        onTap: () => Navigator.pop(context, a.id),
                      ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Small rounded label like "Upcoming" or "3/12".
class TagChip extends StatelessWidget {
  const TagChip(this.text, {super.key, this.color});

  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? Theme.of(context).colorScheme.primary;
    return Container(
      margin: const EdgeInsets.only(left: 6),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(text,
          style: TextStyle(fontSize: 11, color: c, fontWeight: FontWeight.w600)),
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

/// Categories of [kind] grouped by their group name ("" last as "Other").
List<MapEntry<String, List<Category>>> groupCategories(List<Category> cats) {
  final map = <String, List<Category>>{};
  for (final c in cats) {
    map.putIfAbsent(c.group.trim(), () => []).add(c);
  }
  final keys = map.keys.where((k) => k.isNotEmpty).toList()
    ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  return [
    for (final k in keys) MapEntry(k, map[k]!),
    if (map.containsKey('')) MapEntry(keys.isEmpty ? 'Categories' : 'Other', map['']!),
  ];
}

/// Form field that opens a searchable, grouped category picker.
class CategoryField extends StatelessWidget {
  const CategoryField({
    super.key,
    required this.kind,
    required this.value,
    required this.onChanged,
  });

  final TxType kind;
  final int? value;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final c = state.categoryById(value);
    return InkWell(
      borderRadius: BorderRadius.circular(4),
      onTap: () async {
        final id = await showModalBottomSheet<int>(
          context: context,
          isScrollControlled: true,
          showDragHandle: true,
          builder: (_) => _CategorySheet(kind: kind, current: value),
        );
        if (id != null) onChanged(id == -1 ? null : id);
      },
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: 'Category',
          border: const OutlineInputBorder(),
          suffixIcon: const Icon(Icons.arrow_drop_down),
          prefixIcon: c == null
              ? null
              : Padding(
                  padding: const EdgeInsets.all(8),
                  child: SizedBox(
                      width: 28,
                      height: 28,
                      child: FittedBox(child: CategoryAvatar(category: c))),
                ),
        ),
        child: c == null
            ? Text('Select category',
                style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant))
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (c.group.isNotEmpty)
                    Text(c.group,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.primary)),
                  Text(c.name, overflow: TextOverflow.ellipsis),
                ],
              ),
      ),
    );
  }
}

/// Opens the grouped category picker. Returns the id, or -1 for "none".
Future<int?> pickCategory(BuildContext context,
        {required TxType kind, int? current}) =>
    showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _CategorySheet(kind: kind, current: current),
    );

class _CategorySheet extends StatefulWidget {
  const _CategorySheet({required this.kind, this.current});

  final TxType kind;
  final int? current;

  @override
  State<_CategorySheet> createState() => _CategorySheetState();
}

class _CategorySheetState extends State<_CategorySheet> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final q = _q.trim().toLowerCase();
    final cats = state.categoriesOf(widget.kind).where((c) =>
        q.isEmpty ||
        c.name.toLowerCase().contains(q) ||
        c.group.toLowerCase().contains(q));
    final groups = groupCategories(cats.toList());
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.8,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Search categories',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (v) => setState(() => _q = v),
            ),
          ),
          Expanded(
            child: ListView(
              children: [
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.block),
                  title: const Text('No category'),
                  onTap: () => Navigator.pop(context, -1),
                ),
                for (final g in groups) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                    child: Text(
                      g.key,
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: Theme.of(context).colorScheme.primary,
                          fontWeight: FontWeight.bold),
                    ),
                  ),
                  for (final c in g.value)
                    ListTile(
                      dense: true,
                      leading: SizedBox(
                          width: 32,
                          height: 32,
                          child: FittedBox(child: CategoryAvatar(category: c))),
                      title: Text(c.name),
                      selected: c.id == widget.current,
                      onTap: () => Navigator.pop(context, c.id),
                    ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
