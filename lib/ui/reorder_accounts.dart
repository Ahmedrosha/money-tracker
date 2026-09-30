import 'package:flutter/material.dart';

import '../data/models.dart';
import '../state/app_state.dart';
import 'widgets.dart';
import '../l10n/l10n.dart';

/// Drag accounts into the order you want inside each group.
class ReorderAccountsScreen extends StatefulWidget {
  const ReorderAccountsScreen({super.key});

  @override
  State<ReorderAccountsScreen> createState() => _ReorderAccountsScreenState();
}

class _ReorderAccountsScreenState extends State<ReorderAccountsScreen> {
  List<MapEntry<String, List<Account>>>? _sections;
  bool _saving = false;

  void _init(AppState state) {
    final active = state.activeAccounts;
    List<MapEntry<String, List<Account>>> sections;
    if (state.accountsGroupBy == 'bank') {
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
    // Start from what the Accounts screen shows now.
    _sections = [
      for (final s in sections) MapEntry(s.key, state.orderAccounts(s.value)),
    ];
  }

  Future<void> _done(AppState state) async {
    setState(() => _saving = true);
    // Accounts not shown here (archived) keep their place after these.
    final shown = [for (final s in _sections!) ...s.value];
    final ids = {for (final a in shown) a.id};
    final rest = state.accounts.where((a) => !ids.contains(a.id)).toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    await state.saveAccountOrder([...shown, ...rest]);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    if (_sections == null) _init(state);
    final sections = _sections!;
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(tr('Reorder Accounts')),
        actions: [
          TextButton(
            onPressed: _saving ? null : () => _done(state),
            child: Text(tr('Done')),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Text(
              tr('Drag the handle on the right to move an account within its group. '
              'Saving switches the Accounts screen to Manual Order.'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          for (var si = 0; si < sections.length; si++) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
              child: Text(sections[si].key,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: scheme.primary, fontWeight: FontWeight.bold)),
            ),
            ReorderableListView(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              buildDefaultDragHandles: false,
              onReorder: (from, to) => setState(() {
                final list = sections[si].value;
                if (to > from) to -= 1;
                list.insert(to, list.removeAt(from));
              }),
              children: [
                for (var i = 0; i < sections[si].value.length; i++)
                  ListTile(
                    key: ValueKey(sections[si].value[i].id),
                    leading: Icon(accountTypeIcon(sections[si].value[i].type)),
                    title: Text(sections[si].value[i].name),
                    subtitle: Text(sections[si].value[i].bank.isEmpty
                        ? sections[si].value[i].type.label
                        : '${sections[si].value[i].type.label} · ${sections[si].value[i].bank}'),
                    trailing: ReorderableDragStartListener(
                      index: i,
                      child: const Padding(
                        padding: EdgeInsets.all(8),
                        child: Icon(Icons.drag_handle),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
