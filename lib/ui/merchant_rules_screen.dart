import 'package:flutter/material.dart';

import '../data/models.dart';
import '../l10n/l10n.dart';
import '../state/app_state.dart';
import 'widgets.dart';

/// What the app fills in for merchants seen in bank messages. Rules are
/// remembered when a message is added; they only prefill the form.
class MerchantRulesScreen extends StatelessWidget {
  const MerchantRulesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final rules = state.merchantRules;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(tr('Merchant Rules'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 32),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 4, 12),
            child: Text(
              tr('When you add a bank message, the name, category and account you choose are remembered for that merchant and filled in next time. You always see the entry before it is saved.'),
              style: theme.textTheme.bodySmall,
            ),
          ),
          if (rules.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 40),
              child: Center(
                child: Text(tr('No merchant rules yet'),
                    style: theme.textTheme.titleMedium),
              ),
            ),
          for (final r in rules)
            Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                title: Text(r.payee.isNotEmpty ? r.payee : r.merchant),
                subtitle: Text([
                  if (r.payee.isNotEmpty) tr('Bank writes: ${r.merchant}'),
                  state.categoryById(r.categoryId)?.name ?? tr('No category'),
                  if (state.accountById(r.accountId) != null)
                    state.accountById(r.accountId)!.name,
                ].join(' · ')),
                trailing: const Icon(Icons.edit_outlined),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => _RuleEdit(rule: r)),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _RuleEdit extends StatefulWidget {
  const _RuleEdit({required this.rule});
  final MerchantRule rule;

  @override
  State<_RuleEdit> createState() => _RuleEditState();
}

class _RuleEditState extends State<_RuleEdit> {
  late final TextEditingController _name =
      TextEditingController(text: widget.rule.payee);
  late int? _category = widget.rule.categoryId;
  late int? _account = widget.rule.accountId;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final kind = state.categoryById(_category)?.kind ?? TxType.expense;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.rule.merchant),
        actions: [
          IconButton(
            tooltip: tr('Delete'),
            icon: const Icon(Icons.delete_outline),
            onPressed: () async {
              await state.deleteMerchantRule(widget.rule.merchant);
              if (context.mounted) Navigator.pop(context);
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _name,
            decoration: InputDecoration(
              labelText: tr('Payee Name'),
              hintText: widget.rule.merchant,
              helperText: tr('Empty = use the name in the message'),
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          CategoryField(
            kind: kind,
            value: _category,
            noneChosen: true,
            onChanged: (v) => setState(() => _category = v),
          ),
          const SizedBox(height: 16),
          AccountField(
            label: tr('Account (when the message doesn\'t say)'),
            value: _account,
            onChanged: (v) => setState(() => _account = v),
          ),
          if (_account != null)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton(
                onPressed: () => setState(() => _account = null),
                child: Text(tr('Clear account')),
              ),
            ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: () async {
              await state.saveMerchantRule(MerchantRule(
                merchant: widget.rule.merchant,
                payee: _name.text.trim(),
                categoryId: _category,
                accountId: _account,
              ));
              if (context.mounted) Navigator.pop(context);
            },
            child: Text(tr('Save')),
          ),
        ],
      ),
    );
  }
}
