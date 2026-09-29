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

/// Free-text bank name with suggestions from banks already used.
class _BankField extends StatelessWidget {
  const _BankField(
      {required this.initial, required this.options, required this.onChanged});

  final String initial;
  final List<String> options;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Autocomplete<String>(
      initialValue: TextEditingValue(text: initial),
      optionsBuilder: (v) {
        final q = v.text.trim().toLowerCase();
        if (q.isEmpty) return options;
        return options.where((o) => o.toLowerCase().contains(q));
      },
      onSelected: onChanged,
      fieldViewBuilder: (context, controller, focus, onSubmit) => TextFormField(
        controller: controller,
        focusNode: focus,
        textCapitalization: TextCapitalization.words,
        decoration: const InputDecoration(
          labelText: 'Bank',
          hintText: 'e.g. CIB, NBE, Banque Misr',
          border: OutlineInputBorder(),
          prefixIcon: Icon(Icons.account_balance),
        ),
        onChanged: onChanged,
      ),
    );
  }
}

class _AccountEditScreenState extends State<AccountEditScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _opening;
  String _bank = '';
  late AccountType _type;
  late String _currency;
  late bool _archived;
  late bool _exclude;
  bool _saving = false;
  late final TextEditingController _limit;
  late final TextEditingController _statementDay;
  late final TextEditingController _dueDay;
  late final TextEditingController _minPct;

  bool get _isNew => widget.account == null;

  @override
  void initState() {
    super.initState();
    final a = widget.account;
    _name = TextEditingController(text: a?.name ?? '');
    _type = a?.type ?? AccountType.bank;
    // Liabilities are entered as a positive "amount owed".
    final opening = a == null
        ? null
        : (_type.isLiability ? -a.openingBalance : a.openingBalance);
    _opening = TextEditingController(
        text: opening == null ? '' : fmtAmountRaw(opening).replaceAll(',', ''));
    _limit = TextEditingController(
        text: a?.creditLimit == null
            ? ''
            : fmtAmountRaw(a!.creditLimit!).replaceAll(',', ''));
    _statementDay =
        TextEditingController(text: a?.statementDay?.toString() ?? '');
    _dueDay = TextEditingController(text: a?.dueDay?.toString() ?? '');
    _minPct = TextEditingController(
        text: a?.minPayPct == null ? '5' : _trimNum(a!.minPayPct!));
    _bank = a?.bank ?? '';
    _archived = a?.archived ?? false;
    _exclude = a?.excludeTotal ?? false;
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
    _limit.dispose();
    _statementDay.dispose();
    _dueDay.dispose();
    _minPct.dispose();
    super.dispose();
  }

  static String _trimNum(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();

  static String? _dayValidator(String? v, {bool required = false}) {
    final t = (v ?? '').trim();
    if (t.isEmpty) return required ? 'Required' : null;
    final n = int.tryParse(t);
    if (n == null || n < 1 || n > 31) return '1–31';
    return null;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final state = AppScope.read(context);
    final opening = parseAmount(_opening.text) ?? 0;
    final card = _type == AccountType.creditCard;
    final a = Account(
      id: widget.account?.id,
      name: _name.text.trim(),
      bank: _type.hasBank ? _bank.trim() : '',
      type: _type,
      currency: _currency,
      openingBalance: _type.isLiability ? -opening.abs() : opening,
      archived: _archived,
      excludeTotal: _exclude,
      sortOrder: widget.account?.sortOrder ?? 0,
      creditLimit: card ? parseAmount(_limit.text)?.abs() : null,
      statementDay: card ? int.tryParse(_statementDay.text.trim()) : null,
      dueDay: card ? int.tryParse(_dueDay.text.trim()) : null,
      minPayPct: card ? parseAmount(_minPct.text)?.abs() : null,
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
          : 'This will also delete $count transaction(s) and any recurring items linked to this account. '
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
        title: Text(_isNew ? 'New Account' : 'Edit Account'),
        actions: [
          IconButton(
            tooltip: 'Save',
            icon: const Icon(Icons.check),
            onPressed: _saving ? null : _save,
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
                labelText: 'Account Name',
                hintText: 'e.g. Current, Visa Gold, Wallet',
                border: OutlineInputBorder(),
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Enter a name' : null,
            ),
            const SizedBox(height: 16),
            InkWell(
              borderRadius: BorderRadius.circular(4),
              onTap: () async {
                final t = await _pickType(context, _type);
                if (t != null) {
                  setState(() {
                    // New gold accounts are measured in grams by default.
                    if (_isNew && t == AccountType.gold && !isGold(_currency)) {
                      _currency = 'XAU21';
                    } else if (_isNew && t != AccountType.gold && isGold(_currency)) {
                      _currency = AppScope.read(context).baseCurrency;
                    }
                    _type = t;
                  });
                }
              },
              child: InputDecorator(
                decoration: InputDecoration(
                  labelText: 'Account Type',
                  border: const OutlineInputBorder(),
                  prefixIcon: Icon(accountTypeIcon(_type)),
                  suffixIcon: const Icon(Icons.arrow_drop_down),
                ),
                child: Text('${_type.label}  ·  ${_type.family.label}'),
              ),
            ),
            if (_type.hasBank) ...[
              const SizedBox(height: 16),
              _BankField(
                initial: _bank,
                options: AppScope.of(context).bankNames,
                onChanged: (v) => _bank = v,
              ),
            ],
            const SizedBox(height: 16),
            if (_type == AccountType.gold && _isNew) ...[
              Text('Measured In', style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 8),
              SegmentedButton<String>(
                showSelectedIcon: false,
                segments: [
                  const ButtonSegment(value: 'XAU24', label: Text('24K g')),
                  const ButtonSegment(value: 'XAU21', label: Text('21K g')),
                  const ButtonSegment(value: 'XAU18', label: Text('18K g')),
                  ButtonSegment(
                      value: AppScope.read(context).baseCurrency,
                      label: Text(AppScope.read(context).baseCurrency)),
                ],
                selected: {_currency},
                onSelectionChanged: (v) => setState(() => _currency = v.first),
              ),
              const SizedBox(height: 4),
              Text(
                isGold(_currency)
                    ? 'Grams of ${goldKarat(_currency)}K gold, valued at today\'s price per gram.'
                    : 'Tracked as money (what you paid), not by weight.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ] else
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
                labelText: _type.isLiability
                    ? 'Amount owed at start'
                    : (isGold(_currency) ? 'Grams You Hold Now' : 'Opening balance'),
                helperText: _type.isLiability
                    ? 'What you owed before your first recorded transaction'
                    : 'Balance before your first recorded transaction',
                suffixText: currencyUnit(_currency),
                border: const OutlineInputBorder(),
              ),
              validator: (v) {
                if (v == null || v.trim().isEmpty) return null;
                return parseAmount(v) == null ? 'Invalid number' : null;
              },
            ),
            if (_type == AccountType.creditCard) ...[
              const SizedBox(height: 24),
              Text('Credit Card',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: Theme.of(context).colorScheme.primary)),
              const SizedBox(height: 12),
              TextFormField(
                controller: _limit,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: 'Credit Limit',
                  suffixText: currencyUnit(_currency),
                  border: const OutlineInputBorder(),
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return null;
                  return parseAmount(v) == null ? 'Invalid number' : null;
                },
              ),
              const SizedBox(height: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _statementDay,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Statement Closing Day',
                        helperText: 'Cycle end, e.g. 25',
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) => _dayValidator(v,
                          required: _dueDay.text.trim().isNotEmpty),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _dueDay,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Payment Due Day',
                        helperText: 'Of the next month, e.g. 15',
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) => _dayValidator(v,
                          required: _statementDay.text.trim().isNotEmpty),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _minPct,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Minimum Payment',
                  suffixText: '% of statement',
                  border: OutlineInputBorder(),
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return null;
                  final n = parseAmount(v);
                  return n == null || n < 0 || n > 100 ? '0–100' : null;
                },
              ),
            ],
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Exclude from Net Worth'),
              subtitle: const Text('Track it, but leave it out of totals'),
              value: _exclude,
              onChanged: (v) => setState(() => _exclude = v),
            ),
            if (!_isNew) ...[
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
            if (!_isNew) ...[
              const SizedBox(height: 32),
              const Divider(),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.error,
                  side: BorderSide(color: Theme.of(context).colorScheme.error),
                  padding: const EdgeInsets.all(12),
                ),
                icon: const Icon(Icons.delete_outline),
                label: const Text('Delete Account'),
                onPressed: _delete,
              ),
              const SizedBox(height: 16),
            ],
          ],
        ),
      ),
    );
  }
}

/// Type picker grouped by family.
Future<AccountType?> _pickType(BuildContext context, AccountType current) {
  return showModalBottomSheet<AccountType>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => SizedBox(
      height: MediaQuery.of(ctx).size.height * 0.75,
      child: ListView(
        children: [
          for (final f in AccountFamily.values) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Text(f.label,
                  style: Theme.of(ctx).textTheme.labelLarge?.copyWith(
                      color: Theme.of(ctx).colorScheme.primary,
                      fontWeight: FontWeight.bold)),
            ),
            for (final t in AccountType.values.where((t) => t.family == f))
              ListTile(
                leading: Icon(accountTypeIcon(t)),
                title: Text(t.label),
                selected: t == current,
                onTap: () => Navigator.pop(ctx, t),
              ),
          ],
        ],
      ),
    ),
  );
}
