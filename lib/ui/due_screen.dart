import 'package:flutter/material.dart';

import '../state/app_state.dart';
import 'widgets.dart';

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
        title: const Text('To confirm'),
        actions: [
          if (actionable.isNotEmpty)
            TextButton(
              onPressed: () async {
                final ok = await confirmDialog(context,
                    title: 'Confirm all?',
                    message:
                        'Record ${due.length} item(s) with their usual amounts.',
                    ok: 'Confirm all');
                if (!ok) return;
                // Confirm in date order; each call advances its rule.
                for (final o in due) {
                  await state.confirmOccurrence(o);
                }
              },
              child: const Text('Confirm all'),
            ),
        ],
      ),
      body: due.isEmpty
          ? const Center(child: Text('Nothing to confirm'))
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
