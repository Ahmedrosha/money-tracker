import '../l10n/l10n.dart';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart' show Intl;
import 'package:path_provider/path_provider.dart';

import '../data/db.dart';
import '../data/models.dart';
import '../services/dropbox.dart';
import '../services/notifications.dart';
import '../util/format.dart';
import '../services/rates.dart';
import '../services/stocks.dart';
import '../services/secure_store.dart';
import '../services/home_widgets.dart';
import '../services/sms_parser.dart';
import '../services/sms_reader.dart';

class AppState extends ChangeNotifier {
  AppState(this.db) {
    dropbox = DropboxSync(() async {
      final dir = await getTemporaryDirectory();
      final path = '${dir.path}/dropbox-upload.db';
      await db.backupTo(path);
      return path;
    }, _replaceFromDropbox);
    dropbox.localIsEmpty = () => accounts.isEmpty;
  }

  late final DropboxSync dropbox;

  /// True while data is being replaced by the Dropbox copy, so that isn't
  /// counted as a change to send back.
  bool _fromDropbox = false;

  Future<void> _replaceFromDropbox(String path) async {
    _fromDropbox = true;
    try {
      // Safety copy goes to temp; dated copies live in Dropbox history.
      final tmp = await getTemporaryDirectory();
      await restoreFrom(path, tmp.path, markBackup: false);
    } finally {
      _fromDropbox = false;
    }
  }

  /// Manual "Restore from Dropbox": replace data and mark it in sync.
  Future<void> restoreFromDropboxFile(String path, String? rev) async {
    await _replaceFromDropbox(path);
    await dropbox.adopt(rev);
  }
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

  /// Order of accounts inside each group: 'manual', 'name' or 'balance'.
  String accountsOrder = 'manual';

  Future<void> setAccountsOrder(String v) async {
    accountsOrder = v;
    await db.setSetting('accounts_order', v);
    notifyListeners();
  }

  /// Saves a dragged order and switches to manual ordering.
  Future<void> saveAccountOrder(List<Account> ordered) async {
    await db.setSortOrders(
        {for (var i = 0; i < ordered.length; i++) ordered[i].id!: i});
    accountsOrder = 'manual';
    await db.setSetting('accounts_order', 'manual');
    await _reloadAll();
  }

  /// Sorts one group's accounts by the chosen order.
  List<Account> orderAccounts(List<Account> list) {
    final out = [...list];
    switch (accountsOrder) {
      case 'name':
        out.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      case 'balance':
        out.sort((a, b) => toBase(b.worth, b.currency)
            .compareTo(toBase(a.worth, a.currency)));
      default:
        // Stable: equal positions keep the list's own order (bank, name).
        final pos = {for (var i = 0; i < list.length; i++) list[i].id: i};
        out.sort((a, b) {
          final c = a.sortOrder.compareTo(b.sortOrder);
          return c != 0 ? c : pos[a.id]!.compareTo(pos[b.id]!);
        });
    }
    return out;
  }

  /// Order of Expenses / Income / Transfers on the Transactions screen.
  List<TxType> sectionOrder = const [TxType.expense, TxType.income, TxType.transfer];

  Future<void> setSectionOrder(List<TxType> order) async {
    sectionOrder = List.unmodifiable(order);
    await db.setSetting('section_order', order.map((t) => t.name).join(','));
    notifyListeners();
  }

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
    HomeWidgets.schedule(this);
  }

  /// 'system' (follow the phone), 'en' or 'ar'.
  String language = 'system';

  /// Changes when the shown language changes (the app rebuilds).
  final ValueNotifier<String> languageNotifier = ValueNotifier('en');

  void _applyLanguage() {
    final code = language == 'system'
        ? WidgetsBinding.instance.platformDispatcher.locale.languageCode
        : language;
    appLang = code == 'ar' ? 'ar' : 'en';
    Intl.defaultLocale = appLang;
    languageNotifier.value = appLang;
  }

  /// Called when the phone's language changes.
  void onSystemLocaleChanged() {
    if (language == 'system') {
      _applyLanguage();
      version++;
      notifyListeners();
    }
  }

  Future<void> setLanguage(String v) async {
    language = v;
    await db.setSetting('language', v);
    _applyLanguage();
    version++;
    notifyListeners();
    // Reminder texts are written when scheduled.
    await rescheduleReminders();
    HomeWidgets.schedule(this);
  }

  /// Collapsed list sections, e.g. 'acc:Bank' (remembered).
  Set<String> collapsed = {};

  bool isCollapsed(String key) => collapsed.contains(key);

  Future<void> toggleCollapsed(String key) async {
    if (!collapsed.remove(key)) collapsed.add(key);
    notifyListeners();
    await db.setSetting('collapsed', collapsed.join('\n'));
  }

  /// Ask for Face ID / fingerprint / passcode when opening the app.
  bool lockEnabled = false;

  Future<void> setLockEnabled(bool v) async {
    lockEnabled = v;
    await db.setSetting('lock_enabled', v ? '1' : '0');
    notifyListeners();
  }

  Future<void> load() async {
    language = await db.getSetting('language') ?? 'system';
    _applyLanguage();
    baseCurrency = await db.getSetting('base_currency') ?? 'EGP';
    accountsGroupBy = await db.getSetting('accounts_group_by') ?? 'type';
    txnSort = await db.getSetting('txn_sort') ?? 'date';
    accountsOrder = await db.getSetting('accounts_order') ?? 'manual';
    final so = (await db.getSetting('section_order') ?? '')
        .split(',')
        .map((n) => TxType.values.where((t) => t.name == n).firstOrNull)
        .whereType<TxType>()
        .toList();
    sectionOrder = so.length == 3
        ? List.unmodifiable(so)
        : const [TxType.expense, TxType.income, TxType.transfer];
    groupOrder = await db.getSetting('group_order') ?? 'value_desc';
    weekStart = int.tryParse(await db.getSetting('week_start') ?? '') ??
        DateTime.saturday;
    amountsHidden = await db.getSetting('hide_amounts') == '1';
    lockEnabled = await db.getSetting('lock_enabled') == '1';
    smsAuto = await db.getSetting('sms_auto') == '1';
    try {
      final o = await db.getSetting('online_rates');
      onlineRates = o == null
          ? {}
          : (jsonDecode(o) as Map<String, dynamic>)
              .map((k, v) => MapEntry(k, (v as num).toDouble()));
    } catch (_) {
      onlineRates = {};
    }
    collapsed = (await db.getSetting('collapsed') ?? '')
        .split('\n')
        .where((s) => s.isNotEmpty)
        .toSet();
    final lb = int.tryParse(await db.getSetting('last_backup') ?? '');
    lastBackup = lb == null ? null : DateTime.fromMillisecondsSinceEpoch(lb);
    await dropbox.init();
    notifSettings = await NotifSettings.load(db);
    await _reloadAll();
    final setupDone = await db.getSetting('setup_done');
    if (setupDone == null && accounts.isNotEmpty) {
      // Existing data (an update, or a restore): no welcome screens.
      await db.setSetting('setup_done', '1');
    }
    needsSetup = setupDone == null && accounts.isEmpty;
    _sampleAccounts = _idList(await db.getSetting('sample_accounts'));
    _sampleBudgets = _idList(await db.getSetting('sample_budgets'));
    _loaded = true;
  }

  Future<void> _reloadAll() async {
    accounts = await db.accountsWithBalances();
    trades = await db.trades();
    stockPrices = {for (final p in await db.stockPrices()) p.symbol: p};
    _applyMarketValues();
    categories = await db.categories();
    rates = {for (final r in await db.rates()) r.code: r};
    rules = await db.recurringRules();
    plans = await db.allPlans();
    budgets = await db.budgets();
    accountDetails = await db.accountDetails();
    smsPending = await db.pendingSms();
    smsDismissed = await db.dismissedSms();
    bankNames = await db.bankNames();
    await _computeProjection();
    await _computeCards();
    version++;
    notifyListeners();
    // Any data change after start-up is sent to Dropbox (debounced).
    if (_loaded && !_fromDropbox) {
      dropbox.scheduleUpload();
      _checkBudgetAlerts();
    }
    rescheduleReminders();
    HomeWidgets.schedule(this);
  }

  // ---------------- Budgets ----------------

  String budgetName(Budget b) {
    switch (b.scope) {
      case BudgetScope.total:
        return tr('All Spending');
      case BudgetScope.group:
        return b.target;
      case BudgetScope.category:
        final c = categoryById(b.categoryId);
        if (c == null) return tr('Deleted category');
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

  // ---------------- Bank messages (SMS) ----------------

  /// Messages waiting to be added as transactions.
  List<SmsItem> smsPending = [];

  /// Dismissed messages (the Archive group in Bank Messages).
  List<SmsItem> smsDismissed = [];

  /// Android: read bank SMS automatically when the app opens.
  bool smsAuto = false;

  static String _normSender(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9؀-ۿ]'), '');

  /// Sender names entered in account details.
  Set<String> get smsSenders => {
        for (final d in accountDetails.values)
          if (d.sender.trim().isNotEmpty) _normSender(d.sender)
      };

  /// Adds a bank message to the list. Returns false when it is not a
  /// transaction (OTP, declined…) or was already added.
  Future<bool> addSms(String sender, String body, {DateTime? at}) async {
    final when = at ?? DateTime.now();
    if (!SmsParser.parse(body, received: when).usable) return false;
    final added = await db.insertSms(sender, body, when);
    if (added) await _reloadAll();
    return added;
  }

  Future<void> setSmsStatus(int id, String status) async {
    await db.setSmsStatus(id, status);
    await _reloadAll();
  }

  Future<void> setSmsAuto(bool v) async {
    smsAuto = v;
    await db.setSetting('sms_auto', v ? '1' : '0');
    if (v && await db.getSetting('sms_since') == null) {
      // First time: look back two weeks.
      final from = DateTime.now().subtract(const Duration(days: 14));
      await db.setSetting('sms_since', '${from.millisecondsSinceEpoch}');
    }
    notifyListeners();
    if (v) await readAndroidSms();
  }

  bool _readingSms = false;

  /// Android: picks up new SMS from the senders set in account details.
  Future<int> readAndroidSms() async {
    if (!Platform.isAndroid || !smsAuto || _readingSms) return 0;
    final senders = smsSenders;
    if (senders.isEmpty || !await SmsReader.granted()) return 0;
    _readingSms = true;
    var added = 0;
    try {
      final sinceMs = int.tryParse(await db.getSetting('sms_since') ?? '') ??
          DateTime.now()
              .subtract(const Duration(days: 14))
              .millisecondsSinceEpoch;
      var latest = sinceMs;
      for (final (sender, body, at) in await SmsReader.inbox(
          DateTime.fromMillisecondsSinceEpoch(sinceMs))) {
        if (at.millisecondsSinceEpoch > latest) {
          latest = at.millisecondsSinceEpoch;
        }
        if (!senders.contains(_normSender(sender))) continue;
        if (!SmsParser.parse(body, received: at).usable) continue;
        if (await db.insertSms(sender, body, at)) added++;
      }
      await db.setSetting('sms_since', '$latest');
    } finally {
      _readingSms = false;
    }
    if (added > 0) await _reloadAll();
    return added;
  }

  /// iPhone: messages left by the "Add Bank Message" Shortcuts action.
  Future<int> readIncomingSmsFile() async {
    if (!Platform.isIOS) return 0;
    var added = 0;
    try {
      final docs = await getApplicationDocumentsDirectory();
      final f = File('${docs.path}/incoming_sms.jsonl');
      if (!await f.exists()) return 0;
      final lines = await f.readAsLines();
      await f.delete();
      for (final l in lines) {
        if (l.trim().isEmpty) continue;
        try {
          final m = jsonDecode(l) as Map<String, dynamic>;
          final text = (m['text'] as String?) ?? '';
          final at = m['at'] is num
              ? DateTime.fromMillisecondsSinceEpoch((m['at'] as num).toInt())
              : DateTime.now();
          if (text.trim().isEmpty) continue;
          if (!SmsParser.parse(text, received: at).usable) continue;
          if (await db.insertSms((m['from'] as String?) ?? '', text, at)) added++;
        } catch (_) {}
      }
    } catch (_) {}
    if (added > 0) await _reloadAll();
    return added;
  }

  /// The account a message belongs to: by its last digits (among accounts
  /// with that sender, when known), else the only account with that sender.
  int? smsAccountFor(ParsedSms p, String sender) {
    final ns = _normSender(sender);
    final active = accounts.where((a) => !a.archived).toList();
    final bySender = ns.isEmpty
        ? <Account>[]
        : active
            .where((a) => _normSender(detailsOf(a.id).sender) == ns)
            .toList();
    if (p.last4.isNotEmpty) {
      final pool = bySender.isNotEmpty ? bySender : active;
      final hits = pool
          .where((a) => detailsOf(a.id)
              .digits
              .any((d) => d.endsWith(p.last4) || p.last4.endsWith(d)))
          .toList();
      if (hits.isNotEmpty) return hits.first.id;
    }
    if (bySender.length == 1) return bySender.first.id;
    return null;
  }

  Future<int?> suggestCategory(String payee, TxType type) =>
      db.lastCategoryForPayee(payee, type);

  // ---------------- Reset ----------------

  /// Deletes data on this phone. [everything]: like a fresh install
  /// (welcome screens again); otherwise accounts, transactions, budgets and
  /// portfolios go but categories and settings stay. Dropbox is
  /// disconnected first so the Dropbox copy and the other phone are left
  /// alone. A copy of the current data is kept in [safetyDir] so
  /// Backup & restore → Undo can bring it back.
  Future<void> resetData({required bool everything, required String safetyDir}) async {
    while (dropbox.busy) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    if (dropbox.connected) await dropbox.disconnect();
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.backupTo('$safetyDir/before-restore-$now.db');
    if (everything) {
      await db.close();
      final target = await AppDb.dbPath();
      for (final suffix in ['', '-wal', '-shm', '-journal']) {
        final f = File('$target$suffix');
        if (await f.exists()) await f.delete();
      }
      db = await AppDb.open();
      await SecureStore.clearAll();
      setupStep = 0;
      await load();
    } else {
      await db.db.transaction((tx) async {
        for (final t in [
          'trades',
          'stock_prices',
          'budgets',
          'recurring',
          'transactions',
          'plans',
          'accounts',
          'sms_inbox',
        ]) {
          await tx.delete(t);
        }
        await tx.delete('settings',
            where: "key IN ('sample_accounts', 'sample_budgets', 'last_backup', 'collapsed') OR key LIKE 'budget_alert_%'");
      });
      await SecureStore.clearAll();
      _sampleAccounts = [];
      _sampleBudgets = [];
      lastBackup = null;
      collapsed = {};
      await _reloadAll();
    }
    version++;
    notifyListeners();
    await rescheduleReminders();
  }

  // ---------------- First launch ----------------

  /// A new install with nothing in it yet: show the welcome screens.
  bool needsSetup = false;

  /// Which welcome screen is showing (kept here so a language change,
  /// which rebuilds the app, stays on the same step).
  int setupStep = 0;

  void setSetupStep(int step) {
    setupStep = step;
    notifyListeners();
  }

  Future<void> completeSetup() async {
    await localizeDefaultCategories();
    await db.setSetting('setup_done', '1');
    needsSetup = false;
    notifyListeners();
  }

  static List<int> _idList(String? s) => (s ?? '')
      .split(',')
      .map(int.tryParse)
      .whereType<int>()
      .toList();

  List<int> _sampleAccounts = [];
  List<int> _sampleBudgets = [];

  bool get hasSampleData =>
      _sampleAccounts.any((id) => accounts.any((a) => a.id == id));

  /// Renames the starter categories into Arabic when the app is in Arabic
  /// (only the ones still carrying their original English name).
  Future<void> localizeDefaultCategories() async {
    if (!isArabic) return;
    var changed = false;
    for (final c in categories) {
      final ar = kArabicStarterCategories[c.name];
      if (ar == null) continue;
      await db.updateCategory(Category(
          id: c.id,
          name: ar,
          group: c.group,
          kind: c.kind,
          icon: c.icon,
          color: c.color));
      changed = true;
    }
    if (changed) await _reloadAll();
  }

  /// Example accounts, three months of transactions, a portfolio and two
  /// budgets, to explore the app. Removed with [clearSampleData].
  Future<void> loadSampleData() async {
    final cur = baseCurrency;
    // Amounts are in Egyptian pounds; scaled down for other currencies.
    final k = cur == 'EGP' ? 1.0 : 0.02;
    double m(double v) => (v * k * 100).roundToDouble() / 100;
    final now = DateTime.now();
    DateTime day(int monthsAgo, int d) =>
        DateTime(now.year, now.month - monthsAgo, d, 12);
    int? cat(String icon, TxType kind) => categories
        .where((c) => c.icon == icon && c.kind == kind)
        .firstOrNull
        ?.id;
    final ids = <int>[];
    Future<int> acc(Account a) async {
      final id = await db.insertAccount(a);
      ids.add(id);
      return id;
    }

    final bankName = tr('Sample Bank');
    final cash = await acc(Account(
        name: tr('Wallet'),
        type: AccountType.cash,
        currency: cur,
        openingBalance: m(1500)));
    final bank = await acc(Account(
        name: tr('Current Account'),
        bank: bankName,
        type: AccountType.bank,
        currency: cur,
        openingBalance: m(42000),
        sortOrder: 1));
    final savings = await acc(Account(
        name: tr('Savings Account'),
        bank: bankName,
        type: AccountType.savings,
        currency: cur,
        openingBalance: m(150000),
        sortOrder: 2));
    final card = await acc(Account(
        name: 'Visa Gold',
        bank: bankName,
        type: AccountType.creditCard,
        currency: cur,
        creditLimit: m(60000),
        statementDay: 25,
        dueDay: 15,
        minPayPct: 5,
        sortOrder: 3));
    final stocks = await acc(Account(
        name: tr('Stocks'),
        bank: 'Thndr',
        type: AccountType.investment,
        currency: 'EGP',
        openingBalance: 30000,
        investMode: 'holdings',
        sortOrder: 4));
    await acc(Account(
        name: tr('Gold'),
        type: AccountType.gold,
        currency: 'XAU21',
        openingBalance: 20,
        sortOrder: 5));

    final ex = TxType.expense;
    final txns = <Txn>[];
    void add(TxType type, DateTime date, double amount, int account,
        {String? icon, String payee = '', int? to}) {
      if (date.isAfter(now)) return;
      txns.add(Txn(
        type: type,
        date: date,
        amount: m(amount),
        accountId: account,
        toAccountId: to,
        toAmount: to == null ? null : m(amount),
        categoryId: icon == null ? null : cat(icon, type),
        payee: payee,
      ));
    }

    for (var mo = 2; mo >= 0; mo--) {
      add(TxType.income, day(mo, 1), 35000, bank, icon: 'salary');
      add(TxType.transfer, day(mo, 2), 3000, bank, to: cash);
      add(ex, day(mo, 3), 9000, bank, icon: 'home', payee: tr('Rent'));
      add(TxType.transfer, day(mo, 4), 5000, bank, to: savings);
      add(ex, day(mo, 5), 2300, card, icon: 'groceries', payee: 'Carrefour');
      add(ex, day(mo, 6), 900, card, icon: 'fuel', payee: 'Wataniya');
      add(ex, day(mo, 8), 640, card, icon: 'food', payee: 'Talabat');
      add(ex, day(mo, 10), 1200, bank, icon: 'bills', payee: tr('Electricity'));
      add(ex, day(mo, 11), 350, cash, icon: 'transport', payee: 'Uber');
      add(ex, day(mo, 12), 450, bank, icon: 'internet', payee: 'WE');
      add(ex, day(mo, 14), 2700 - mo * 400, card,
          icon: 'clothes', payee: 'Zara');
      add(TxType.transfer, day(mo, 15), 8500, bank, to: card);
      add(ex, day(mo, 16), 980, card, icon: 'food', payee: 'Zooba');
      add(ex, day(mo, 17), 600, card, icon: 'entertainment', payee: 'Vox Cinemas');
      add(ex, day(mo, 19), 1850, card, icon: 'groceries', payee: 'Seoudi');
      add(ex, day(mo, 20), 900, card, icon: 'fuel', payee: 'Wataniya');
      add(ex, day(mo, 22), 420, cash, icon: 'food', payee: 'Koshary Abou Tarek');
      add(ex, day(mo, 26), 750 + mo * 150, card, icon: 'health', payee: tr('Pharmacy'));
    }
    for (final t in txns) {
      await db.insertTxn(t);
    }

    final start = DateTime(now.year, now.month - 2, 1);
    final budgetIds = <int>[
      await db.insertBudget(
          Budget(scope: BudgetScope.total, amount: m(25000), start: start)),
      if (cat('food', ex) != null)
        await db.insertBudget(Budget(
            scope: BudgetScope.category,
            target: '${cat('food', ex)}',
            amount: m(3000),
            start: start,
            sortOrder: 1)),
    ];

    await db.setSetting('sample_accounts', ids.join(','));
    await db.setSetting('sample_budgets', budgetIds.join(','));
    _sampleAccounts = ids;
    _sampleBudgets = budgetIds;
    await _reloadAll();

    final stockAcc = accounts.firstWhere((a) => a.id == stocks);
    await addTrade(stockAcc, 'COMI', true, 150, 82.5, 0, day(2, 9));
    await addTrade(stockAcc, 'TMGH', true, 400, 58, 0, day(1, 13));
    await addTrade(stockAcc, 'FWRY', true, 1000, 11.2, 0, day(0, 2));
  }

  Future<void> clearSampleData() async {
    for (final id in _sampleBudgets) {
      await db.deleteBudget(id);
    }
    for (final id in _sampleAccounts) {
      await db.deleteAccount(id);
    }
    await db.setSetting('sample_accounts', '');
    await db.setSetting('sample_budgets', '');
    _sampleAccounts = [];
    _sampleBudgets = [];
    await _reloadAll();
  }

  /// Creates a starter account from the welcome screens.
  Future<void> addStarterAccount(
      String name, AccountType type, double balance, {String bank = ''}) async {
    await db.insertAccount(Account(
      name: name,
      bank: bank,
      type: type,
      currency: baseCurrency,
      openingBalance: type.isLiability ? -balance.abs() : balance,
      sortOrder: accounts.length,
    ));
    await _reloadAll();
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
    // Portfolios: add today's market gain on top of the balance.
    for (final a in countedAccounts) {
      if (a.marketValue != null) sum += toBase(a.worth - a.balance, a.currency);
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
  Future<String> restoreFrom(String path, String safetyDir,
      {bool markBackup = true}) async {
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
    if (markBackup) await markBackedUp();
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

    // Loan installments: on the due day (and the days chosen for cards).
    if (s.recurring) {
      for (final a in plannedLoans) {
        final t = a.loan!;
        for (final r in t.schedule().skip(t.nextIndex).take(3)) {
          for (final d in {0, ...s.cardDays.where((d) => d > 0)}) {
            out.add(Reminder(
              at(r.date, d),
              '🏦 ${a.fullName}',
              '${fmtMoneyRaw(r.payment, a.currency)} installment ${r.index + 1}/${t.months} due ${reminderWhen(d, r.date)}',
            ));
          }
        }
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
  /// Latest downloaded rates (units per USD), even where a manual rate is
  /// set: the "market" rate for comparing transfers.
  Map<String, double> onlineRates = {};

  double? _onlinePerUsd(String code) {
    if (code == 'USD') return 1;
    final o = onlineRates[code];
    if (o != null) return o;
    final r = rates[code];
    return r != null && !r.manual ? r.perUsd : null;
  }

  /// Market rate: units of [to] per 1 [from].
  double? onlineRate(String from, String to) {
    final f = _onlinePerUsd(from), t = _onlinePerUsd(to);
    if (f == null || t == null || f == 0) return null;
    return t / f;
  }

  /// The rate set by hand in Currencies, when either side has one.
  double? myRate(String from, String to) {
    if (!(rates[from]?.manual ?? false) && !(rates[to]?.manual ?? false)) {
      return null;
    }
    return convert(1, from, to);
  }

  /// Rate of the last transfer between these two currencies (either way).
  Future<double?> lastTransferRate(String from, String to, {int? exceptId}) =>
      db.lastTransferRate(from, to, exceptId: exceptId);

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
      sum += toBase(a.worth, a.currency);
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
    // Stock prices: refresh when older than an hour.
    DateTime? sp;
    for (final p in stockPrices.values) {
      if (p.manual || p.updatedAt == null) continue;
      if (sp == null || p.updatedAt!.isBefore(sp)) sp = p.updatedAt;
    }
    if (sp == null || DateTime.now().difference(sp).inMinutes >= 15) {
      refreshStockPrices().catchError((_) => 0);
    }
    final last = lastRateUpdate;
    // A currency in use with no rate yet (e.g. a new gold karat): refresh now.
    final missing = usedCurrencies.any((c) => c != 'USD' && !rates.containsKey(c));
    if (!missing && last != null && DateTime.now().difference(last) < maxAge) return;
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
      // Market rates kept apart, also for currencies with a manual rate.
      onlineRates = {...onlineRates, ...fetched};
      await db.setSetting('online_rates', jsonEncode(onlineRates));
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

  /// Saves and returns the account's id.
  Future<int> saveAccount(Account a) async {
    int id;
    if (a.id == null) {
      id = await db.insertAccount(a);
    } else {
      await db.updateAccount(a);
      id = a.id!;
    }
    await _reloadAll();
    return id;
  }

  /// Account details (last digits, expiry, phone, IBAN…), by account id.
  Map<int, AccountDetails> accountDetails = {};

  AccountDetails detailsOf(int? id) =>
      id == null ? AccountDetails.empty : (accountDetails[id] ?? AccountDetails.empty);

  Future<void> saveAccountDetails(int accountId, AccountDetails d) async {
    await db.saveAccountDetails(accountId, d);
    await _reloadAll();
  }

  // ---------------- Stocks ----------------

  List<Trade> trades = [];
  Map<String, StockPrice> stockPrices = {};
  final StockPriceService _stockService = StockPriceService();
  final CryptoPriceService _cryptoService = CryptoPriceService();

  /// Price table key: coins are kept apart from EGX symbols ("C:BTC").
  /// Coin prices are stored in USD, stock prices in EGP.
  static String priceKey(Account a, String symbol) =>
      a.type == AccountType.crypto ? 'C:$symbol' : symbol;
  bool refreshingStocks = false;

  /// Shares held now in an account, at average cost (sells reduce the
  /// cost at the average price).
  List<Holding> holdings(int accountId) {
    final acc = accountById(accountId);
    final map = <String, Holding>{};
    for (final t in trades) {
      if (t.accountId != accountId) continue;
      final h = map.putIfAbsent(t.symbol, () => Holding(t.symbol));
      if (t.buy) {
        h.qty += t.qty;
        h.cost += t.qty * t.price;
      } else {
        final avg = h.avgCost;
        h.qty -= t.qty;
        h.cost -= t.qty * avg;
        if (h.qty < 1e-9) {
          h.qty = 0;
          h.cost = 0;
        }
      }
    }
    final out = map.values.where((h) => h.qty > 1e-9).toList()
      ..sort((a, b) => a.symbol.compareTo(b.symbol));
    for (final h in out) {
      final p = acc == null ? null : stockPrices[priceKey(acc, h.symbol)];
      if (p != null) {
        h.price = acc!.type == AccountType.crypto
            ? (convert(p.price, 'USD', acc.currency) ?? p.price)
            : p.price;
        h.manualPrice = p.manual;
        h.priceAt = p.updatedAt;
      }
    }
    return out;
  }

  /// Portfolio value for tracked investment accounts.
  void _applyMarketValues() {
    accounts = [
      for (final a in accounts)
        if (a.investMode == 'holdings')
          a.withMarketValue(a.balance +
              holdings(a.id!).fold<double>(0, (s, h) => s + h.gain))
        else if (a.hasAssetValue && a.assetValue != null)
          a.withMarketValue(a.assetShareValue)
        else if (a.investMode == 'simple' && a.investValue != null)
          a.withMarketValue(
              a.investValue! + (a.balance - (a.investBase ?? a.balance)))
        else
          a,
    ];
  }

  /// Cash in a holdings account (balance minus the cost of shares held).
  double portfolioCash(Account a) =>
      a.balance - holdings(a.id!).fold<double>(0, (s, h) => s + h.cost);

  /// Money put in minus money taken out (transfers), in the account currency.
  Future<double> invested(Account a) async {
    final txns = await db.transactions(accountId: a.id);
    var v = a.openingBalance;
    for (final t in txns) {
      if (t.isFuture || t.type != TxType.transfer) continue;
      if (t.toAccountId == a.id) v += t.toAmount ?? t.amount;
      if (t.accountId == a.id) v -= t.amount;
    }
    return v;
  }

  Future<int?> _categoryNamed(String name, TxType kind, String icon) async {
    for (final c in categories) {
      if (c.kind == kind && c.name.toLowerCase() == name.toLowerCase()) {
        return c.id;
      }
    }
    return db.insertCategory(Category(
        name: name, group: 'Investments', kind: kind, icon: icon,
        color: 0xFF00897B));
  }

  /// Records a buy or sell. Fees become an expense; a sell's profit or
  /// loss (against the average cost) becomes income (negative = loss).
  Future<void> addTrade(Account a, String symbol, bool buy, double qty,
      double price, double fees, DateTime date) async {
    symbol = symbol.trim().toUpperCase();
    double realized = 0;
    if (!buy) {
      final h = holdings(a.id!).where((h) => h.symbol == symbol).firstOrNull;
      if (h == null || h.qty + 1e-9 < qty) {
        throw Exception('You hold only ${h?.qty ?? 0} $symbol');
      }
      realized = (price - h.avgCost) * qty;
    }
    int? feeId, pnlId;
    if (fees > 0.004) {
      feeId = await db.insertTxn(Txn(
        type: TxType.expense,
        date: date,
        amount: fees,
        accountId: a.id!,
        categoryId: await _categoryNamed('Brokerage Fees', TxType.expense, 'fees'),
        payee: a.name,
        note: '${buy ? 'Buy' : 'Sell'} $symbol',
      ));
    }
    if (!buy && realized.abs() > 0.004) {
      pnlId = await db.insertTxn(Txn(
        type: TxType.income,
        date: date,
        amount: (realized * 100).roundToDouble() / 100,
        accountId: a.id!,
        categoryId: await _categoryNamed(
            a.type == AccountType.crypto ? 'Crypto Profit' : 'Stock Profit',
            TxType.income, 'interest'),
        payee: symbol,
        note: 'Sold ${_qty(qty)} $symbol at ${fmtAmountRaw(price)}',
      ));
    }
    await db.insertTrade(Trade(
      accountId: a.id!,
      symbol: symbol,
      date: date,
      buy: buy,
      qty: qty,
      price: price,
      fees: fees,
      realized: realized,
      feeTxnId: feeId,
      pnlTxnId: pnlId,
    ));
    final key = priceKey(a, symbol);
    if (buy && !stockPrices.containsKey(key)) {
      // Until a live price arrives, value it at the price paid.
      final stored = a.type == AccountType.crypto
          ? (convert(price, a.currency, 'USD') ?? price)
          : price;
      await db.upsertStockPrice(
          StockPrice(key, stored, updatedAt: DateTime.now()));
    }
    await _reloadAll();
    if (buy) refreshStockPrices(only: {key});
  }

  static String _qty(double q) =>
      q == q.roundToDouble() ? q.toStringAsFixed(0) : q.toString();

  Future<void> deleteTrade(Trade t) async {
    await db.deleteTrade(t);
    await _reloadAll();
  }

  /// [price] is in the account's currency.
  Future<void> setStockPrice(Account a, String symbol, double price) async {
    final stored = a.type == AccountType.crypto
        ? (convert(price, a.currency, 'USD') ?? price)
        : price;
    await db.upsertStockPrice(StockPrice(priceKey(a, symbol), stored,
        manual: true, updatedAt: DateTime.now()));
    await _reloadAll();
  }

  Future<void> clearManualStockPrice(Account a, String symbol) async {
    final key = priceKey(a, symbol);
    final p = stockPrices[key];
    if (p != null) {
      await db.upsertStockPrice(StockPrice(key, p.price, updatedAt: p.updatedAt));
    }
    await refreshStockPrices(only: {key});
  }

  /// Fetches prices for held symbols (manual prices are left alone).
  /// Returns how many were updated.
  Future<int> refreshStockPrices({Set<String>? only}) async {
    final symbols = <String>{};
    for (final a in accounts) {
      if (a.investMode != 'holdings') continue;
      for (final h in holdings(a.id!)) {
        symbols.add(priceKey(a, h.symbol));
      }
    }
    if (only != null) symbols.retainAll(only);
    symbols.removeWhere((s) => stockPrices[s]?.manual ?? false);
    if (symbols.isEmpty) return 0;
    refreshingStocks = true;
    notifyListeners();
    var n = 0;
    try {
      for (final s in symbols) {
        final p = s.startsWith('C:')
            ? await _cryptoService.fetchUsd(s.substring(2))
            : await _stockService.fetch(s);
        if (p == null) continue;
        await db.upsertStockPrice(StockPrice(s, p, updatedAt: DateTime.now()));
        n++;
      }
    } finally {
      refreshingStocks = false;
    }
    if (n > 0) {
      // Prices only change values, not data: no Dropbox upload needed.
      stockPrices = {for (final p in await db.stockPrices()) p.symbol: p};
      _applyMarketValues();
      version++;
    }
    notifyListeners();
    return n;
  }

  /// Property / car / other asset: market value of the whole item and
  /// your ownership share in %.
  Future<void> setAssetValue(Account a, double? value, double share) async {
    await db.updateAccount(Account.fromMap({
      ...a.toMap(),
      'asset_value': value,
      'asset_share': share,
      'asset_value_at': value == null ? null : DateTime.now().millisecondsSinceEpoch,
    }));
    await _reloadAll();
  }

  /// Simple mode: the portfolio total as shown by the broker.
  Future<void> setInvestValue(Account a, double value) async {
    await db.updateAccount(Account.fromMap({
      ...a.toMap(),
      'invest_value': value,
      'invest_value_at': DateTime.now().millisecondsSinceEpoch,
      'invest_base': a.balance,
    }));
    await _reloadAll();
  }

  // ---------------- InstaPay fee ----------------

  /// InstaPay: 0.1% of the amount, at least 0.50 and at most 20.
  static double instaPayFee(double amount) {
    final f = amount.abs() * 0.001;
    final c = f < 0.5 ? 0.5 : (f > 20 ? 20.0 : f);
    return (c * 100).roundToDouble() / 100;
  }

  /// Adds, updates or removes the InstaPay fee linked to transaction
  /// [mainId]. [fee] null or 0 removes it.
  Future<void> setInstaPayFee(int mainId, int accountId, DateTime date,
      double? fee, {String note = ''}) async {
    final old = await db.feeOf(mainId);
    if (fee == null || fee <= 0.004) {
      if (old != null) {
        await db.deleteTxn(old.id!);
        await _reloadAll();
      }
      return;
    }
    if (old != null) {
      await db.updateTxn(Txn.fromMap({
        ...old.toMap(),
        'amount': fee,
        'date': date.millisecondsSinceEpoch,
        'account_id': accountId,
      }));
      await _reloadAll();
      return;
    }
    await addInstaPayFee(accountId, date, fee, note: note, feeFor: mainId);
  }

  /// Records the fee as its own expense from [accountId].
  Future<void> addInstaPayFee(int accountId, DateTime date, double fee,
      {String note = '', int? feeFor}) async {
    int? cat;
    for (final c in categories) {
      if (c.kind == TxType.expense && c.name.toLowerCase() == 'instapay fees') {
        cat = c.id;
        break;
      }
    }
    cat ??= await db.insertCategory(const Category(
        name: 'InstaPay Fees', group: 'Bank', kind: TxType.expense,
        icon: 'fees', color: 0xFF607D8B));
    await db.insertTxn(Txn(
      type: TxType.expense,
      date: date,
      amount: fee,
      accountId: accountId,
      categoryId: cat,
      payee: 'InstaPay',
      note: note,
      feeFor: feeFor,
    ));
    await _reloadAll();
  }

  // ---------------- Loans ----------------

  /// Loan accounts with a repayment plan.
  List<Account> get plannedLoans =>
      accounts.where((a) => !a.archived && a.loan != null).toList();

  /// Installments whose date has arrived and aren't recorded yet.
  List<(Account, LoanRow)> get loansDue {
    final end = DateTime.now();
    final today = DateTime(end.year, end.month, end.day + 1);
    final out = <(Account, LoanRow)>[];
    for (final a in plannedLoans) {
      final t = a.loan!;
      for (final r in t.schedule()) {
        if (r.index < t.nextIndex) continue;
        if (!r.date.isBefore(today)) break;
        out.add((a, r));
      }
    }
    out.sort((x, y) => x.$2.date.compareTo(y.$2.date));
    return out;
  }

  /// Next unpaid installment of a loan, if any.
  LoanRow? nextInstallment(Account a) {
    final t = a.loan;
    if (t == null) return null;
    final rows = t.schedule();
    return t.nextIndex < rows.length ? rows[t.nextIndex] : null;
  }

  Future<int?> _loanInterestCategory() async {
    for (final c in categories) {
      if (c.kind == TxType.expense && c.name.toLowerCase() == 'loan interest') {
        return c.id;
      }
    }
    return db.insertCategory(const Category(
        name: 'Loan Interest', group: 'Bank', kind: TxType.expense,
        icon: 'fees', color: 0xFF607D8B));
  }

  /// Creates a loan account with a plan. When the money was received into
  /// another account, that is recorded as a transfer out of the loan.
  Future<void> createLoan(Account a,
      {int? receivedInto, double received = 0}) async {
    final t = a.loan!;
    final gotMoney = receivedInto != null && received > 0.004;
    // Owed at start = total to repay. Money received shows as a transfer,
    // the rest (installments mode) is the loan's cost.
    final opening = -(t.startOwed - (gotMoney ? received : 0));
    final id = await db.insertAccount(Account.fromMap(
        {...a.toMap(), 'opening_balance': opening}..remove('id')));
    if (gotMoney) {
      final to = accountById(receivedInto);
      await db.insertTxn(Txn(
        type: TxType.transfer,
        date: DateTime.now(),
        amount: received,
        accountId: id,
        toAccountId: receivedInto,
        toAmount: to == null || to.currency == a.currency
            ? null
            : convert(received, a.currency, to.currency),
        note: 'Loan received',
      ));
    }
    await _reloadAll();
  }

  /// Records one installment: a transfer from the paying account into the
  /// loan (principal) and, for interest loans, the interest as an expense.
  Future<void> payLoanInstallment(Account loan, LoanRow row,
      {int? fromAccountId, DateTime? date}) async {
    final t = loan.loan!;
    final from = fromAccountId ?? t.payAccountId;
    if (from == null) throw Exception(tr('Choose the account you pay from'));
    final when = date ?? (row.date.isAfter(DateTime.now()) ? DateTime.now() : row.date);
    final label = 'Installment ${row.index + 1}/${t.months}';
    final payFrom = accountById(from);
    final conv = payFrom == null || payFrom.currency == loan.currency
        ? null
        : convert(row.principal, loan.currency, payFrom.currency);
    await db.insertTxn(Txn(
      type: TxType.transfer,
      date: when,
      amount: conv ?? row.principal,
      accountId: from,
      toAccountId: loan.id,
      toAmount: conv == null ? null : row.principal,
      note: '${loan.name} · $label',
    ));
    if (row.interest > 0.004) {
      await db.insertTxn(Txn(
        type: TxType.expense,
        date: when,
        amount: payFrom == null || payFrom.currency == loan.currency
            ? row.interest
            : (convert(row.interest, loan.currency, payFrom.currency) ?? row.interest),
        accountId: from,
        categoryId: await _loanInterestCategory(),
        payee: loan.fullName,
        note: 'Interest · $label',
      ));
    }
    await db.updateAccount(Account.fromMap({
      ...loan.toMap(),
      ...LoanTerms.toColumns(t.copyWith(nextIndex: row.index + 1)),
    }));
    await _reloadAll();
  }

  /// Gold kept in money -> gold kept in grams (see switchGoldToWeight UI).
  Future<void> switchGoldToWeight(Account old, String code, double grams) async {
    final id = await db.insertAccount(Account.fromMap({
      ...old.toMap(),
      'id': null,
      'name': '${old.name} (grams)',
      'currency': code,
      // Nothing paid on record: the grams are simply the starting balance.
      'opening_balance': old.balance > 0.004 ? 0.0 : grams,
      'archived': 0,
    }..remove('id')));
    final now = DateTime.now();
    if (old.balance > 0.004) await db.insertTxn(Txn(
      type: TxType.transfer,
      date: now,
      amount: old.balance,
      accountId: old.id!,
      toAccountId: id,
      toAmount: grams,
      note: 'Switched to tracking by weight',
    ));
    await db.updateAccount(Account.fromMap({...old.toMap(), 'archived': 1}));
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
    await SecureStore.setCardNumber(id, null);
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

  /// Saves and returns the transaction's id.
  Future<int> saveTxn(Txn t) async {
    int id;
    if (t.id == null) {
      id = await db.insertTxn(t);
    } else {
      await db.updateTxn(t);
      id = t.id!;
    }
    await _reloadAll();
    return id;
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
  /// Redraws screens that depend on today's date (due badge) — e.g. when
  /// the app comes back after midnight.
  void refreshForToday() => notifyListeners();

  /// Recurring items dated today or earlier, still to confirm.
  List<Occurrence> get dueOccurrences {
    final n = DateTime.now();
    return pendingOccurrences(DateTime(1970), DateTime(n.year, n.month, n.day + 1));
  }

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
  Future<int> confirmOccurrence(Occurrence o, [Txn? t]) async {
    final id = await db.insertTxn(t ?? o.rule.toTxn(o.index));
    await _advance(o);
    return id;
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
