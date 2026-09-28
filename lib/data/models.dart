enum AccountType { cash, bank, savings, creditCard, investment, other }

extension AccountTypeX on AccountType {
  String get key => name;

  String get label {
    switch (this) {
      case AccountType.cash:
        return 'Cash';
      case AccountType.bank:
        return 'Bank account';
      case AccountType.savings:
        return 'Savings';
      case AccountType.creditCard:
        return 'Credit card';
      case AccountType.investment:
        return 'Investment';
      case AccountType.other:
        return 'Other';
    }
  }

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
    this.balance = 0,
  });

  /// "CIB · Visa Gold" or just the name when there is no bank.
  String get fullName => bank.isEmpty ? name : '$bank · $name';

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'name': name,
        'bank': bank,
        'type': type.key,
        'currency': currency,
        'opening_balance': openingBalance,
        'archived': archived ? 1 : 0,
        'sort_order': sortOrder,
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
        balance: _toDouble(m['balance']),
      );
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
  final TxType kind; // expense or income
  final String icon; // key into kCategoryIcons
  final int color; // ARGB

  const Category({
    this.id,
    required this.name,
    required this.kind,
    this.icon = 'other',
    this.color = 0xFF607D8B,
  });

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'name': name,
        'kind': kind.name,
        'icon': icon,
        'color': color,
      };

  factory Category.fromMap(Map<String, Object?> m) => Category(
        id: m['id'] as int?,
        name: (m['name'] as String?) ?? '',
        kind: TxTypeX.fromKey(m['kind'] as String?),
        icon: (m['icon'] as String?) ?? 'other',
        color: m['color'] as int? ?? 0xFF607D8B,
      );
}

class Txn {
  final int? id;
  final TxType type;
  final DateTime date;

  /// Amount in the source account's currency. Always positive.
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
  });

  bool get isFuture => date.isAfter(DateTime.now());

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
