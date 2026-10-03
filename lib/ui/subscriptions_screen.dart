import 'package:flutter/material.dart';

import '../data/models.dart';
import '../l10n/l10n.dart';
import '../state/app_state.dart';
import '../util/format.dart';
import 'transaction_edit.dart';
import 'export_screen.dart';
import '../services/export_excel.dart';
import 'widgets.dart';

/// Recurring expenses marked as subscriptions: what they cost a month and a
/// year, price changes, payees that look like subscriptions, and cancelled
/// ones.
class SubscriptionsScreen extends StatefulWidget {
  const SubscriptionsScreen({super.key});

  @override
  State<SubscriptionsScreen> createState() => _SubscriptionsScreenState();
}

class _SubscriptionsScreenState extends State<SubscriptionsScreen> {
  Future<List<SubCandidate>>? _found;
  int _foundVersion = -1;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final theme = Theme.of(context);
    final base = state.baseCurrency;
    if (_foundVersion != state.version) {
      _foundVersion = state.version;
      _found = state.findSubscriptionCandidates();
    }
    final subs = state.subscriptions
      ..sort((a, b) => state.subPerMonthBase(b).compareTo(state.subPerMonthBase(a)));
    final monthly = subs.fold<double>(0, (s, r) => s + state.subPerMonthBase(r));
    final cancelled = state.cancelledSubscriptions;

    return Scaffold(
      appBar: AppBar(
        title: Text(tr('Subscriptions')),
        actions: [
          IconButton(
            tooltip: tr('Export to Excel'),
            icon: const Icon(Icons.table_view_outlined),
            onPressed: () => shareExcel(context, () => ExcelExport.subscriptions(state)),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 32),
        children: [
          Card(
            color: theme.colorScheme.primaryContainer,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                      tr('${subs.length} subscription${subs.length == 1 ? '' : 's'}'),
                      style: theme.textTheme.bodyMedium),
                  const SizedBox(height: 4),
                  Text(tr('${fmtMoney(monthly, base)} / month'),
                      style: theme.textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.bold)),
                  Text(tr('${fmtMoney(monthly * 12, base)} / year'),
                      style: theme.textTheme.titleSmall),
                ],
              ),
            ),
          ),
          if (subs.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 16, 8, 8),
              child: Text(
                tr('No subscriptions yet. Turn on "Subscription" in a recurring expense, or add one found below.'),
                style: theme.textTheme.bodyMedium,
              ),
            ),
          for (final r in subs) _SubTile(rule: r),
          FutureBuilder<List<SubCandidate>>(
            future: _found,
            builder: (context, snap) {
              final list = snap.data ?? const <SubCandidate>[];
              if (list.isEmpty) return const SizedBox.shrink();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _heading(context, tr('Looks Like a Subscription'),
                      tr('Charged about the same amount every month')),
                  for (final c in list) _CandidateTile(c: c),
                ],
              );
            },
          ),
          if (cancelled.isNotEmpty) ...[
            InkWell(
              onTap: () => state.toggleCollapsed('subs:cancelled'),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
                child: Row(
                  children: [
                    CollapseArrow(collapsed: !state.isCollapsed('subs:cancelled')),
                    const SizedBox(width: 6),
                    Text(tr('Cancelled (${cancelled.length})'),
                        style: theme.textTheme.titleSmall),
                  ],
                ),
              ),
            ),
            if (state.isCollapsed('subs:cancelled'))
              for (final r in cancelled)
                Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    title: Text(_name(state, r)),
                    subtitle: Text(tr(
                        'Cancelled ${shortDateFmt.format(r.cancelledAt!)} · saving ${fmtMoney(state.subPerMonthBase(r) * 12, base)} / year')),
                  ),
                ),
          ],
        ],
      ),
    );
  }

  Widget _heading(BuildContext context, String title, String sub) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleSmall),
            Text(sub, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      );
}

String _name(AppState state, RecurringRule r) => r.payee.isNotEmpty
    ? r.payee
    : (state.categoryById(r.categoryId)?.name ?? tr('Subscription'));

class _SubTile extends StatelessWidget {
  const _SubTile({required this.rule});
  final RecurringRule rule;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final theme = Theme.of(context);
    final r = rule;
    final acc = state.accountById(r.accountId);
    final cur = acc?.currency ?? state.baseCurrency;
    final next = r.finished ? null : r.occurrence(r.nextIndex);
    final latest = state.subLatest[r.id];
    final change = state.subPriceChange[r.id];
    final foreign = latest != null && latest.isForeign
        ? ' (${fmtMoney(latest.origAmount!.abs(), latest.origCurrency!)})'
        : '';

    return Card(
      margin: const EdgeInsets.only(top: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _actions(context, state),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_name(state, r),
                            style: theme.textTheme.titleMedium),
                        Text(
                          '${fmtMoney(r.amount, cur)}$foreign ${r.scheduleLabel.toLowerCase()}',
                          style: theme.textTheme.bodySmall,
                        ),
                        Text(
                          [
                            if (next != null) tr('Next ${shortDateFmt.format(next)}'),
                            if (acc != null) acc.name,
                          ].join(' · '),
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(fmtMoney(state.subPerMonthBase(r) * 12, state.baseCurrency),
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      Text(tr('a year'), style: theme.textTheme.bodySmall),
                    ],
                  ),
                ],
              ),
              if (change != null) ...[
                const SizedBox(height: 8),
                _priceChange(context, state, r, change, cur),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _priceChange(BuildContext context, AppState state, RecurringRule r,
      Txn latest, String cur) {
    final theme = Theme.of(context);
    String text;
    if (latest.isForeign) {
      text = tr('Price changed: now ${fmtMoney(latest.origAmount!.abs(), latest.origCurrency!)} (since ${shortDateFmt.format(latest.date)})');
    } else {
      final pct = r.amount == 0 ? 0 : (latest.amount - r.amount) / r.amount * 100;
      final up = latest.amount > r.amount;
      text = tr('Price went ${up ? 'up' : 'down'}: ${fmtMoney(r.amount, cur)} → ${fmtMoney(latest.amount, cur)} (${up ? '+' : ''}${pct.toStringAsFixed(0)}%) since ${shortDateFmt.format(latest.date)}');
    }
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 6, 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.tertiaryContainer.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.trending_up, size: 18, color: theme.colorScheme.tertiary),
              const SizedBox(width: 6),
              Expanded(child: Text(text, style: theme.textTheme.bodySmall)),
            ],
          ),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: Wrap(
              spacing: 4,
              children: [
                TextButton(
                  onPressed: () => state.keepSubPrice(r, latest),
                  child: Text(tr('Keep Old Price')),
                ),
                FilledButton.tonal(
                  onPressed: () => state.useNewSubPrice(r, latest),
                  child: Text(tr('Use New Price')),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _actions(BuildContext context, AppState state) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(title: Text(_name(state, rule)), subtitle: Text(rule.scheduleLabel)),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: Text(tr('Edit Recurring Item')),
              onTap: () => Navigator.pop(ctx, 'edit'),
            ),
            ListTile(
              leading: const Icon(Icons.cancel_outlined),
              title: Text(tr('Cancelled')),
              subtitle: Text(tr('Stops it from today; it moves to Cancelled')),
              onTap: () => Navigator.pop(ctx, 'cancel'),
            ),
          ],
        ),
      ),
    );
    if (choice == null || !context.mounted) return;
    if (choice == 'edit') {
      await Navigator.push(context,
          MaterialPageRoute(builder: (_) => TransactionEditScreen(rule: rule)));
    } else if (choice == 'cancel') {
      final yearly = state.subPerMonthBase(rule) * 12;
      final ok = await confirmDialog(context,
          title: tr('Cancel ${_name(state, rule)}?'),
          message: tr('No more charges will be expected from today.'),
          ok: tr('Cancelled'));
      if (!ok) return;
      await state.cancelSubscription(rule);
      if (context.mounted) {
        showSnack(context, tr('You save ${fmtMoney(yearly, state.baseCurrency)} a year'));
      }
    }
  }
}

class _CandidateTile extends StatelessWidget {
  const _CandidateTile({required this.c});
  final SubCandidate c;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final t = c.last;
    final acc = state.accountById(t.accountId);
    final cur = acc?.currency ?? state.baseCurrency;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 8, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(t.payee, style: Theme.of(context).textTheme.titleMedium),
            Text(
              tr('${fmtMoney(t.amount.abs(), cur)} on day ${t.date.day} · ${c.months} months in a row${acc == null ? '' : ' · ${acc.name}'}'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: Wrap(
                spacing: 4,
                children: [
                  TextButton(
                    onPressed: () => state.dismissSubscriptionCandidate(t.payee),
                    child: Text(tr('Not a Subscription')),
                  ),
                  FilledButton.tonal(
                    onPressed: () async {
                      await state.makeSubscription(c);
                      if (context.mounted) showSnack(context, tr('Added to Subscriptions'));
                    },
                    child: Text(tr('Make Recurring')),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
