import 'package:flutter/material.dart';

import '../data/models.dart';
import '../state/app_state.dart';
import '../util/currencies.dart';
import '../util/format.dart';
import 'widgets.dart';

class AccountEditScreen extends StatefulWidget {
  const AccountEditScreen({super.key, this.account});

  final Account? account;

  @override
  State<AccountEditScreen> createState() => _AccountEditScreenState();
}

class _AccountEditScreenState extends State<AccountEditScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _opening;
  late AccountType _type;
  late String _currency;
  late bool _archived;
  bool _saving = false;

  bool get _isNew => widget.account == null;

  @override
  void initState() {
    super.initState();
    final a = widget.account;
    _name = TextEditingController(text: a?.name ?? '');
    _opening = TextEditingController(
        text: a == null ? '' : fmtAmount(a.openingBalance).replaceAll(',', ''));
    _type = a?.type ?? AccountType.bank;
    _archived = a?.archived ?? false;
    _currency = a?.currency ?? 'EGP';
  }

  bool _defaultsApplied = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_defaultsApplied) {
      _defaultsApplied = true;
      if (_isNew) _currency = AppScope.read(context).baseCurrency;
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _opening.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final state = AppScope.read(context);
    final a = Account(
      id: widget.account?.id,
      name: _name.text.trim(),
      type: _type,
      currency: _currency,
      openingBalance: parseAmount(_opening.text) ?? 0,
      archived: _archived,
      sortOrder: widget.account?.sortOrder ?? 0,
    );
    await state.saveAccount(a);
    if (!mounted) return;
    Navigator.pop(context);
  }

  Future<void> _delete() async {
    final state = AppScope.read(context);
    final id = widget.account!.id!;
    final count = await state.db.countAccountTransactions(id);
    if (!mounted) return;
    final ok = await confirmDialog(
      context,
      title: 'Delete account?',
      message: count == 0
          ? 'This account has no transactions.'
          : 'This will also delete $count transaction(s) linked to this account. '
              'Consider archiving it instead.',
    );
    if (!ok) return;
    await state.deleteAccount(id);
    if (!mounted) return;
    Navigator.of(context).popUntil((r) => r.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isNew ? 'New account' : 'Edit account'),
        actions: [
          if (!_isNew)
            IconButton(
              tooltip: 'Delete',
              icon: const Icon(Icons.delete_outline),
              onPressed: _delete,
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Name',
                hintText: 'e.g. CIB Current, Wallet cash',
                border: OutlineInputBorder(),
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Enter a name' : null,
            ),
            const SizedBox(height: 16),
            LabeledDropdown<AccountType>(
              label: 'Type',
              value: _type,
              items: [
                for (final t in AccountType.values)
                  DropdownMenuItem(value: t, child: Text(t.label)),
              ],
              onChanged: (v) => setState(() => _type = v ?? _type),
            ),
            const SizedBox(height: 16),
            InkWell(
              borderRadius: BorderRadius.circular(4),
              onTap: () async {
                final c = await pickCurrency(context, current: _currency);
                if (c != null) setState(() => _currency = c);
              },
              child: InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Currency',
                  border: OutlineInputBorder(),
                  suffixIcon: Icon(Icons.arrow_drop_down),
                ),
                child: Text('$_currency — ${currencyName(_currency)}'),
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _opening,
              keyboardType: const TextInputType.numberWithOptions(
                  decimal: true, signed: true),
              decoration: InputDecoration(
                labelText: 'Opening balance',
                helperText: _type == AccountType.creditCard
                    ? 'Use a negative number for money you owe'
                    : 'Balance before your first recorded transaction',
                suffixText: _currency,
                border: const OutlineInputBorder(),
              ),
              validator: (v) {
                if (v == null || v.trim().isEmpty) return null;
                return parseAmount(v) == null ? 'Invalid number' : null;
              },
            ),
            if (!_isNew) ...[
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Archived'),
                subtitle: const Text('Hide from lists and net worth'),
                value: _archived,
                onChanged: (v) => setState(() => _archived = v),
              ),
            ],
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: const Padding(
                padding: EdgeInsets.all(12),
                child: Text('Save'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
