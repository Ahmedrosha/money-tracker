import 'package:flutter/material.dart';

import '../data/models.dart';
import '../l10n/l10n.dart';
import '../state/app_state.dart';
import '../util/format.dart';
import 'pay_card.dart';
import 'statement_detail.dart';
import 'widgets.dart';

const _amber = Color(0xFFE6A23C);

int _daysLeft(CardStatement s) {
  final n = DateTime.now();
  final today = DateTime(n.year, n.month, n.day);
  final due = DateTime(s.dueDate.year, s.dueDate.month, s.dueDate.day);
  return due.difference(today).inDays;
}

Color? _urgency(BuildContext context, CardStatement s) {
  if (s.overdue) return Theme.of(context).colorScheme.error;
  if (_daysLeft(s) <= 5) return _amber;
  return null;
}

String _whenText(CardStatement s) {
  final d = _daysLeft(s);
  if (s.overdue) return tr('Overdue');
  if (d == 0) return tr('Due today');
  if (d == 1) return tr('Tomorrow');
  return tr('In $d days');
}

/// Accounts screen: one compact card for all credit cards with something
/// to pay, instead of a banner per card.
class CardsDueBox extends StatelessWidget {
  const CardsDueBox({super.key});

  static const _shown = 3;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    if (state.cardsBoxHidden) return const SizedBox.shrink();
    final cards = state.cardsToShow;
    final theme = Theme.of(context);
    if (cards.isEmpty) {
      // Everything due is snoozed: a small line to still reach them.
      final snoozed = state.cardsDue.length;
      if (snoozed == 0) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => const CardsDueScreen())),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Row(
              children: [
                Icon(Icons.snooze, size: 18, color: theme.colorScheme.onSurfaceVariant),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    tr('$snoozed card${snoozed == 1 ? '' : 's'} snoozed · tap to view'),
                    style: theme.textTheme.bodySmall,
                  ),
                ),
                Icon(Icons.chevron_right, size: 18, color: theme.colorScheme.onSurfaceVariant),
              ],
            ),
          ),
        ),
      );
    }
    final base = state.baseCurrency;
    final total = cards.fold<double>(
        0, (t, c) => t + state.toBase(c.last!.remaining, c.card.currency));
    final showAll = state.isCollapsed('cardsdue:all');
    final list = showAll ? cards : cards.take(_shown).toList();
    final anyOverdue = cards.any((c) => c.last!.overdue);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Card(
        clipBehavior: Clip.antiAlias,
        margin: EdgeInsets.zero,
        child: Column(
          children: [
            ListTile(
              leading: Icon(Icons.credit_card,
                  color: anyOverdue ? theme.colorScheme.error : _amber),
              title: Text(
                tr('${cards.length} card${cards.length == 1 ? '' : 's'} due · ${fmtMoney(total, base)}'),
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: Text(tr('Next: ${shortDateFmt.format(cards.first.last!.dueDate)} · tap for all cards')),
              trailing: IconButton(
                tooltip: tr('Hide until the app is reopened'),
                icon: const Icon(Icons.close),
                onPressed: state.hideCardsBox,
              ),
              onTap: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const CardsDueScreen())),
            ),
            for (final c in list) _CardLine(c: c),
            if (cards.length > _shown)
              InkWell(
                onTap: () => state.toggleCollapsed('cardsdue:all'),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Center(
                    child: Text(
                      showAll ? tr('Show less') : tr('Show all ${cards.length}'),
                      style: TextStyle(color: theme.colorScheme.primary),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _CardLine extends StatelessWidget {
  const _CardLine({required this.c});

  final CardSummary c;

  @override
  Widget build(BuildContext context) {
    final s = c.last!;
    final theme = Theme.of(context);
    final color = _urgency(context, s);
    return InkWell(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => StatementDetailScreen(card: c.card, close: s.closeDate),
        ),
      ),
      child: Container(
        decoration: BoxDecoration(
            border: Border(top: BorderSide(color: theme.dividerColor.withValues(alpha: 0.4)))),
        padding: const EdgeInsets.fromLTRB(16, 8, 10, 8),
        child: Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                  color: color ?? theme.colorScheme.outline,
                  shape: BoxShape.circle),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(c.card.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w500)),
                  Text(
                    '${s.overdue ? tr('Overdue since') : tr('Due')} ${shortDateFmt.format(s.dueDate)}'
                    '${_daysLeft(s) <= 5 && !s.overdue ? ' · ${_whenText(s)}' : ''}'
                    ' · ${tr('min')} ${fmtAmount(s.minimumDue)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(fmtAmount(s.remaining),
                style: TextStyle(fontWeight: FontWeight.w600, color: color)),
            const SizedBox(width: 6),
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 12),
              ),
              onPressed: () => showPayCard(context, c),
              child: Text(tr('Pay')),
            ),
          ],
        ),
      ),
    );
  }
}

/// All cards with something to pay: statement, paid, minimum, and quick
/// pay / snooze.
class CardsDueScreen extends StatelessWidget {
  const CardsDueScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final theme = Theme.of(context);
    final base = state.baseCurrency;
    final cards = state.cardsDue;
    final now = DateTime.now();
    final thisMonth = cards.where((c) =>
        c.last!.dueDate.year == now.year && c.last!.dueDate.month == now.month ||
        c.last!.overdue);
    final dueMonth = thisMonth.fold<double>(
        0, (t, c) => t + state.toBase(c.last!.remaining, c.card.currency));
    final dueAll = cards.fold<double>(
        0, (t, c) => t + state.toBase(c.last!.remaining, c.card.currency));
    final cash = state.countedAccounts
        .where((a) =>
            a.type.family == AccountFamily.cash ||
            a.type.family == AccountFamily.bank)
        .fold<double>(0, (t, a) => t + state.toBase(a.balance, a.currency));

    Widget tile(String label, String value, {Color? color}) => Expanded(
          child: Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: theme.textTheme.bodySmall),
                  const SizedBox(height: 2),
                  FittedBox(
                    child: Text(value,
                        style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700, color: color)),
                  ),
                ],
              ),
            ),
          ),
        );

    return Scaffold(
      appBar: AppBar(title: Text(tr('Cards Due'))),
      body: cards.isEmpty
          ? Center(child: Text(tr('Nothing due')))
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                Row(
                  children: [
                    tile(tr('Due this month'), fmtAmount(dueMonth)),
                    const SizedBox(width: 8),
                    tile(tr('Cash & bank now'), fmtAmount(cash),
                        color: cash >= dueAll ? kIncomeColor : kExpenseColor),
                  ],
                ),
                if (dueAll > dueMonth + 0.004)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(tr('All cards: ${fmtMoney(dueAll, base)}'),
                        style: theme.textTheme.bodySmall),
                  ),
                for (final c in cards) _CardDueTile(c: c),
              ],
            ),
    );
  }
}

class _CardDueTile extends StatelessWidget {
  const _CardDueTile({required this.c});

  final CardSummary c;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final s = c.last!;
    final theme = Theme.of(context);
    final color = _urgency(context, s);
    final snoozed = state.isSnoozed(c);
    final partly = s.paid > 0.004;
    final frac = s.amount <= 0 ? 0.0 : (s.paid / s.amount).clamp(0.0, 1.0);

    Widget kv(String k, String v) => Padding(
          padding: const EdgeInsetsDirectional.only(end: 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(k, style: theme.textTheme.bodySmall),
              Text(v, style: const TextStyle(fontWeight: FontWeight.w600)),
            ],
          ),
        );

    return Card(
      margin: const EdgeInsets.only(top: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => StatementDetailScreen(card: c.card, close: s.closeDate),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 10, 8),
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
                        Text(c.card.fullName,
                            style: theme.textTheme.titleSmall
                                ?.copyWith(fontWeight: FontWeight.w600)),
                        Text(
                          tr('Statement ${shortDateFmt.format(s.closeDate)} · due ${shortDateFmt.format(s.dueDate)}'),
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: (color ?? theme.colorScheme.outline)
                          .withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      snoozed
                          ? tr('Hidden until ${shortDateFmt.format(state.snoozedUntil(c)!)}')
                          : _whenText(s),
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: color ?? theme.colorScheme.onSurfaceVariant),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  kv(tr('Statement'), fmtAmount(s.amount)),
                  kv(tr('Paid'), fmtAmount(s.paid)),
                  partly
                      ? kv(tr('Left'), fmtAmount(s.remaining))
                      : kv(tr('Minimum'), fmtAmount(s.minimumDue)),
                ],
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(value: frac, minHeight: 6),
              ),
              const SizedBox(height: 4),
              Wrap(
                spacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  FilledButton(
                    style: FilledButton.styleFrom(
                        visualDensity: VisualDensity.compact),
                    onPressed: () =>
                        showPayCard(context, c, preset: s.remaining),
                    child: Text(partly ? tr('Pay Rest') : tr('Pay Full')),
                  ),
                  if (s.minimumDue > 0.004 &&
                      (s.minimumDue - s.remaining).abs() > 0.004)
                    OutlinedButton(
                      style: OutlinedButton.styleFrom(
                          visualDensity: VisualDensity.compact),
                      onPressed: () =>
                          showPayCard(context, c, preset: s.minimumDue),
                      child: Text(tr('Minimum')),
                    ),
                  TextButton(
                    onPressed: () => showPayCard(context, c, preset: 0),
                    child: Text(tr('Other…')),
                  ),
                  if (!snoozed && !s.overdue)
                    TextButton.icon(
                      icon: const Icon(Icons.snooze, size: 18),
                      onPressed: () async {
                        await state.snoozeCard(c);
                        if (context.mounted) {
                          showSnack(context, tr('Hidden until 3 days before it is due'));
                        }
                      },
                      label: Text(tr('Snooze')),
                    ),
                  if (snoozed)
                    TextButton.icon(
                      icon: const Icon(Icons.notifications_active_outlined, size: 18),
                      onPressed: () => state.unsnoozeCard(c),
                      label: Text(tr('Unsnooze')),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
