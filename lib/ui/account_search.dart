import 'package:flutter/material.dart';

import '../data/models.dart';
import '../state/app_state.dart';
import '../util/format.dart';
import 'account_detail.dart';
import 'widgets.dart';

/// Type to find an account (archived ones too) and jump straight to it.
class AccountSearchScreen extends StatefulWidget {
  const AccountSearchScreen({super.key});

  @override
  State<AccountSearchScreen> createState() => _AccountSearchScreenState();
}

class _AccountSearchScreenState extends State<AccountSearchScreen> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final words = _q.trim().toLowerCase().split(RegExp(r'\s+'))
      ..removeWhere((w) => w.isEmpty);
    bool match(Account a) {
      final hay = '${a.name} ${a.bank} ${a.type.label} ${a.type.family.label} '
              '${a.currency}'
          .toLowerCase();
      return words.every(hay.contains);
    }

    final found = state.accounts.where(match).toList()
      // Active accounts first, archived ones after.
      ..sort((a, b) => (a.archived ? 1 : 0).compareTo(b.archived ? 1 : 0));
    final groups = groupByBank(found);

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: TextField(
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Find account, bank, type…',
            border: InputBorder.none,
          ),
          onChanged: (v) => setState(() => _q = v),
        ),
      ),
      body: found.isEmpty
          ? const Center(child: Text('No matching accounts'))
          : ListView(
              padding: const EdgeInsets.only(bottom: 24),
              children: [
                for (final g in groups) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                    child: Text(g.key,
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                            color: Theme.of(context).colorScheme.primary,
                            fontWeight: FontWeight.bold)),
                  ),
                  for (final a in g.value)
                    ListTile(
                      leading: CircleAvatar(child: Icon(accountTypeIcon(a.type))),
                      title: Text(a.name),
                      subtitle: Text([
                        a.type.label,
                        a.currency,
                        if (a.archived) 'archived',
                      ].join(' · ')),
                      trailing: Text(
                        fmtMoney(a.type.isLiability ? -a.balance : a.balance,
                            a.currency),
                        style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: amountColor(context, a.balance)),
                      ),
                      onTap: () => Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(
                            builder: (_) => AccountDetailScreen(accountId: a.id!)),
                      ),
                    ),
                ],
              ],
            ),
    );
  }
}
