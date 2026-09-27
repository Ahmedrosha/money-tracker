import 'package:flutter/material.dart';

import '../data/models.dart';
import '../state/app_state.dart';
import '../util/format.dart';
import 'account_edit.dart';
import 'widgets.dart';

class TransactionEditScreen extends StatefulWidget {
  const TransactionEditScreen({super.key, this.txn, this.initialAccountId});

  final Txn? txn;
  final int? initialAccountId;

  @override
  State<TransactionEditScreen> createState() => _TransactionEditScreenState();
}

class _TransactionEditScreenState extends State<TransactionEditScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _amount;
  late final TextEditingController _toAmount;
  late final TextEditingController _payee;
  late final TextEditingController _note;

  late TxType _type;
  int? _accountId;
  int? _toAccountId;
  int? _categoryId;
  late DateTime _date;

  /// True once the user typed the received amount themselves.
  bool _toAmountEdited = false;
  bool _saving = false;
  bool _initialized = false;

  bool get _isNew => widget.txn == null;

  @override
  void initState() {
    super.initState();
    final t = widget.txn;
    _type = t?.type ?? TxType.expense;
    _amount = TextEditingController(
        text: t == null ? '' : _plain(t.amount));
    _toAmount = TextEditingController(
        text: t?.toAmount == null ? '' : _plain(t!.toAmount!));
    _toAmountEdited = t?.toAmount != null;
    _payee = TextEditingController(text: t?.payee ?? '');
    _note = TextEditingController(text: t?.note ?? '');
    _accountId = t?.accountId ?? widget.initialAccountId;
    _toAccountId = t?.toAccountId;
    _categoryId = t?.categoryId;
    _date = t?.date ?? DateTime.now();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    final state = AppScope.read(context);
    final active = state.activeAccounts;
    if (_accountId == null && active.isNotEmpty) {
      _accountId = active.first.id;
    }
  }

  @override
  void dispose() {
    _amount.dispose();
    _toAmount.dispose();
    _payee.dispose();
    _note.dispose();
    super.dispose();
  }

  static String _plain(double v) {
    final s = v.toStringAsFixed(8);
    // Trim trailing zeros but keep at least 2 decimals.
    var trimmed = s.replaceFirst(RegExp(r'0+$'), '');
    if (trimmed.endsWith('.')) trimmed = '${trimmed}00';
    final dot = trimmed.indexOf('.');
    if (dot >= 0 && trimmed.length - dot - 1 < 2) {
      trimmed = trimmed.padRight(dot + 3, '0');
    }
    return trimmed;
  }

  bool _currenciesDiffer(AppState state) {
    final a = state.accountById(_accountId);
    final b = state.accountById(_toAccountId);
    return a != null && b != null && a.currency != b.currency;
  }

  void _recalcToAmount() {
    if (_toAmountEdited) return;
    final state = AppScope.read(context);
    final a = state.accountById(_accountId);
    final b = state.accountById(_toAccountId);
    final amt = parseAmount(_amount.text);
    if (a == null || b == null || amt == null || a.currency == b.currency) {
      return;
    }
    final conv = state.convert(amt, a.currency, b.currency);
    if (conv != null) _toAmount.text = conv.toStringAsFixed(2);
  }

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (d == null || !mounted) return;
    final tm = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_date),
    );
    setState(() {
      _date = DateTime(d.year, d.month, d.day, tm?.hour ?? _date.hour,
          tm?.minute ?? _date.minute);
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final state = AppScope.read(context);
    final amount = parseAmount(_amount.text)!.abs();
    double? toAmount;
    if (_type == TxType.transfer) {
      if (_currenciesDiffer(state)) {
        toAmount = parseAmount(_toAmount.text)?.abs();
        if (toAmount == null) {
          showSnack(context, 'Enter the amount received');
          return;
        }
      }
    }
    setState(() => _saving = true);
    final t = Txn(
      id: widget.txn?.id,
      type: _type,
      date: _date,
      amount: amount,
      accountId: _accountId!,
      toAccountId: _type == TxType.transfer ? _toAccountId : null,
      toAmount: toAmount,
      categoryId: _type == TxType.transfer ? null : _categoryId,
      payee: _type == TxType.transfer ? '' : _payee.text.trim(),
      note: _note.text.trim(),
    );
    await state.saveTxn(t);
    if (!mounted) return;
    Navigator.pop(context);
  }

  Future<void> _delete() async {
    final ok = await confirmDialog(context,
        title: 'Delete transaction?', message: 'This cannot be undone.');
    if (!ok || !mounted) return;
    await AppScope.read(context).deleteTxn(widget.txn!.id!);
    if (!mounted) return;
    Navigator.pop(context);
  }

  List<DropdownMenuItem<int>> _accountItems(AppState state, int? keepId) {
    final list = state.accounts
        .where((a) => !a.archived || a.id == keepId)
        .toList();
    return [
      for (final a in list)
        DropdownMenuItem(
          value: a.id,
          child: Text('${a.name} (${a.currency})',
              overflow: TextOverflow.ellipsis),
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);

    if (state.activeAccounts.isEmpty && _isNew) {
      return Scaffold(
        appBar: AppBar(title: const Text('New transaction')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Add an account first.'),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const AccountEditScreen()),
                  ),
                  child: const Text('Add account'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final account = state.accountById(_accountId);
    final toAccount = state.accountById(_toAccountId);
    final differ = _type == TxType.transfer && _currenciesDiffer(state);
    final cats = state.categoriesOf(_type);
    final rate = differ
        ? state.rate(account!.currency, toAccount!.currency)
        : null;

    return Scaffold(
      appBar: AppBar(
        title: Text(_isNew ? 'New transaction' : 'Edit transaction'),
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
            SegmentedButton<TxType>(
              segments: const [
                ButtonSegment(
                    value: TxType.expense,
                    label: Text('Expense'),
                    icon: Icon(Icons.remove)),
                ButtonSegment(
                    value: TxType.income,
                    label: Text('Income'),
                    icon: Icon(Icons.add)),
                ButtonSegment(
                    value: TxType.transfer,
                    label: Text('Transfer'),
                    icon: Icon(Icons.swap_horiz)),
              ],
              selected: {_type},
              onSelectionChanged: (s) => setState(() {
                _type = s.first;
                final c = state.categoryById(_categoryId);
                if (c != null && c.kind != _type) _categoryId = null;
                _recalcToAmount();
              }),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _amount,
              autofocus: _isNew,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              style: Theme.of(context).textTheme.headlineSmall,
              decoration: InputDecoration(
                labelText: 'Amount',
                suffixText: account?.currency,
                border: const OutlineInputBorder(),
              ),
              validator: (v) {
                final a = parseAmount(v ?? '');
                if (a == null) return 'Enter an amount';
                if (a == 0) return 'Amount cannot be zero';
                return null;
              },
              onChanged: (_) => setState(_recalcToAmount),
            ),
            const SizedBox(height: 16),
            LabeledDropdown<int>(
              label: _type == TxType.transfer ? 'From account' : 'Account',
              value: _accountId,
              items: _accountItems(state, widget.txn?.accountId),
              onChanged: (v) => setState(() {
                _accountId = v;
                _recalcToAmount();
              }),
            ),
            if (_type == TxType.transfer) ...[
              const SizedBox(height: 16),
              FormField<int>(
                validator: (_) {
                  if (_toAccountId == null) return 'Choose destination';
                  if (_toAccountId == _accountId) {
                    return 'Choose a different account';
                  }
                  return null;
                },
                builder: (field) => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    LabeledDropdown<int>(
                      label: 'To account',
                      value: _toAccountId,
                      hint: 'Select',
                      items: _accountItems(state, widget.txn?.toAccountId),
                      onChanged: (v) => setState(() {
                        _toAccountId = v;
                        _recalcToAmount();
                      }),
                    ),
                    if (field.hasError)
                      Padding(
                        padding: const EdgeInsets.only(left: 12, top: 6),
                        child: Text(field.errorText!,
                            style: TextStyle(
                                color: Theme.of(context).colorScheme.error,
                                fontSize: 12)),
                      ),
                  ],
                ),
              ),
              if (differ) ...[
                const SizedBox(height: 16),
                TextFormField(
                  controller: _toAmount,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: 'Amount received',
                    suffixText: toAccount!.currency,
                    helperText: rate == null
                        ? 'No rate available — enter manually'
                        : '1 ${account!.currency} = ${fmtRate(rate)} ${toAccount!.currency}'
                            '${_toAmountEdited ? ' (edited)' : ''}',
                    border: const OutlineInputBorder(),
                    suffixIcon: _toAmountEdited
                        ? IconButton(
                            tooltip: 'Recalculate from rate',
                            icon: const Icon(Icons.refresh),
                            onPressed: () => setState(() {
                              _toAmountEdited = false;
                              _recalcToAmount();
                            }),
                          )
                        : null,
                  ),
                  onChanged: (_) => setState(() => _toAmountEdited = true),
                ),
              ],
            ],
            if (_type != TxType.transfer) ...[
              const SizedBox(height: 16),
              LabeledDropdown<int>(
                label: 'Category',
                value: _categoryId,
                hint: 'Select category',
                items: [
                  for (final c in cats)
                    DropdownMenuItem(
                      value: c.id,
                      child: Row(
                        children: [
                          SizedBox(
                            width: 28,
                            height: 28,
                            child: FittedBox(
                                child: CategoryAvatar(category: c)),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                              child: Text(c.name,
                                  overflow: TextOverflow.ellipsis)),
                        ],
                      ),
                    ),
                ],
                onChanged: (v) => setState(() => _categoryId = v),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _payee,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                  labelText: _type == TxType.income ? 'From (payer)' : 'Payee / store',
                  border: const OutlineInputBorder(),
                ),
              ),
            ],
            const SizedBox(height: 16),
            InkWell(
              borderRadius: BorderRadius.circular(4),
              onTap: _pickDate,
              child: InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Date',
                  border: OutlineInputBorder(),
                  suffixIcon: Icon(Icons.calendar_today),
                ),
                child: Text(
                    '${dayFmt.format(_date)}  ${TimeOfDay.fromDateTime(_date).format(context)}'),
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _note,
              maxLines: 2,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Note',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _saving || _accountId == null ? null : _save,
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
