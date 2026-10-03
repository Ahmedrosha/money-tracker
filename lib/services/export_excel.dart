import 'dart:io';

import 'package:excel/excel.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';

import '../data/models.dart';
import '../l10n/l10n.dart';
import '../state/app_state.dart';

/// Builds .xlsx files and returns their path (to share).
class ExcelExport {
  static final _d = DateFormat('yyyy-MM-dd');

  static CellValue _t(String s) => TextCellValue(s);
  static CellValue _n(double v) => DoubleCellValue((v * 100).roundToDouble() / 100);

  static Excel _book(String firstSheet) {
    final x = Excel.createExcel();
    final def = x.getDefaultSheet() ?? 'Sheet1';
    x.rename(def, firstSheet);
    return x;
  }

  static Future<String> _write(Excel x, String name) async {
    final bytes = x.encode();
    if (bytes == null) throw Exception('Could not create the file');
    final dir = await getTemporaryDirectory();
    final f = File('${dir.path}/$name.xlsx');
    await f.writeAsBytes(bytes, flush: true);
    return f.path;
  }

  /// Transactions in [from, to) with a summary sheet (by category and by
  /// month, in the main currency).
  static Future<String> transactions(
    AppState state, {
    required DateTime from,
    required DateTime to,
    int? accountId,
    required Set<TxType> types,
  }) async {
    final base = state.baseCurrency;
    final txns = (await state.db.transactions(from: from, to: to))
        .where((t) => types.contains(t.type))
        .where((t) =>
            accountId == null || t.accountId == accountId || t.toAccountId == accountId)
        .toList()
      ..sort((a, b) => a.date.compareTo(b.date));

    final x = _book('Transactions');
    final s = x['Transactions'];
    s.appendRow([
      for (final h in [
        'Date', 'Type', 'Account', 'To account', 'Category', 'Group', 'Payee',
        'Amount', 'Currency', 'Amount ($base)', 'Paid amount', 'Paid currency',
        'Tags', 'Note',
      ])
        _t(tr(h)),
    ]);
    final byCat = <String, double>{};
    final byMonth = <String, (double, double)>{};
    for (final t in txns) {
      final a = state.accountById(t.accountId);
      final b = state.accountById(t.toAccountId);
      final c = state.categoryById(t.categoryId);
      final cur = a?.currency ?? base;
      final inBase = state.toBase(t.amount, cur);
      s.appendRow([
        _t(_d.format(t.date)),
        _t(t.type.label),
        _t(a?.fullName ?? ''),
        _t(b?.fullName ?? ''),
        _t(c?.name ?? ''),
        _t(c?.group ?? ''),
        _t(t.payee),
        _n(t.type == TxType.expense ? -t.amount : t.amount),
        _t(cur),
        _n(t.type == TxType.expense ? -inBase : inBase),
        t.isForeign ? _n(t.origAmount!) : _t(''),
        _t(t.isForeign ? t.origCurrency! : ''),
        _t(t.tags.join(', ')),
        _t(t.note),
      ]);
      if (t.type == TxType.transfer) continue;
      final cat = c?.name ?? tr('No category');
      final key = '${t.type == TxType.expense ? tr('Expense') : tr('Income')} · $cat';
      byCat[key] = (byCat[key] ?? 0) + inBase;
      final m = DateFormat('yyyy-MM').format(t.date);
      final cur2 = byMonth[m] ?? (0.0, 0.0);
      byMonth[m] = t.type == TxType.income
          ? (cur2.$1 + inBase, cur2.$2)
          : (cur2.$1, cur2.$2 + inBase);
    }

    final sum = x['Summary'];
    sum.appendRow([_t(tr('From')), _t(_d.format(from))]);
    sum.appendRow([_t(tr('To')), _t(_d.format(to.subtract(const Duration(days: 1))))]);
    sum.appendRow([_t('')]);
    sum.appendRow([_t(tr('By category')), _t(tr('Amount ($base)'))]);
    final cats = byCat.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    for (final e in cats) {
      sum.appendRow([_t(e.key), _n(e.value)]);
    }
    sum.appendRow([_t('')]);
    sum.appendRow([_t(tr('Month')), _t(tr('Income')), _t(tr('Spent')), _t(tr('Saved'))]);
    final months = byMonth.keys.toList()..sort();
    for (final m in months) {
      final v = byMonth[m]!;
      sum.appendRow([_t(m), _n(v.$1), _n(v.$2), _n(v.$1 - v.$2)]);
    }
    return _write(x, 'Transactions ${_d.format(from)} to ${_d.format(to.subtract(const Duration(days: 1)))}');
  }

  /// A loan's full schedule with what is paid.
  static Future<String> loanSchedule(AppState state, Account loan) async {
    final t = loan.loan!;
    final x = _book('Schedule');
    final s = x['Schedule'];
    final pays = state.loanPayments[loan.id] ?? const {};
    s.appendRow([
      for (final h in ['#', 'Due date', 'Payment', 'Principal', 'Interest', 'Left after', 'Status', 'Paid on'])
        _t(tr(h)),
    ]);
    for (final r in t.schedule()) {
      final paid = state.installmentPaid(loan, r.index);
      final on = pays[r.index]?.where((x) => x.type == TxType.transfer).firstOrNull?.date;
      s.appendRow([
        IntCellValue(r.index + 1),
        _t(_d.format(r.date)),
        _n(r.payment),
        _n(r.principal),
        _n(r.interest),
        _n(r.balanceAfter),
        _t(paid ? tr('Paid') : tr('Upcoming')),
        _t(on == null ? '' : _d.format(on)),
      ]);
    }
    return _write(x, '${loan.name} schedule');
  }

  /// Subscriptions with monthly and yearly cost.
  static Future<String> subscriptions(AppState state) async {
    final base = state.baseCurrency;
    final x = _book('Subscriptions');
    final s = x['Subscriptions'];
    s.appendRow([
      for (final h in ['Name', 'Amount', 'Currency', 'Schedule', 'Next charge', 'Account', 'Per month ($base)', 'Per year ($base)'])
        _t(tr(h)),
    ]);
    for (final r in state.subscriptions) {
      final a = state.accountById(r.accountId);
      final next = r.finished ? null : r.occurrence(r.nextIndex);
      final m = state.subPerMonthBase(r);
      s.appendRow([
        _t(r.payee.isNotEmpty ? r.payee : (state.categoryById(r.categoryId)?.name ?? '')),
        _n(r.amount),
        _t(a?.currency ?? base),
        _t(r.scheduleLabel),
        _t(next == null ? '' : _d.format(next)),
        _t(a?.fullName ?? ''),
        _n(m),
        _n(m * 12),
      ]);
    }
    return _write(x, 'Subscriptions');
  }
}
