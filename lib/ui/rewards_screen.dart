import 'package:flutter/material.dart';

import '../data/models.dart';
import '../l10n/l10n.dart';
import '../state/app_state.dart';
import '../util/format.dart';
import 'transaction_edit.dart';
import 'widgets.dart';

/// Cards that can earn points.
bool canEarnPoints(Account a) =>
    a.type == AccountType.creditCard || a.type == AccountType.debitCard;

String _plain(double v) =>
    v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();

/// Points block on a card's screen.
class RewardsPanel extends StatelessWidget {
  const RewardsPanel({super.key, required this.account});
  final Account account;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final s = state.rewards[account.id];
    if (s == null) {
      return Card(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: ListTile(
          leading: const Icon(Icons.card_giftcard_outlined),
          title: Text(tr('Card Points')),
          subtitle: Text(tr('Set up the points this card gives')),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => RewardsSetupScreen(account: account)),
          ),
        ),
      );
    }
    final cur = account.currency;
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: ListTile(
        leading: const Icon(Icons.card_giftcard),
        title: Text(tr('${fmtPoints(s.balance)} points')),
        subtitle: Text(tr('Worth ${fmtMoney(s.balanceValue, cur)} · +${fmtPoints(s.earnedThisMonth)} this month')),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => CardRewardsScreen(account: account)),
        ),
      ),
    );
  }
}

/// A card's points: balance, what was earned and redeemed.
class CardRewardsScreen extends StatelessWidget {
  const CardRewardsScreen({super.key, required this.account});
  final Account account;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final s = state.rewards[account.id];
    final theme = Theme.of(context);
    if (s == null) {
      return Scaffold(
        appBar: AppBar(title: Text(tr('Card Points'))),
        body: Center(child: Text(tr('No points set up for this card'))),
      );
    }
    final cur = account.currency;
    final r = s.rules;
    Widget row(String label, String value, {bool bold = false}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            children: [
              Expanded(child: Text(label)),
              Text(value,
                  style: TextStyle(
                      fontWeight: bold ? FontWeight.bold : FontWeight.normal)),
            ],
          ),
        );
    return Scaffold(
      appBar: AppBar(
        title: Text(tr('Points · ${account.name}')),
        actions: [
          IconButton(
            tooltip: tr('Points Rules'),
            icon: const Icon(Icons.tune),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => RewardsSetupScreen(account: account)),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tr('Points Balance'), style: theme.textTheme.bodySmall),
                Text(fmtPoints(s.balance),
                    style: theme.textTheme.headlineMedium
                        ?.copyWith(fontWeight: FontWeight.bold)),
                Text(tr('Worth ${fmtMoney(s.balanceValue, cur)}'),
                    style: theme.textTheme.titleSmall),
              ],
            ),
          ),
          Card(
            margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  row(tr('Earned this month'), fmtPoints(s.earnedThisMonth)),
                  row(tr('Earned this year'), fmtPoints(s.earnedThisYear)),
                  row(tr('Received from points this year'),
                      fmtMoney(s.valueThisYear, cur)),
                  const Divider(),
                  row(tr('Balance on ${shortDateFmt.format(r.startAt)}'),
                      fmtPoints(r.startPoints)),
                  row(tr('Earned since'), '+${fmtPoints(s.earned)}'),
                  row(tr('Redeemed since'), '−${fmtPoints(s.redeemed)}'),
                  row(tr('Balance now'), fmtPoints(s.balance), bold: true),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: () => _redeem(context, state, s),
                  icon: const Icon(Icons.payments_outlined),
                  label: Text(tr('Redeem as Cashback')),
                ),
                OutlinedButton.icon(
                  onPressed: () => _fromBank(context, state, s),
                  icon: const Icon(Icons.sync_alt),
                  label: Text(tr('Update from Bank')),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              tr('To pay for a purchase with points, add the expense on this card and turn on "Paid with points".'),
              style: theme.textTheme.bodySmall,
            ),
          ),
          if (s.redemptions.isNotEmpty) ...[
            const Divider(),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Text(tr('Redeemed'), style: theme.textTheme.titleSmall),
            ),
            for (final t in s.redemptions)
              TxnTile(
                txn: t,
                showDate: true,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => TransactionEditScreen(txn: t)),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Future<void> _redeem(
      BuildContext context, AppState state, RewardsStatus s) async {
    final pts = TextEditingController(
        text: s.balance > 0 ? _plain(s.balance.floorToDouble()) : '');
    final amt = TextEditingController(
        text: s.balance > 0
            ? (s.balance.floorToDouble() * s.rules.pointValue).toStringAsFixed(2)
            : '');
    var amountTyped = false;
    var date = DateTime.now();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text(tr('Redeem as Cashback')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: pts,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: tr('Points'),
                  helperText: tr('You have ${fmtPointsRaw(s.balance)}'),
                ),
                onChanged: (v) {
                  if (amountTyped) return;
                  final p = parseAmount(v);
                  amt.text = p == null
                      ? ''
                      : (p * s.rules.pointValue).toStringAsFixed(2);
                },
              ),
              const SizedBox(height: 8),
              TextField(
                controller: amt,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: tr('Cashback Amount (${account.currency})'),
                ),
                onChanged: (_) => amountTyped = true,
              ),
              const SizedBox(height: 8),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.event),
                title: Text(dayFmt.format(date)),
                onTap: () async {
                  final d = await showDatePicker(
                    context: ctx,
                    initialDate: date,
                    firstDate: DateTime(2000),
                    lastDate: DateTime(2100),
                  );
                  if (d != null) setD(() => date = d);
                },
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(tr('Cancel'))),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(tr('Save'))),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final p = parseAmount(pts.text)?.abs();
    final a = parseAmount(amt.text)?.abs();
    if (p == null || p == 0 || a == null || a == 0) {
      if (context.mounted) showSnack(context, tr('Enter the points and the amount'));
      return;
    }
    await state.redeemCashback(account, p, a, date);
    if (context.mounted) {
      showSnack(context, tr('Cashback of ${fmtMoney(a, account.currency)} added as income'));
    }
  }

  Future<void> _fromBank(
      BuildContext context, AppState state, RewardsStatus s) async {
    final ctl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Update from Bank')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(tr('The app works out ${fmtPointsRaw(s.balance)} points. Enter the balance your bank shows and counting continues from it.')),
            const SizedBox(height: 12),
            TextField(
              controller: ctl,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(labelText: tr('Points the bank shows')),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(tr('Cancel'))),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(tr('Save'))),
        ],
      ),
    );
    if (ok != true) return;
    final v = parseAmount(ctl.text)?.abs();
    if (v == null) return;
    final diff = v - s.balance;
    await state.setPointsFromBank(account.id!, v);
    if (!context.mounted) return;
    if (diff.abs() < 0.5) {
      showSnack(context, tr('Matches the app'));
    } else if (diff > 0) {
      showSnack(context, tr('The bank shows ${fmtPointsRaw(diff)} more points than the app worked out'));
    } else {
      showSnack(context, tr('The bank shows ${fmtPointsRaw(-diff)} fewer points than the app worked out'));
    }
  }
}

class _CatRate {
  _CatRate(this.categoryId, String points)
      : points = TextEditingController(text: points);
  int? categoryId;
  final TextEditingController points;
}

/// How a card earns points and what they are worth.
class RewardsSetupScreen extends StatefulWidget {
  const RewardsSetupScreen({super.key, required this.account});
  final Account account;

  @override
  State<RewardsSetupScreen> createState() => _RewardsSetupScreenState();
}

class _RewardsSetupScreenState extends State<RewardsSetupScreen> {
  late final CardRewards? _old =
      AppScope.read(context).cardRewards[widget.account.id];
  late final _points = TextEditingController(text: _old == null ? '1' : _plain(_old.points));
  late final _per = TextEditingController(text: _old == null ? '10' : _plain(_old.per));
  late final _valuePoints =
      TextEditingController(text: _old == null ? '1000' : _plain(_old.valuePoints));
  late final _valueMoney =
      TextEditingController(text: _old == null ? '' : _plain(_old.valueMoney));
  final _start = TextEditingController();
  late final List<_CatRate> _cats = [
    for (final e in (_old?.categoryPoints ?? const <int, double>{}).entries)
      _CatRate(e.key, _plain(e.value)),
  ];

  @override
  void dispose() {
    for (final c in [_points, _per, _valuePoints, _valueMoney, _start]) {
      c.dispose();
    }
    for (final c in _cats) {
      c.points.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final state = AppScope.read(context);
    final points = parseAmount(_points.text)?.abs();
    final per = parseAmount(_per.text)?.abs();
    final vp = parseAmount(_valuePoints.text)?.abs();
    final vm = parseAmount(_valueMoney.text)?.abs();
    if (points == null || per == null || per == 0) {
      showSnack(context, tr('Enter the points and the amount they are for'));
      return;
    }
    if (vp == null || vp == 0 || vm == null) {
      showSnack(context, tr('Enter what the points are worth'));
      return;
    }
    final cats = <int, double>{};
    for (final c in _cats) {
      final v = parseAmount(c.points.text)?.abs();
      if (c.categoryId != null && v != null) cats[c.categoryId!] = v;
    }
    await state.saveCardRewards(CardRewards(
      accountId: widget.account.id!,
      points: points,
      per: per,
      categoryPoints: cats,
      valuePoints: vp,
      valueMoney: vm,
      startPoints: _old?.startPoints ?? (parseAmount(_start.text)?.abs() ?? 0),
      startAt: _old?.startAt ?? DateTime.now(),
    ));
    if (!mounted) return;
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final cur = widget.account.currency;
    final theme = Theme.of(context);
    const numKb = TextInputType.numberWithOptions(decimal: true);
    final pts = parseAmount(_points.text);
    final per = parseAmount(_per.text);
    final vp = parseAmount(_valuePoints.text);
    final vm = parseAmount(_valueMoney.text);
    String? back;
    if (pts != null && per != null && per > 0 && vp != null && vp > 0 && vm != null) {
      final pct = pts / per * (vm / vp) * 100;
      back = tr('About ${pct.toStringAsFixed(pct < 1 ? 2 : 1)}% back');
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(tr('Points Rules')),
        actions: [
          if (_old != null)
            IconButton(
              tooltip: tr('Delete'),
              icon: const Icon(Icons.delete_outline),
              onPressed: () async {
                final ok = await confirmDialog(context,
                    title: 'Remove points?',
                    message: 'The points rules for this card are removed. Your transactions stay.',
                    ok: 'Remove');
                if (!ok || !context.mounted) return;
                await state.deleteCardRewards(widget.account.id!);
                if (context.mounted) Navigator.pop(context);
              },
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(tr('Points earned'), style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _points,
                  keyboardType: numKb,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    labelText: tr('Points'),
                    border: const OutlineInputBorder(),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(tr('for every')),
              ),
              Expanded(
                child: TextField(
                  controller: _per,
                  keyboardType: numKb,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    labelText: tr('Spent ($cur)'),
                    border: const OutlineInputBorder(),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Text(tr('What points are worth'), style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _valuePoints,
                  keyboardType: numKb,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    labelText: tr('Points'),
                    border: const OutlineInputBorder(),
                  ),
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: Text('='),
              ),
              Expanded(
                child: TextField(
                  controller: _valueMoney,
                  keyboardType: numKb,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    labelText: cur,
                    border: const OutlineInputBorder(),
                  ),
                ),
              ),
            ],
          ),
          if (back != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(back, style: theme.textTheme.bodySmall),
            ),
          const SizedBox(height: 24),
          Text(tr('Other rates by category'), style: theme.textTheme.titleSmall),
          Text(
            tr('Points for every ${_per.text.isEmpty ? '…' : _per.text} $cur in that category, e.g. more on Fuel, none on Bills.'),
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          for (final c in _cats)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: CategoryField(
                      kind: TxType.expense,
                      value: c.categoryId,
                      onChanged: (v) => setState(() => c.categoryId = v),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: TextField(
                      controller: c.points,
                      keyboardType: numKb,
                      decoration: InputDecoration(
                        labelText: tr('Points'),
                        border: const OutlineInputBorder(),
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => setState(() => _cats.remove(c)),
                  ),
                ],
              ),
            ),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              onPressed: () => setState(() => _cats.add(_CatRate(null, ''))),
              icon: const Icon(Icons.add),
              label: Text(tr('Add Category Rate')),
            ),
          ),
          if (_old == null) ...[
            const SizedBox(height: 16),
            TextField(
              controller: _start,
              keyboardType: numKb,
              decoration: InputDecoration(
                labelText: tr('Points you have now'),
                helperText: tr('From your bank app. Purchases from today on add to it.'),
                border: const OutlineInputBorder(),
              ),
            ),
          ],
          const SizedBox(height: 24),
          FilledButton(onPressed: _save, child: Text(tr('Save'))),
        ],
      ),
    );
  }
}
