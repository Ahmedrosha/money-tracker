import 'package:flutter/material.dart';

import '../state/app_state.dart';
import 'widgets.dart';
import '../l10n/l10n.dart';

/// Recurring items whose date has arrived and are waiting for confirmation.
class DueScreen extends StatelessWidget {
  const DueScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final due = state.dueOccurrences;
    final actionable = due.where(state.isNextOccurrence).toList();
    return Scaffold(
      appBar: AppBar(
        title: Text(tr('To Confirm')),
        actions: [
          if (actionable.isNotEmpty)
            TextButton(
              onPressed: () async {
                final ok = await confirmDialog(context,
                    title: tr('Confirm all?'),
                    message:
                        tr('Record ${due.length} item(s) with their usual amounts.'),
                    ok: tr('Confirm All'));
                if (!ok) return;
                // Confirm in date order; each call advances its rule.
                for (final o in due) {
                  await state.confirmOccurrence(o);
                }
              },
              child: Text(tr('Confirm All')),
            ),
        ],
      ),
      body: due.isEmpty
          ? Center(child: Text(tr('Nothing to confirm')))
          : ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                for (final o in due)
                  OccurrenceTile(occurrence: o, showDate: true),
              ],
            ),
    );
  }
}
