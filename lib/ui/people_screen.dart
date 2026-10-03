import 'package:flutter/material.dart';

import '../data/models.dart';
import '../l10n/l10n.dart';
import '../state/app_state.dart';
import '../util/format.dart';
import 'transaction_edit.dart';
import 'widgets.dart';

/// Asks for a new person's name.
Future<String?> askPersonName(BuildContext context) async {
  final c = TextEditingController();
  final name = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(tr('New Person')),
      content: TextField(
        controller: c,
        autofocus: true,
        textCapitalization: TextCapitalization.words,
        decoration: InputDecoration(labelText: tr('Name')),
        onSubmitted: (v) => Navigator.pop(ctx, v),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Cancel'))),
        FilledButton(onPressed: () => Navigator.pop(ctx, c.text), child: Text(tr('Add'))),
      ],
    ),
  );
  return name == null || name.trim().isEmpty ? null : name.trim();
}

String _balanceText(Account p) {
  if (p.balance.abs() < 0.005) return tr('Settled');
  return p.balance > 0
      ? tr('Owes you ${fmtMoney(p.balance, p.currency)}')
      : tr('You owe ${fmtMoney(-p.balance, p.currency)}');
}

/// Everyone you lend to or borrow from.
class PeopleScreen extends StatelessWidget {
  const PeopleScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final people = state.people;
    final base = state.baseCurrency;
    var owedToMe = 0.0, iOwe = 0.0;
    for (final p in people) {
      final v = state.toBase(p.balance, p.currency);
      if (v > 0) owedToMe += v;
      if (v < 0) iOwe -= v;
    }
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(tr('People'))),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.person_add_alt),
        label: Text(tr('Add Person')),
        onPressed: () async {
          final name = await askPersonName(context);
          if (name != null) await state.addPerson(name);
        },
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
        children: [
          Row(
            children: [
              Expanded(child: _total(context, tr('Owed to you'), fmtMoney(owedToMe, base), kIncomeColor)),
              const SizedBox(width: 8),
              Expanded(child: _total(context, tr('You owe'), fmtMoney(iOwe, base), kExpenseColor)),
            ],
          ),
          const SizedBox(height: 8),
          if (people.isEmpty)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                tr('Add the people you lend money to or borrow from. Lending, borrowing, paying back and splitting bills then keep their balance up to date.'),
                textAlign: TextAlign.center,
              ),
            ),
          for (final p in people)
            Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: CircleAvatar(child: Text(p.name.characters.first.toUpperCase())),
                title: Text(p.name),
                subtitle: Text([
                  _balanceText(p),
                  if (state.personDue[p.id] != null && p.balance.abs() >= 0.005)
                    tr('by ${shortDateFmt.format(state.personDue[p.id]!.$1)}'),
                ].join(' · ')),
                trailing: Text(
                  fmtMoney(p.balance, p.currency),
                  style: theme.textTheme.titleSmall?.copyWith(
                      color: p.balance.abs() < 0.005
                          ? null
                          : (p.balance > 0 ? kIncomeColor : kExpenseColor)),
                ),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => PersonScreen(personId: p.id!)),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _total(BuildContext context, String label, String value, Color color) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: Theme.of(context).textTheme.bodySmall),
            FittedBox(
              child: Text(value,
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17, color: color)),
            ),
          ],
        ),
      );
}

enum _Move { lend, borrow, gotBack, payBack }

/// One person: balance, quick actions, due date and history.
class PersonScreen extends StatefulWidget {
  const PersonScreen({super.key, required this.personId});
  final int personId;

  @override
  State<PersonScreen> createState() => _PersonScreenState();
}

class _PersonScreenState extends State<PersonScreen> {
  Future<List<Txn>>? _future;
  int _version = -1;

  Future<void> _move(AppState state, Account p, _Move m, {double? preset}) async {
    final amount = TextEditingController(text: preset == null ? '' : preset.toStringAsFixed(2));
    var acc = state.accounts
        .where((a) => !a.archived && (a.type.family == AccountFamily.cash || a.type.family == AccountFamily.bank))
        .map((a) => a.id)
        .firstOrNull;
    var date = DateTime.now();
    final title = switch (m) {
      _Move.lend => tr('Lend to ${p.name}'),
      _Move.borrow => tr('Borrow from ${p.name}'),
      _Move.gotBack => tr('${p.name} paid you back'),
      _Move.payBack => tr('Pay ${p.name} back'),
    };
    final toPerson = m == _Move.lend || m == _Move.payBack;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: Text(title),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: amount,
                autofocus: preset == null,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                    labelText: tr('Amount'), suffixText: p.currency, border: const OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              AccountField(
                label: toPerson ? tr('From account') : tr('Into account'),
                value: acc,
                onChanged: (v) => setS(() => acc = v),
              ),
              const SizedBox(height: 12),
              InkWell(
                onTap: () async {
                  final d = await showDatePicker(
                      context: ctx, initialDate: date, firstDate: DateTime(2000), lastDate: DateTime(2100));
                  if (d != null) setS(() => date = DateTime(d.year, d.month, d.day, date.hour, date.minute));
                },
                child: InputDecorator(
                  decoration: InputDecoration(
                      labelText: tr('Date'), border: const OutlineInputBorder(),
                      suffixIcon: const Icon(Icons.calendar_today)),
                  child: Text(dayFmt.format(date)),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Cancel'))),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Save'))),
          ],
        ),
      ),
    );
    final v = parseAmount(amount.text)?.abs();
    if (ok != true || v == null || v == 0 || acc == null) return;
    final other = state.accountById(acc);
    final note = switch (m) {
      _Move.lend => 'Lent to ${p.name}',
      _Move.borrow => 'Borrowed from ${p.name}',
      _Move.gotBack => '${p.name} paid back',
      _Move.payBack => 'Paid ${p.name} back',
    };
    // Amount is in the person's currency; convert for the other account.
    double? conv(double x) => other == null || other.currency == p.currency
        ? null
        : state.convert(x, p.currency, other.currency);
    if (toPerson) {
      final c = conv(v);
      await state.saveTxn(Txn(
        type: TxType.transfer, date: date, amount: c ?? v, accountId: acc!,
        toAccountId: p.id, toAmount: c == null ? null : v, note: note));
    } else {
      final c = conv(v);
      await state.saveTxn(Txn(
        type: TxType.transfer, date: date, amount: v, accountId: p.id!,
        toAccountId: acc, toAmount: c, note: note));
    }
  }

  Future<void> _due(AppState state, Account p) async {
    final current = state.personDue[p.id];
    final d = await showDatePicker(
      context: context,
      initialDate: current?.$1 ?? DateTime.now().add(const Duration(days: 30)),
      firstDate: DateTime.now(),
      lastDate: DateTime(2100),
      helpText: p.balance >= 0 ? tr('${p.name} pays back by') : tr('You pay back by'),
    );
    if (d == null) return;
    await state.setPersonDue(p.id!, d, p.balance.abs());
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final p = state.accountById(widget.personId);
    if (p == null) return Scaffold(appBar: AppBar(), body: const SizedBox.shrink());
    if (_version != state.version) {
      _version = state.version;
      _future = state.db.transactions(accountId: p.id);
    }
    final theme = Theme.of(context);
    final due = state.personDue[p.id];
    final open = p.balance.abs() >= 0.005;
    return Scaffold(
      appBar: AppBar(title: Text(p.name)),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_balanceText(p), style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: !open ? null : (p.balance > 0 ? kIncomeColor : kExpenseColor))),
                if (due != null && open)
                  Text(tr('Expected back by ${dayFmt.format(due.$1)}'), style: theme.textTheme.bodySmall),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.tonalIcon(
                  icon: const Icon(Icons.call_made, size: 18),
                  label: Text(tr('Lend')),
                  onPressed: () => _move(state, p, _Move.lend),
                ),
                FilledButton.tonalIcon(
                  icon: const Icon(Icons.call_received, size: 18),
                  label: Text(tr('Borrow')),
                  onPressed: () => _move(state, p, _Move.borrow),
                ),
                OutlinedButton(
                  onPressed: () => _move(state, p, _Move.gotBack),
                  child: Text(tr('Got Paid Back')),
                ),
                OutlinedButton(
                  onPressed: () => _move(state, p, _Move.payBack),
                  child: Text(tr('Pay Back')),
                ),
                if (open)
                  FilledButton.icon(
                    icon: const Icon(Icons.handshake_outlined, size: 18),
                    label: Text(tr('Settle Up')),
                    onPressed: () => _move(state, p, p.balance > 0 ? _Move.gotBack : _Move.payBack,
                        preset: p.balance.abs()),
                  ),
              ],
            ),
          ),
          ListTile(
            leading: const Icon(Icons.event_outlined),
            title: Text(due == null ? tr('Set a pay-back date') : tr('Pay-back date: ${dayFmt.format(due.$1)}')),
            subtitle: Text(tr('A reminder on that day')),
            trailing: due == null
                ? null
                : IconButton(
                    tooltip: tr('Remove'),
                    icon: const Icon(Icons.close),
                    onPressed: () => state.setPersonDue(p.id!, null, 0),
                  ),
            onTap: () => _due(state, p),
          ),
          const Divider(),
          FutureBuilder<List<Txn>>(
            future: _future,
            builder: (context, snap) {
              final list = snap.data ?? const <Txn>[];
              if (list.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(tr('Nothing yet'), textAlign: TextAlign.center),
                );
              }
              return Column(
                children: [
                  for (final t in list)
                    TxnTile(
                      txn: t,
                      perspectiveAccountId: p.id,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => TransactionEditScreen(txn: t)),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}
