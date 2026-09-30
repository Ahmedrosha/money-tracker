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

  // Investment tracking: null / 'holdings' / 'simple'.
  String? _investMode;

  bool get _showInvest =>
      _type == AccountType.investment || _type == AccountType.funds;

  // Loan plan.
  bool _loanPlan = true;
  LoanMode _loanMode = LoanMode.installments;
  final _loanPayment = TextEditingController();
  final _loanMonths = TextEditingController();
  final _loanPrincipal = TextEditingController();
  final _loanRate = TextEditingController();
  bool _loanFlat = true;
  late DateTime _loanFirstDue;
  int? _loanPayFrom;
  int? _loanReceivedInto;
  final _loanReceived = TextEditingController();

  /// Show the plan section: new loans, or loans that already have a plan.
  bool get _showLoan =>
      _type == AccountType.loan && (_isNew || widget.account?.loan != null);

  LoanTerms? _buildLoan() {
    if (!_showLoan || !_loanPlan) return null;
    final months = int.tryParse(_loanMonths.text.trim()) ?? 0;
    if (months <= 0) return null;
    final old = widget.account?.loan;
    if (_loanMode == LoanMode.installments) {
      final p = parseAmount(_loanPayment.text)?.abs() ?? 0;
      if (p <= 0) return null;
      return LoanTerms(
          mode: LoanMode.installments,
          payment: p,
          months: months,
          firstDue: _loanFirstDue,
          payAccountId: _loanPayFrom,
          nextIndex: old?.nextIndex ?? 0);
    }
    final principal = parseAmount(_loanPrincipal.text)?.abs() ?? 0;
    final rate = parseAmount(_loanRate.text)?.abs() ?? 0;
    if (principal <= 0) return null;
    return LoanTerms(
        mode: LoanMode.interest,
        payment: LoanTerms.interestPayment(principal, rate, months, _loanFlat),
        months: months,
        firstDue: _loanFirstDue,
        payAccountId: _loanPayFrom,
        principal: principal,
        rate: rate,
        flat: _loanFlat,
        nextIndex: old?.nextIndex ?? 0);
  }

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
    _investMode = a?.investMode ?? (a == null ? 'holdings' : null);
    final n = DateTime.now();
    final l = a?.loan;
    _loanFirstDue = l?.firstDue ?? DateTime(n.year, n.month + 1, n.day);
    if (l != null) {
      _loanMode = l.mode;
      _loanPayment.text = _trimNum(l.payment);
      _loanMonths.text = '${l.months}';
      _loanPrincipal.text = l.principal > 0 ? _trimNum(l.principal) : '';
      _loanRate.text = l.rate > 0 ? _trimNum(l.rate) : '';
      _loanFlat = l.flat;
      _loanPayFrom = l.payAccountId;
    }
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
    for (final c in [_loanPayment, _loanMonths, _loanPrincipal, _loanRate, _loanReceived]) {
      c.dispose();
    }
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
    final loan = _buildLoan();
    if (_showLoan && _loanPlan && loan == null) {
      setState(() => _saving = false);
      showSnack(context, 'Fill in the loan amounts and number of months');
      return;
    }
    final a = Account(
      loan: _type == AccountType.loan ? (loan ?? widget.account?.loan) : null,
      investMode: _showInvest ? _investMode : null,
      investValue: widget.account?.investValue,
      investValueAt: widget.account?.investValueAt,
      investBase: widget.account?.investBase,
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
    if (_isNew && loan != null) {
      final received = _loanMode == LoanMode.interest
          ? loan.principal
          : (parseAmount(_loanReceived.text)?.abs() ?? 0);
      await state.createLoan(a,
          receivedInto: _loanReceivedInto, received: received);
    } else {
      await state.saveAccount(a);
    }
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

  List<Widget> _loanSection() {
    final cur = currencyUnit(_currency);
    final small = Theme.of(context).textTheme.bodySmall;
    final preview = _buildLoan();
    return [
      const SizedBox(height: 24),
      Text('Loan',
          style: Theme.of(context)
              .textTheme
              .titleSmall
              ?.copyWith(color: Theme.of(context).colorScheme.primary)),
      if (_isNew)
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Repayment Plan'),
          subtitle: const Text('Monthly installments, schedule and reminders'),
          value: _loanPlan,
          onChanged: (v) => setState(() => _loanPlan = v),
        ),
      if (_loanPlan) ...[
        const SizedBox(height: 8),
        SegmentedButton<LoanMode>(
          segments: const [
            ButtonSegment(value: LoanMode.installments, label: Text('Installments')),
            ButtonSegment(value: LoanMode.interest, label: Text('Principal + Interest')),
          ],
          selected: {_loanMode},
          onSelectionChanged: (v) => setState(() => _loanMode = v.first),
        ),
        const SizedBox(height: 4),
        Text(
            _loanMode == LoanMode.installments
                ? 'You know the monthly installment. The loan balance is all installments still to pay.'
                : 'You know the amount borrowed and the rate. Each installment is split: principal reduces the loan, interest is recorded as an expense.',
            style: small),
        const SizedBox(height: 12),
        if (_loanMode == LoanMode.interest) ...[
          TextFormField(
            controller: _loanPrincipal,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
                labelText: 'Amount Borrowed',
                suffixText: cur,
                border: const OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: TextFormField(
                controller: _loanRate,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                    labelText: 'Interest Rate',
                    suffixText: '% / year',
                    border: OutlineInputBorder()),
              ),
            ),
            const SizedBox(width: 12),
            SegmentedButton<bool>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: true, label: Text('Flat')),
                ButtonSegment(value: false, label: Text('Declining')),
              ],
              selected: {_loanFlat},
              onSelectionChanged: (v) => setState(() => _loanFlat = v.first),
            ),
          ]),
          const SizedBox(height: 12),
        ] else ...[
          TextFormField(
            controller: _loanPayment,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
                labelText: 'Monthly Installment',
                suffixText: cur,
                border: const OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
        ],
        TextFormField(
          controller: _loanMonths,
          keyboardType: TextInputType.number,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(
              labelText: 'Number of Months', border: OutlineInputBorder()),
        ),
        if (preview != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              _loanMode == LoanMode.interest
                  ? 'Installment ${fmtMoneyRaw(preview.payment, _currency)} · total interest '
                      '${fmtMoneyRaw(preview.schedule().fold<double>(0, (s, r) => s + r.interest), _currency)}'
                  : 'Total to repay ${fmtMoneyRaw(preview.startOwed, _currency)}',
              style: small?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
        const SizedBox(height: 12),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.event),
          title: const Text('First Installment'),
          subtitle: Text(dayFmt.format(_loanFirstDue)),
          onTap: () async {
            final d = await showDatePicker(
                context: context,
                initialDate: _loanFirstDue,
                firstDate: DateTime(2000),
                lastDate: DateTime(2100));
            if (d != null) setState(() => _loanFirstDue = d);
          },
        ),
        AccountField(
          label: 'Pay Installments From',
          value: _loanPayFrom,
          onChanged: (v) => setState(() => _loanPayFrom = v),
        ),
        if (_isNew) ...[
          const SizedBox(height: 12),
          AccountField(
            label: 'Money Received Into (optional)',
            value: _loanReceivedInto,
            onChanged: (v) => setState(() => _loanReceivedInto = v),
          ),
          if (_loanMode == LoanMode.installments && _loanReceivedInto != null) ...[
            const SizedBox(height: 12),
            TextFormField(
              controller: _loanReceived,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                  labelText: 'Amount Received',
                  suffixText: cur,
                  border: const OutlineInputBorder()),
            ),
          ],
          const SizedBox(height: 4),
          Text(
              'If you choose where the money went, that account gets it as a transfer from this loan.',
              style: small),
        ],
      ],
    ];
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
            if (_showLoan) ..._loanSection(),
            if (_showInvest) ...[
              const SizedBox(height: 24),
              Text('Portfolio Tracking',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: Theme.of(context).colorScheme.primary)),
              const SizedBox(height: 8),
              SegmentedButton<String?>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: 'holdings', label: Text('Stocks')),
                  ButtonSegment(value: 'simple', label: Text('Total Value')),
                  ButtonSegment(value: null, label: Text('Balance Only')),
                ],
                selected: {_investMode},
                onSelectionChanged: (v) => setState(() => _investMode = v.first),
              ),
              const SizedBox(height: 4),
              Text(
                _investMode == 'holdings'
                    ? 'Record buys and sells of each stock; valued at live EGX prices (or your own).'
                    : _investMode == 'simple'
                        ? 'Now and then type the portfolio total shown by your broker.'
                        : 'Just the money in the account, no market value.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            if (!(_showLoan && _loanPlan && _isNew)) ...[
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
            ],
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
