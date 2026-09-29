import 'package:flutter/material.dart';

import '../data/models.dart';
import '../state/app_state.dart';
import '../util/calc.dart';
import '../util/format.dart';
import 'account_edit.dart';
import 'calc_pad.dart';
import 'widgets.dart';

enum _Mode { newTxn, editTxn, editPlan, editRule, confirm }

/// One editor for everything that looks like a transaction:
/// - new entry (optionally split into installments or set to repeat)
/// - edit an existing entry
/// - edit a whole installment plan ([planTxn] = any installment of it)
/// - edit a recurring item ([rule])
/// - confirm a recurring occurrence with changes ([occurrence])
class TransactionEditScreen extends StatefulWidget {
  const TransactionEditScreen({
    super.key,
    this.txn,
    this.initialAccountId,
    this.initialDate,
    this.planTxn,
    this.rule,
    this.occurrence,
    this.initialType,
    this.initialToAccountId,
    this.initialAmount,
    this.initialNote,
  });

  final Txn? txn;
  final int? initialAccountId;
  final DateTime? initialDate;
  final Txn? planTxn;
  final RecurringRule? rule;
  final Occurrence? occurrence;

  // Prefill for new entries (e.g. paying a credit card).
  final TxType? initialType;
  final int? initialToAccountId;
  final double? initialAmount;
  final String? initialNote;

  @override
  State<TransactionEditScreen> createState() => _TransactionEditScreenState();
}

class _TransactionEditScreenState extends State<TransactionEditScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _amount;
  late final TextEditingController _toAmount;
  late final TextEditingController _payee;
  late final TextEditingController _note;
  late final TextEditingController _interval;
  late final TextEditingController _endCount;

  late _Mode _mode;
  late TxType _type;
  int? _accountId;
  int? _toAccountId;
  int? _categoryId;
  late DateTime _date;

  /// Card expenses: posting date set by hand. Null = follows [_date].
  DateTime? _postDate;

  // Installments
  bool _installments = false;
  int _months = 12;
  late DateTime _startMonth;

  // Repeat
  bool _repeat = false;
  Freq _freq = Freq.monthly;
  EndType _endType = EndType.never;
  DateTime? _endDate;

  /// True once the user typed the received amount themselves.
  bool _toAmountEdited = false;
  bool _saving = false;

  /// false = app calculator keypad, true = phone keyboard (typed math).
  bool _sysKeyboard = false;
  bool _initialized = false;

  InstallmentPlan? _plan;

  @override
  void initState() {
    super.initState();
    _amount = TextEditingController();
    _toAmount = TextEditingController();
    _payee = TextEditingController();
    _note = TextEditingController();
    _interval = TextEditingController(text: '1');
    _endCount = TextEditingController(text: '12');
    _type = TxType.expense;
    _date = widget.initialDate ?? DateTime.now();
    _accountId = widget.initialAccountId;

    if (widget.occurrence != null) {
      _mode = _Mode.confirm;
      _fillFromRule(widget.occurrence!.rule);
      _date = widget.occurrence!.date;
    } else if (widget.rule != null) {
      _mode = _Mode.editRule;
      _fillFromRule(widget.rule!);
      final r = widget.rule!;
      _repeat = true;
      _freq = r.freq;
      _interval.text = '${r.interval}';
      _endType = r.endType;
      _endDate = r.endDate;
      // The rule is edited "from the next occurrence on".
      _date = r.finished ? DateTime.now() : r.occurrence(r.nextIndex);
      if (r.endType == EndType.count) {
        final remaining = (r.endCount ?? 0) - r.nextIndex;
        _endCount.text = '${remaining < 1 ? 1 : remaining}';
      }
    } else if (widget.planTxn != null) {
      _mode = _Mode.editPlan;
      _fillFromTxn(widget.planTxn!);
    } else if (widget.txn != null) {
      _mode = _Mode.editTxn;
      _fillFromTxn(widget.txn!);
    } else {
      _mode = _Mode.newTxn;
      _type = widget.initialType ?? TxType.expense;
      _toAccountId = widget.initialToAccountId;
      if (widget.initialAmount != null) {
        _amount.text = widget.initialAmount!.toStringAsFixed(2);
      }
      _note.text = widget.initialNote ?? '';
    }
    _startMonth = DateTime(_date.year, _date.month + 1);
  }

  void _fillFromTxn(Txn t) {
    _type = t.type;
    _amount.text = _plain(t.amount);
    if (t.toAmount != null) {
      _toAmount.text = _plain(t.toAmount!);
      _toAmountEdited = true;
    }
    _payee.text = t.payee;
    _note.text = t.note;
    _accountId = t.accountId;
    _toAccountId = t.toAccountId;
    _categoryId = t.categoryId;
    _date = t.date;
    if (t.postedLater) _postDate = t.postDate;
  }

  void _fillFromRule(RecurringRule r) {
    _type = r.type;
    _amount.text = _plain(r.amount);
    if (r.toAmount != null) {
      _toAmount.text = _plain(r.toAmount!);
      _toAmountEdited = true;
    }
    _payee.text = r.payee;
    _note.text = r.note;
    _accountId = r.accountId;
    _toAccountId = r.toAccountId;
    _categoryId = r.categoryId;
  }

  Future<void> _openPad(TextEditingController c, String? currency,
      {bool received = false}) async {
    FocusScope.of(context).unfocus();
    await showCalcPad(context, c, currency: currency, onChanged: () {
      setState(() {
        if (received) {
          _toAmountEdited = true;
        } else {
          _recalcToAmount();
        }
      });
    });
    if (mounted) setState(() {});
  }

  /// Replaces typed math like "250+75" with its result.
  void _settleExpression(TextEditingController c) {
    if (!hasOperator(c.text)) return;
    final v = evaluateExpression(c.text);
    if (v != null) setState(() => c.text = calcResultText(v));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    if (_mode == _Mode.newTxn && widget.initialAmount == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final cur = AppScope.read(context).accountById(_accountId)?.currency;
        _openPad(_amount, cur);
      });
    }
    _initialized = true;
    final state = AppScope.read(context);
    if (_mode == _Mode.editPlan) {
      _plan = state.plans[widget.planTxn!.planId];
      if (_plan != null) {
        _installments = true;
        _months = _plan!.months;
        _amount.text = _plain(_plan!.total);
        _date = _plan!.purchaseDate;
        _startMonth = DateTime(_plan!.firstDate.year, _plan!.firstDate.month);
      }
    }
    final active = state.activeAccounts;
    if (_accountId == null && active.isNotEmpty) {
      _accountId = active.first.id;
    }
    // A prefilled transfer amount is in the destination's currency (e.g.
    // a card payment). If the source differs, convert and fix what arrives.
    final want = widget.initialAmount;
    if (_mode == _Mode.newTxn && want != null && _type == TxType.transfer) {
      final from = state.accountById(_accountId);
      final to = state.accountById(_toAccountId);
      if (from != null && to != null && from.currency != to.currency) {
        final conv = state.convert(want, to.currency, from.currency);
        if (conv != null) _amount.text = conv.toStringAsFixed(2);
        _toAmount.text = want.toStringAsFixed(2);
        _toAmountEdited = true;
      }
    }
  }

  @override
  void dispose() {
    _amount.dispose();
    _toAmount.dispose();
    _payee.dispose();
    _note.dispose();
    _interval.dispose();
    _endCount.dispose();
    super.dispose();
  }

  static String _plain(double v) {
    var s = v.toStringAsFixed(8).replaceFirst(RegExp(r'0+$'), '');
    if (s.endsWith('.')) s = '${s}00';
    final dot = s.indexOf('.');
    if (dot >= 0 && s.length - dot - 1 < 2) s = s.padRight(dot + 3, '0');
    return s;
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
      final moved = d.year != _date.year || d.month != _date.month;
      _date = DateTime(d.year, d.month, d.day, tm?.hour ?? _date.hour,
          tm?.minute ?? _date.minute);
      // A manual post date can't be before the transaction; if the date
      // moves past it (or onto it), the post date follows automatically.
      if (_postDate != null &&
          !DateTime(_postDate!.year, _postDate!.month, _postDate!.day)
              .isAfter(DateTime(_date.year, _date.month, _date.day))) {
        _postDate = null;
      }
      // Keep the default "first installment next month" in sync.
      if (moved && _mode == _Mode.newTxn) {
        _startMonth = DateTime(_date.year, _date.month + 1);
      }
    });
  }

  bool _showPostDate(AppState state) =>
      _type == TxType.expense &&
      !_installments &&
      !_repeat &&
      _mode != _Mode.editPlan &&
      _mode != _Mode.editRule &&
      (state.accountById(_accountId)?.isCard ?? false);

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  Future<void> _pickPostDate() async {
    final current = _postDate ?? _date;
    final d = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(_date.year, _date.month, _date.day),
      lastDate: DateTime(2100),
      helpText: 'Date the bank posted it',
    );
    if (d == null) return;
    setState(() {
      // Same day as the transaction = back to automatic.
      _postDate = _sameDay(d, _date)
          ? null
          : DateTime(d.year, d.month, d.day, _date.hour, _date.minute);
    });
  }

  Future<void> _pickEndDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _endDate ?? DateTime(_date.year + 1, _date.month, _date.day),
      firstDate: _date,
      lastDate: DateTime(2100),
    );
    if (d != null) setState(() => _endDate = d);
  }

  // ---------------- Save / delete ----------------

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final state = AppScope.read(context);
    // A negative expense is a refund; transfers are always positive.
    final raw = parseAmount(_amount.text)!;
    final amount =
        (_type == TxType.transfer || _installments || _repeat) ? raw.abs() : raw;
    double? toAmount;
    if (_type == TxType.transfer && _currenciesDiffer(state)) {
      toAmount = parseAmount(_toAmount.text)?.abs();
      if (toAmount == null) {
        showSnack(context, 'Enter the amount received');
        return;
      }
    }
    if (_repeat && _endType == EndType.date && _endDate == null) {
      showSnack(context, 'Pick an end date');
      return;
    }
    setState(() => _saving = true);

    final isTransfer = _type == TxType.transfer;
    final template = Txn(
      id: widget.txn?.id,
      type: _type,
      date: _date,
      amount: amount,
      accountId: _accountId!,
      toAccountId: isTransfer ? _toAccountId : null,
      toAmount: isTransfer ? toAmount : null,
      categoryId: isTransfer ? null : _categoryId,
      payee: isTransfer ? '' : _payee.text.trim(),
      note: _note.text.trim(),
      planId: widget.txn?.planId,
      planIndex: widget.txn?.planIndex,
      recurringId: widget.txn?.recurringId ?? widget.occurrence?.rule.id,
      // Where the post date isn't shown (e.g. a payment moved to another
      // statement), keep it as long as the date itself is unchanged.
      postDate: _showPostDate(state)
          ? (_postDate ?? _date)
          : (widget.txn != null && widget.txn!.date == _date
              ? widget.txn!.postDate
              : null),
      toPostDate: isTransfer &&
              widget.txn != null &&
              widget.txn!.date == _date &&
              widget.txn!.toAccountId == _toAccountId
          ? widget.txn!.toPostDate
          : null,
    );

    if (_installments && _type == TxType.expense) {
      final plan = InstallmentPlan(
        id: _plan?.id,
        total: amount,
        months: _months,
        purchaseDate: _date,
        firstDate: dateInMonth(_startMonth.year, _startMonth.month, _date.day,
            _date.hour, _date.minute),
      );
      await state.savePlan(plan, template);
    } else if (_mode == _Mode.editPlan && _plan != null) {
      // Plan turned off: replace all installments by one normal entry.
      await state.deletePlan(_plan!.id!);
      await state.saveTxn(Txn(
        type: template.type,
        date: _date,
        amount: amount,
        accountId: template.accountId,
        categoryId: template.categoryId,
        payee: template.payee,
        note: template.note,
      ));
    } else if (_repeat) {
      final interval = int.tryParse(_interval.text.trim()) ?? 1;
      final rule = RecurringRule(
        id: widget.rule?.id,
        type: _type,
        amount: amount,
        accountId: _accountId!,
        toAccountId: isTransfer ? _toAccountId : null,
        toAmount: isTransfer ? toAmount : null,
        categoryId: isTransfer ? null : _categoryId,
        payee: template.payee,
        note: template.note,
        freq: _freq,
        interval: interval < 1 ? 1 : interval,
        start: _date,
        endType: _endType,
        endCount: _endType == EndType.count
            ? (int.tryParse(_endCount.text.trim()) ?? 1)
            : null,
        endDate: _endType == EndType.date ? _endDate : null,
        nextIndex: 0,
      );
      if (_mode == _Mode.editRule) {
        await state.updateRule(rule);
      } else {
        await state.createRule(rule);
      }
    } else if (_mode == _Mode.confirm) {
      await state.confirmOccurrence(widget.occurrence!, template);
    } else {
      await state.saveTxn(template);
    }
    if (!mounted) return;
    Navigator.pop(context);
  }

  Future<void> _delete() async {
    final state = AppScope.read(context);
    switch (_mode) {
      case _Mode.editRule:
        final ok = await confirmDialog(context,
            title: 'Delete recurring item?',
            message:
                'Future occurrences stop. Entries already recorded are kept.');
        if (!ok) return;
        await state.deleteRule(widget.rule!.id!);
        break;
      case _Mode.editPlan:
        final ok = await confirmDialog(context,
            title: 'Delete whole plan?',
            message: 'All ${_plan?.months ?? ''} installments will be deleted.');
        if (!ok) return;
        await state.deletePlan(_plan!.id!);
        break;
      case _Mode.editTxn:
        final t = widget.txn!;
        if (t.planId != null) {
          final choice = await showDialog<String>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Delete Installment'),
              content: const Text(
                  'Delete only this installment, or the whole plan?'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Cancel')),
                TextButton(
                    onPressed: () => Navigator.pop(ctx, 'one'),
                    child: const Text('This One')),
                FilledButton(
                    onPressed: () => Navigator.pop(ctx, 'all'),
                    child: const Text('Whole Plan')),
              ],
            ),
          );
          if (choice == null) return;
          if (choice == 'all') {
            await state.deletePlan(t.planId!);
          } else {
            await state.deleteTxn(t.id!);
          }
        } else {
          final ok = await confirmDialog(context,
              title: 'Delete transaction?', message: 'This cannot be undone.');
          if (!ok) return;
          await state.deleteTxn(t.id!);
        }
        break;
      default:
        return;
    }
    if (!mounted) return;
    Navigator.pop(context);
  }

  // ---------------- UI ----------------

  String get _title {
    switch (_mode) {
      case _Mode.newTxn:
        return 'New Transaction';
      case _Mode.editTxn:
        return 'Edit Transaction';
      case _Mode.editPlan:
        return 'Edit installment plan';
      case _Mode.editRule:
        return 'Edit recurring item';
      case _Mode.confirm:
        return 'Confirm recurring item';
    }
  }

  bool get _canDelete =>
      _mode == _Mode.editTxn ||
      _mode == _Mode.editRule ||
      (_mode == _Mode.editPlan && _plan != null);

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);

    if (state.activeAccounts.isEmpty && _mode == _Mode.newTxn) {
      return Scaffold(
        appBar: AppBar(title: const Text('New Transaction')),
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
                  child: const Text('Add Account'),
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
    final rate =
        differ ? state.rate(account!.currency, toAccount!.currency) : null;
    final typeLocked = _mode == _Mode.editPlan || _mode == _Mode.confirm;

    return Scaffold(
      appBar: AppBar(
        title: Text(_title),
        actions: [
          if (_canDelete)
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
            ..._banners(state),
            if (!typeLocked)
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
                  if (_type != TxType.expense) _installments = false;
                  _recalcToAmount();
                }),
              ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _amount,
              readOnly: !_sysKeyboard,
              showCursor: true,
              autofocus: _sysKeyboard && _mode == _Mode.newTxn,
              keyboardType: TextInputType.text,
              onTap: _sysKeyboard
                  ? null
                  : () => _openPad(_amount, account?.currency),
              onFieldSubmitted: (_) => _settleExpression(_amount),
              onTapOutside: (_) => _settleExpression(_amount),
              style: Theme.of(context).textTheme.headlineSmall,
              decoration: InputDecoration(
                labelText: _installments ? 'Total amount' : 'Amount',
                helperText: _amountHelper(state, account),
                helperStyle: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.w600),
                suffixText: account?.currency,
                suffixIcon: IconButton(
                  tooltip:
                      _sysKeyboard ? 'Use calculator' : 'Use phone keyboard',
                  icon: Icon(_sysKeyboard
                      ? Icons.calculate_outlined
                      : Icons.keyboard_outlined),
                  onPressed: () {
                    setState(() => _sysKeyboard = !_sysKeyboard);
                    if (!_sysKeyboard) {
                      _settleExpression(_amount);
                      _openPad(_amount, account?.currency);
                    }
                  },
                ),
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
            AccountField(
              label: _type == TxType.transfer ? 'From account' : 'Account',
              value: _accountId,
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
                builder: (field) => AccountField(
                  label: 'To Account',
                  value: _toAccountId,
                  errorText: field.errorText,
                  onChanged: (v) => setState(() {
                    _toAccountId = v;
                    _recalcToAmount();
                  }),
                ),
              ),
              if (differ) ...[
                const SizedBox(height: 16),
                TextFormField(
                  controller: _toAmount,
                  readOnly: !_sysKeyboard,
                  showCursor: true,
                  keyboardType: TextInputType.text,
                  onTap: _sysKeyboard
                      ? null
                      : () => _openPad(_toAmount, toAccount?.currency,
                          received: true),
                  onFieldSubmitted: (_) => _settleExpression(_toAmount),
                  onTapOutside: (_) => _settleExpression(_toAmount),
                  decoration: InputDecoration(
                    labelText: 'Amount Received',
                    suffixText: toAccount!.currency,
                    helperText: rate == null
                        ? 'No rate available — enter manually'
                        : '1 ${account!.currency} = ${fmtRate(rate)} ${toAccount.currency}'
                            '${_toAmountEdited ? ' (edited)' : ''}',
                    border: const OutlineInputBorder(),
                    suffixIcon: _toAmountEdited
                        ? IconButton(
                            tooltip: 'Recalculate from Rate',
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
              CategoryField(
                kind: _type,
                value: _categoryId,
                onChanged: (v) => setState(() => _categoryId = v),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _payee,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                  labelText:
                      _type == TxType.income ? 'From (payer)' : 'Payee / store',
                  border: const OutlineInputBorder(),
                ),
              ),
            ],
            const SizedBox(height: 16),
            InkWell(
              borderRadius: BorderRadius.circular(4),
              onTap: _pickDate,
              child: InputDecorator(
                decoration: InputDecoration(
                  labelText: _dateLabel,
                  border: const OutlineInputBorder(),
                  suffixIcon: const Icon(Icons.calendar_today),
                ),
                child: Text(
                    '${dayFmt.format(_date)}  ${TimeOfDay.fromDateTime(_date).format(context)}'),
              ),
            ),
            if (_showPostDate(state)) ...[
              const SizedBox(height: 16),
              InkWell(
                borderRadius: BorderRadius.circular(4),
                onTap: _pickPostDate,
                child: InputDecorator(
                  decoration: InputDecoration(
                    labelText: 'Post Date',
                    helperText: _postDate == null
                        ? 'Same as transaction date — change it if the bank posted it later'
                        : 'Decides which statement it falls in',
                    border: const OutlineInputBorder(),
                    suffixIcon: _postDate == null
                        ? const Icon(Icons.event_available)
                        : IconButton(
                            tooltip: 'Same as transaction date',
                            icon: const Icon(Icons.restart_alt),
                            onPressed: () => setState(() => _postDate = null),
                          ),
                  ),
                  child: Text(dayFmt.format(_postDate ?? _date),
                      style: _postDate == null
                          ? TextStyle(
                              color:
                                  Theme.of(context).colorScheme.onSurfaceVariant)
                          : null),
                ),
              ),
            ],
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
            ..._installmentSection(account),
            ..._repeatSection(),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _saving || _accountId == null ? null : _save,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(_mode == _Mode.confirm ? 'Confirm' : 'Save'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Small line under the amount: the EGP (main currency) equivalent for
  /// foreign-currency expenses and income, and a refund hint.
  String? _amountHelper(AppState state, Account? account) {
    final parts = <String>[];
    final amt = parseAmount(_amount.text);
    if (hasOperator(_amount.text)) {
      parts.add(amt == null ? 'Incomplete calculation' : '= ${fmtAmountRaw(amt)}');
    }
    final base = state.baseCurrency;
    if (account != null &&
        _type != TxType.transfer &&
        account.currency != base &&
        amt != null &&
        amt != 0) {
      final v = state.convert(amt, account.currency, base);
      parts.add(v == null
          ? 'No $base rate for ${account.currency} yet'
          : '≈ ${fmtMoneyRaw(v, base)}');
    }
    if (_type == TxType.expense && (amt ?? 0) < 0) parts.add('negative = refund');
    return parts.isEmpty ? null : parts.join(' · ');
  }

  String get _dateLabel {
    if (_installments) return 'Purchase date';
    if (_mode == _Mode.editRule) return 'Next date';
    if (_repeat) return 'First date';
    return 'Date';
  }

  List<Widget> _banners(AppState state) {
    final out = <Widget>[];
    final t = widget.txn;
    if (_mode == _Mode.editTxn && t != null && t.planId != null) {
      final plan = state.plans[t.planId];
      out.add(Card(
        child: ListTile(
          leading: const Icon(Icons.view_week_outlined),
          title: Text('Installment ${t.planIndex}/${plan?.months ?? '?'}'),
          subtitle: Text(plan == null
              ? 'Changes here apply to this installment only'
              : 'Total ${fmtAmountRaw(plan.total)} · changes here apply to this installment only'),
          trailing: plan == null
              ? null
              : TextButton(
                  onPressed: () => Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(
                        builder: (_) => TransactionEditScreen(planTxn: t)),
                  ),
                  child: const Text('Edit Plan'),
                ),
        ),
      ));
    }
    if (_mode == _Mode.editTxn && t != null && t.recurringId != null) {
      final rule = state.ruleById(t.recurringId);
      out.add(Card(
        child: ListTile(
          leading: const Icon(Icons.repeat),
          title: const Text('From a Recurring Item'),
          subtitle: Text(rule == null
              ? 'The recurring item was deleted'
              : '${rule.scheduleLabel} · changes here apply to this entry only'),
          trailing: rule == null
              ? null
              : TextButton(
                  onPressed: () => Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(
                        builder: (_) => TransactionEditScreen(rule: rule)),
                  ),
                  child: const Text('Edit All'),
                ),
        ),
      ));
    }
    if (_mode == _Mode.editRule) {
      out.add(const Card(
        child: ListTile(
          leading: Icon(Icons.info_outline),
          title: Text('Changes apply from the next date on'),
          subtitle: Text('Entries already recorded are not changed.'),
        ),
      ));
    }
    if (_mode == _Mode.editPlan) {
      out.add(const Card(
        child: ListTile(
          leading: Icon(Icons.info_outline),
          title: Text('Saving rebuilds all installments of this plan'),
        ),
      ));
    }
    if (out.isNotEmpty) out.add(const SizedBox(height: 8));
    return out;
  }

  List<Widget> _installmentSection(Account? account) {
    if (_type != TxType.expense) return const [];
    if (_mode != _Mode.newTxn && _mode != _Mode.editPlan) return const [];
    final total = parseAmount(_amount.text)?.abs();
    final parts =
        total == null || total == 0 ? null : InstallmentPlan.split(total, _months);
    final lastMonth = DateTime(_startMonth.year, _startMonth.month + _months - 1);
    // Offer start months from 2 months before the purchase to 12 after.
    final base = DateTime(_date.year, _date.month);
    final monthOptions = [
      for (var i = -2; i <= 12; i++) DateTime(base.year, base.month + i),
    ];
    if (!monthOptions.contains(_startMonth)) monthOptions.add(_startMonth);
    monthOptions.sort();

    return [
      const SizedBox(height: 8),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        secondary: const Icon(Icons.view_week_outlined),
        title: const Text('Split Into Monthly Installments'),
        subtitle: const Text('e.g. credit card installments'),
        value: _installments,
        onChanged: (v) => setState(() {
          _installments = v;
          if (v) _repeat = false;
        }),
      ),
      if (_installments) ...[
        Row(
          children: [
            Expanded(
              child: LabeledDropdown<int>(
                label: 'Months',
                value: _months,
                items: [
                  for (var m = 2; m <= 24; m++)
                    DropdownMenuItem(value: m, child: Text('$m')),
                ],
                onChanged: (v) => setState(() => _months = v ?? _months),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: LabeledDropdown<DateTime>(
                label: 'First Installment',
                value: _startMonth,
                items: [
                  for (final m in monthOptions)
                    DropdownMenuItem(value: m, child: Text(monthFmt.format(m))),
                ],
                onChanged: (v) => setState(() => _startMonth = v ?? _startMonth),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (parts != null)
          Text(
            '$_months × ${fmtAmountRaw(parts.first)} ${account?.currency ?? ''}'
            '${parts.last != parts.first ? ' (last ${fmtAmountRaw(parts.last)})' : ''}'
            '\n${monthFmt.format(_startMonth)} → ${monthFmt.format(lastMonth)}, on day ${_date.day}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
      ],
    ];
  }

  List<Widget> _repeatSection() {
    if (_mode != _Mode.newTxn && _mode != _Mode.editRule) return const [];
    final interval = int.tryParse(_interval.text) ?? 1;
    return [
      if (_mode == _Mode.newTxn)
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          secondary: const Icon(Icons.repeat),
          title: const Text('Repeat'),
          subtitle: const Text('Subscriptions, salary, rent…'),
          value: _repeat,
          onChanged: (v) => setState(() {
            _repeat = v;
            if (v) _installments = false;
          }),
        ),
      if (_repeat) ...[
        const SizedBox(height: 8),
        Row(
          children: [
            SizedBox(
              width: 90,
              child: TextFormField(
                controller: _interval,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Every',
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: LabeledDropdown<Freq>(
                label: 'Period',
                value: _freq,
                items: [
                  for (final f in Freq.values)
                    DropdownMenuItem(
                        value: f,
                        child: Text(f.unit(interval < 1 ? 1 : interval))),
                ],
                onChanged: (v) => setState(() => _freq = v ?? _freq),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        const Text('Ends'),
        const SizedBox(height: 6),
        SegmentedButton<EndType>(
          segments: const [
            ButtonSegment(value: EndType.never, label: Text('Never')),
            ButtonSegment(value: EndType.count, label: Text('After')),
            ButtonSegment(value: EndType.date, label: Text('On Date')),
          ],
          selected: {_endType},
          onSelectionChanged: (s) => setState(() => _endType = s.first),
        ),
        if (_endType == EndType.count) ...[
          const SizedBox(height: 12),
          TextFormField(
            controller: _endCount,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: _mode == _Mode.editRule
                  ? 'Remaining times'
                  : 'Number of times',
              border: const OutlineInputBorder(),
            ),
            validator: (v) {
              final n = int.tryParse((v ?? '').trim());
              return n == null || n < 1 ? 'Enter 1 or more' : null;
            },
          ),
        ],
        if (_endType == EndType.date) ...[
          const SizedBox(height: 12),
          InkWell(
            borderRadius: BorderRadius.circular(4),
            onTap: _pickEndDate,
            child: InputDecorator(
              decoration: const InputDecoration(
                labelText: 'End Date',
                border: OutlineInputBorder(),
                suffixIcon: Icon(Icons.event),
              ),
              child: Text(
                  _endDate == null ? 'Select' : shortDateFmt.format(_endDate!)),
            ),
          ),
        ],
        const SizedBox(height: 8),
        Text(
          'When each date arrives it appears under "To confirm" so you can '
          'record it (and adjust the amount if needed).',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    ];
  }
}
