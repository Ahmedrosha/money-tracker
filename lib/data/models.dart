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
  final AccountType type;
  final String currency;
  final double openingBalance;
  final bool archived;
  final int sortOrder;

  /// Computed current balance in the account's own currency (not stored).
  final double balance;

  const Account({
    this.id,
    required this.name,
    required this.type,
    required this.currency,
    this.openingBalance = 0,
    this.archived = false,
    this.sortOrder = 0,
    this.balance = 0,
  });

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'name': name,
        'type': type.key,
        'currency': currency,
        'opening_balance': openingBalance,
        'archived': archived ? 1 : 0,
        'sort_order': sortOrder,
      };

  factory Account.fromMap(Map<String, Object?> m) => Account(
        id: m['id'] as int?,
        name: (m['name'] as String?) ?? '',
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
  });

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
      );
}

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
