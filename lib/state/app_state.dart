import 'package:flutter/widgets.dart';

import '../data/db.dart';
import '../data/models.dart';
import '../services/rates.dart';

class AppState extends ChangeNotifier {
  AppState(this.db);

  final AppDb db;
  final RateService _rateService = RateService();

  List<Account> accounts = [];
  List<Category> categories = [];
  Map<String, CurrencyRate> rates = {};
  String baseCurrency = 'EGP';

  /// Bumped on every data change so screens that query the DB reload.
  int version = 0;

  bool refreshingRates = false;

  Future<void> load() async {
    baseCurrency = await db.getSetting('base_currency') ?? 'EGP';
    await _reloadAll();
  }

  Future<void> _reloadAll() async {
    accounts = await db.accountsWithBalances();
    categories = await db.categories();
    rates = {for (final r in await db.rates()) r.code: r};
    version++;
    notifyListeners();
  }

  // ---------------- Lookups ----------------

  Account? accountById(int? id) {
    if (id == null) return null;
    for (final a in accounts) {
      if (a.id == id) return a;
    }
    return null;
  }

  Category? categoryById(int? id) {
    if (id == null) return null;
    for (final c in categories) {
      if (c.id == id) return c;
    }
    return null;
  }

  List<Account> get activeAccounts =>
      accounts.where((a) => !a.archived).toList();

  List<Category> categoriesOf(TxType kind) =>
      categories.where((c) => c.kind == kind).toList();

  /// Currencies in use by accounts, plus the base currency.
  List<String> get usedCurrencies {
    final set = <String>{baseCurrency};
    for (final a in accounts) {
      set.add(a.currency);
    }
    final list = set.toList()..sort();
    return list;
  }

  // ---------------- Currency ----------------

  /// Converts [amount] from one currency to another. Returns null when a
  /// rate is missing.
  double? convert(double amount, String from, String to) {
    if (from == to) return amount;
    final f = rates[from]?.perUsd;
    final t = rates[to]?.perUsd;
    if (f == null || t == null || f == 0) return null;
    return amount / f * t;
  }

  /// Rate to multiply by to go from [from] to [to].
  double? rate(String from, String to) => convert(1, from, to);

  double toBase(double amount, String from) =>
      convert(amount, from, baseCurrency) ?? 0;

  bool hasRate(String code) => code == baseCurrency
      ? true
      : rates.containsKey(code) && rates.containsKey(baseCurrency);

  double get netWorth {
    var sum = 0.0;
    for (final a in activeAccounts) {
      sum += toBase(a.balance, a.currency);
    }
    return sum;
  }

  List<String> get missingRates => usedCurrencies
      .where((c) => c != 'USD' && !rates.containsKey(c))
      .toList();

  DateTime? get lastRateUpdate {
    DateTime? latest;
    for (final r in rates.values) {
      if (r.manual || r.updatedAt == null) continue;
      if (latest == null || r.updatedAt!.isAfter(latest)) latest = r.updatedAt;
    }
    return latest;
  }

  /// Refreshes rates if they are older than [maxAge]. Errors are swallowed.
  Future<void> autoRefreshRates(
      {Duration maxAge = const Duration(hours: 12)}) async {
    final last = lastRateUpdate;
    if (last != null && DateTime.now().difference(last) < maxAge) return;
    try {
      await refreshRates();
    } catch (_) {
      // Offline is fine; stored rates are used.
    }
  }

  Future<void> refreshRates() async {
    refreshingRates = true;
    notifyListeners();
    try {
      final fetched = await _rateService.fetchPerUsd();
      await db.saveFetchedRates(fetched);
      rates = {for (final r in await db.rates()) r.code: r};
      version++;
    } finally {
      refreshingRates = false;
      notifyListeners();
    }
  }

  /// Sets a manual rate expressed as "1 [code] = [valueInBase] base".
  Future<void> setManualRate(String code, double valueInBase) async {
    if (code == baseCurrency || valueInBase <= 0) return;
    if (code == 'USD') {
      // USD is the pivot (always 1), so "1 USD = X base" is stored as a
      // manual rate on the base currency.
      await db.upsertRate(CurrencyRate(
          code: baseCurrency,
          perUsd: valueInBase,
          manual: true,
          updatedAt: DateTime.now()));
      await _reloadAll();
      return;
    }
    final basePerUsd = baseCurrency == 'USD' ? 1.0 : rates[baseCurrency]?.perUsd;
    if (basePerUsd == null) {
      throw Exception('No rate for $baseCurrency yet. Refresh rates first.');
    }
    // 1 code = valueInBase base, and base-per-USD = basePerUsd
    // => code-per-USD = basePerUsd / valueInBase
    await db.upsertRate(CurrencyRate(
        code: code,
        perUsd: basePerUsd / valueInBase,
        manual: true,
        updatedAt: DateTime.now()));
    await _reloadAll();
  }

  /// Whether the rate shown for [code] (against the base) is manual.
  bool isManual(String code) {
    if (code == 'USD') return rates[baseCurrency]?.manual ?? false;
    return rates[code]?.manual ?? false;
  }

  /// Removes the manual flag and re-fetches the online rate.
  Future<void> clearManualRate(String code) async {
    if (code == 'USD') code = baseCurrency;
    final r = rates[code];
    if (r == null) return;
    await db.upsertRate(CurrencyRate(
        code: r.code, perUsd: r.perUsd, manual: false, updatedAt: null));
    await _reloadAll();
    try {
      await refreshRates();
    } catch (_) {}
  }

  Future<void> setBaseCurrency(String code) async {
    baseCurrency = code;
    await db.setSetting('base_currency', code);
    await _reloadAll();
  }

  // ---------------- Accounts ----------------

  Future<void> saveAccount(Account a) async {
    if (a.id == null) {
      await db.insertAccount(a);
    } else {
      await db.updateAccount(a);
    }
    await _reloadAll();
  }

  Future<void> deleteAccount(int id) async {
    await db.deleteAccount(id);
    await _reloadAll();
  }

  // ---------------- Categories ----------------

  Future<void> saveCategory(Category c) async {
    if (c.id == null) {
      await db.insertCategory(c);
    } else {
      await db.updateCategory(c);
    }
    await _reloadAll();
  }

  Future<void> deleteCategory(int id) async {
    await db.deleteCategory(id);
    await _reloadAll();
  }

  // ---------------- Transactions ----------------

  Future<void> saveTxn(Txn t) async {
    if (t.id == null) {
      await db.insertTxn(t);
    } else {
      await db.updateTxn(t);
    }
    await _reloadAll();
  }

  Future<void> deleteTxn(int id) async {
    await db.deleteTxn(id);
    await _reloadAll();
  }
}

/// Makes [AppState] available to the widget tree and rebuilds dependents
/// when it changes.
class AppScope extends InheritedNotifier<AppState> {
  const AppScope({super.key, required AppState state, required super.child})
      : super(notifier: state);

  static AppState of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope not found');
    return scope!.notifier!;
  }

  /// Access without subscribing to rebuilds (for callbacks).
  static AppState read(BuildContext context) {
    final scope = context.getInheritedWidgetOfExactType<AppScope>();
    return scope!.notifier!;
  }
}
