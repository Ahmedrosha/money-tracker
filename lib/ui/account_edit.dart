import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/models.dart';
import '../state/app_state.dart';
import '../util/currencies.dart';
import '../util/format.dart';
import 'widgets.dart';
import '../services/secure_store.dart';
import '../l10n/l10n.dart';

class AccountEditScreen extends StatefulWidget {
  const AccountEditScreen({super.key, this.account});

  final Account? account;

  @override
  State<AccountEditScreen> createState() => _AccountEditScreenState();
}

/// Free-text bank name with suggestions from banks already used.
class _BankField extends StatelessWidget {
  const _BankField(
      {super.key,
      required this.initial,
      required this.options,
      required this.onChanged,
      this.label = 'Bank',
      this.hint = 'e.g. CIB, NBE, Banque Misr'});

  final String label;
  final String hint;

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
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          border: const OutlineInputBorder(),
          prefixIcon: const Icon(Icons.account_balance),
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

  // Account details.
  final _last4 = TextEditingController();
  final _expiry = TextEditingController();
  final _phone = TextEditingController();
  final _customerNo = TextEditingController();
  final _accountNo = TextEditingController();
  final _iban = TextEditingController();
  final _notes = TextEditingController();
  final _sender = TextEditingController();
  final _fxFee = TextEditingController();
  final _cardNumber = TextEditingController();
  bool _hasCardNumber = false;
  bool _removeCardNumber = false;
  bool _showDetails = false;

  // Property / car / other asset value.
  final _assetValue = TextEditingController();
  final _assetShare = TextEditingController(text: '100');

  bool get _showAsset =>
      _type == AccountType.property ||
      _type == AccountType.car ||
      _type == AccountType.otherAsset;

  // Investment tracking: null / 'holdings' / 'simple'.
  String? _investMode;

  bool get _showInvest =>
      _type == AccountType.investment ||
      _type == AccountType.funds ||
      _type == AccountType.crypto;

  // Loan plan.
  bool _loanPlan = true;
  LoanMode _loanMode = LoanMode.installments;
  final _loanPayment = TextEditingController();
  final _loanFirst = TextEditingController();
  final _loanLast = TextEditingController();

  /// Installments mode: the bank's total, only to work out the last one.
  final _loanTotal = TextEditingController();
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

  /// An existing installments loan whose total changed (e.g. a different
  /// last payment): move the opening balance with it, unless it was
  /// edited by hand.
  double _loanOpening(LoanTerms? loan, double opening) {
    final old = widget.account?.loan;
    if (_isNew || loan == null || old == null) return opening;
    if (loan.mode != LoanMode.installments || old.mode != LoanMode.installments) {
      return opening;
    }
    if ((opening - widget.account!.openingBalance).abs() > 0.004) return opening;
    final delta = loan.startOwed - old.startOwed;
    return opening - delta;
  }

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
          nextIndex: old?.nextIndex ?? 0,
          firstPayment: parseAmount(_loanFirst.text)?.abs(),
          lastPayment: parseAmount(_loanLast.text)?.abs());
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
        nextIndex: old?.nextIndex ?? 0,
        firstPayment: parseAmount(_loanFirst.text)?.abs(),
        lastPayment: parseAmount(_loanLast.text)?.abs());
  }

  /// First and last installment (when the bank's differ), the total to
  /// work the last one out from, and a check that it all adds up.
  List<Widget> _loanEnds(LoanTerms? preview) {
    final cur = currencyUnit(_currency);
    final small = Theme.of(context).textTheme.bodySmall;
    final interest = _loanMode == LoanMode.interest;
    final months = int.tryParse(_loanMonths.text.trim()) ?? 0;
    final regular = preview?.payment;
    final auto = interest && preview != null ? preview.autoLastPayment : null;

    // Installments: last = total − first − regular × middle months.
    double? workedOut;
    final total = parseAmount(_loanTotal.text)?.abs();
    if (!interest && total != null && regular != null && months >= 2) {
      final first = parseAmount(_loanFirst.text)?.abs() ?? regular;
      workedOut = total - first - regular * (months - 2);
    }
    String? diff;
    double? fix;
    if (!interest && workedOut != null && preview != null) {
      final d = total! - preview.startOwed;
      if (d.abs() > 0.004) {
        diff = tr('Difference ${fmtMoneyRaw(d, _currency)} from the total');
        fix = workedOut;
      }
    } else if (interest && preview != null && preview.lastPayment != null) {
      final left = preview.schedule().last.balanceAfter;
      if (left.abs() > 0.004) {
        diff = tr('The loan ends with ${fmtMoneyRaw(left, _currency)} left');
        fix = auto;
      }
    }

    String fmtPlain(double v) => v.toStringAsFixed(2);
    return [
      const SizedBox(height: 12),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: TextFormField(
              controller: _loanFirst,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: tr('First Payment'),
                hintText: regular == null ? null : fmtPlain(regular),
                helperText: tr('Empty = regular'),
                suffixText: cur,
                border: const OutlineInputBorder(),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: TextFormField(
              controller: _loanLast,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: tr('Last Payment'),
                hintText: auto != null
                    ? fmtPlain(auto)
                    : (regular == null ? null : fmtPlain(regular)),
                helperText: interest ? tr('Empty = what is left') : tr('Empty = regular'),
                suffixText: cur,
                border: const OutlineInputBorder(),
              ),
            ),
          ),
        ],
      ),
      if (!interest) ...[
        const SizedBox(height: 12),
        TextFormField(
          controller: _loanTotal,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            labelText: tr('Total to Repay (optional)'),
            helperText: tr('From the bank\'s contract — to work out the last payment'),
            suffixText: cur,
            border: const OutlineInputBorder(),
          ),
        ),
      ],
      if (!interest && workedOut != null)
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton.icon(
            icon: const Icon(Icons.calculate_outlined, size: 18),
            label: Text(tr('Work out last payment (${fmtMoneyRaw(workedOut, _currency)})')),
            onPressed: workedOut <= 0
                ? null
                : () => setState(() {
                      _loanLast.text = fmtPlain(workedOut!);
                    }),
          ),
        ),
      if (interest && auto != null && _loanLast.text.trim().isNotEmpty)
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton.icon(
            icon: const Icon(Icons.calculate_outlined, size: 18),
            label: Text(tr('Use what is left (${fmtMoneyRaw(auto, _currency)})')),
            onPressed: () => setState(() => _loanLast.clear()),
          ),
        ),
      if (diff != null)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Row(
            children: [
              Icon(Icons.warning_amber_rounded,
                  size: 18, color: Theme.of(context).colorScheme.tertiary),
              const SizedBox(width: 6),
              Expanded(child: Text(diff, style: small)),
              if (fix != null && fix > 0)
                TextButton(
                  onPressed: () => setState(() {
                    if (interest) {
                      _loanLast.clear();
                    } else {
                      _loanLast.text = fmtPlain(fix!);
                    }
                  }),
                  child: Text(tr('Adjust Last Payment')),
                ),
            ],
          ),
        ),
    ];
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
    if (a?.assetValue != null) _assetValue.text = _trimNum(a!.assetValue!);
    if (a?.assetShare != null) _assetShare.text = _trimNum(a!.assetShare!);
    if (a?.id != null) {
      final d = AppScope.read(context).detailsOf(a!.id);
      _last4.text = d.last4;
      _expiry.text = d.expiry;
      _phone.text = d.phone;
      _customerNo.text = d.customerNo;
      _accountNo.text = d.accountNo;
      _iban.text = d.iban;
      _notes.text = d.notes;
      _sender.text = d.sender;
      _fxFee.text = d.fxFee;
      _showDetails = !d.isEmpty;
      SecureStore.hasCardNumber(a.id!).then((v) {
        if (mounted && v) setState(() => _hasCardNumber = _showDetails = true);
      });
    }
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
      _loanFirst.text = l.firstPayment == null ? '' : _trimNum(l.firstPayment!);
      _loanLast.text = l.lastPayment == null ? '' : _trimNum(l.lastPayment!);
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
    for (final c in [_loanPayment, _loanFirst, _loanLast, _loanTotal, _loanMonths, _loanPrincipal, _loanRate, _loanReceived, _assetValue, _assetShare,
        _last4, _expiry, _phone, _customerNo, _accountNo, _iban, _notes, _sender, _fxFee, _cardNumber]) {
      c.dispose();
    }
    super.dispose();
  }

  static String _trimNum(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();

  static String? _dayValidator(String? v, {bool required = false}) {
    final t = (v ?? '').trim();
    if (t.isEmpty) return required ? tr('Required') : null;
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
      showSnack(context, tr('Fill in the loan amounts and number of months'));
      return;
    }
    final a = Account(
      loan: _type == AccountType.loan ? (loan ?? widget.account?.loan) : null,
      investMode: _showInvest ? _investMode : null,
      assetValue: _showAsset ? parseAmount(_assetValue.text)?.abs() : null,
      assetShare: _showAsset
          ? (parseAmount(_assetShare.text)?.abs() ?? 100).clamp(0, 100).toDouble()
          : null,
      assetValueAt: !_showAsset || parseAmount(_assetValue.text) == null
          ? null
          : (parseAmount(_assetValue.text)?.abs() == widget.account?.assetValue
              ? widget.account?.assetValueAt
              : DateTime.now()),
      investValue: widget.account?.investValue,
      investValueAt: widget.account?.investValueAt,
      investBase: widget.account?.investBase,
      id: widget.account?.id,
      name: _name.text.trim(),
      bank: _type.hasBank ? _bank.trim() : '',
      type: _type,
      currency: _currency,
      openingBalance: _loanOpening(loan, _type.isLiability ? -opening.abs() : opening),
      archived: _archived,
      excludeTotal: _exclude,
      sortOrder: widget.account?.sortOrder ?? 0,
      creditLimit: card ? parseAmount(_limit.text)?.abs() : null,
      statementDay: card ? int.tryParse(_statementDay.text.trim()) : null,
      dueDay: card ? int.tryParse(_dueDay.text.trim()) : null,
      minPayPct: card ? parseAmount(_minPct.text)?.abs() : null,
    );
    int id;
    if (_isNew && loan != null) {
      final received = _loanMode == LoanMode.interest
          ? loan.principal
          : (parseAmount(_loanReceived.text)?.abs() ?? 0);
      await state.createLoan(a,
          receivedInto: _loanReceivedInto, received: received);
      id = state.accounts.map((x) => x.id ?? 0).fold(0, (m, v) => v > m ? v : m);
    } else {
      id = await state.saveAccount(a);
    }
    final details = AccountDetails(
      last4: _last4.text.trim(),
      expiry: _expiry.text.trim(),
      phone: _phone.text.trim(),
      customerNo: _customerNo.text.trim(),
      accountNo: _accountNo.text.trim(),
      iban: _iban.text.trim().toUpperCase(),
      notes: _notes.text.trim(),
      sender: _sender.text.trim(),
      fxFee: _fxFee.text.trim(),
    );
    if (!(details.isEmpty && state.detailsOf(id).isEmpty)) {
      await state.saveAccountDetails(id, details);
    }
    final number = _cardNumber.text.replaceAll(RegExp(r'\D'), '');
    if (number.isNotEmpty) {
      await SecureStore.setCardNumber(id, number);
    } else if (_removeCardNumber) {
      await SecureStore.setCardNumber(id, null);
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
      title: tr('Delete account?'),
      message: count == 0
          ? tr('This account has no transactions.')
          : tr('This will also delete $count transaction(s) and any recurring items linked to this account. '
              'Consider archiving it instead.'),
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
      Text(tr('Loan'),
          style: Theme.of(context)
              .textTheme
              .titleSmall
              ?.copyWith(color: Theme.of(context).colorScheme.primary)),
      if (_isNew)
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(tr('Repayment Plan')),
          subtitle: Text(tr('Monthly installments, schedule and reminders')),
          value: _loanPlan,
          onChanged: (v) => setState(() => _loanPlan = v),
        ),
      if (_loanPlan) ...[
        const SizedBox(height: 8),
        SegmentedButton<LoanMode>(
          segments: [
            ButtonSegment(value: LoanMode.installments, label: Text(tr('Installments'))),
            ButtonSegment(value: LoanMode.interest, label: Text(tr('Principal + Interest'))),
          ],
          selected: {_loanMode},
          onSelectionChanged: (v) => setState(() => _loanMode = v.first),
        ),
        const SizedBox(height: 4),
        Text(
            _loanMode == LoanMode.installments
                ? tr('You know the monthly installment. The loan balance is all installments still to pay.')
                : tr('You know the amount borrowed and the rate. Each installment is split: principal reduces the loan, interest is recorded as an expense.'),
            style: small),
        const SizedBox(height: 12),
        if (_loanMode == LoanMode.interest) ...[
          TextFormField(
            controller: _loanPrincipal,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
                labelText: tr('Amount Borrowed'),
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
                decoration: InputDecoration(
                    labelText: tr('Interest Rate'),
                    suffixText: tr('% / year'),
                    border: OutlineInputBorder()),
              ),
            ),
            const SizedBox(width: 12),
            SegmentedButton<bool>(
              showSelectedIcon: false,
              segments: [
                ButtonSegment(value: true, label: Text(tr('Flat'))),
                ButtonSegment(value: false, label: Text(tr('Declining'))),
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
                labelText: tr('Monthly Installment'),
                suffixText: cur,
                border: const OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
        ],
        TextFormField(
          controller: _loanMonths,
          keyboardType: TextInputType.number,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
              labelText: tr('Number of Months'), border: OutlineInputBorder()),
        ),
        if (preview != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              _loanMode == LoanMode.interest
                  ? tr('Installment ${fmtMoneyRaw(preview.payment, _currency)} · total interest '
                      '${fmtMoneyRaw(preview.schedule().fold<double>(0, (s, r) => s + r.interest), _currency)}')
                  : tr('Total to repay ${fmtMoneyRaw(preview.startOwed, _currency)}'),
              style: small?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
        ..._loanEnds(preview),
        const SizedBox(height: 12),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.event),
          title: Text(tr('First Installment')),
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
          label: tr('Pay Installments From'),
          value: _loanPayFrom,
          onChanged: (v) => setState(() => _loanPayFrom = v),
        ),
        if (_isNew) ...[
          const SizedBox(height: 12),
          AccountField(
            label: tr('Money Received Into (optional)'),
            value: _loanReceivedInto,
            onChanged: (v) => setState(() => _loanReceivedInto = v),
          ),
          if (_loanMode == LoanMode.installments && _loanReceivedInto != null) ...[
            const SizedBox(height: 12),
            TextFormField(
              controller: _loanReceived,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                  labelText: tr('Amount Received'),
                  suffixText: cur,
                  border: const OutlineInputBorder()),
            ),
          ],
          const SizedBox(height: 4),
          Text(
              tr('If you choose where the money went, that account gets it as a transfer from this loan.'),
              style: small),
        ],
      ],
    ];
  }

  Widget _detailsSection(BuildContext context) {
    final cardLike = _type.hasBank;
    InputDecoration deco(String label, {String? hint, String? helper}) =>
        InputDecoration(
          labelText: label,
          hintText: hint,
          helperText: helper,
          helperMaxLines: 3,
          border: const OutlineInputBorder(),
        );
    const gap = SizedBox(height: 12);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.badge_outlined),
          title: Text(tr('Account Details')),
          subtitle: Text(tr('Last digits, SMS sender, expiry, bank phone, IBAN, notes')),
          trailing: CollapseArrow(collapsed: !_showDetails),
          onTap: () => setState(() => _showDetails = !_showDetails),
        ),
        if (_showDetails) ...[
          const SizedBox(height: 4),
          TextFormField(
            controller: _last4,
            keyboardType: TextInputType.text,
            decoration: deco(tr('Last 4 Digits'),
                hint: tr('e.g. 8397'),
                helper: tr('Card and account endings, separated by commas. Used to match bank messages.')),
          ),
          if (cardLike) ...[
            gap,
            TextFormField(
              controller: _cardNumber,
              keyboardType: TextInputType.number,
              obscureText: true,
              autocorrect: false,
              enableSuggestions: false,
              decoration: deco(
                  _hasCardNumber
                      ? tr('Full Card Number (saved — type to replace)')
                      : tr('Full Card Number'),
                  helper: tr('Kept only in this phone\'s secure storage, shown with Face ID / fingerprint. Not in backups or Dropbox.')),
            ),
            if (_hasCardNumber)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _removeCardNumber,
                onChanged: (v) => setState(() => _removeCardNumber = v ?? false),
                title: Text(tr('Remove the saved card number')),
                controlAffinity: ListTileControlAffinity.leading,
              ),
            gap,
            TextFormField(
              controller: _expiry,
              keyboardType: TextInputType.number,
              inputFormatters: [_ExpiryFormatter()],
              decoration: deco(tr('Card Expiry'), hint: 'MM/YY'),
              validator: (v) {
                final t = (v ?? '').trim();
                if (t.isEmpty) return null;
                final m = RegExp(r'^(\d{2})/(\d{2})$').firstMatch(t);
                final month = m == null ? 0 : int.parse(m.group(1)!);
                return month >= 1 && month <= 12 ? null : tr('Use MM/YY, e.g. 09/28');
              },
            ),
          ],
          gap,
          TextFormField(
            controller: _sender,
            decoration: deco(tr('SMS Sender Name'),
                hint: tr('e.g. ADCB Egypt'),
                helper: tr('Exactly as it shows in Messages. Only messages from this sender are read for this account.')),
          ),
          gap,
          TextFormField(
            controller: _fxFee,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: deco(tr('Foreign Purchase Fee %'),
                hint: tr('e.g. 3'),
                helper: tr('Added by the bank when you pay in another currency. Used to estimate the amount charged.')),
            validator: (v) {
              final t = (v ?? '').replaceAll('%', '').trim();
              if (t.isEmpty) return null;
              final d = double.tryParse(t.replaceAll(',', '.'));
              return d == null || d < 0 || d > 50 ? tr('Enter a percentage, e.g. 3') : null;
            },
          ),
          gap,
          TextFormField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            decoration: deco(tr('Bank Phone Number'), hint: tr('e.g. 16862')),
          ),
          gap,
          TextFormField(
            controller: _customerNo,
            decoration: deco(tr('Customer Number')),
          ),
          gap,
          TextFormField(
            controller: _accountNo,
            keyboardType: TextInputType.text,
            autocorrect: false,
            decoration: deco(tr('Account Number')),
          ),
          gap,
          TextFormField(
            controller: _iban,
            textCapitalization: TextCapitalization.characters,
            autocorrect: false,
            decoration: deco('IBAN', hint: 'EG00 0000 …'),
          ),
          gap,
          TextFormField(
            controller: _notes,
            minLines: 2,
            maxLines: 6,
            decoration: deco(tr('Notes'),
                helper: tr('Don\'t keep the CVV or passwords here: notes are included in backups and Dropbox.')),
          ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isNew ? tr('New Account') : tr('Edit Account')),
        actions: [
          IconButton(
            tooltip: tr('Save'),
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
              decoration: InputDecoration(
                labelText: tr('Account Name'),
                hintText: tr('e.g. Current, Visa Gold, Wallet'),
                border: OutlineInputBorder(),
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? tr('Enter a name') : null,
            ),
            const SizedBox(height: 16),
            InkWell(
              borderRadius: BorderRadius.circular(4),
              onTap: () async {
                final t = await _pickType(context, _type);
                if (t != null) {
                  setState(() {
                    // New gold accounts are measured in grams by default.
                    if (_isNew && t == AccountType.crypto) {
                      // Crypto is priced in dollars (USDT counts as USD).
                      _currency = 'USD';
                    } else if (_isNew && t == AccountType.gold && !isGold(_currency)) {
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
                  labelText: tr('Account Type'),
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
                key: ValueKey(_type.bankLabel),
                label: _type.bankLabel,
                hint: _type.bankHint,
                initial: _bank,
                options: AppScope.of(context).bankNames,
                onChanged: (v) => _bank = v,
              ),
            ],
            const SizedBox(height: 16),
            if (_type == AccountType.gold && _isNew) ...[
              Text(tr('Measured In'), style: Theme.of(context).textTheme.labelLarge),
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
                    ? tr('Grams of ${goldKarat(_currency)}K gold, valued at today\'s price per gram.')
                    : tr('Tracked as money (what you paid), not by weight.'),
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
                decoration: InputDecoration(
                  labelText: tr('Currency'),
                  border: OutlineInputBorder(),
                  suffixIcon: Icon(Icons.arrow_drop_down),
                ),
                child: Text('$_currency — ${currencyName(_currency)}'),
              ),
            ),
            if (_showLoan) ..._loanSection(),
            if (_showAsset) ...[
              const SizedBox(height: 24),
              Text(tr('Current Value'),
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: Theme.of(context).colorScheme.primary)),
              const SizedBox(height: 8),
              TextFormField(
                controller: _assetValue,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: _type == AccountType.property
                      ? tr('Market Value of the Whole Unit')
                      : tr('Market Value'),
                  helperText: tr('Leave empty to count what you paid'),
                  suffixText: currencyUnit(_currency),
                  border: const OutlineInputBorder(),
                ),
                validator: (v) => v == null || v.trim().isEmpty || parseAmount(v) != null
                    ? null
                    : tr('Invalid number'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _assetShare,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: tr('Your Ownership'),
                  helperText: tr('Your share if you own it with others'),
                  suffixText: '%',
                  border: OutlineInputBorder(),
                ),
                validator: (v) {
                  final n = parseAmount(v ?? '');
                  return n == null || n <= 0 || n > 100 ? '1–100' : null;
                },
              ),
              if (parseAmount(_assetValue.text) != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    tr('Your share: ${fmtMoneyRaw((parseAmount(_assetValue.text)!.abs()) * ((parseAmount(_assetShare.text) ?? 100).clamp(0, 100)) / 100, _currency)}'),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600),
                  ),
                ),
            ],
            if (_showInvest) ...[
              const SizedBox(height: 24),
              Text(tr('Portfolio Tracking'),
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: Theme.of(context).colorScheme.primary)),
              const SizedBox(height: 8),
              SegmentedButton<String?>(
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(
                      value: 'holdings',
                      label: Text(_type == AccountType.crypto ? tr('Coins') : tr('Stocks'))),
                  ButtonSegment(value: 'simple', label: Text(tr('Total Value'))),
                  ButtonSegment(value: null, label: Text(tr('Balance Only'))),
                ],
                selected: {_investMode},
                onSelectionChanged: (v) => setState(() => _investMode = v.first),
              ),
              const SizedBox(height: 4),
              Text(
                _investMode == 'holdings'
                    ? (_type == AccountType.crypto
                        ? tr('Record buys and sells of each coin; valued at live prices from Binance (or your own).')
                        : tr('Record buys and sells of each stock; valued at live EGX prices (or your own).'))
                    : _investMode == 'simple'
                        ? tr('Now and then type the portfolio total shown by your broker.')
                        : tr('Just the money in the account, no market value.'),
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
                    ? tr('Amount owed at start')
                    : (isGold(_currency) ? tr('Grams You Hold Now') : tr('Opening balance')),
                helperText: _type.isLiability
                    ? tr('What you owed before your first recorded transaction')
                    : tr('Balance before your first recorded transaction'),
                suffixText: currencyUnit(_currency),
                border: const OutlineInputBorder(),
              ),
              validator: (v) {
                if (v == null || v.trim().isEmpty) return null;
                return parseAmount(v) == null ? tr('Invalid number') : null;
              },
            ),
            ],
            if (_type == AccountType.creditCard) ...[
              const SizedBox(height: 24),
              Text(tr('Credit Card'),
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: Theme.of(context).colorScheme.primary)),
              const SizedBox(height: 12),
              TextFormField(
                controller: _limit,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: tr('Credit Limit'),
                  suffixText: currencyUnit(_currency),
                  border: const OutlineInputBorder(),
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return null;
                  return parseAmount(v) == null ? tr('Invalid number') : null;
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
                      decoration: InputDecoration(
                        labelText: tr('Statement Closing Day'),
                        helperText: tr('Cycle end, e.g. 25'),
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
                      decoration: InputDecoration(
                        labelText: tr('Payment Due Day'),
                        helperText: tr('Of the next month, e.g. 15'),
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
                decoration: InputDecoration(
                  labelText: tr('Minimum Payment'),
                  suffixText: tr('% of statement'),
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
            _detailsSection(context),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(tr('Exclude from Net Worth')),
              subtitle: Text(tr('Track it, but leave it out of totals')),
              value: _exclude,
              onChanged: (v) => setState(() => _exclude = v),
            ),
            if (!_isNew) ...[
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(tr('Archived')),
                subtitle: Text(tr('Hide from lists and net worth')),
                value: _archived,
                onChanged: (v) => setState(() => _archived = v),
              ),
            ],
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: Padding(
                padding: EdgeInsets.all(12),
                child: Text(tr('Save')),
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
                label: Text(tr('Delete Account')),
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

/// Card expiry as MM/YY: digits only, the "/" is added after the month.
class _ExpiryFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    var digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    // Deleting the "/" also removes the digit before it.
    if (oldValue.text.endsWith('/') &&
        newValue.text.length < oldValue.text.length &&
        digits.length == 2) {
      digits = digits.substring(0, 1);
    }
    // "9" → "09/" (no month starts with 2–9 as a first digit).
    if (digits.length == 1 && int.parse(digits) > 1) digits = '0$digits';
    if (digits.length > 4) digits = digits.substring(0, 4);
    final text = digits.length >= 2
        ? '${digits.substring(0, 2)}/${digits.substring(2)}'
        : digits;
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}
