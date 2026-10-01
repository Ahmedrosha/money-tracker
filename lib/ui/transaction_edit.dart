import 'package:flutter/material.dart';

import '../data/models.dart';
import '../state/app_state.dart';
import '../util/calc.dart';
import '../util/format.dart';
import '../util/currencies.dart';
import 'account_edit.dart';
import 'calc_pad.dart';
import 'widgets.dart';
import '../l10n/l10n.dart';

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
    this.initialPayee,
    this.initialCategoryId,
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
  final String? initialPayee;
  final int? initialCategoryId;

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

  /// A category (or "No category") was picked on purpose. New entries
  /// start without one; Save asks for it.
  bool _categoryChosen = true;
  late DateTime _date;

  /// Card expenses: posting date set by hand. Null = follows [_date].
  DateTime? _postDate;

  // Installments
  bool _installments = false;

  // One payment split across several categories (new entries only).
  bool _split = false;
  final List<_SplitRow> _rows = [];

  bool get _canSplit =>
      _mode == _Mode.newTxn &&
      _type != TxType.transfer &&
      !_installments &&
      !_repeat;

  double get _splitAssigned => _rows.fold(
      0.0, (sum, r) => sum + (parseAmount(r.amount.text) ?? 0));

  void _startSplit() {
    final total = parseAmount(_amount.text) ?? 0;
    _rows
      ..clear()
      ..add(_SplitRow(_categoryChosen ? _categoryId : null,
          _categoryChosen, total == 0 ? '' : _plain(total)))
      ..add(_SplitRow(null, false, ''));
    _split = true;
  }

  void _addSplitRow() {
    final left = (parseAmount(_amount.text) ?? 0) - _splitAssigned;
    _rows.add(_SplitRow(null, false, left > 0.004 ? _plain(left) : ''));
  }
  int _months = 12;
  late DateTime _startMonth;

  // Repeat
  bool _repeat = false;
  Freq _freq = Freq.monthly;
  EndType _endType = EndType.never;
  DateTime? _endDate;

  // InstaPay fee (new expenses and transfers only).
  bool _instaPay = false;
  final _fee = TextEditingController();
  bool _feeEdited = false;

  /// Fee already linked to the transaction being edited.
  Txn? _existingFee;

  bool get _showFee =>
      (_mode == _Mode.newTxn ||
          _mode == _Mode.confirm ||
          (_mode == _Mode.editTxn &&
              widget.txn?.planId == null &&
              widget.txn?.feeFor == null)) &&
      (_type == TxType.expense || _type == TxType.transfer) &&
      !_installments &&
      !_repeat;

  Future<void> _loadFee(int txnId) async {
    final f = await AppScope.read(context).db.feeOf(txnId);
    if (f == null || !mounted) return;
    setState(() {
      _existingFee = f;
      _instaPay = true;
      _feeEdited = true; // keep the amount that was saved
      _fee.text = f.amount.toStringAsFixed(2);
    });
  }

  void _updateFee() {
    if (!_instaPay || _feeEdited) return;
    final a = parseAmount(_amount.text);
    final t = a == null || a == 0 ? '' : AppState.instaPayFee(a).toStringAsFixed(2);
    if (_fee.text != t) setState(() => _fee.text = t);
  }

  List<Widget> _feeSection() {
    if (!_showFee) return const [];
    return [
      const SizedBox(height: 8),
      CheckboxListTile(
        contentPadding: EdgeInsets.zero,
        controlAffinity: ListTileControlAffinity.leading,
        title: Text(tr('InstaPay Fee')),
        subtitle: Text(tr('0.1% · min 0.50 · max 20 — saved as a separate expense')),
        value: _instaPay,
        onChanged: (v) {
          setState(() {
            _instaPay = v ?? false;
            _feeEdited = false;
          });
          _updateFee();
        },
      ),
      if (_instaPay)
        TextFormField(
          controller: _fee,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          onChanged: (_) => _feeEdited = true,
          decoration: InputDecoration(
            labelText: tr('Fee'),
            border: const OutlineInputBorder(),
            helperText: _feeEdited ? tr('Edited') : tr('Worked out from the amount; you can change it'),
            suffixIcon: _feeEdited
                ? IconButton(
                    tooltip: tr('Recalculate'),
                    icon: const Icon(Icons.refresh),
                    onPressed: () {
                      _feeEdited = false;
                      _updateFee();
                    },
                  )
                : null,
          ),
          validator: (v) {
            if (!_instaPay) return null;
            final f = parseAmount(v ?? '');
            return f == null || f < 0 ? tr('Enter the fee') : null;
          },
        ),
    ];
  }

  /// True once the user typed the received amount themselves.
  bool _toAmountEdited = false;

  // Cross-currency transfers: units received per 1 unit sent. Sent, rate
  // and received are linked: change one and the next one follows.
  double? _rate;
  final _rateCtl = TextEditingController();

  /// Rate shown as "1 <from> = x <to>" (true) or "1 <to> = x <from>";
  /// null = whichever gives a number of 1 or more.
  bool? _rateFromSide;
  double? _lastRate;
  bool _saving = false;

  /// false = app calculator keypad, true = phone keyboard (typed math).
  bool _sysKeyboard = false;
  bool _initialized = false;

  InstallmentPlan? _plan;

  @override
  void initState() {
    super.initState();
    _amount = TextEditingController();
    _amount.addListener(_updateFee);
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
      _payee.text = widget.initialPayee ?? '';
      _categoryId = widget.initialCategoryId;
      _categoryChosen = widget.initialCategoryId != null;
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
    if (t.id != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadFee(t.id!));
    }
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

  /// Rate field, quick rates and the comparison with the market rate.
  List<Widget> _rateSection(AppState state, Account from, Account to) {
    final theme = Theme.of(context);
    final fromU = currencyUnit(from.currency);
    final toU = currencyUnit(to.currency);
    final showFrom = _rateShowsFrom;
    final online = state.onlineRate(from.currency, to.currency);
    final mine = state.myRate(from.currency, to.currency);
    String show(double r) => _rateText(showFrom ? r : 1 / r);

    Widget chip(String label, double r) => ActionChip(
          label: Text('$label ${show(r)}'),
          onPressed: () => setState(() => _useRate(r)),
        );

    // Compared with the market (online) rate.
    String? compare;
    final amt = parseAmount(_amount.text)?.abs();
    if (online != null && _rate != null && amt != null && amt > 0) {
      final pct = (_rate! / online - 1) * 100;
      final diff = amt * (_rate! - online); // in the "to" currency
      final diffBase = state.toBase(diff.abs(), to.currency);
      if (pct.abs() < 0.05) {
        compare = tr('Same as the market rate (${show(online)})');
      } else {
        final p = pct.abs().toStringAsFixed(pct.abs() < 10 ? 1 : 0);
        compare = pct < 0
            ? tr('Market rate ${show(online)}: you get $p% less (≈ ${fmtMoney(diffBase, state.baseCurrency)})')
            : tr('Market rate ${show(online)}: you get $p% more (≈ ${fmtMoney(diffBase, state.baseCurrency)})');
      }
    }

    return [
      TextFormField(
        controller: _rateCtl,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(
          labelText: tr('Exchange Rate'),
          prefixText: '1 ${showFrom ? fromU : toU} = ',
          suffixText: showFrom ? toU : fromU,
          border: const OutlineInputBorder(),
          suffixIcon: IconButton(
            tooltip: tr('Flip the rate'),
            icon: const Icon(Icons.swap_horiz),
            onPressed: () => setState(() {
              _rateFromSide = !showFrom;
              _syncRateText();
            }),
          ),
        ),
        onChanged: (v) => setState(() => _rateTyped(v)),
      ),
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        runSpacing: 4,
        children: [
          if (online != null) chip(tr('Online'), online),
          if (mine != null) chip(tr('My rate'), mine),
          if (_lastRate != null) chip(tr('Last used'), _lastRate!),
        ],
      ),
      if (compare != null)
        Padding(
          padding: const EdgeInsets.only(top: 6, left: 4),
          child: Text(compare,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        ),
    ];
  }

  Future<void> _openPad(TextEditingController c, String? currency,
      {bool received = false}) async {
    FocusScope.of(context).unfocus();
    await showCalcPad(context, c, currency: currency, onChanged: () {
      setState(() {
        if (received) {
          _rateFromReceived();
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
    if (_type == TxType.transfer) {
      _recalcToAmount();
      _loadLastRate();
    }
  }

  @override
  void dispose() {
    _amount.dispose();
    _toAmount.dispose();
    _rateCtl.dispose();
    for (final r in _rows) {
      r.amount.dispose();
    }
    _payee.dispose();
    _note.dispose();
    _fee.dispose();
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

  /// Received = sent × rate. The rate starts from your own / the online
  /// rate, or from the two amounts of an existing transfer.
  void _recalcToAmount({bool keepRateText = false}) {
    final state = AppScope.read(context);
    final a = state.accountById(_accountId);
    final b = state.accountById(_toAccountId);
    if (a == null || b == null || a.currency == b.currency) return;
    final amt = parseAmount(_amount.text)?.abs();
    if (_rate == null) {
      final rcv = parseAmount(_toAmount.text)?.abs();
      if (_toAmountEdited && amt != null && amt > 0 && rcv != null && rcv > 0) {
        _rate = rcv / amt;
      } else {
        _rate = state.rate(a.currency, b.currency);
      }
    }
    if (!keepRateText) _syncRateText();
    if (amt == null || _rate == null) return;
    _toAmount.text = (amt * _rate!).toStringAsFixed(2);
  }

  bool get _rateShowsFrom => _rateFromSide ?? ((_rate ?? 1) >= 1);

  static String _rateText(double v) {
    var t = v.toStringAsFixed(v >= 100 ? 2 : (v >= 1 ? 4 : 6));
    if (t.contains('.')) {
      t = t.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
    }
    return t;
  }

  void _syncRateText() {
    final r = _rate;
    if (r == null || r <= 0) {
      _rateCtl.text = '';
      return;
    }
    _rateCtl.text = _rateText(_rateShowsFrom ? r : 1 / r);
  }

  /// The received amount was typed: work the rate out from it.
  void _rateFromReceived() {
    _toAmountEdited = true;
    final amt = parseAmount(_amount.text)?.abs();
    final rcv = parseAmount(_toAmount.text)?.abs();
    if (amt != null && amt > 0 && rcv != null && rcv > 0) {
      _rate = rcv / amt;
      _syncRateText();
    }
  }

  /// The rate was typed (in the direction shown).
  void _rateTyped(String v) {
    final d = parseAmount(v)?.abs();
    if (d == null || d == 0) return;
    _rate = _rateShowsFrom ? d : 1 / d;
    _toAmountEdited = true;
    _recalcToAmount(keepRateText: true);
  }

  void _useRate(double r) {
    _rate = r;
    _toAmountEdited = true;
    _recalcToAmount();
  }

  /// Accounts changed: start again from the usual rate.
  void _resetRate() {
    _rate = null;
    _rateFromSide = null;
    _toAmountEdited = false;
    _lastRate = null;
    _recalcToAmount();
    _loadLastRate();
  }

  Future<void> _loadLastRate() async {
    final state = AppScope.read(context);
    final a = state.accountById(_accountId);
    final b = state.accountById(_toAccountId);
    if (a == null || b == null || a.currency == b.currency) return;
    final r = await state.lastTransferRate(a.currency, b.currency,
        exceptId: widget.txn?.id);
    if (mounted && r != null) setState(() => _lastRate = r);
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
      helpText: tr('Date the bank posted it'),
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
        showSnack(context, tr('Enter the amount received'));
        return;
      }
    }
    if (_repeat && _endType == EndType.date && _endDate == null) {
      showSnack(context, tr('Pick an end date'));
      return;
    }
    // Every expense / income needs a category — or "No category", chosen
    // on purpose.
    if (_split && _type != TxType.transfer) {
      if (_rows.any((r) => !r.chosen)) {
        showSnack(context, tr('Choose a category for each part'));
        return;
      }
      if (_rows.any((r) => (parseAmount(r.amount.text) ?? 0) == 0)) {
        showSnack(context, tr('Enter an amount for each part'));
        return;
      }
      final left = raw - _splitAssigned;
      if (left.abs() > 0.004) {
        showSnack(context, tr('The parts must add up to the total (${fmtAmountRaw(left)} left)'));
        return;
      }
    } else if (_type != TxType.transfer && !_categoryChosen) {
      showSnack(context, tr('Choose a category, or No category if you\'re not sure'));
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
      feeFor: widget.txn?.feeFor,
      splitId: widget.txn?.splitId,
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
    } else {
      final int mainId;
      if (_mode == _Mode.confirm) {
        mainId = await state.confirmOccurrence(widget.occurrence!, template);
      } else if (_split && !isTransfer) {
        mainId = await state.saveSplit(template, [
          for (final r in _rows) (r.categoryId, parseAmount(r.amount.text)!),
        ]);
      } else {
        mainId = await state.saveTxn(template);
      }
      // InstaPay fee: its own expense from the same account, linked to
      // this transaction (added, changed or removed).
      if (_showFee && (_instaPay || _existingFee != null)) {
        final fee = _instaPay ? (parseAmount(_fee.text)?.abs() ?? 0) : 0.0;
        final what = isTransfer
            ? 'Transfer to ${state.accountById(_toAccountId)?.name ?? ''}'
            : (template.payee.isNotEmpty
                ? template.payee
                : (state.categoryById(_categoryId)?.name ?? 'Expense'));
        await state.setInstaPayFee(mainId, _accountId!, _date, fee,
            note: 'Fee for $what (${fmtAmountRaw(amount.abs())})');
      }
    }
    if (!mounted) return;
    Navigator.pop(context, true);
  }

  Future<void> _delete() async {
    final state = AppScope.read(context);
    switch (_mode) {
      case _Mode.editRule:
        final ok = await confirmDialog(context,
            title: tr('Delete recurring item?'),
            message:
                tr('Future occurrences stop. Entries already recorded are kept.'));
        if (!ok) return;
        await state.deleteRule(widget.rule!.id!);
        break;
      case _Mode.editPlan:
        final ok = await confirmDialog(context,
            title: tr('Delete whole plan?'),
            message: tr('All ${_plan?.months ?? ''} installments will be deleted.'));
        if (!ok) return;
        await state.deletePlan(_plan!.id!);
        break;
      case _Mode.editTxn:
        final t = widget.txn!;
        if (t.planId != null) {
          final choice = await showDialog<String>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: Text(tr('Delete Installment')),
              content: Text(
                  tr('Delete only this installment, or the whole plan?')),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: Text(tr('Cancel'))),
                TextButton(
                    onPressed: () => Navigator.pop(ctx, 'one'),
                    child: Text(tr('This One'))),
                FilledButton(
                    onPressed: () => Navigator.pop(ctx, 'all'),
                    child: Text(tr('Whole Plan'))),
              ],
            ),
          );
          if (choice == null) return;
          if (choice == 'all') {
            await state.deletePlan(t.planId!);
          } else {
            await state.deleteTxn(t.id!);
          }
        } else if (t.splitId != null) {
          final choice = await showDialog<String>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: Text(tr('Delete Split Payment')),
              content: Text(tr('Delete only this part, or the whole payment with all its categories?')),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: Text(tr('Cancel'))),
                TextButton(
                    onPressed: () => Navigator.pop(ctx, 'one'),
                    child: Text(tr('This Part'))),
                FilledButton(
                    onPressed: () => Navigator.pop(ctx, 'all'),
                    child: Text(tr('Whole Payment'))),
              ],
            ),
          );
          if (choice == null) return;
          if (choice == 'all') {
            await state.deleteSplit(t.splitId!);
          } else {
            await state.deleteTxn(t.id!);
          }
        } else {
          final ok = await confirmDialog(context,
              title: tr('Delete transaction?'), message: tr('This cannot be undone.'));
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
        return tr('New Transaction');
      case _Mode.editTxn:
        return tr('Edit Transaction');
      case _Mode.editPlan:
        return tr('Edit installment plan');
      case _Mode.editRule:
        return tr('Edit recurring item');
      case _Mode.confirm:
        return tr('Confirm recurring item');
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
        appBar: AppBar(title: Text(tr('New Transaction'))),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(tr('Add an account first.')),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const AccountEditScreen()),
                  ),
                  child: Text(tr('Add Account')),
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
    final typeLocked = _mode == _Mode.editPlan || _mode == _Mode.confirm;

    const gap = SizedBox(height: 10);
    return Scaffold(
      appBar: AppBar(
        title: Text(_title),
        actions: [
          IconButton(
            tooltip: _mode == _Mode.confirm ? tr('Confirm') : tr('Save'),
            icon: const Icon(Icons.check),
            onPressed: _saving || _accountId == null ? null : _save,
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
          child: FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            onPressed: _saving || _accountId == null ? null : _save,
            child: Text(_mode == _Mode.confirm ? tr('Confirm') : tr('Save')),
          ),
        ),
      ),
      body: Form(
        key: _formKey,
        child: Theme(
          data: Theme.of(context).copyWith(
            inputDecorationTheme: Theme.of(context).inputDecorationTheme.copyWith(
                  isDense: true,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                ),
          ),
          child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          children: [
            ..._banners(state),
            if (!typeLocked)
              SegmentedButton<TxType>(
                segments: [
                  ButtonSegment(
                      value: TxType.expense,
                      label: Text(tr('Expense')),
                      icon: Icon(Icons.remove)),
                  ButtonSegment(
                      value: TxType.income,
                      label: Text(tr('Income')),
                      icon: Icon(Icons.add)),
                  ButtonSegment(
                      value: TxType.transfer,
                      label: Text(tr('Transfer')),
                      icon: Icon(Icons.swap_horiz)),
                ],
                selected: {_type},
                onSelectionChanged: (s) => setState(() {
                  _type = s.first;
                  final c = state.categoryById(_categoryId);
                  if (c != null && c.kind != _type) {
                    _categoryId = null;
                    _categoryChosen = false;
                  }
                  if (_type != TxType.expense) _installments = false;
                  if (_type == TxType.transfer) _split = false;
                  for (final r in _rows) {
                    final rc = state.categoryById(r.categoryId);
                    if (rc != null && rc.kind != _type) {
                      r.categoryId = null;
                      r.chosen = false;
                    }
                  }
                  _recalcToAmount();
                  if (_type == TxType.transfer) _loadLastRate();
                }),
              ),
            gap,
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
                labelText: _installments ? tr('Total amount') : tr('Amount'),
                helperText: _amountHelper(state, account),
                helperStyle: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.w600),
                suffixText: account == null ? null : currencyUnit(account.currency),
                suffixIcon: IconButton(
                  tooltip:
                      _sysKeyboard ? tr('Use calculator') : tr('Use phone keyboard'),
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
                if (a == null) return tr('Enter an amount');
                if (a == 0) return tr('Amount cannot be zero');
                return null;
              },
              onChanged: (_) => setState(_recalcToAmount),
            ),
            gap,
            AccountField(
              label: _type == TxType.transfer ? tr('From account') : tr('Account'),
              value: _accountId,
              onChanged: (v) => setState(() {
                _accountId = v;
                _resetRate();
              }),
            ),
            if (_type == TxType.transfer) ...[
              gap,
              FormField<int>(
                validator: (_) {
                  if (_toAccountId == null) return tr('Choose destination');
                  if (_toAccountId == _accountId) {
                    return tr('Choose a different account');
                  }
                  return null;
                },
                builder: (field) => AccountField(
                  label: tr('To Account'),
                  value: _toAccountId,
                  errorText: field.errorText,
                  onChanged: (v) => setState(() {
                    _toAccountId = v;
                    _resetRate();
                  }),
                ),
              ),
              if (differ) ...[
                gap,
                ..._rateSection(state, account!, toAccount!),
                gap,
                TextFormField(
                  controller: _toAmount,
                  readOnly: !_sysKeyboard,
                  showCursor: true,
                  keyboardType: TextInputType.text,
                  onTap: _sysKeyboard
                      ? null
                      : () => _openPad(_toAmount, toAccount.currency,
                          received: true),
                  onFieldSubmitted: (_) => _settleExpression(_toAmount),
                  onTapOutside: (_) => _settleExpression(_toAmount),
                  decoration: InputDecoration(
                    labelText: tr('Amount Received'),
                    suffixText: currencyUnit(toAccount.currency),
                    helperText: _receivedHelper(state, toAccount),
                    border: const OutlineInputBorder(),
                  ),
                  onChanged: (_) => setState(_rateFromReceived),
                ),
              ],
            ],
            if (_type != TxType.transfer) ...[
              gap,
              if (_split)
                ..._splitEditor(state, account)
              else
                Row(
                  children: [
                    Expanded(
                      child: CategoryField(
                        kind: _type,
                        value: _categoryId,
                        noneChosen: _categoryChosen,
                        onChanged: (v) => setState(() {
                          _categoryId = v;
                          _categoryChosen = true;
                        }),
                      ),
                    ),
                    if (_canSplit)
                      Padding(
                        padding: const EdgeInsetsDirectional.only(start: 6),
                        child: IconButton.outlined(
                          tooltip: tr('Split into several categories'),
                          icon: const Icon(Icons.call_split),
                          onPressed: () => setState(_startSplit),
                        ),
                      ),
                  ],
                ),
              gap,
              TextFormField(
                controller: _payee,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                  labelText:
                      _type == TxType.income ? tr('From (payer)') : tr('Payee / store'),
                  border: const OutlineInputBorder(),
                ),
              ),
            ],
            gap,
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
              gap,
              InkWell(
                borderRadius: BorderRadius.circular(4),
                onTap: _pickPostDate,
                child: InputDecorator(
                  decoration: InputDecoration(
                    labelText: tr('Post Date'),
                    helperText: _postDate == null
                        ? tr('Same as transaction date — change it if the bank posted it later')
                        : tr('Decides which statement it falls in'),
                    border: const OutlineInputBorder(),
                    suffixIcon: _postDate == null
                        ? const Icon(Icons.event_available)
                        : IconButton(
                            tooltip: tr('Same as transaction date'),
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
            gap,
            TextFormField(
              controller: _note,
              minLines: 1,
              maxLines: 3,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: tr('Note'),
                border: OutlineInputBorder(),
              ),
            ),
            ..._feeSection(),
            ..._installmentSection(account),
            ..._repeatSection(),
            if (_canDelete) ...[
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
                label: Text(_mode == _Mode.editRule
                    ? tr('Delete Recurring Item')
                    : _mode == _Mode.editPlan
                        ? tr('Delete Whole Plan')
                        : tr('Delete Transaction')),
                onPressed: _delete,
              ),
              gap,
            ],
          ],
        ),
        ),
      ),
    );
  }

  /// Category + amount rows for a payment split across categories.
  List<Widget> _splitEditor(AppState state, Account? account) {
    final theme = Theme.of(context);
    final total = parseAmount(_amount.text) ?? 0;
    final left = total - _splitAssigned;
    final ok = left.abs() < 0.005;
    final unit = account == null ? '' : currencyUnit(account.currency);
    return [
      Row(
        children: [
          Icon(Icons.call_split, size: 18, color: theme.colorScheme.primary),
          const SizedBox(width: 6),
          Expanded(
            child: Text(tr('Split Between Categories'),
                style: theme.textTheme.titleSmall),
          ),
          TextButton(
            onPressed: () => setState(() {
              // Back to one category: keep the first part's choice.
              final first = _rows.isEmpty ? null : _rows.first;
              _categoryId = first?.categoryId;
              _categoryChosen = first?.chosen ?? false;
              _split = false;
            }),
            child: Text(tr('Cancel Split')),
          ),
        ],
      ),
      for (var i = 0; i < _rows.length; i++)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 3,
                child: CategoryField(
                  kind: _type,
                  value: _rows[i].categoryId,
                  noneChosen: _rows[i].chosen,
                  onChanged: (v) => setState(() {
                    _rows[i].categoryId = v;
                    _rows[i].chosen = true;
                  }),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: TextField(
                  controller: _rows[i].amount,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: tr('Amount'),
                    suffixText: unit,
                    border: const OutlineInputBorder(),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              if (_rows.length > 2)
                IconButton(
                  tooltip: tr('Remove'),
                  icon: const Icon(Icons.close),
                  onPressed: () => setState(() {
                    _rows.removeAt(i).amount.dispose();
                  }),
                ),
            ],
          ),
        ),
      Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Row(
          children: [
            TextButton.icon(
              icon: const Icon(Icons.add),
              label: Text(tr('Add Category')),
              onPressed: () => setState(_addSplitRow),
            ),
            const Spacer(),
            Text(
              ok
                  ? tr('Adds up to the total')
                  : (left > 0
                      ? tr('${fmtAmountRaw(left)} left to assign')
                      : tr('${fmtAmountRaw(-left)} over the total')),
              style: theme.textTheme.bodySmall?.copyWith(
                  color: ok ? Colors.green.shade600 : theme.colorScheme.error,
                  fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    ];
  }

  /// Main-currency equivalent of the amount received (transfers).
  String? _receivedHelper(AppState state, Account to) {
    final base = state.baseCurrency;
    final amt = parseAmount(_toAmount.text);
    if (to.currency == base || amt == null || amt == 0) return null;
    final v = state.convert(amt, to.currency, base);
    return v == null
        ? tr('No $base rate for ${to.currency} yet')
        : '≈ ${fmtMoneyRaw(v, base)}';
  }

  /// Small line under the amount: the EGP (main currency) equivalent for
  /// foreign-currency expenses and income, and a refund hint.
  String? _amountHelper(AppState state, Account? account) {
    final parts = <String>[];
    final amt = parseAmount(_amount.text);
    if (hasOperator(_amount.text)) {
      parts.add(amt == null ? tr('Incomplete calculation') : '= ${fmtAmountRaw(amt)}');
    }
    final base = state.baseCurrency;
    if (account != null &&
        account.currency != base &&
        amt != null &&
        amt != 0) {
      final v = state.convert(amt, account.currency, base);
      parts.add(v == null
          ? tr('No $base rate for ${account.currency} yet')
          : '≈ ${fmtMoneyRaw(v, base)}');
    }
    if (_type == TxType.expense && (amt ?? 0) < 0) parts.add(tr('negative = refund'));
    return parts.isEmpty ? null : parts.join(' · ');
  }

  String get _dateLabel {
    if (_installments) return tr('Purchase date');
    if (_mode == _Mode.editRule) return tr('Next date');
    if (_repeat) return tr('First date');
    return tr('Date');
  }

  List<Widget> _banners(AppState state) {
    final out = <Widget>[];
    final t = widget.txn;
    if (_mode == _Mode.editTxn && t != null && t.planId != null) {
      final plan = state.plans[t.planId];
      out.add(Card(
        child: ListTile(
          leading: const Icon(Icons.view_week_outlined),
          title: Text(tr('Installment ${t.planIndex}/${plan?.months ?? '?'}')),
          subtitle: Text(plan == null
              ? tr('Changes here apply to this installment only')
              : tr('Total ${fmtAmountRaw(plan.total)} · changes here apply to this installment only')),
          trailing: plan == null
              ? null
              : TextButton(
                  onPressed: () => Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(
                        builder: (_) => TransactionEditScreen(planTxn: t)),
                  ),
                  child: Text(tr('Edit Plan')),
                ),
        ),
      ));
    }
    if (_mode == _Mode.editTxn && t != null && t.recurringId != null) {
      final rule = state.ruleById(t.recurringId);
      out.add(Card(
        child: ListTile(
          leading: const Icon(Icons.repeat),
          title: Text(tr('From a Recurring Item')),
          subtitle: Text(rule == null
              ? tr('The recurring item was deleted')
              : tr('${rule.scheduleLabel} · changes here apply to this entry only')),
          trailing: rule == null
              ? null
              : TextButton(
                  onPressed: () => Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(
                        builder: (_) => TransactionEditScreen(rule: rule)),
                  ),
                  child: Text(tr('Edit All')),
                ),
        ),
      ));
    }
    if (_mode == _Mode.editRule) {
      out.add(Card(
        child: ListTile(
          leading: Icon(Icons.info_outline),
          title: Text(tr('Changes apply from the next date on')),
          subtitle: Text(tr('Entries already recorded are not changed.')),
        ),
      ));
    }
    if (_mode == _Mode.editPlan) {
      out.add(Card(
        child: ListTile(
          leading: Icon(Icons.info_outline),
          title: Text(tr('Saving rebuilds all installments of this plan')),
        ),
      ));
    }
    if (out.isNotEmpty) out.add(const SizedBox(height: 8));
    return out;
  }

  List<Widget> _installmentSection(Account? account) {
    if (_type != TxType.expense || _split) return const [];
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
        title: Text(tr('Split Into Monthly Installments')),
        subtitle: Text(tr('e.g. credit card installments')),
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
                label: tr('Months'),
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
                label: tr('First Installment'),
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
            '${parts.last != parts.first ? tr(' (last ${fmtAmountRaw(parts.last)})') : ''}'
            '\n${monthFmt.format(_startMonth)} → ${monthFmt.format(lastMonth)}, on day ${_date.day}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
      ],
    ];
  }

  List<Widget> _repeatSection() {
    if (_mode != _Mode.newTxn && _mode != _Mode.editRule) return const [];
    if (_split) return const [];
    final interval = int.tryParse(_interval.text) ?? 1;
    return [
      if (_mode == _Mode.newTxn)
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          secondary: const Icon(Icons.repeat),
          title: Text(tr('Repeat')),
          subtitle: Text(tr('Subscriptions, salary, rent…')),
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
                decoration: InputDecoration(
                  labelText: tr('Every'),
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: LabeledDropdown<Freq>(
                label: tr('Period'),
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
        Text(tr('Ends')),
        const SizedBox(height: 6),
        SegmentedButton<EndType>(
          segments: [
            ButtonSegment(value: EndType.never, label: Text(tr('Never'))),
            ButtonSegment(value: EndType.count, label: Text(tr('After'))),
            ButtonSegment(value: EndType.date, label: Text(tr('On Date'))),
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
                  ? tr('Remaining times')
                  : tr('Number of times'),
              border: const OutlineInputBorder(),
            ),
            validator: (v) {
              final n = int.tryParse((v ?? '').trim());
              return n == null || n < 1 ? tr('Enter 1 or more') : null;
            },
          ),
        ],
        if (_endType == EndType.date) ...[
          const SizedBox(height: 12),
          InkWell(
            borderRadius: BorderRadius.circular(4),
            onTap: _pickEndDate,
            child: InputDecorator(
              decoration: InputDecoration(
                labelText: tr('End Date'),
                border: OutlineInputBorder(),
                suffixIcon: Icon(Icons.event),
              ),
              child: Text(
                  _endDate == null ? tr('Select') : shortDateFmt.format(_endDate!)),
            ),
          ),
        ],
        const SizedBox(height: 8),
        Text(
          tr('When each date arrives it appears under "To confirm" so you can '
          'record it (and adjust the amount if needed).'),
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    ];
  }
}

/// One part of a split payment.
class _SplitRow {
  _SplitRow(this.categoryId, this.chosen, String amount)
      : amount = TextEditingController(text: amount);

  int? categoryId;
  bool chosen;
  final TextEditingController amount;
}
