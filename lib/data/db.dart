import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'models.dart';

class AppDb {
  AppDb._(this.db);

  final Database db;

  static const int schemaVersion = 1;

  static Future<AppDb> open() async {
    final dir = await getDatabasesPath();
    final path = p.join(dir, 'money_tracker.db');
    final db = await openDatabase(
      path,
      version: schemaVersion,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: (db, version) async {
        await _createV1(db);
        await _seed(db);
      },
      onUpgrade: (db, oldV, newV) async {
        // Future migrations go here, one step at a time.
      },
    );
    return AppDb._(db);
  }

  static Future<void> _createV1(Database db) async {
    await db.execute('''
      CREATE TABLE accounts (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        type TEXT NOT NULL,
        currency TEXT NOT NULL,
        opening_balance REAL NOT NULL DEFAULT 0,
        archived INTEGER NOT NULL DEFAULT 0,
        sort_order INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute('''
      CREATE TABLE categories (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        kind TEXT NOT NULL,
        icon TEXT NOT NULL DEFAULT 'other',
        color INTEGER NOT NULL DEFAULT 4284513675
      )
    ''');
    await db.execute('''
      CREATE TABLE transactions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        type TEXT NOT NULL,
        date INTEGER NOT NULL,
        amount REAL NOT NULL,
        account_id INTEGER NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
        to_account_id INTEGER REFERENCES accounts(id) ON DELETE CASCADE,
        to_amount REAL,
        category_id INTEGER REFERENCES categories(id) ON DELETE SET NULL,
        payee TEXT NOT NULL DEFAULT '',
        note TEXT NOT NULL DEFAULT ''
      )
    ''');
    await db.execute('CREATE INDEX idx_tx_date ON transactions(date)');
    await db.execute('CREATE INDEX idx_tx_account ON transactions(account_id)');
    await db.execute('CREATE INDEX idx_tx_to_account ON transactions(to_account_id)');
    await db.execute('''
      CREATE TABLE rates (
        code TEXT PRIMARY KEY,
        per_usd REAL NOT NULL,
        manual INTEGER NOT NULL DEFAULT 0,
        updated_at INTEGER
      )
    ''');
    await db.execute('''
      CREATE TABLE settings (
        key TEXT PRIMARY KEY,
        value TEXT
      )
    ''');
  }

  static Future<void> _seed(Database db) async {
    const expense = [
      ['Food & Dining', 'food', 0xFFFB8C00],
      ['Groceries', 'groceries', 0xFF43A047],
      ['Transport', 'transport', 0xFF1E88E5],
      ['Fuel', 'fuel', 0xFF6D4C41],
      ['Home & Rent', 'home', 0xFF5E35B1],
      ['Bills & Utilities', 'bills', 0xFF3949AB],
      ['Phone & Internet', 'internet', 0xFF039BE5],
      ['Health', 'health', 0xFFE53935],
      ['Shopping', 'shopping', 0xFFD81B60],
      ['Clothes', 'clothes', 0xFF8E24AA],
      ['Entertainment', 'entertainment', 0xFFF4511E],
      ['Travel', 'travel', 0xFF00897B],
      ['Education', 'education', 0xFF7CB342],
      ['Gifts', 'gift', 0xFFFFB300],
      ['Charity', 'charity', 0xFF00897B],
      ['Bank fees', 'fees', 0xFF607D8B],
      ['Other', 'other', 0xFF607D8B],
    ];
    const income = [
      ['Salary', 'salary', 0xFF43A047],
      ['Bonus', 'bonus', 0xFFFFB300],
      ['Business', 'business', 0xFF1E88E5],
      ['Interest & Dividends', 'interest', 0xFF00897B],
      ['Refund', 'refund', 0xFF7CB342],
      ['Other income', 'other', 0xFF607D8B],
    ];
    final batch = db.batch();
    for (final c in expense) {
      batch.insert('categories',
          {'name': c[0], 'kind': 'expense', 'icon': c[1], 'color': c[2]});
    }
    for (final c in income) {
      batch.insert('categories',
          {'name': c[0], 'kind': 'income', 'icon': c[1], 'color': c[2]});
    }
    batch.insert('settings', {'key': 'base_currency', 'value': 'EGP'});
    batch.insert('rates', {'code': 'USD', 'per_usd': 1.0, 'manual': 0});
    await batch.commit(noResult: true);
  }

  // ---------------- Settings ----------------

  Future<String?> getSetting(String key) async {
    final rows =
        await db.query('settings', where: 'key = ?', whereArgs: [key], limit: 1);
    if (rows.isEmpty) return null;
    return rows.first['value'] as String?;
  }

  Future<void> setSetting(String key, String value) async {
    await db.insert('settings', {'key': key, 'value': value},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  // ---------------- Accounts ----------------

  /// Accounts with their current balance computed in SQL.
  Future<List<Account>> accountsWithBalances() async {
    final rows = await db.rawQuery('''
      SELECT a.*,
        a.opening_balance
        + COALESCE((SELECT SUM(amount) FROM transactions
            WHERE account_id = a.id AND type = 'income'), 0)
        - COALESCE((SELECT SUM(amount) FROM transactions
            WHERE account_id = a.id AND type IN ('expense', 'transfer')), 0)
        + COALESCE((SELECT SUM(COALESCE(to_amount, amount)) FROM transactions
            WHERE to_account_id = a.id AND type = 'transfer'), 0)
        AS balance
      FROM accounts a
      ORDER BY a.archived, a.sort_order, a.name COLLATE NOCASE
    ''');
    return rows.map(Account.fromMap).toList();
  }

  Future<int> insertAccount(Account a) => db.insert('accounts', a.toMap());

  Future<void> updateAccount(Account a) =>
      db.update('accounts', a.toMap(), where: 'id = ?', whereArgs: [a.id]);

  Future<void> deleteAccount(int id) =>
      db.delete('accounts', where: 'id = ?', whereArgs: [id]);

  Future<int> countAccountTransactions(int id) async {
    final r = await db.rawQuery(
        'SELECT COUNT(*) AS c FROM transactions WHERE account_id = ? OR to_account_id = ?',
        [id, id]);
    return (r.first['c'] as int?) ?? 0;
  }

  // ---------------- Categories ----------------

  Future<List<Category>> categories() async {
    final rows = await db.query('categories', orderBy: 'name COLLATE NOCASE');
    return rows.map(Category.fromMap).toList();
  }

  Future<int> insertCategory(Category c) => db.insert('categories', c.toMap());

  Future<void> updateCategory(Category c) =>
      db.update('categories', c.toMap(), where: 'id = ?', whereArgs: [c.id]);

  Future<void> deleteCategory(int id) =>
      db.delete('categories', where: 'id = ?', whereArgs: [id]);

  // ---------------- Transactions ----------------

  Future<List<Txn>> transactions({
    DateTime? from,
    DateTime? to,
    int? accountId,
    int? limit,
  }) async {
    final where = <String>[];
    final args = <Object?>[];
    if (from != null) {
      where.add('date >= ?');
      args.add(from.millisecondsSinceEpoch);
    }
    if (to != null) {
      where.add('date < ?');
      args.add(to.millisecondsSinceEpoch);
    }
    if (accountId != null) {
      where.add('(account_id = ? OR to_account_id = ?)');
      args.add(accountId);
      args.add(accountId);
    }
    final rows = await db.query(
      'transactions',
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
      orderBy: 'date DESC, id DESC',
      limit: limit,
    );
    return rows.map(Txn.fromMap).toList();
  }

  Future<int> insertTxn(Txn t) => db.insert('transactions', t.toMap());

  Future<void> updateTxn(Txn t) =>
      db.update('transactions', t.toMap(), where: 'id = ?', whereArgs: [t.id]);

  Future<void> deleteTxn(int id) =>
      db.delete('transactions', where: 'id = ?', whereArgs: [id]);

  // ---------------- Rates ----------------

  Future<List<CurrencyRate>> rates() async {
    final rows = await db.query('rates', orderBy: 'code');
    return rows.map(CurrencyRate.fromMap).toList();
  }

  Future<void> upsertRate(CurrencyRate r) => db.insert('rates', r.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace);

  /// Saves fetched rates, leaving manually-set ones untouched.
  Future<void> saveFetchedRates(Map<String, double> perUsd) async {
    final existing = {for (final r in await rates()) r.code: r};
    final now = DateTime.now();
    final batch = db.batch();
    perUsd.forEach((code, value) {
      final old = existing[code];
      if (old != null && old.manual) return;
      batch.insert(
        'rates',
        CurrencyRate(code: code, perUsd: value, updatedAt: now).toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });
    await batch.commit(noResult: true);
  }
}
