/// Account types. Stored by name, so existing keys (cash, bank, savings,
/// creditCard, investment, other) must never be renamed.
enum AccountType {
  cash,
  ewallet,
  bank,
  savings,
  certificate,
  debitCard,
  creditCard,
  loan,
  investment,
  funds,
  crypto,
  gold,
  property,
  car,
  otherAsset,
  receivable,
  other,
}

enum AccountFamily { cash, bank, credit, investments, assets, receivables, other }

extension AccountFamilyX on AccountFamily {
  String get label {
    switch (this) {
      case AccountFamily.cash:
        return 'Cash & Wallets';
      case AccountFamily.bank:
        return 'Bank';
      case AccountFamily.credit:
        return 'Credit & Loans';
      case AccountFamily.investments:
        return 'Investments';
      case AccountFamily.assets:
        return 'Assets';
      case AccountFamily.receivables:
        return 'Receivables';
      case AccountFamily.other:
        return 'Other';
    }
  }
}

extension AccountTypeX on AccountType {
  String get key => name;

  String get label {
    switch (this) {
      case AccountType.cash:
        return 'Cash';
      case AccountType.ewallet:
        return 'E-wallet';
      case AccountType.bank:
        return 'Current Account';
      case AccountType.savings:
        return 'Savings Account';
      case AccountType.certificate:
        return 'Certificate / Deposit';
      case AccountType.debitCard:
        return 'Debit / Prepaid Card';
      case AccountType.creditCard:
        return 'Credit Card';
      case AccountType.loan:
        return 'Loan';
      case AccountType.investment:
        return 'Stocks / Brokerage';
      case AccountType.funds:
        return 'Funds';
      case AccountType.crypto:
        return 'Crypto';
      case AccountType.gold:
        return 'Gold';
      case AccountType.property:
        return 'Property';
      case AccountType.car:
        return 'Car';
      case AccountType.otherAsset:
        return 'Other Asset';
      case AccountType.receivable:
        return 'Money Lent';
      case AccountType.other:
        return 'Other';
    }
  }

  AccountFamily get family {
    switch (this) {
      case AccountType.cash:
      case AccountType.ewallet:
        return AccountFamily.cash;
      case AccountType.bank:
      case AccountType.savings:
      case AccountType.certificate:
      case AccountType.debitCard:
        return AccountFamily.bank;
      case AccountType.creditCard:
      case AccountType.loan:
        return AccountFamily.credit;
      case AccountType.investment:
      case AccountType.funds:
      case AccountType.crypto:
      case AccountType.gold:
        return AccountFamily.investments;
      case AccountType.property:
      case AccountType.car:
      case AccountType.otherAsset:
        return AccountFamily.assets;
      case AccountType.receivable:
        return AccountFamily.receivables;
      case AccountType.other:
        return AccountFamily.other;
    }
  }

  /// Types where the balance is normally money you owe.
  bool get isLiability =>
      this == AccountType.creditCard || this == AccountType.loan;

  /// What the "bank" field means for this type.
  String get bankLabel {
    switch (this) {
      case AccountType.investment:
      case AccountType.funds:
        return 'Broker / Platform';
      case AccountType.crypto:
        return 'Exchange / Wallet';
      default:
        return 'Bank';
    }
  }

  String get bankHint {
    switch (this) {
      case AccountType.investment:
      case AccountType.funds:
        return 'e.g. Thndr, EFG Hermes, CI Capital';
      case AccountType.crypto:
        return 'e.g. Binance, Bybit, Trust Wallet';
      default:
        return 'e.g. CIB, NBE, Banque Misr';
    }
  }

  /// Types that usually have no bank.
  bool get hasBank =>
      this != AccountType.cash &&
      this != AccountType.property &&
      this != AccountType.car &&
      this != AccountType.receivable;

  static AccountType fromKey(String? key) {
    for (final t in AccountType.values) {
      if (t.name == key) return t;
    }
    return AccountType.other;
  }
}

class Account {
  final int? id;
  final String name;

  /// Bank / institution name. Empty for cash or unassigned.
  final String bank;
  final AccountType type;
  final String currency;
  final double openingBalance;
  final bool archived;
  final int sortOrder;

  /// Not counted in net worth (e.g. tracking-only accounts).
  final bool excludeTotal;

  // Credit card settings (null for other types).
  final double? creditLimit;

  /// Day of month the statement cycle closes (1-31, clamped to month end).
  final int? statementDay;

  /// Day of month the payment is due, after the closing date.
  final int? dueDay;

  /// Minimum payment as % of the statement.
  final double? minPayPct;

  /// Loan plan (null = plain loan account, tracked by balance only).
  final LoanTerms? loan;

  /// Investment tracking: 'holdings' (stocks with prices), 'simple'
  /// (total value typed in now and then) or null (balance only).
  final String? investMode;

  /// Simple mode: last portfolio value entered, when, and the account
  /// balance at that moment (so later deposits/withdrawals still count).
  final double? investValue;
  final DateTime? investValueAt;
  final double? investBase;

  /// Property / car / other asset: market value of the whole item, your
  /// ownership share in % (100 = all yours), and when the value was set.
  final double? assetValue;
  final double? assetShare;
  final DateTime? assetValueAt;

  /// Your share of [assetValue].
  double? get assetShareValue =>
      assetValue == null ? null : assetValue! * (assetShare ?? 100) / 100;

  /// Types valued at a market value you enter.
  bool get hasAssetValue =>
      type == AccountType.property ||
      type == AccountType.car ||
      type == AccountType.otherAsset;

  /// Portfolio value including stock prices (not stored; set by the app).
  final double? marketValue;

  /// What the account is worth now: market value for tracked portfolios,
  /// otherwise the balance.
  double get worth => marketValue ?? balance;

  /// Computed current balance in the account's own currency (not stored).
  /// Only includes transactions dated up to now.
  final double balance;

  const Account({
    this.id,
    required this.name,
    this.bank = '',
    required this.type,
    required this.currency,
    this.openingBalance = 0,
    this.archived = false,
    this.sortOrder = 0,
    this.excludeTotal = false,
    this.creditLimit,
    this.statementDay,
    this.dueDay,
    this.minPayPct,
    this.loan,
    this.investMode,
    this.investValue,
    this.investValueAt,
    this.investBase,
    this.assetValue,
    this.assetShare,
    this.assetValueAt,
    this.marketValue,
    this.balance = 0,
  });

  Account withMarketValue(double? v) => Account(
        id: id, name: name, bank: bank, type: type, currency: currency,
        openingBalance: openingBalance, archived: archived,
        sortOrder: sortOrder, excludeTotal: excludeTotal,
        creditLimit: creditLimit, statementDay: statementDay, dueDay: dueDay,
        minPayPct: minPayPct, loan: loan, investMode: investMode,
        investValue: investValue, investValueAt: investValueAt,
        investBase: investBase, assetValue: assetValue,
        assetShare: assetShare, assetValueAt: assetValueAt,
        marketValue: v, balance: balance,
      );

  /// "CIB · Visa Gold" or just the name when there is no bank.
  String get fullName => bank.isEmpty ? name : '$bank · $name';

  bool get isCard => type == AccountType.creditCard;

  /// Card with a statement cycle configured.
  bool get hasCycle => isCard && statementDay != null && dueDay != null;

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'name': name,
        'bank': bank,
        'type': type.key,
        'currency': currency,
        'opening_balance': openingBalance,
        'archived': archived ? 1 : 0,
        'sort_order': sortOrder,
        'exclude_total': excludeTotal ? 1 : 0,
        'credit_limit': creditLimit,
        'statement_day': statementDay,
        'due_day': dueDay,
        'min_pay_pct': minPayPct,
        ...LoanTerms.toColumns(loan),
        'invest_mode': investMode,
        'invest_value': investValue,
        'invest_value_at': investValueAt?.millisecondsSinceEpoch,
        'invest_base': investBase,
        'asset_value': assetValue,
        'asset_share': assetShare,
        'asset_value_at': assetValueAt?.millisecondsSinceEpoch,
      };

  factory Account.fromMap(Map<String, Object?> m) => Account(
        id: m['id'] as int?,
        name: (m['name'] as String?) ?? '',
        bank: (m['bank'] as String?) ?? '',
        type: AccountTypeX.fromKey(m['type'] as String?),
        currency: (m['currency'] as String?) ?? 'EGP',
        openingBalance: _toDouble(m['opening_balance']),
        archived: (m['archived'] as int? ?? 0) == 1,
        sortOrder: m['sort_order'] as int? ?? 0,
        excludeTotal: (m['exclude_total'] as int? ?? 0) == 1,
        creditLimit:
            m['credit_limit'] == null ? null : _toDouble(m['credit_limit']),
        statementDay: m['statement_day'] as int?,
        dueDay: m['due_day'] as int?,
        minPayPct:
            m['min_pay_pct'] == null ? null : _toDouble(m['min_pay_pct']),
        loan: LoanTerms.fromColumns(m),
        investMode: m['invest_mode'] as String?,
        investValue:
            m['invest_value'] == null ? null : _toDouble(m['invest_value']),
        investValueAt: m['invest_value_at'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(m['invest_value_at'] as int),
        investBase:
            m['invest_base'] == null ? null : _toDouble(m['invest_base']),
        assetValue:
            m['asset_value'] == null ? null : _toDouble(m['asset_value']),
        assetShare:
            m['asset_share'] == null ? null : _toDouble(m['asset_share']),
        assetValueAt: m['asset_value_at'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(m['asset_value_at'] as int),
        balance: _toDouble(m['balance']),
      );
}

/// One statement cycle of a credit card.
class CardStatement {
  /// Closing moment (end of the closing day).
  final DateTime closeDate;
  final DateTime dueDate;

  /// Amount owed at closing (positive = owed).
  final double amount;

  /// Payments / credits received after closing (up to now).
  final double paid;
  final double minPct;

  const CardStatement({
    required this.closeDate,
    required this.dueDate,
    required this.amount,
    required this.paid,
    required this.minPct,
  });

  double get remaining => (amount - paid) > 0.004 ? amount - paid : 0;

  double get minimumDue {
    if (amount <= 0) return 0;
    final m = amount * minPct / 100 - paid;
    if (m <= 0) return 0;
    return m > remaining ? remaining : (m * 100).ceilToDouble() / 100;
  }

  bool get settled => remaining <= 0;
  bool get overdue => !settled && DateTime.now().isAfter(dueDate);
}

/// Everything the app shows about a credit card right now.
class CardSummary {
  final Account card;

  /// Most recent closed statement (null if the card has no cycle yet).
  final CardStatement? last;
  final DateTime? nextClose;

  /// Owed right now (positive).
  final double owedNow;

  /// Future installments still to be billed on this card.
  final double futureInstallments;

  /// Spent in the current (open) cycle so far.
  final double cycleSpent;

  const CardSummary({
    required this.card,
    this.last,
    this.nextClose,
    required this.owedNow,
    required this.futureInstallments,
    required this.cycleSpent,
  });

  double? get available => card.creditLimit == null
      ? null
      : card.creditLimit! - owedNow - futureInstallments;

  double get used => owedNow + futureInstallments;
}

/// End of the closing day for the cycle that closes in [year]/[month].
DateTime cycleCloseIn(int year, int month, int day) {
  final d = dateInMonth(year, month, day);
  return DateTime(d.year, d.month, d.day, 23, 59, 59, 999);
}

/// Most recent closing moment at or before [now].
DateTime lastCloseBefore(DateTime now, int day) {
  var c = cycleCloseIn(now.year, now.month, day);
  if (c.isAfter(now)) c = cycleCloseIn(now.year, now.month - 1, day);
  return c;
}

/// First date with day-of-month [dueDay] strictly after [close].
DateTime dueDateAfter(DateTime close, int dueDay) {
  var d = dateInMonth(close.year, close.month, dueDay);
  if (!d.isAfter(DateTime(close.year, close.month, close.day))) {
    d = dateInMonth(close.year, close.month + 1, dueDay);
  }
  return d;
}

enum TxType { expense, income, transfer }

extension TxTypeX on TxType {
  String get label {
    switch (this) {
      case TxType.expense:
        return 'Expense';
      case TxType.income:
        return 'Income';
      case TxType.transfer:
        return 'Transfer';
    }
  }

  static TxType fromKey(String? key) {
    for (final t in TxType.values) {
      if (t.name == key) return t;
    }
    return TxType.expense;
  }
}

class Category {
  final int? id;
  final String name;

  /// Parent group, e.g. "Food & Dining". Empty = no group.
  final String group;
  final TxType kind; // expense or income
  final String icon; // key into kCategoryIcons
  final int color; // ARGB

  const Category({
    this.id,
    required this.name,
    this.group = '',
    required this.kind,
    this.icon = 'other',
    this.color = 0xFF607D8B,
  });

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'name': name,
        'grp': group,
        'kind': kind.name,
        'icon': icon,
        'color': color,
      };

  factory Category.fromMap(Map<String, Object?> m) => Category(
        id: m['id'] as int?,
        name: (m['name'] as String?) ?? '',
        group: (m['grp'] as String?) ?? '',
        kind: TxTypeX.fromKey(m['kind'] as String?),
        icon: (m['icon'] as String?) ?? 'other',
        color: m['color'] as int? ?? 0xFF607D8B,
      );
}

class Txn {
  final int? id;
  final TxType type;
  final DateTime date;

  /// Amount in the source account's currency. Positive normally; a
  /// negative expense is a refund, a negative income a correction.
  final double amount;
  final int accountId;

  /// Transfer destination.
  final int? toAccountId;

  /// Amount received in destination account's currency (transfers only).
  final double? toAmount;
  final int? categoryId;
  final String payee;
  final String note;

  /// Installment plan this entry belongs to, and its 1-based position.
  final int? planId;
  final int? planIndex;

  /// Recurring rule that produced this entry.
  final int? recurringId;

  /// Credit card expenses: the day the bank posted it. Decides which
  /// statement it belongs to. Null = same as [date].
  final DateTime? postDate;

  /// Transfers into a credit card: the day the card counted the payment.
  /// Decides which statement it belongs to. Null = same as [date].
  final DateTime? toPostDate;

  /// A fee entry (e.g. InstaPay): the transaction it belongs to.
  final int? feeFor;

  const Txn({
    this.id,
    required this.type,
    required this.date,
    required this.amount,
    required this.accountId,
    this.toAccountId,
    this.toAmount,
    this.categoryId,
    this.payee = '',
    this.note = '',
    this.planId,
    this.planIndex,
    this.recurringId,
    this.postDate,
    this.toPostDate,
    this.feeFor,
  });

  bool get isFuture => date.isAfter(DateTime.now());

  DateTime get effectivePostDate => postDate ?? date;

  /// Posted on a different day than it was made.
  bool get postedLater =>
      postDate != null &&
      (postDate!.year != date.year ||
          postDate!.month != date.month ||
          postDate!.day != date.day);

  /// Not posted by the bank yet.
  bool get isPending => postDate != null && postDate!.isAfter(DateTime.now());

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'type': type.name,
        'date': date.millisecondsSinceEpoch,
        'amount': amount,
        'account_id': accountId,
        'to_account_id': toAccountId,
        'to_amount': toAmount,
        'category_id': categoryId,
        'payee': payee,
        'note': note,
        'plan_id': planId,
        'plan_index': planIndex,
        'recurring_id': recurringId,
        'post_date': postDate?.millisecondsSinceEpoch,
        'to_post_date': toPostDate?.millisecondsSinceEpoch,
        'fee_for': feeFor,
      };

  factory Txn.fromMap(Map<String, Object?> m) => Txn(
        id: m['id'] as int?,
        type: TxTypeX.fromKey(m['type'] as String?),
        date: DateTime.fromMillisecondsSinceEpoch(m['date'] as int? ?? 0),
        amount: _toDouble(m['amount']),
        accountId: m['account_id'] as int? ?? 0,
        toAccountId: m['to_account_id'] as int?,
        toAmount: m['to_amount'] == null ? null : _toDouble(m['to_amount']),
        categoryId: m['category_id'] as int?,
        payee: (m['payee'] as String?) ?? '',
        note: (m['note'] as String?) ?? '',
        planId: m['plan_id'] as int?,
        planIndex: m['plan_index'] as int?,
        recurringId: m['recurring_id'] as int?,
        postDate: m['post_date'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(m['post_date'] as int),
        toPostDate: m['to_post_date'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(m['to_post_date'] as int),
        feeFor: m['fee_for'] as int?,
      );
}

/// A purchase split into equal monthly installments. The installments
/// themselves are ordinary transactions with [Txn.planId] set.
class InstallmentPlan {
  final int? id;
  final double total;
  final int months;
  final DateTime purchaseDate;
  final DateTime firstDate;

  const InstallmentPlan({
    this.id,
    required this.total,
    required this.months,
    required this.purchaseDate,
    required this.firstDate,
  });

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'total': total,
        'months': months,
        'purchase_date': purchaseDate.millisecondsSinceEpoch,
        'first_date': firstDate.millisecondsSinceEpoch,
      };

  factory InstallmentPlan.fromMap(Map<String, Object?> m) => InstallmentPlan(
        id: m['id'] as int?,
        total: _toDouble(m['total']),
        months: m['months'] as int? ?? 1,
        purchaseDate:
            DateTime.fromMillisecondsSinceEpoch(m['purchase_date'] as int? ?? 0),
        firstDate:
            DateTime.fromMillisecondsSinceEpoch(m['first_date'] as int? ?? 0),
      );

  /// Splits [total] into [months] parts rounded to 2 decimals; the last part
  /// absorbs the rounding difference.
  static List<double> split(double total, int months) {
    final part = (total / months * 100).floorToDouble() / 100;
    final parts = List<double>.filled(months, part);
    parts[months - 1] =
        ((total - part * (months - 1)) * 100).roundToDouble() / 100;
    return parts;
  }
}

enum Freq { weekly, monthly, yearly }

extension FreqX on Freq {
  String get label {
    switch (this) {
      case Freq.weekly:
        return 'Weekly';
      case Freq.monthly:
        return 'Monthly';
      case Freq.yearly:
        return 'Yearly';
    }
  }

  String unit(int n) {
    switch (this) {
      case Freq.weekly:
        return n == 1 ? 'week' : 'weeks';
      case Freq.monthly:
        return n == 1 ? 'month' : 'months';
      case Freq.yearly:
        return n == 1 ? 'year' : 'years';
    }
  }

  static Freq fromKey(String? k) {
    for (final f in Freq.values) {
      if (f.name == k) return f;
    }
    return Freq.monthly;
  }
}

enum EndType { never, count, date }

EndType _endFromKey(String? k) {
  for (final e in EndType.values) {
    if (e.name == k) return e;
  }
  return EndType.never;
}

/// A repeating income / expense / transfer. Occurrences are not stored until
/// the user confirms them; [nextIndex] is the first unhandled occurrence.
class RecurringRule {
  final int? id;
  final TxType type;
  final double amount;
  final int accountId;
  final int? toAccountId;
  final double? toAmount;
  final int? categoryId;
  final String payee;
  final String note;
  final Freq freq;
  final int interval;
  final DateTime start;
  final EndType endType;
  final int? endCount;
  final DateTime? endDate;
  final int nextIndex;

  const RecurringRule({
    this.id,
    required this.type,
    required this.amount,
    required this.accountId,
    this.toAccountId,
    this.toAmount,
    this.categoryId,
    this.payee = '',
    this.note = '',
    this.freq = Freq.monthly,
    this.interval = 1,
    required this.start,
    this.endType = EndType.never,
    this.endCount,
    this.endDate,
    this.nextIndex = 0,
  });

  RecurringRule copyWith({int? nextIndex}) => RecurringRule(
        id: id,
        type: type,
        amount: amount,
        accountId: accountId,
        toAccountId: toAccountId,
        toAmount: toAmount,
        categoryId: categoryId,
        payee: payee,
        note: note,
        freq: freq,
        interval: interval,
        start: start,
        endType: endType,
        endCount: endCount,
        endDate: endDate,
        nextIndex: nextIndex ?? this.nextIndex,
      );

  /// Date of occurrence [i] (0-based). Monthly/yearly keep the start day,
  /// clamped to the month's length (e.g. 31st → 30th/28th).
  DateTime occurrence(int i) {
    final step = i * interval;
    switch (freq) {
      case Freq.weekly:
        return DateTime(start.year, start.month, start.day + 7 * step,
            start.hour, start.minute);
      case Freq.monthly:
        return _clampedDate(start.year, start.month + step, start.day,
            start.hour, start.minute);
      case Freq.yearly:
        return _clampedDate(start.year + step, start.month, start.day,
            start.hour, start.minute);
    }
  }

  bool isValidIndex(int i) {
    if (endType == EndType.count && endCount != null && i >= endCount!) {
      return false;
    }
    if (endType == EndType.date && endDate != null) {
      final d = occurrence(i);
      final end = DateTime(endDate!.year, endDate!.month, endDate!.day + 1);
      if (!d.isBefore(end)) return false;
    }
    return true;
  }

  bool get finished => !isValidIndex(nextIndex);

  /// Unhandled occurrences with dates in [from, to).
  List<Occurrence> occurrencesBetween(DateTime from, DateTime to) {
    final out = <Occurrence>[];
    for (var i = nextIndex; i < nextIndex + 2000; i++) {
      if (!isValidIndex(i)) break;
      final d = occurrence(i);
      if (!d.isBefore(to)) break;
      if (!d.isBefore(from)) out.add(Occurrence(this, i, d));
    }
    return out;
  }

  String get scheduleLabel {
    final every = interval == 1
        ? freq.label
        : 'Every $interval ${freq.unit(interval)}';
    switch (endType) {
      case EndType.never:
        return every;
      case EndType.count:
        return '$every · ${endCount ?? 0} times';
      case EndType.date:
        final e = endDate!;
        return '$every · until ${e.day}/${e.month}/${e.year}';
    }
  }

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'type': type.name,
        'amount': amount,
        'account_id': accountId,
        'to_account_id': toAccountId,
        'to_amount': toAmount,
        'category_id': categoryId,
        'payee': payee,
        'note': note,
        'freq': freq.name,
        'interval': interval,
        'start': start.millisecondsSinceEpoch,
        'end_type': endType.name,
        'end_count': endCount,
        'end_date': endDate?.millisecondsSinceEpoch,
        'next_index': nextIndex,
      };

  factory RecurringRule.fromMap(Map<String, Object?> m) => RecurringRule(
        id: m['id'] as int?,
        type: TxTypeX.fromKey(m['type'] as String?),
        amount: _toDouble(m['amount']),
        accountId: m['account_id'] as int? ?? 0,
        toAccountId: m['to_account_id'] as int?,
        toAmount: m['to_amount'] == null ? null : _toDouble(m['to_amount']),
        categoryId: m['category_id'] as int?,
        payee: (m['payee'] as String?) ?? '',
        note: (m['note'] as String?) ?? '',
        freq: FreqX.fromKey(m['freq'] as String?),
        interval: m['interval'] as int? ?? 1,
        start: DateTime.fromMillisecondsSinceEpoch(m['start'] as int? ?? 0),
        endType: _endFromKey(m['end_type'] as String?),
        endCount: m['end_count'] as int?,
        endDate: m['end_date'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(m['end_date'] as int),
        nextIndex: m['next_index'] as int? ?? 0,
      );

  /// The transaction this rule would create for occurrence [i].
  Txn toTxn(int i) => Txn(
        type: type,
        date: occurrence(i),
        amount: amount,
        accountId: accountId,
        toAccountId: type == TxType.transfer ? toAccountId : null,
        toAmount: type == TxType.transfer ? toAmount : null,
        categoryId: type == TxType.transfer ? null : categoryId,
        payee: payee,
        note: note,
        recurringId: id,
      );
}

/// One not-yet-confirmed occurrence of a recurring rule.
class Occurrence {
  final RecurringRule rule;
  final int index;
  final DateTime date;

  const Occurrence(this.rule, this.index, this.date);

  /// Due = date has arrived and it still needs confirming.
  bool get isDue => !date.isAfter(DateTime.now());
}

DateTime _clampedDate(int year, int month, int day, int hour, int minute) {
  // Normalise month overflow first.
  final first = DateTime(year, month, 1);
  final lastDay = DateTime(first.year, first.month + 1, 0).day;
  return DateTime(
      first.year, first.month, day > lastDay ? lastDay : day, hour, minute);
}

/// [day] of the given month, clamped to the month's last day.
DateTime dateInMonth(int year, int month, int day, [int hour = 0, int minute = 0]) =>
    _clampedDate(year, month, day, hour, minute);

/// Adds [months] to [d], keeping the day where possible.
DateTime addMonths(DateTime d, int months) =>
    _clampedDate(d.year, d.month + months, d.day, d.hour, d.minute);

class CurrencyRate {
  final String code;

  /// Units of this currency per 1 USD.
  final double perUsd;
  final bool manual;
  final DateTime? updatedAt;

  const CurrencyRate({
    required this.code,
    required this.perUsd,
    this.manual = false,
    this.updatedAt,
  });

  Map<String, Object?> toMap() => {
        'code': code,
        'per_usd': perUsd,
        'manual': manual ? 1 : 0,
        'updated_at': updatedAt?.millisecondsSinceEpoch,
      };

  factory CurrencyRate.fromMap(Map<String, Object?> m) => CurrencyRate(
        code: m['code'] as String,
        perUsd: _toDouble(m['per_usd']),
        manual: (m['manual'] as int? ?? 0) == 1,
        updatedAt: m['updated_at'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(m['updated_at'] as int),
      );
}

double _toDouble(Object? v) {
  if (v == null) return 0;
  if (v is double) return v;
  if (v is int) return v.toDouble();
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString()) ?? 0;
}

// ---------------------------------------------------------------------------
// Budgets
// ---------------------------------------------------------------------------

enum BudgetScope { total, group, category }

/// A monthly spending limit on everything, a category group or one category.
/// Amounts are in the main currency.
class Budget {
  final int? id;
  final BudgetScope scope;

  /// Group name for [BudgetScope.group], category id for
  /// [BudgetScope.category], empty for [BudgetScope.total].
  final String target;
  final double amount;

  /// Unspent money (or overspending) carries into the next month.
  final bool rollover;

  /// First month the budget applies to (rollover counts from here).
  final DateTime start;
  final int sortOrder;

  const Budget({
    this.id,
    required this.scope,
    this.target = '',
    required this.amount,
    this.rollover = false,
    required this.start,
    this.sortOrder = 0,
  });

  int? get categoryId =>
      scope == BudgetScope.category ? int.tryParse(target) : null;

  Budget copyWith({double? amount, bool? rollover, DateTime? start}) => Budget(
        id: id,
        scope: scope,
        target: target,
        amount: amount ?? this.amount,
        rollover: rollover ?? this.rollover,
        start: start ?? this.start,
        sortOrder: sortOrder,
      );

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'scope': scope.name,
        'target': target,
        'amount': amount,
        'rollover': rollover ? 1 : 0,
        'start': DateTime(start.year, start.month).millisecondsSinceEpoch,
        'sort_order': sortOrder,
      };

  factory Budget.fromMap(Map<String, Object?> m) => Budget(
        id: m['id'] as int?,
        scope: BudgetScope.values.firstWhere((s) => s.name == m['scope'],
            orElse: () => BudgetScope.total),
        target: (m['target'] as String?) ?? '',
        amount: _toDouble(m['amount']),
        rollover: (m['rollover'] as int? ?? 0) == 1,
        start: DateTime.fromMillisecondsSinceEpoch(m['start'] as int),
        sortOrder: m['sort_order'] as int? ?? 0,
      );
}

/// A budget's position for one month.
class BudgetStatus {
  final Budget budget;
  final String name;

  /// This month's limit plus anything carried over.
  final double limit;
  final double carried;
  final double spent;

  const BudgetStatus({
    required this.budget,
    required this.name,
    required this.limit,
    required this.carried,
    required this.spent,
  });

  double get left => limit - spent;
  double get fraction => limit <= 0 ? (spent > 0 ? 1.0 : 0.0) : spent / limit;
  bool get over => spent > limit + 0.004;
}


// ---------------------------------------------------------------------------
// Loans
// ---------------------------------------------------------------------------

enum LoanMode { installments, interest }

/// How a loan is repaid. Stored on the loan account.
class LoanTerms {
  final LoanMode mode;

  /// Monthly installment (installments mode; computed for interest mode).
  final double payment;
  final int months;
  final DateTime firstDue;

  /// Account the installments are paid from.
  final int? payAccountId;

  // Interest mode.
  final double principal;

  /// Yearly interest rate in %.
  final double rate;

  /// true = flat rate (common for Egyptian personal loans), false =
  /// declining balance.
  final bool flat;

  /// Installments already handled (confirmed); the next one is this index.
  final int nextIndex;

  const LoanTerms({
    required this.mode,
    required this.payment,
    required this.months,
    required this.firstDue,
    this.payAccountId,
    this.principal = 0,
    this.rate = 0,
    this.flat = true,
    this.nextIndex = 0,
  });

  LoanTerms copyWith({int? nextIndex}) => LoanTerms(
        mode: mode,
        payment: payment,
        months: months,
        firstDue: firstDue,
        payAccountId: payAccountId,
        principal: principal,
        rate: rate,
        flat: flat,
        nextIndex: nextIndex ?? this.nextIndex,
      );

  /// Monthly payment for an interest loan.
  static double interestPayment(double p, double ratePct, int n, bool flat) {
    if (n <= 0) return 0;
    if (flat) return (p + p * ratePct / 100 * n / 12) / n;
    final r = ratePct / 100 / 12;
    if (r == 0) return p / n;
    return p * r / (1 - _pow(1 + r, -n));
  }

  static double _pow(double b, int e) {
    var out = 1.0;
    final n = e.abs();
    for (var i = 0; i < n; i++) {
      out *= b;
    }
    return e < 0 ? 1 / out : out;
  }

  static double _r2(double v) => (v * 100).roundToDouble() / 100;

  /// Every installment with its date and split.
  List<LoanRow> schedule() {
    final out = <LoanRow>[];
    if (mode == LoanMode.installments) {
      var left = payment * months;
      for (var i = 0; i < months; i++) {
        left -= payment;
        out.add(LoanRow(i, addMonths(firstDue, i), payment, payment, 0,
            left.abs() < 0.005 ? 0 : left));
      }
      return out;
    }
    var bal = principal;
    final totalInterest = principal * rate / 100 * months / 12;
    for (var i = 0; i < months; i++) {
      double interest, princ;
      if (flat) {
        interest = _r2(totalInterest / months);
        princ = i == months - 1 ? bal : _r2(principal / months);
      } else {
        interest = _r2(bal * rate / 100 / 12);
        princ = i == months - 1 ? bal : _r2(payment - interest);
      }
      bal -= princ;
      out.add(LoanRow(i, addMonths(firstDue, i), _r2(princ + interest), princ,
          interest, bal.abs() < 0.005 ? 0 : bal));
    }
    return out;
  }

  /// What the loan account should show as owed at the start.
  double get startOwed =>
      mode == LoanMode.installments ? payment * months : principal;

  static Map<String, Object?> toColumns(LoanTerms? t) => {
        'loan_mode': t?.mode.name,
        'loan_payment': t?.payment,
        'loan_months': t?.months,
        'loan_first_due': t?.firstDue.millisecondsSinceEpoch,
        'loan_pay_account': t?.payAccountId,
        'loan_principal': t?.principal,
        'loan_rate': t?.rate,
        'loan_flat': t == null ? null : (t.flat ? 1 : 0),
        'loan_next': t?.nextIndex ?? 0,
      };

  static LoanTerms? fromColumns(Map<String, Object?> m) {
    final mode = m['loan_mode'] as String?;
    if (mode == null || m['loan_months'] == null || m['loan_first_due'] == null) {
      return null;
    }
    return LoanTerms(
      mode: mode == 'interest' ? LoanMode.interest : LoanMode.installments,
      payment: _toDouble(m['loan_payment']),
      months: m['loan_months'] as int,
      firstDue: DateTime.fromMillisecondsSinceEpoch(m['loan_first_due'] as int),
      payAccountId: m['loan_pay_account'] as int?,
      principal: _toDouble(m['loan_principal']),
      rate: _toDouble(m['loan_rate']),
      flat: (m['loan_flat'] as int? ?? 1) == 1,
      nextIndex: m['loan_next'] as int? ?? 0,
    );
  }
}

/// One installment of a loan.
class LoanRow {
  final int index; // 0-based
  final DateTime date;
  final double payment;
  final double principal;
  final double interest;

  /// Still owed after this installment.
  final double balanceAfter;
  const LoanRow(this.index, this.date, this.payment, this.principal,
      this.interest, this.balanceAfter);
}


// ---------------------------------------------------------------------------
// Stocks
// ---------------------------------------------------------------------------

/// A buy or sell of shares in an investment account.
class Trade {
  final int? id;
  final int accountId;
  final String symbol;
  final DateTime date;
  final bool buy;
  final double qty;
  final double price;
  final double fees;

  /// Sells: profit or loss against the average cost at the time.
  final double realized;

  /// Linked entries (fee expense, profit/loss) so they can be removed too.
  final int? feeTxnId;
  final int? pnlTxnId;

  const Trade({
    this.id,
    required this.accountId,
    required this.symbol,
    required this.date,
    required this.buy,
    required this.qty,
    required this.price,
    this.fees = 0,
    this.realized = 0,
    this.feeTxnId,
    this.pnlTxnId,
  });

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'account_id': accountId,
        'symbol': symbol,
        'date': date.millisecondsSinceEpoch,
        'side': buy ? 'buy' : 'sell',
        'qty': qty,
        'price': price,
        'fees': fees,
        'realized': realized,
        'fee_txn_id': feeTxnId,
        'pnl_txn_id': pnlTxnId,
      };

  factory Trade.fromMap(Map<String, Object?> m) => Trade(
        id: m['id'] as int?,
        accountId: m['account_id'] as int,
        symbol: m['symbol'] as String,
        date: DateTime.fromMillisecondsSinceEpoch(m['date'] as int),
        buy: m['side'] == 'buy',
        qty: _toDouble(m['qty']),
        price: _toDouble(m['price']),
        fees: _toDouble(m['fees']),
        realized: _toDouble(m['realized']),
        feeTxnId: m['fee_txn_id'] as int?,
        pnlTxnId: m['pnl_txn_id'] as int?,
      );
}

/// Shares of one stock held now, at average cost.
class Holding {
  final String symbol;
  double qty = 0;

  /// Total cost of the shares still held.
  double cost = 0;
  double? price;
  bool manualPrice = false;
  DateTime? priceAt;
  Holding(this.symbol);

  double get avgCost => qty > 0 ? cost / qty : 0;
  double get value => price == null ? cost : qty * price!;
  double get gain => value - cost;
}

/// Latest known price of a stock.
class StockPrice {
  final String symbol;
  final double price;
  final bool manual;
  final DateTime? updatedAt;
  const StockPrice(this.symbol, this.price, {this.manual = false, this.updatedAt});

  Map<String, Object?> toMap() => {
        'symbol': symbol,
        'price': price,
        'manual': manual ? 1 : 0,
        'updated_at': updatedAt?.millisecondsSinceEpoch,
      };

  factory StockPrice.fromMap(Map<String, Object?> m) => StockPrice(
        m['symbol'] as String,
        _toDouble(m['price']),
        manual: (m['manual'] as int? ?? 0) == 1,
        updatedAt: m['updated_at'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(m['updated_at'] as int),
      );
}
