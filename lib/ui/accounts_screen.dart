import 'package:flutter/material.dart';

import '../data/models.dart';
import '../state/app_state.dart';
import '../util/format.dart';
import 'account_detail.dart';
import 'account_edit.dart';
import 'account_search.dart';
import 'reorder_accounts.dart';
import 'backup_screen.dart';
import 'due_screen.dart';
import 'pay_card.dart';
import 'statement_detail.dart';
import 'widgets.dart';

class AccountsScreen extends StatelessWidget {
  const AccountsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final active = state.activeAccounts;
    final archived = state.accounts.where((a) => a.archived).toList();
    final missing = state.missingRates;

    final byBank = state.accountsGroupBy == 'bank';
    final List<MapEntry<String, List<Account>>> sections;
    if (byBank) {
      sections = groupByBank(active);
    } else {
      final g = <AccountFamily, List<Account>>{};
      for (final a in active) {
        g.putIfAbsent(a.type.family, () => []).add(a);
      }
      sections = [
        for (final f in AccountFamily.values)
          if (g[f] != null) MapEntry(f.label, g[f]!),
      ];
    }
    final due = state.dueOccurrences;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Accounts'),
        actions: [
          const HideAmountsButton(),
          IconButton(
            tooltip: 'Find Account',
            icon: const Icon(Icons.search),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AccountSearchScreen()),
            ),
          ),
          PopupMenuButton<String>(
            tooltip: 'Group and Order',
            icon: const Icon(Icons.sort),
            onSelected: (v) {
              if (v.startsWith('group:')) {
                state.setAccountsGroupBy(v.substring(6));
              } else if (v.startsWith('order:')) {
                state.setAccountsOrder(v.substring(6));
              } else if (v == 'reorder') {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const ReorderAccountsScreen()),
                );
              }
            },
            itemBuilder: (_) {
              PopupMenuItem<String> item(String v, String label, bool on) =>
                  PopupMenuItem(
                    value: v,
                    child: Row(children: [
                      SizedBox(
                          width: 28,
                          child: on ? const Icon(Icons.check, size: 18) : null),
                      Text(label),
                    ]),
                  );
              return [
                item('group:type', 'Group by Type', state.accountsGroupBy == 'type'),
                item('group:bank', 'Group by Bank', state.accountsGroupBy == 'bank'),
                const PopupMenuDivider(),
                item('order:manual', 'Manual Order', state.accountsOrder == 'manual'),
                item('order:name', 'Name A–Z', state.accountsOrder == 'name'),
                item('order:balance', 'Balance', state.accountsOrder == 'balance'),
                const PopupMenuDivider(),
                const PopupMenuItem(
                  value: 'reorder',
                  child: Row(children: [
                    SizedBox(width: 28, child: Icon(Icons.drag_handle, size: 18)),
                    Text('Reorder Accounts…'),
                  ]),
                ),
              ];
            },
          ),
          IconButton(
            tooltip: 'Add Account',
            icon: const Icon(Icons.add_card),
            onPressed: () => _openEdit(context, null),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 96),
        children: [
          _NetWorthCard(state: state),
          if (due.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Card(
                color: Theme.of(context).colorScheme.tertiaryContainer,
                child: ListTile(
                  leading: const Icon(Icons.notifications_active_outlined),
                  title: Text(
                      '${due.length} recurring item${due.length == 1 ? '' : 's'} to confirm'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const DueScreen()),
                  ),
                ),
              ),
            ),
          for (final c in state.cardsDue
              .where((c) => !state.dismissedCards.contains(c.card.id)))
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Card(
                color: c.last!.overdue
                    ? Theme.of(context).colorScheme.errorContainer
                    : Theme.of(context).colorScheme.secondaryContainer,
                child: ListTile(
                  // Tap the banner to see the statement behind it.
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => StatementDetailScreen(
                          card: c.card, close: c.last!.closeDate),
                    ),
                  ),
                  leading: const Icon(Icons.credit_card),
                  title: Text(
                      '${c.card.fullName}: ${fmtMoney(c.last!.remaining, c.card.currency)} due'),
                  subtitle: Text(
                      '${c.last!.overdue ? 'Overdue since' : 'Due'} ${shortDateFmt.format(c.last!.dueDate)}'
                      ' · minimum ${fmtAmount(c.last!.minimumDue)}'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      FilledButton.tonal(
                        onPressed: () => showPayCard(context, c),
                        child: const Text('Pay'),
                      ),
                      IconButton(
                        tooltip: 'Hide until the app is reopened',
                        icon: const Icon(Icons.close),
                        onPressed: () => state.dismissCard(c.card.id!),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          if (state.backupOverdue)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Card(
                child: ListTile(
                  leading: const Icon(Icons.backup_outlined),
                  title: Text(state.lastBackup == null
                      ? 'No backup yet'
                      : 'Last backup ${state.lastBackup!.day}/${state.lastBackup!.month}'),
                  subtitle: const Text('Your data is only on this phone'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const BackupScreen()),
                  ),
                ),
              ),
            ),
          if (missing.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Card(
                color: Theme.of(context).colorScheme.errorContainer,
                child: ListTile(
                  leading: const Icon(Icons.warning_amber),
                  title: Text('No exchange rate for ${missing.join(', ')}'),
                  subtitle: const Text(
                      'Totals skip these. Refresh or set rates in Settings → Currencies.'),
                ),
              ),
            ),
          if (active.isEmpty)
            Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                children: [
                  const Icon(Icons.account_balance_wallet_outlined, size: 56),
                  const SizedBox(height: 12),
                  const Text('No accounts yet',
                      style: TextStyle(fontSize: 18)),
                  const SizedBox(height: 8),
                  const Text(
                    'Add your cash, bank accounts, cards and investments.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: () => _openEdit(context, null),
                    icon: const Icon(Icons.add),
                    label: const Text('Add Account'),
                  ),
                ],
              ),
            ),
          for (final sec in sections) ...[
            _GroupHeader(
              title: sec.key,
              total: sec.value.fold<double>(
                  0, (s, a) => s + state.toBase(a.balance, a.currency)),
              currency: state.baseCurrency,
              count: sec.value.length,
              collapsed: state.isCollapsed('acc:${byBank ? 'bank' : 'type'}:${sec.key}'),
              onTap: () => state.toggleCollapsed(
                  'acc:${byBank ? 'bank' : 'type'}:${sec.key}'),
            ),
            if (!state.isCollapsed('acc:${byBank ? 'bank' : 'type'}:${sec.key}'))
              for (final a in state.orderAccounts(sec.value))
                _AccountTile(account: a, showBank: !byBank),
          ],
          if (archived.isNotEmpty)
            ExpansionTile(
              title: Text('Archived (${archived.length})'),
              children: [
                for (final a in archived)
                  _AccountTile(account: a, showBank: true)
              ],
            ),
        ],
      ),
    );
  }

  static void _openEdit(BuildContext context, Account? a) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => AccountEditScreen(account: a)),
    );
  }
}

class _NetWorthCard extends StatelessWidget {
  const _NetWorthCard({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    var assets = 0.0;
    var debts = 0.0;
    for (final a in state.countedAccounts) {
      final v = state.toBase(a.balance, a.currency);
      if (v >= 0) {
        assets += v;
      } else {
        debts += v;
      }
    }
    return Card(
      margin: const EdgeInsets.all(16),
      color: scheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Net Worth',
                style: TextStyle(color: scheme.onPrimaryContainer)),
            const SizedBox(height: 4),
            Text(
              fmtMoney(state.netWorth, state.baseCurrency),
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  color: scheme.onPrimaryContainer,
                  fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _MiniStat(
                      label: 'Assets',
                      value: fmtAmount(assets),
                      color: scheme.onPrimaryContainer),
                ),
                Expanded(
                  child: _MiniStat(
                      label: 'Liabilities',
                      value: fmtAmount(debts),
                      color: scheme.onPrimaryContainer),
                ),
                Expanded(
                  child: _MiniStat(
                      label: 'Expected End of Month',
                      value: fmtAmount(state.projectedEom),
                      color: scheme.onPrimaryContainer),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat(
      {required this.label, required this.value, required this.color});

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: TextStyle(color: color.withValues(alpha: 0.75), fontSize: 12)),
        Text(value,
            style: TextStyle(color: color, fontWeight: FontWeight.w600)),
      ],
    );
  }
}

class _GroupHeader extends StatelessWidget {
  const _GroupHeader({
    required this.title,
    required this.total,
    required this.currency,
    required this.count,
    required this.collapsed,
    required this.onTap,
  });

  final String title;
  final double total;
  final String currency;
  final int count;
  final bool collapsed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.titleSmall?.copyWith(
        color: Theme.of(context).colorScheme.primary,
        fontWeight: FontWeight.bold);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 12, 16, 4),
        child: Row(
          children: [
            CollapseArrow(collapsed: collapsed),
            const SizedBox(width: 4),
            Expanded(
                child: Text(collapsed ? '$title ($count)' : title, style: style)),
            Text(fmtMoney(total, currency), style: style),
          ],
        ),
      ),
    );
  }
}

class _AccountTile extends StatelessWidget {
  const _AccountTile({required this.account, this.showBank = true});

  final Account account;
  final bool showBank;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final card = state.cards[account.id];
    final showBase = account.currency != state.baseCurrency &&
        state.convert(account.balance, account.currency, state.baseCurrency) !=
            null;
    return ListTile(
      leading: CircleAvatar(child: Icon(accountTypeIcon(account.type))),
      title: Text(account.name),
      subtitle: Text([
        account.type.label,
        if (showBank && account.bank.isNotEmpty) account.bank,
        account.currency,
        if (card?.available != null)
          'Available ${fmtAmount(card!.available!)}',
        if (account.excludeTotal) 'not in net worth',
      ].join(' · ')),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            fmtMoney(account.balance, account.currency),
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: amountColor(context, account.balance),
            ),
          ),
          if (showBase)
            Text(
              '≈ ${fmtMoney(state.toBase(account.balance, account.currency), state.baseCurrency)}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
        ],
      ),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => AccountDetailScreen(accountId: account.id!)),
      ),
    );
  }
}
