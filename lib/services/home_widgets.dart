import 'dart:async';

import 'package:home_widget/home_widget.dart';

import '../data/models.dart';
import '../l10n/l10n.dart';
import '../state/app_state.dart';
import '../util/currencies.dart';
import '../util/format.dart';

/// Home screen and lock screen widgets (iPhone and Android). The app saves
/// ready-to-show text after changes; the widgets only display it.
class HomeWidgets {
  static const appGroup = 'group.com.rashad.moneytracker';

  // iOS widget kinds and Android provider classes.
  static const _ios = ['AddExpenseWidget', 'NetWorthWidget', 'MonthWidget', 'DueWidget'];
  static const _android = [
    'com.rashad.money_tracker.AddExpenseWidget',
    'com.rashad.money_tracker.NetWorthWidget',
    'com.rashad.money_tracker.MonthWidget',
    'com.rashad.money_tracker.DueWidget',
  ];

  static bool _ready = false;
  static Timer? _debounce;

  static Future<void> init() async {
    if (_ready) return;
    try {
      await HomeWidget.setAppGroupId(appGroup);
      _ready = true;
    } catch (_) {}
  }

  /// Saves the numbers a moment after the last change.
  static void schedule(AppState state) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 2), () => update(state));
  }

  static Future<void> update(AppState state) async {
    try {
      await init();
      final d = await _data(state);
      for (final e in d.entries) {
        await HomeWidget.saveWidgetData<String>(e.key, e.value);
      }
      for (var i = 0; i < _ios.length; i++) {
        await HomeWidget.updateWidget(
            iOSName: _ios[i], qualifiedAndroidName: _android[i]);
      }
    } catch (_) {
      // Widgets are optional; never break the app over them.
    }
  }

  static Future<Map<String, String>> _data(AppState state) async {
    final base = state.baseCurrency;
    final unit = currencyUnit(base);
    final hide = amountsHidden;
    String money(double v) =>
        hide ? kHiddenAmount : stripDirectionMarks(fmtAmountRaw(v));
    String short(double v) {
      if (hide) return kHiddenAmount;
      final a = v.abs();
      final s = a >= 1e6
          ? '${(a / 1e6).toStringAsFixed(a >= 1e7 ? 1 : 2)}M'
          : a >= 1e4
              ? '${(a / 1e3).toStringAsFixed(1)}K'
              : a.toStringAsFixed(0);
      return v < 0 ? '−$s' : s;
    }

    // This month: spending and income in the main currency.
    final now = DateTime.now();
    final from = DateTime(now.year, now.month, 1);
    final to = DateTime(now.year, now.month + 1, 1);
    final rows = await state.db.db.rawQuery('''
      SELECT t.type AS type, t.amount AS amount, a.currency AS cur
      FROM transactions t JOIN accounts a ON a.id = t.account_id
      WHERE t.type IN ('expense', 'income') AND t.date >= ? AND t.date < ?
    ''', [from.millisecondsSinceEpoch, to.millisecondsSinceEpoch]);
    var spent = 0.0, income = 0.0;
    for (final r in rows) {
      final v = state.toBase((r['amount'] as num).toDouble(), r['cur'] as String);
      if (r['type'] == 'expense') {
        spent += v;
      } else {
        income += v;
      }
    }

    // The overall monthly budget, when there is one.
    var budgetLine = '';
    var budgetPct = -1;
    final total = state.budgets.where((b) => b.scope == BudgetScope.total).firstOrNull;
    if (total != null) {
      final st = await state.budgetStatusFor(total, from);
      budgetPct = (st.fraction * 100).round();
      budgetLine = hide
          ? tr('Budget $budgetPct%')
          : tr('${money(st.spent)} of ${money(st.limit)} · $budgetPct%');
    }

    // Next card payment and recurring items to confirm.
    final cards = state.cardsDue;
    final dueCount = state.dueOccurrences.length;
    var dueTitle = tr('Nothing due');
    var dueSub = '';
    if (cards.isNotEmpty) {
      final c = cards.first;
      dueTitle = c.card.fullName;
      dueSub = '${money(c.last!.remaining)} $unit · ${tr('due')} ${shortDateFmt.format(c.last!.dueDate)}';
    }

    String two(int n) => n.toString().padLeft(2, '0');
    return {
      'hidden': hide ? '1' : '0',
      'unit': unit,
      'updated': '${tr('Updated')} ${two(now.hour)}:${two(now.minute)}',
      'l_add': tr('Add Expense'),
      'l_networth': tr('Net Worth'),
      'l_month': tr('This Month'),
      'l_spent': tr('Spent'),
      'l_income': tr('Income'),
      'l_due': tr('Due Soon'),
      'networth': money(state.netWorth),
      'networth_short': short(state.netWorth),
      'spent': money(spent),
      'spent_short': short(spent),
      'income': money(income),
      'budget': budgetLine,
      'budget_pct': '$budgetPct',
      'due_title': dueTitle,
      'due_sub': dueSub,
      'recurring': dueCount == 0
          ? ''
          : tr('$dueCount recurring item${dueCount == 1 ? '' : 's'} to confirm'),
      'rtl': isArabic ? '1' : '0',
    };
  }
}
