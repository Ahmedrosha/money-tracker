import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';

import '../data/db.dart';
import '../data/models.dart';
import '../services/dropbox.dart';
import '../services/notifications.dart';
import '../util/format.dart';
import '../services/rates.dart';

class AppState extends ChangeNotifier {
  AppState(this.db) {
    dropbox = DropboxSync(() async {
      final dir = await getTemporaryDirectory();
      final path = '${dir.path}/dropbox-upload.db';
      await db.backupTo(path);
      return path;
    });
  }

  late final DropboxSync dropbox;
  final Notifier notifier = Notifier();
  NotifSettings notifSettings = NotifSettings();
  bool _loaded = false;

  AppDb db;
  final RateService _rateService = RateService();

  List<Account> accounts = [];
  List<Category> categories = [];
  Map<String, CurrencyRate> rates = {};
  List<RecurringRule> rules = [];
  Map<int, InstallmentPlan> plans = {};
  List<Budget> budgets = [];
  List<String> bankNames = [];
  String baseCurrency = 'EGP';

  /// Accounts screen grouping: 'type' or 'bank'.
  String accountsGroupBy = 'type';

  /// Transactions screen order: 'date' or 'category'.
  String txnSort = 'date';

  /// Order of groups in the "by type" view: value / count / name, each
  /// with a direction, e.g. 'value_desc'.
  String groupOrder = 'value_desc';

  /// First day of week for the calendar (DateTime.saturday etc.).
  int weekStart = DateTime.saturday;

  /// Net worth expected at the end of this month, including future-dated
  /// transactions and pending recurring items.
  double projectedEom = 0;

  /// Card payment banners hidden until the app is closed (not saved).
  final Set<int> dismissedCards = {};

  void dismissCard(int id) {
    dismissedCards.add(id);
    notifyListeners();
  }

  /// Credit card summaries keyed by account id.
  Map<int, CardSummary> cards = {};

  /// Bumped on every data change so screens that query the DB reload.
  int version = 0;

  bool refreshingRates = false;

  /// Amounts shown as dots (remembered between sessions).
  bool get hideAmounts => amountsHidden;

  Future<void> setHideAmounts(bool v) async {
    amountsHidden = v;
    await db.setSetting('hide_amounts', v ? '1' : '0');
    version++;
    notifyListeners();
  }

  /// Ask for Face ID / fingerprint / passcode when opening the app.
  bool lockEnabled = false;

  Future<void> setLockEnabled(bool v) async {
    lockEnabled = v;
    await db.setSetting('lock_enabled', v ? '1' : '0');
    notifyListeners();
  }

  Future<void> load() async {
    baseCurrency = await db.getSetting('base_currency') ?? 'EGP';
    accountsGroupBy = await db.getSetting('accounts_group_by') ?? 'type';
    txnSort = await db.getSetting('txn_sort') ?? 'date';
    groupOrder = await db.getSetting('group_order') ?? 'value_desc';
    weekStart = int.tryParse(await db.getSetting('week_start') ?? '') ??
        DateTime.saturday;
    amountsHidden = await db.getSetting('hide_amounts') == '1';
    lockEnabled = await db.getSetting('lock_enabled') == '1';
    final lb = int.tryParse(await db.getSetting('last_backup') ?? '');
    lastBackup = lb == null ? null : DateTime.fromMillisecondsSinceEpoch(lb);
    await dropbox.init();
    notifSettings = await NotifSettings.load(db);
    await _reloadAll();
    _loaded = true;
  }

  Future<void> _reloadAll() async {
    accounts = await db.accountsWithBalances();
    categories = await db.categories();
    rates = {for (final r in await db.rates()) r.code: r};
    rules = await db.recurringRules();
    plans = await db.allPlans();
    budgets = await db.budgets();
    bankNames = await db.bankNames();
    await _computeProjection();
    await _computeCards();
    version++;
    notifyListeners();
    // Any data change after start-up is sent to Dropbox (debounced).
    if (_loaded) {
      dropbox.scheduleUpload();
      _checkBudgetAlerts();
    }
    rescheduleReminders();
  }

  // ---------------- Budgets ----------------

  String budgetName(Budget b) {
    switch (b.scope) {
      case BudgetScope.total:
        return 'All spending';
      case BudgetScope.group:
        return b.target;
      case BudgetScope.category:
        final c = categoryById(b.categoryId);
        if (c == null) return 'Deleted category';
        return c.group.isEmpty ? c.name : '${c.group} › ${c.name}';
    }
  }

  bool _budgetCovers(Budget b, int? catId) {
    switch (b.scope) {
      case BudgetScope.total:
        return true;
      case BudgetScope.group:
        return categoryById(catId)?.group == b.target;
      case BudgetScope.category:
        return catId != null && catId == b.categoryId;
    }
  }

  static String _ymKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}';

  /// Where every budget stands in [month]. With rollover, what was left
  /// (or overspent) in each earlier month since the budget started is
  /// carried forward.
  Future<List<BudgetStatus>> budgetStatus(DateTime month) =>
      _budgetStatus(budgets, month);

  /// Status of a single (possibly unsaved) budget.
  Future<BudgetStatus> budgetStatusFor(Budget b, DateTime month) async =>
      (await _budgetStatus([b], month)).first;

  Future<List<BudgetStatus>> _budgetStatus(
      List<Budget> budgets, DateTime month) async {
    if (budgets.isEmpty) return const [];
    final m = DateTime(month.year, month.month);
    var from = m;
    for (final b in budgets) {
      if (b.rollover && b.start.isBefore(from)) from = b.start;
    }
    final rows =
        await db.expensesByMonthCategory(from, DateTime(m.year, m.month + 1));
    // month -> category -> spent in main currency
    final spent = <String, Map<int?, double>>{};
    for (final r in rows) {
      final byCat = spent.putIfAbsent(r['ym'] as String, () => {});
      final cat = r['cat'] as int?;
      byCat[cat] = (byCat[cat] ?? 0) +
          toBase((r['total'] as num).toDouble(),
              (r['cur'] as String?) ?? baseCurrency);
    }
    double spentIn(Budget b, DateTime d) {
      var sum = 0.0;
      (spent[_ymKey(d)] ?? const {}).forEach((cat, v) {
        if (_budgetCovers(b, cat)) sum += v;
      });
      return sum;
    }

    final out = <BudgetStatus>[];
    for (final b in budgets) {
      var carried = 0.0;
      if (b.rollover) {
        var d = DateTime(b.start.year, b.start.month);
        while (d.isBefore(m)) {
          carried += b.amount - spentIn(b, d);
          d = DateTime(d.year, d.month + 1);
        }
      }
      out.add(BudgetStatus(
        budget: b,
        name: budgetName(b),
        limit: b.amount + carried,
        carried: carried,
        spent: spentIn(b, m),
      ));
    }
    return out;
  }

  Future<void> saveBudget(Budget b) async {
    if (b.id == null) {
      await db.insertBudget(b);
    } else {
      await db.updateBudget(b);
    }
    await _reloadAll();
  }

  Future<void> deleteBudget(int id) async {
    await db.deleteBudget(id);
    await _reloadAll();
  }

  /// Notifies once per month when a budget passes 80% and again when it
  /// is exceeded.
  Future<void> _checkBudgetAlerts() async {
    final s = notifSettings;
    if (!s.enabled || !s.budgets || budgets.isEmpty) return;
    try {
      final now = DateTime.now();
      final ym = _ymKey(now);
      for (final st in await budgetStatus(now)) {
        final id = st.budget.id;
        if (id == null) continue;
        final level = st.over ? 100 : (st.fraction >= 0.8 ? 80 : 0);
        final key = 'budget_alert_$id';
        final saved = (await db.getSetting(key) ?? '').split(':');
        final prev = saved.length == 2 && saved[0] == ym
            ? int.tryParse(saved[1]) ?? 0
            : 0;
        if (level <= prev) continue;
        await db.setSetting(key, '$ym:$level');
        final pct = (st.fraction * 100).toStringAsFixed(0);
        await notifier.showBudgetAlert(
          id,
          level == 100
              ? '🚨 ${st.name} budget exceeded'
              : '⚠️ ${st.name} budget at $pct%',
          level == 100
              ? 'Spent ${fmtMoneyRaw(st.spent, baseCurrency)} of ${fmtAmountRaw(st.limit)} — ${fmtAmountRaw(-st.left)} over'
              : 'Spent ${fmtMoneyRaw(st.spent, baseCurrency)} of ${fmtAmountRaw(st.limit)} — ${fmtAmountRaw(st.left)} left this month',
        );
      }
    } catch (_) {}
  }

  // ---------------- Credit cards ----------------

  Future<void> _computeCards() async {
    final now = DateTime.now();
    final out = <int, CardSummary>{};
    for (final a in accounts) {
      if (!a.isCard) continue;
      final owed = -a.balance;
      final future = await db.futureInstallments(a.id!, now);
      CardStatement? last;
      DateTime? nextClose;
      var cycleSpent = 0.0;
      if (a.hasCycle) {
        final close = lastCloseBefore(now, a.statementDay!);
        nextClose = cycleCloseIn(close.year, close.month + 1, a.statementDay!);
        last = await _statement(a, close, now);
        // Everything posting in the open cycle, incl. pending and
        // installments already scheduled for it.
        cycleSpent = await db.debitsBetween(a.id!, close, nextClose);
      }
      out[a.id!] = CardSummary(
        card: a,
        last: last,
        nextClose: nextClose,
        owedNow: owed > 0 ? owed : 0,
        futureInstallments: future,
        cycleSpent: cycleSpent,
      );
    }
    cards = out;
  }

  Future<CardStatement> _statement(
      Account a, DateTime close, DateTime paidUntil) async {
    final bal = await db.balanceAsOf(a.id!, close);
    final paid = await db.creditsBetween(a.id!, close, paidUntil);
    return CardStatement(
      closeDate: close,
      dueDate: dueDateAfter(close, a.dueDay!),
      amount: bal < 0 ? -bal : 0,
      paid: paid,
      minPct: a.minPayPct ?? 5,
    );
  }

  /// Past statements of a card, newest first. Payments for each are those
  /// made before the following statement closed.
  Future<List<CardStatement>> statementHistory(Account a,
      {int count = 12}) async {
    if (!a.hasCycle) return const [];
    final now = DateTime.now();
    final last = lastCloseBefore(now, a.statementDay!);
    final out = <CardStatement>[];
    for (var i = 0; i < count; i++) {
      final close = cycleCloseIn(last.year, last.month - i, a.statementDay!);
      final next = cycleCloseIn(close.year, close.month + 1, a.statementDay!);
      out.add(await _statement(a, close, next.isAfter(now) ? now : next));
    }
    return out;
  }

  /// Moves [t] onto the statement that ends at [close] of [card] by setting
  /// the day it counts on the card.
  Future<void> moveToStatement(Txn t, Account card, DateTime when) async {
    await db.setCardPostDate(t, card.id!, when);
    await _reloadAll();
  }

  /// Cards whose last statement still has something to pay, soonest first.
  List<CardSummary> get cardsDue {
    final list = cards.values
        .where((c) => !c.card.archived && c.last != null && !c.last!.settled)
        .toList()
      ..sort((a, b) => a.last!.dueDate.compareTo(b.last!.dueDate));
    return list;
  }

  Future<void> _computeProjection() async {
    final now = DateTime.now();
    final eom = DateTime(now.year, now.month + 1, 1);
    final atEom = await db.accountsWithBalances(
        asOf: eom.subtract(const Duration(milliseconds: 1)));
    var sum = 0.0;
    for (final a in atEom) {
      if (a.archived || a.excludeTotal) continue;
      sum += toBase(a.balance, a.currency);
    }
    for (final o in pendingOccurrences(DateTime(1970), eom)) {
      sum += _occurrenceEffect(o);
    }
    projectedEom = sum;
  }

  double _occurrenceEffect(Occurrence o) {
    final r = o.rule;
    final from = accountById(r.accountId);
    if (from == null) return 0;
    switch (r.type) {
      case TxType.income:
        return toBase(r.amount, from.currency);
      case TxType.expense:
        return -toBase(r.amount, from.currency);
      case TxType.transfer:
        final to = accountById(r.toAccountId);
        if (to == null) return 0;
        return toBase(r.toAmount ?? r.amount, to.currency) -
            toBase(r.amount, from.currency);
    }
  }

  // ---------------- Backup & restore ----------------

  DateTime? lastBackup;

  /// Creates a backup file in [dir] and returns its path.
  Future<String> createBackup(String dir) async {
    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    final name =
        'money-tracker-${now.year}-${two(now.month)}-${two(now.day)}_${two(now.hour)}${two(now.minute)}.db';
    final path = '$dir/$name';
    await db.backupTo(path);
    await markBackedUp();
    return path;
  }

  Future<void> markBackedUp() async {
    lastBackup = DateTime.now();
    await db.setSetting('last_backup', '${lastBackup!.millisecondsSinceEpoch}');
    notifyListeners();
  }

  bool get backupOverdue {
    if (accounts.isEmpty) return false;
    final l = lastBackup;
    return l == null || DateTime.now().difference(l).inDays >= 7;
  }

  /// Replaces all data with the backup at [path]. The current data is first
  /// saved to [safetyDir] so the restore can be undone.
  Future<String> restoreFrom(String path, String safetyDir) async {
    final info = await AppDb.inspect(path);
    if (info.version > AppDb.schemaVersion) {
      throw Exception(
          'This backup is from a newer app version. Update the app first.');
    }
    // Don't swap the database while it is being uploaded.
    while (dropbox.busy) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    final safety = '$safetyDir/before-restore-$now.db';
    await db.backupTo(safety);
    await db.close();
    final target = await AppDb.dbPath();
    for (final suffix in ['-wal', '-shm', '-journal']) {
      final f = File('$target$suffix');
      if (await f.exists()) await f.delete();
    }
    await File(path).copy(target);
    db = await AppDb.open();
    await load();
    // The restored data is backed up by definition.
    await markBackedUp();
    return safety;
  }

  // ---------------- Reminders ----------------

  Future<void> saveNotifSettings(NotifSettings s) async {
    notifSettings = s;
    await s.save(db);
    notifyListeners();
    await rescheduleReminders();
  }

  /// Rebuilds all scheduled reminders from the current data.
  Future<void> rescheduleReminders() async {
    final s = notifSettings;
    if (!s.enabled) {
      await notifier.replaceAll(const []);
      return;
    }
    final now = DateTime.now();
    DateTime at(DateTime day, [int daysBefore = 0]) =>
        DateTime(day.year, day.month, day.day - daysBefore, s.hour, s.minute);
    final out = <Reminder>[];

    for (final c in cards.values) {
      final a = c.card;
      if (a.archived || !a.hasCycle) continue;
      final cur = a.currency;
      final last = c.last;
      // Statement already issued and not fully paid.
      if (last != null && !last.settled) {
        for (final d in s.cardDays) {
          out.add(Reminder(
            at(last.dueDate, d),
            '💳 ${a.fullName}',
            '${fmtMoneyRaw(last.remaining, cur)} due ${reminderWhen(d, last.dueDate)}'
                '${last.minimumDue > 0 ? ' · minimum ${fmtAmountRaw(last.minimumDue)}' : ''}',
          ));
        }
      }
      // Next statement (amount is an estimate until it closes).
      final nextClose = c.nextClose;
      if (nextClose != null) {
        final nextDue = dueDateAfter(nextClose, a.dueDay!);
        final est = c.cycleSpent + (last?.remaining ?? 0);
        if (est > 0.004) {
          for (final d in s.cardDays) {
            out.add(Reminder(
              at(nextDue, d),
              '💳 ${a.fullName}',
              'About ${fmtMoneyRaw(est, cur)} due ${reminderWhen(d, nextDue)}',
            ));
          }
          if (s.statementClosed) {
            out.add(Reminder(
              at(nextClose.add(const Duration(days: 1))),
              '🧾 ${a.fullName} statement closed',
              'About ${fmtMoneyRaw(est, cur)}, due ${shortDateFmt.format(nextDue)}',
            ));
          }
        }
      }
    }

    if (s.recurring) {
      for (final o in pendingOccurrences(
          DateTime(now.year, now.month, now.day), now.add(const Duration(days: 60)))) {
        final r = o.rule;
        final acc = accountById(r.accountId);
        final name = r.type == TxType.transfer
            ? 'Transfer to ${accountById(r.toAccountId)?.name ?? '?'}'
            : (r.payee.isNotEmpty
                ? r.payee
                : (categoryById(r.categoryId)?.name ?? r.type.label));
        out.add(Reminder(
          at(o.date),
          '🔁 $name',
          '${fmtMoneyRaw(r.amount, acc?.currency ?? baseCurrency)} is due today — open the app to confirm',
        ));
      }
    }

    if (s.backup && !dropbox.connected && accounts.isNotEmpty) {
      var when = at((lastBackup ?? now).add(const Duration(days: 7)));
      if (!when.isAfter(now)) when = at(now.add(const Duration(days: 1)));
      out.add(Reminder(when, '💾 Time for a backup',
          'Your data is only on this phone. Open Settings → Backup & restore.'));
    }

    await notifier.replaceAll(out);
  }

  // ---------------- Preferences ----------------

  Future<void> setAccountsGroupBy(String v) async {
    accountsGroupBy = v;
    await db.setSetting('accounts_group_by', v);
    notifyListeners();
  }

  Future<void> setGroupOrder(String v) async {
    groupOrder = v;
    await db.setSetting('group_order', v);
    notifyListeners();
  }

  Future<void> setTxnSort(String v) async {
    txnSort = v;
    await db.setSetting('txn_sort', v);
    notifyListeners();
  }

  Future<void> setWeekStart(int v) async {
    weekStart = v;
    await db.setSetting('week_start', '$v');
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

  /// Accounts that count toward net worth.
  List<Account> get countedAccounts =>
      accounts.where((a) => !a.archived && !a.excludeTotal).toList();

  double get netWorth {
    var sum = 0.0;
    for (final a in countedAccounts) {
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

  /// Sets the opening balance so the balance today equals [target].
  Future<void> setCurrentBalance(Account a, double target) async {
    final diff = target - a.balance;
    await db.updateAccount(Account.fromMap({
      ...a.toMap(),
      'opening_balance': a.openingBalance + diff,
    }));
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

  // ---------------- Installments ----------------

  Future<void> savePlan(InstallmentPlan plan, Txn template) async {
    await db.savePlan(plan, template);
    await _reloadAll();
  }

  Future<void> deletePlan(int planId) async {
    await db.deletePlan(planId);
    await _reloadAll();
  }

  // ---------------- Recurring ----------------

  RecurringRule? ruleById(int? id) {
    if (id == null) return null;
    for (final r in rules) {
      if (r.id == id) return r;
    }
    return null;
  }

  /// Unconfirmed occurrences of all rules with dates in [from, to).
  List<Occurrence> pendingOccurrences(DateTime from, DateTime to) {
    final out = <Occurrence>[];
    for (final r in rules) {
      out.addAll(r.occurrencesBetween(from, to));
    }
    out.sort((a, b) => a.date.compareTo(b.date));
    return out;
  }

  /// Only the earliest pending occurrence of a rule can be confirmed or
  /// skipped, so none get lost.
  bool isNextOccurrence(Occurrence o) =>
      ruleById(o.rule.id)?.nextIndex == o.index;

  /// Occurrences whose date has arrived and need confirming.
  List<Occurrence> get dueOccurrences =>
      pendingOccurrences(DateTime(1970), DateTime.now().add(const Duration(seconds: 1)));

  /// Creates a rule. If its first date has already arrived, that first
  /// occurrence is recorded straight away (the user just entered it).
  Future<void> createRule(RecurringRule r) async {
    final id = await db.insertRule(r);
    final saved = RecurringRule.fromMap({...r.toMap(), 'id': id});
    if (!saved.occurrence(0).isAfter(DateTime.now())) {
      await db.insertTxn(saved.toTxn(0));
      await db.updateRule(saved.copyWith(nextIndex: 1));
    }
    await _reloadAll();
  }

  /// Updates rule details; already-confirmed entries are not changed.
  Future<void> updateRule(RecurringRule r) async {
    await db.updateRule(r);
    await _reloadAll();
  }

  Future<void> deleteRule(int id) async {
    await db.deleteRule(id);
    await _reloadAll();
  }

  /// Records occurrence [o] as the transaction [t] (possibly edited by the
  /// user) and moves the rule past it.
  Future<void> confirmOccurrence(Occurrence o, [Txn? t]) async {
    await db.insertTxn(t ?? o.rule.toTxn(o.index));
    await _advance(o);
  }

  Future<void> skipOccurrence(Occurrence o) => _advance(o);

  Future<void> _advance(Occurrence o) async {
    final current = ruleById(o.rule.id);
    if (current == null) return;
    // Occurrences are handled in order; skipping ahead also marks earlier
    // ones as handled.
    final next = o.index + 1;
    if (next > current.nextIndex) {
      await db.updateRule(current.copyWith(nextIndex: next));
    }
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
