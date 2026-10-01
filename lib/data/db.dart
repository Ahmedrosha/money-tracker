import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'models.dart';

class SearchResult {
  final List<Txn> txns;

  /// All matches (txns is capped).
  final int count;

  /// type -> currency -> sum of amounts.
  final Map<String, Map<String, double>> totals;

  const SearchResult(
      {required this.txns, required this.count, required this.totals});
}

class BackupInfo {
  final int version;
  final int accounts;
  final int transactions;
  final DateTime? first;
  final DateTime? last;

  const BackupInfo({
    required this.version,
    required this.accounts,
    required this.transactions,
    this.first,
    this.last,
  });
}

class AppDb {
  AppDb._(this.db);

  final Database db;

  static const int schemaVersion = 16;

  static Future<String> dbPath() async =>
      p.join(await getDatabasesPath(), 'money_tracker.db');

  Future<void> close() => db.close();

  /// Writes a consistent copy of the database to [dest].
  Future<void> backupTo(String dest) async {
    final f = File(dest);
    if (await f.exists()) await f.delete();
    try {
      // Produces a clean, self-contained copy (SQLite 3.27+).
      await db.execute('VACUUM INTO ?', [dest]);
    } catch (_) {
      // Older SQLite: flush the journal and copy the file.
      try {
        await db.rawQuery('PRAGMA wal_checkpoint(TRUNCATE)');
      } catch (_) {}
      await File(await dbPath()).copy(dest);
    }
  }

  /// Reads basic facts from a backup file without touching the live data.
  /// Throws if the file is not a Money Tracker database.
  static Future<BackupInfo> inspect(String path) async {
    final d = await openDatabase(path, readOnly: true, singleInstance: false);
    try {
      final tables = (await d.rawQuery(
              "SELECT name FROM sqlite_master WHERE type = 'table'"))
          .map((r) => r['name'] as String)
          .toSet();
      if (!tables.containsAll(['accounts', 'transactions', 'categories'])) {
        throw const FormatException('Not a Money Tracker backup');
      }
      final version =
          (await d.rawQuery('PRAGMA user_version')).first.values.first as int;
      final acc = (await d.rawQuery('SELECT COUNT(*) AS c FROM accounts'))
          .first['c'] as int;
      final tx = await d.rawQuery(
          'SELECT COUNT(*) AS c, MIN(date) AS mn, MAX(date) AS mx FROM transactions');
      final r = tx.first;
      return BackupInfo(
        version: version,
        accounts: acc,
        transactions: r['c'] as int,
        first: r['mn'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(r['mn'] as int),
        last: r['mx'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(r['mx'] as int),
      );
    } finally {
      await d.close();
    }
  }

  static Future<AppDb> open() async {
    final path = await dbPath();
    final db = await openDatabase(
      path,
      version: schemaVersion,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: (db, version) async {
        await _createV1(db);
        await _migrateToV2(db);
        await _migrateToV3(db);
        await _migrateToV4(db);
        await _migrateToV5(db);
        await _migrateToV6(db);
        await _migrateToV7(db);
        await _migrateToV8(db);
        await _migrateToV9(db);
        await _migrateToV10(db);
        await _migrateToV11(db);
        await _migrateToV12(db);
        await _migrateToV13(db);
        await _migrateToV14(db);
        await _migrateToV15(db);
        await _migrateToV16(db);
        await _seed(db);
      },
      onUpgrade: (db, oldV, newV) async {
        if (oldV < 2) await _migrateToV2(db);
        if (oldV < 3) await _migrateToV3(db);
        if (oldV < 4) await _migrateToV4(db);
        if (oldV < 5) await _migrateToV5(db);
        if (oldV < 6) await _migrateToV6(db);
        if (oldV < 7) await _migrateToV7(db);
        if (oldV < 8) await _migrateToV8(db);
        if (oldV < 9) await _migrateToV9(db);
        if (oldV < 10) await _migrateToV10(db);
        if (oldV < 11) await _migrateToV11(db);
        if (oldV < 12) await _migrateToV12(db);
        if (oldV < 13) await _migrateToV13(db);
        if (oldV < 14) await _migrateToV14(db);
        if (oldV < 15) await _migrateToV15(db);
        if (oldV < 16) await _migrateToV16(db);
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

  static Future<void> _migrateToV2(Database db) async {
    await db.execute(
        "ALTER TABLE accounts ADD COLUMN bank TEXT NOT NULL DEFAULT ''");
    await db.execute('ALTER TABLE transactions ADD COLUMN plan_id INTEGER');
    await db.execute('ALTER TABLE transactions ADD COLUMN plan_index INTEGER');
    await db.execute('ALTER TABLE transactions ADD COLUMN recurring_id INTEGER');
    await db.execute('CREATE INDEX idx_tx_plan ON transactions(plan_id)');
    await db.execute('''
      CREATE TABLE plans (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        total REAL NOT NULL,
        months INTEGER NOT NULL,
        purchase_date INTEGER NOT NULL,
        first_date INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE recurring (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        type TEXT NOT NULL,
        amount REAL NOT NULL,
        account_id INTEGER NOT NULL,
        to_account_id INTEGER,
        to_amount REAL,
        category_id INTEGER,
        payee TEXT NOT NULL DEFAULT '',
        note TEXT NOT NULL DEFAULT '',
        freq TEXT NOT NULL,
        interval INTEGER NOT NULL DEFAULT 1,
        start INTEGER NOT NULL,
        end_type TEXT NOT NULL DEFAULT 'never',
        end_count INTEGER,
        end_date INTEGER,
        next_index INTEGER NOT NULL DEFAULT 0
      )
    ''');
  }

  static Future<void> _migrateToV3(Database db) async {
    await db.execute('ALTER TABLE accounts ADD COLUMN credit_limit REAL');
    await db.execute('ALTER TABLE accounts ADD COLUMN statement_day INTEGER');
    await db.execute('ALTER TABLE accounts ADD COLUMN due_day INTEGER');
    await db.execute('ALTER TABLE accounts ADD COLUMN min_pay_pct REAL');
  }

  static Future<void> _migrateToV4(Database db) async {
    await db.execute(
        "ALTER TABLE categories ADD COLUMN grp TEXT NOT NULL DEFAULT ''");
    await db.execute(
        'ALTER TABLE accounts ADD COLUMN exclude_total INTEGER NOT NULL DEFAULT 0');
  }

  static Future<void> _migrateToV5(Database db) async {
    await db.execute('ALTER TABLE transactions ADD COLUMN post_date INTEGER');
    // Existing credit card expenses: posted on the day they were made.
    await db.execute('''
      UPDATE transactions SET post_date = date
      WHERE type = 'expense'
        AND account_id IN (SELECT id FROM accounts WHERE type = 'creditCard')
    ''');
  }

  static Future<void> _migrateToV6(Database db) async {
    await db.execute('''
      CREATE TABLE budgets (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        scope TEXT NOT NULL,
        target TEXT NOT NULL DEFAULT '',
        amount REAL NOT NULL,
        rollover INTEGER NOT NULL DEFAULT 0,
        start INTEGER NOT NULL,
        sort_order INTEGER NOT NULL DEFAULT 0
      )
    ''');
  }

  static Future<void> _migrateToV7(Database db) async {
    await db.execute('ALTER TABLE transactions ADD COLUMN to_post_date INTEGER');
  }

  static Future<void> _migrateToV8(Database db) async {
    for (final col in const [
      'loan_mode TEXT', 'loan_payment REAL', 'loan_months INTEGER',
      'loan_first_due INTEGER', 'loan_pay_account INTEGER',
      'loan_principal REAL', 'loan_rate REAL', 'loan_flat INTEGER',
      'loan_next INTEGER NOT NULL DEFAULT 0',
    ]) {
      await db.execute('ALTER TABLE accounts ADD COLUMN $col');
    }
  }

  static Future<void> _migrateToV9(Database db) async {
    for (final col in const [
      'invest_mode TEXT', 'invest_value REAL', 'invest_value_at INTEGER',
      'invest_base REAL',
    ]) {
      await db.execute('ALTER TABLE accounts ADD COLUMN $col');
    }
    await db.execute('''
      CREATE TABLE trades (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        account_id INTEGER NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
        symbol TEXT NOT NULL,
        date INTEGER NOT NULL,
        side TEXT NOT NULL,
        qty REAL NOT NULL,
        price REAL NOT NULL,
        fees REAL NOT NULL DEFAULT 0,
        realized REAL NOT NULL DEFAULT 0,
        fee_txn_id INTEGER,
        pnl_txn_id INTEGER
      )
    ''');
    await db.execute('''
      CREATE TABLE stock_prices (
        symbol TEXT PRIMARY KEY,
        price REAL NOT NULL,
        manual INTEGER NOT NULL DEFAULT 0,
        updated_at INTEGER
      )
    ''');
  }

  static Future<void> _migrateToV10(Database db) async {
    await db.execute('ALTER TABLE transactions ADD COLUMN fee_for INTEGER');
    // Link InstaPay fees saved earlier to the transaction saved just
    // before them (same account, same moment).
    await db.execute('''
      UPDATE transactions SET fee_for = id - 1
      WHERE type = 'expense' AND payee = 'InstaPay' AND fee_for IS NULL
        AND EXISTS (SELECT 1 FROM transactions m
                    WHERE m.id = transactions.id - 1
                      AND m.account_id = transactions.account_id
                      AND m.date = transactions.date
                      AND m.type IN ('expense', 'transfer')
                      AND m.payee <> 'InstaPay')
    ''');
  }

  static Future<void> _migrateToV11(Database db) async {
    for (final col in const [
      'asset_value REAL', 'asset_share REAL', 'asset_value_at INTEGER',
    ]) {
      await db.execute('ALTER TABLE accounts ADD COLUMN $col');
    }
  }

  /// Account details: last digits (to match bank SMS), expiry, bank phone,
  /// customer number, IBAN and notes. The full card number is not here; it
  /// is kept in the phone's secure storage.
  static Future<void> _migrateToV12(Database db) async {
    await db.execute('''
      CREATE TABLE account_details (
        account_id INTEGER PRIMARY KEY REFERENCES accounts(id) ON DELETE CASCADE,
        last4 TEXT NOT NULL DEFAULT '',
        expiry TEXT NOT NULL DEFAULT '',
        phone TEXT NOT NULL DEFAULT '',
        customer_no TEXT NOT NULL DEFAULT '',
        iban TEXT NOT NULL DEFAULT '',
        notes TEXT NOT NULL DEFAULT ''
      )
    ''');
  }

  /// SMS sender name of the bank (e.g. "ADCB Egypt").
  static Future<void> _migrateToV13(Database db) async {
    await db.execute(
        "ALTER TABLE account_details ADD COLUMN sender TEXT NOT NULL DEFAULT ''");
  }

  /// Bank messages waiting to be turned into transactions.
  static Future<void> _migrateToV14(Database db) async {
    await db.execute('''
      CREATE TABLE sms_inbox (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        sender TEXT NOT NULL DEFAULT '',
        body TEXT NOT NULL,
        received_at INTEGER NOT NULL,
        status TEXT NOT NULL DEFAULT 'pending',
        hash TEXT NOT NULL UNIQUE
      )
    ''');
  }

  /// Account number in account details.
  static Future<void> _migrateToV15(Database db) async {
    await db.execute(
        "ALTER TABLE account_details ADD COLUMN account_no TEXT NOT NULL DEFAULT ''");
  }

  /// Payments split across several categories.
  static Future<void> _migrateToV16(Database db) async {
    await db.execute('ALTER TABLE transactions ADD COLUMN split_id INTEGER');
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

  /// Accounts with their balance as of [asOf] (default now) computed in SQL.
  /// Future-dated transactions are not included.
  Future<List<Account>> accountsWithBalances({DateTime? asOf}) async {
    final t = (asOf ?? DateTime.now()).millisecondsSinceEpoch;
    final rows = await db.rawQuery('''
      SELECT a.*,
        a.opening_balance
        + COALESCE((SELECT SUM(amount) FROM transactions
            WHERE account_id = a.id AND type = 'income' AND date <= ?), 0)
        - COALESCE((SELECT SUM(amount) FROM transactions
            WHERE account_id = a.id AND type IN ('expense', 'transfer') AND date <= ?), 0)
        + COALESCE((SELECT SUM(COALESCE(to_amount, amount)) FROM transactions
            WHERE to_account_id = a.id AND type = 'transfer' AND date <= ?), 0)
        AS balance
      FROM accounts a
      ORDER BY a.archived, a.sort_order, a.bank COLLATE NOCASE, a.name COLLATE NOCASE
    ''', [t, t, t]);
    return rows.map(Account.fromMap).toList();
  }

  Future<int> insertAccount(Account a) => db.insert('accounts', a.toMap());

  /// Adds a bank message; false when it was already there.
  Future<bool> insertSms(String sender, String body, DateTime at) async {
    final hash = '${sender.trim().toLowerCase()}|${body.trim()}';
    final seen = await db.query('sms_inbox',
        columns: ['id'], where: 'hash = ?', whereArgs: [hash], limit: 1);
    if (seen.isNotEmpty) return false;
    final id = await db.insert(
        'sms_inbox',
        {
          'sender': sender.trim(),
          'body': body.trim(),
          'received_at': at.millisecondsSinceEpoch,
          'status': 'pending',
          'hash': hash,
        },
        conflictAlgorithm: ConflictAlgorithm.ignore);
    return id > 0;
  }

  Future<List<SmsItem>> pendingSms() async {
    // Old handled ones are no longer needed to spot duplicates.
    final cutoff = DateTime.now()
        .subtract(const Duration(days: 120))
        .millisecondsSinceEpoch;
    await db.delete('sms_inbox',
        where: "status != 'pending' AND received_at < ?", whereArgs: [cutoff]);
    final rows = await db.query('sms_inbox',
        where: "status = 'pending'", orderBy: 'received_at DESC');
    return rows.map(SmsItem.fromMap).toList();
  }

  /// Dismissed messages, newest first (kept 120 days).
  Future<List<SmsItem>> dismissedSms() async {
    final rows = await db.query('sms_inbox',
        where: "status = 'dismissed'", orderBy: 'received_at DESC', limit: 300);
    return rows.map(SmsItem.fromMap).toList();
  }

  Future<void> setSmsStatus(int id, String status) => db.update(
      'sms_inbox', {'status': status},
      where: 'id = ?', whereArgs: [id]);

  /// Units of [to] per 1 [from] in the latest transfer between the two
  /// currencies (a transfer the other way is turned around).
  Future<double?> lastTransferRate(String from, String to, {int? exceptId}) async {
    final rows = await db.rawQuery('''
      SELECT t.amount AS amount, t.to_amount AS to_amount, a.currency AS fc
      FROM transactions t
      JOIN accounts a ON a.id = t.account_id
      JOIN accounts b ON b.id = t.to_account_id
      WHERE t.type = 'transfer' AND t.to_amount IS NOT NULL
        AND t.amount != 0 AND t.to_amount != 0 AND t.id != ?
        AND ((a.currency = ? AND b.currency = ?) OR (a.currency = ? AND b.currency = ?))
      ORDER BY t.date DESC, t.id DESC LIMIT 1
    ''', [exceptId ?? -1, from, to, to, from]);
    if (rows.isEmpty) return null;
    final amount = (rows.first['amount'] as num).toDouble().abs();
    final received = (rows.first['to_amount'] as num).toDouble().abs();
    final r = received / amount;
    return rows.first['fc'] == from ? r : 1 / r;
  }

  /// Category last used with this payee, to suggest it again.
  Future<int?> lastCategoryForPayee(String payee, TxType type) async {
    if (payee.trim().isEmpty) return null;
    final rows = await db.query('transactions',
        columns: ['category_id'],
        where: 'LOWER(payee) = ? AND type = ? AND category_id IS NOT NULL',
        whereArgs: [payee.trim().toLowerCase(), type.name],
        orderBy: 'date DESC',
        limit: 1);
    return rows.isEmpty ? null : rows.first['category_id'] as int?;
  }

  Future<Map<int, AccountDetails>> accountDetails() async {
    final rows = await db.query('account_details');
    return {
      for (final r in rows)
        r['account_id'] as int: AccountDetails.fromMap(r),
    };
  }

  Future<void> saveAccountDetails(int accountId, AccountDetails d) async {
    if (d.isEmpty) {
      await db.delete('account_details',
          where: 'account_id = ?', whereArgs: [accountId]);
    } else {
      await db.insert('account_details', {'account_id': accountId, ...d.toMap()},
          conflictAlgorithm: ConflictAlgorithm.replace);
    }
  }

  /// Saves a manual order: account id -> position.
  Future<void> setSortOrders(Map<int, int> order) async {
    final batch = db.batch();
    order.forEach((id, pos) => batch.update('accounts', {'sort_order': pos},
        where: 'id = ?', whereArgs: [id]));
    await batch.commit(noResult: true);
  }

  Future<void> updateAccount(Account a) =>
      db.update('accounts', a.toMap(), where: 'id = ?', whereArgs: [a.id]);

  Future<void> deleteAccount(int id) async {
    await db.transaction((tx) async {
      await tx.delete('recurring',
          where: 'account_id = ? OR to_account_id = ?', whereArgs: [id, id]);
      await tx.delete('accounts', where: 'id = ?', whereArgs: [id]);
      // Plans with no remaining installments.
      await tx.execute(
          'DELETE FROM plans WHERE id NOT IN (SELECT DISTINCT plan_id FROM transactions WHERE plan_id IS NOT NULL)');
    });
  }

  /// Balance of one account as of [asOf] (inclusive), counting card
  /// expenses on their posting date (used for statements).
  Future<double> balanceAsOf(int accountId, DateTime asOf) async {
    final t = asOf.millisecondsSinceEpoch;
    final r = await db.rawQuery('''
      SELECT a.opening_balance
        + COALESCE((SELECT SUM(amount) FROM transactions
            WHERE account_id = a.id AND type = 'income'
              AND COALESCE(post_date, date) <= ?), 0)
        - COALESCE((SELECT SUM(amount) FROM transactions
            WHERE account_id = a.id AND type IN ('expense', 'transfer')
              AND COALESCE(post_date, date) <= ?), 0)
        + COALESCE((SELECT SUM(COALESCE(to_amount, amount)) FROM transactions
            WHERE to_account_id = a.id AND type = 'transfer'
              AND COALESCE(to_post_date, date) <= ?), 0)
        AS balance
      FROM accounts a WHERE a.id = ?
    ''', [t, t, t, accountId]);
    if (r.isEmpty) return 0;
    final v = r.first['balance'];
    return v is num ? v.toDouble() : 0;
  }

  /// Money coming into an account (income + incoming transfers) with dates
  /// in (from, to].
  Future<double> creditsBetween(int accountId, DateTime from, DateTime to) async {
    final f = from.millisecondsSinceEpoch;
    final t = to.millisecondsSinceEpoch;
    final r = await db.rawQuery('''
      SELECT
        COALESCE((SELECT SUM(amount) FROM transactions
          WHERE account_id = ? AND type = 'income'
            AND COALESCE(post_date, date) > ? AND COALESCE(post_date, date) <= ?), 0)
        + COALESCE((SELECT SUM(COALESCE(to_amount, amount)) FROM transactions
          WHERE to_account_id = ? AND type = 'transfer'
            AND COALESCE(to_post_date, date) > ? AND COALESCE(to_post_date, date) <= ?), 0)
        AS credits
    ''', [accountId, f, t, accountId, f, t]);
    final v = r.first['credits'];
    return v is num ? v.toDouble() : 0;
  }

  /// Money going out of an account (expenses + outgoing transfers) with
  /// dates in (from, to].
  Future<double> debitsBetween(int accountId, DateTime from, DateTime to) async {
    final r = await db.rawQuery('''
      SELECT COALESCE(SUM(amount), 0) AS debits FROM transactions
      WHERE account_id = ? AND type IN ('expense', 'transfer')
        AND COALESCE(post_date, date) > ? AND COALESCE(post_date, date) <= ?
    ''', [accountId, from.millisecondsSinceEpoch, to.millisecondsSinceEpoch]);
    final v = r.first['debits'];
    return v is num ? v.toDouble() : 0;
  }

  /// Installments on an account dated after [now] (not billed yet).
  Future<double> futureInstallments(int accountId, DateTime now) async {
    final r = await db.rawQuery('''
      SELECT COALESCE(SUM(amount), 0) AS s FROM transactions
      WHERE account_id = ? AND plan_id IS NOT NULL AND type = 'expense' AND date > ?
    ''', [accountId, now.millisecondsSinceEpoch]);
    final v = r.first['s'];
    return v is num ? v.toDouble() : 0;
  }

  /// Everything a card statement is made of: charges and credits whose
  /// posting date on [accountId] is in (from, to], oldest first.
  Future<List<Txn>> statementTxns(int accountId, DateTime from, DateTime to) async {
    final f = from.millisecondsSinceEpoch;
    final t = to.millisecondsSinceEpoch;
    final rows = await db.rawQuery('''
      SELECT *,
        CASE WHEN to_account_id = ? AND type = 'transfer'
             THEN COALESCE(to_post_date, date)
             ELSE COALESCE(post_date, date) END AS eff
      FROM transactions
      WHERE (account_id = ? AND COALESCE(post_date, date) > ? AND COALESCE(post_date, date) <= ?)
         OR (to_account_id = ? AND type = 'transfer'
             AND COALESCE(to_post_date, date) > ? AND COALESCE(to_post_date, date) <= ?)
      ORDER BY eff, id
    ''', [accountId, accountId, f, t, accountId, f, t]);
    return rows.map(Txn.fromMap).toList();
  }

  /// Sets the day [t] counts on card [accountId] (its statement).
  Future<void> setCardPostDate(Txn t, int accountId, DateTime when) async {
    final incoming = t.type == TxType.transfer && t.toAccountId == accountId;
    await db.update(
      'transactions',
      {(incoming ? 'to_post_date' : 'post_date'): when.millisecondsSinceEpoch},
      where: 'id = ?',
      whereArgs: [t.id],
    );
  }

  Future<List<String>> bankNames() async {
    final rows = await db.rawQuery(
        "SELECT DISTINCT bank FROM accounts WHERE bank <> '' ORDER BY bank COLLATE NOCASE");
    return rows.map((r) => r['bank'] as String).toList();
  }

  /// Number of transactions and the latest one's date (for sync choices).
  Future<(int, DateTime?)> stats() async {
    final r = await db.rawQuery('SELECT COUNT(*) AS c, MAX(date) AS mx FROM transactions');
    final mx = r.first['mx'] as int?;
    return (
      (r.first['c'] as int?) ?? 0,
      mx == null ? null : DateTime.fromMillisecondsSinceEpoch(mx)
    );
  }

  Future<int> countAccountTransactions(int id) async {
    final r = await db.rawQuery(
        'SELECT COUNT(*) AS c FROM transactions WHERE account_id = ? OR to_account_id = ?',
        [id, id]);
    return (r.first['c'] as int?) ?? 0;
  }

  // ---------------- Categories ----------------

  Future<List<Category>> categories() async {
    final rows = await db.query('categories',
        orderBy: 'grp COLLATE NOCASE, name COLLATE NOCASE');
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

  /// The fee entry linked to a transaction, if any.
  Future<Txn?> feeOf(int txnId) async {
    final rows = await db.query('transactions',
        where: 'fee_for = ?', whereArgs: [txnId], limit: 1);
    return rows.isEmpty ? null : Txn.fromMap(rows.first);
  }

  /// Sum and count per category (and account currency) for [type] with
  /// dates in [from, to).
  Future<List<Map<String, Object?>>> categoryTotals(
      TxType type, DateTime from, DateTime to) {
    return db.rawQuery('''
      SELECT t.category_id AS cat, a.currency AS cur,
             SUM(t.amount) AS total, COUNT(*) AS n
      FROM transactions t JOIN accounts a ON a.id = t.account_id
      WHERE t.type = ? AND t.date >= ? AND t.date < ?
      GROUP BY t.category_id, a.currency
    ''', [type.name, from.millisecondsSinceEpoch, to.millisecondsSinceEpoch]);
  }

  /// Net change per account per calendar month (local time), up to [until].
  /// Transfers count out of the source and into the destination.
  Future<List<Map<String, Object?>>> monthlyAccountChanges(DateTime until) {
    final t = until.millisecondsSinceEpoch;
    return db.rawQuery('''
      SELECT account_id AS acc,
             strftime('%Y-%m', date / 1000, 'unixepoch', 'localtime') AS ym,
             SUM(CASE type WHEN 'income' THEN amount ELSE -amount END) AS delta
      FROM transactions WHERE date <= ?
      GROUP BY acc, ym
      UNION ALL
      SELECT to_account_id AS acc,
             strftime('%Y-%m', date / 1000, 'unixepoch', 'localtime') AS ym,
             SUM(COALESCE(to_amount, amount)) AS delta
      FROM transactions WHERE type = 'transfer' AND date <= ?
      GROUP BY acc, ym
    ''', [t, t]);
  }

  /// Sum per month (local time) for one category.
  Future<List<Map<String, Object?>>> categoryMonthly(
      int categoryId, DateTime from, DateTime to) {
    return db.rawQuery('''
      SELECT strftime('%Y-%m', t.date / 1000, 'unixepoch', 'localtime') AS ym,
             a.currency AS cur, SUM(t.amount) AS total
      FROM transactions t JOIN accounts a ON a.id = t.account_id
      WHERE t.category_id = ? AND t.date >= ? AND t.date < ?
      GROUP BY ym, a.currency
    ''', [categoryId, from.millisecondsSinceEpoch, to.millisecondsSinceEpoch]);
  }

  /// Date of the first transaction, if any.
  Future<DateTime?> firstTransactionDate() async {
    final r = await db.rawQuery('SELECT MIN(date) AS d FROM transactions');
    final v = r.first['d'];
    return v == null ? null : DateTime.fromMillisecondsSinceEpoch(v as int);
  }

  /// Income and expense sums per calendar month (local time) in [from, to).
  Future<List<Map<String, Object?>>> monthlyTotals(DateTime from, DateTime to) {
    return db.rawQuery('''
      SELECT strftime('%Y-%m', t.date / 1000, 'unixepoch', 'localtime') AS ym,
             t.type AS type, a.currency AS cur, SUM(t.amount) AS total
      FROM transactions t JOIN accounts a ON a.id = t.account_id
      WHERE t.type IN ('income', 'expense') AND t.date >= ? AND t.date < ?
      GROUP BY ym, t.type, a.currency
    ''', [from.millisecondsSinceEpoch, to.millisecondsSinceEpoch]);
  }

  /// Full-text-ish search across all transactions (all accounts, archived
  /// included). Every word in [query] must match somewhere: payee, note,
  /// category, category group, account or bank (either side of a
  /// transfer), or an amount.
  Future<SearchResult> search({
    String query = '',
    TxType? type,
    DateTime? from,
    DateTime? to,
    int? accountId,
    int? categoryId,
    int limit = 500,
  }) async {
    final where = <String>[];
    final args = <Object?>[];
    for (final raw in query.trim().split(RegExp(r'\s+'))) {
      if (raw.isEmpty) continue;
      final like = '%$raw%';
      final parts = <String>[
        't.payee LIKE ?', 't.note LIKE ?', 'c.name LIKE ?', 'c.grp LIKE ?',
        'a.name LIKE ?', 'a.bank LIKE ?', 'b.name LIKE ?', 'b.bank LIKE ?',
      ];
      args.addAll(List.filled(parts.length, like));
      final n = double.tryParse(raw.replaceAll(',', ''));
      if (n != null) {
        if (raw.contains('.')) {
          parts.add('ABS(ABS(t.amount) - ?) < 0.005');
          parts.add('ABS(ABS(COALESCE(t.to_amount, -1)) - ?) < 0.005');
          args.addAll([n, n]);
        } else {
          parts.add('CAST(ABS(t.amount) AS INTEGER) = ?');
          parts.add('CAST(ABS(COALESCE(t.to_amount, -1)) AS INTEGER) = ?');
          args.addAll([n.toInt(), n.toInt()]);
        }
      }
      where.add('(${parts.join(' OR ')})');
    }
    if (type != null) {
      where.add('t.type = ?');
      args.add(type.name);
    }
    if (from != null) {
      where.add('t.date >= ?');
      args.add(from.millisecondsSinceEpoch);
    }
    if (to != null) {
      where.add('t.date < ?');
      args.add(to.millisecondsSinceEpoch);
    }
    if (accountId != null) {
      where.add('(t.account_id = ? OR t.to_account_id = ?)');
      args.addAll([accountId, accountId]);
    }
    if (categoryId != null) {
      where.add('t.category_id = ?');
      args.add(categoryId);
    }
    final w = where.isEmpty ? '' : 'WHERE ${where.join(' AND ')}';
    const from_ = '''
      FROM transactions t
      LEFT JOIN accounts a ON a.id = t.account_id
      LEFT JOIN accounts b ON b.id = t.to_account_id
      LEFT JOIN categories c ON c.id = t.category_id''';
    final rows = await db.rawQuery(
        'SELECT t.* $from_ $w ORDER BY t.date DESC, t.id DESC LIMIT $limit',
        args);
    final sums = await db.rawQuery(
        'SELECT t.type AS type, a.currency AS currency, COUNT(*) AS n, '
        'SUM(t.amount) AS total $from_ $w GROUP BY t.type, a.currency',
        args);
    var count = 0;
    final totals = <String, Map<String, double>>{};
    for (final r in sums) {
      count += r['n'] as int;
      final t = r['type'] as String;
      final cur = (r['currency'] as String?) ?? 'EGP';
      final v = (r['total'] as num?)?.toDouble() ?? 0;
      totals.putIfAbsent(t, () => {})[cur] = v;
    }
    return SearchResult(
        txns: rows.map(Txn.fromMap).toList(), count: count, totals: totals);
  }

  Future<void> updateTxn(Txn t) =>
      db.update('transactions', t.toMap(), where: 'id = ?', whereArgs: [t.id]);

  Future<void> deleteTxn(int id) async {
    await db.delete('transactions',
        where: 'id = ? OR fee_for = ?', whereArgs: [id, id]);
    await db.execute(
        'DELETE FROM plans WHERE id NOT IN (SELECT DISTINCT plan_id FROM transactions WHERE plan_id IS NOT NULL)');
  }

  // ---------------- Installment plans ----------------

  Future<InstallmentPlan?> plan(int id) async {
    final rows =
        await db.query('plans', where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : InstallmentPlan.fromMap(rows.first);
  }

  Future<List<Txn>> planTxns(int planId) async {
    final rows = await db.query('transactions',
        where: 'plan_id = ?', whereArgs: [planId], orderBy: 'plan_index');
    return rows.map(Txn.fromMap).toList();
  }

  /// Creates (or replaces, when [plan.id] is set) a plan and its monthly
  /// installments. [template] supplies account, category, payee, note.
  Future<void> savePlan(InstallmentPlan plan, Txn template) async {
    await db.transaction((tx) async {
      int planId;
      if (plan.id == null) {
        planId = await tx.insert('plans', plan.toMap());
      } else {
        planId = plan.id!;
        await tx.update('plans', plan.toMap(),
            where: 'id = ?', whereArgs: [planId]);
        await tx.delete('transactions',
            where: 'plan_id = ?', whereArgs: [planId]);
      }
      final parts = InstallmentPlan.split(plan.total, plan.months);
      for (var i = 0; i < plan.months; i++) {
        final t = Txn(
          type: TxType.expense,
          date: addMonths(plan.firstDate, i),
          amount: parts[i],
          accountId: template.accountId,
          categoryId: template.categoryId,
          payee: template.payee,
          note: template.note,
          planId: planId,
          planIndex: i + 1,
        );
        await tx.insert('transactions', t.toMap());
      }
    });
  }

  Future<void> deletePlan(int planId) async {
    await db.transaction((tx) async {
      await tx.delete('transactions', where: 'plan_id = ?', whereArgs: [planId]);
      await tx.delete('plans', where: 'id = ?', whereArgs: [planId]);
    });
  }

  Future<Map<int, InstallmentPlan>> allPlans() async {
    final rows = await db.query('plans');
    return {
      for (final r in rows)
        r['id'] as int: InstallmentPlan.fromMap(r),
    };
  }

  // ---------------- Recurring ----------------

  Future<List<RecurringRule>> recurringRules() async {
    final rows = await db.query('recurring', orderBy: 'id');
    return rows.map(RecurringRule.fromMap).toList();
  }

  Future<int> insertRule(RecurringRule r) => db.insert('recurring', r.toMap());

  Future<void> updateRule(RecurringRule r) =>
      db.update('recurring', r.toMap(), where: 'id = ?', whereArgs: [r.id]);

  Future<void> deleteRule(int id) =>
      db.delete('recurring', where: 'id = ?', whereArgs: [id]);

  // ---------------- Budgets ----------------

  Future<List<Budget>> budgets() async {
    final rows = await db.query('budgets', orderBy: 'sort_order, id');
    return rows.map(Budget.fromMap).toList();
  }

  Future<int> insertBudget(Budget b) => db.insert('budgets', b.toMap());

  Future<void> updateBudget(Budget b) =>
      db.update('budgets', b.toMap(), where: 'id = ?', whereArgs: [b.id]);

  Future<void> deleteBudget(int id) =>
      db.delete('budgets', where: 'id = ?', whereArgs: [id]);

  /// Expense sums per month (local time), category and account currency
  /// with dates in [from, to).
  Future<List<Map<String, Object?>>> expensesByMonthCategory(
      DateTime from, DateTime to) {
    return db.rawQuery('''
      SELECT strftime('%Y-%m', t.date / 1000, 'unixepoch', 'localtime') AS ym,
             t.category_id AS cat, a.currency AS cur, SUM(t.amount) AS total
      FROM transactions t JOIN accounts a ON a.id = t.account_id
      WHERE t.type = 'expense' AND t.date >= ? AND t.date < ?
      GROUP BY ym, t.category_id, a.currency
    ''', [from.millisecondsSinceEpoch, to.millisecondsSinceEpoch]);
  }

  /// Sum and count per payee (and currency) for [type] in [from, to).
  /// Transactions without a payee are left out.
  Future<List<Map<String, Object?>>> payeeTotals(
      TxType type, DateTime from, DateTime to) {
    return db.rawQuery('''
      SELECT TRIM(t.payee) AS payee, a.currency AS cur,
             SUM(t.amount) AS total, COUNT(*) AS n
      FROM transactions t JOIN accounts a ON a.id = t.account_id
      WHERE t.type = ? AND TRIM(t.payee) <> '' AND t.date >= ? AND t.date < ?
      GROUP BY TRIM(t.payee) COLLATE NOCASE, a.currency
    ''', [type.name, from.millisecondsSinceEpoch, to.millisecondsSinceEpoch]);
  }

  // ---------------- Stocks ----------------

  Future<List<Trade>> trades() async {
    final rows = await db.query('trades', orderBy: 'date, id');
    return rows.map(Trade.fromMap).toList();
  }

  Future<int> insertTrade(Trade t) => db.insert('trades', t.toMap());

  Future<void> deleteTrade(Trade t) async {
    await db.transaction((tx) async {
      for (final id in [t.feeTxnId, t.pnlTxnId]) {
        if (id != null) await tx.delete('transactions', where: 'id = ?', whereArgs: [id]);
      }
      await tx.delete('trades', where: 'id = ?', whereArgs: [t.id]);
    });
  }

  Future<List<StockPrice>> stockPrices() async {
    final rows = await db.query('stock_prices');
    return rows.map(StockPrice.fromMap).toList();
  }

  Future<void> upsertStockPrice(StockPrice p) => db.insert(
      'stock_prices', p.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace);

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
