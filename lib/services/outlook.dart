import 'package:flutter/material.dart';

import '../data/models.dart';
import '../l10n/l10n.dart';
import '../state/app_state.dart';

/// Cash, wallets and bank accounts (what pays the bills).
bool isSpendable(Account a) =>
    !a.archived &&
    !a.excludeTotal &&
    (a.type.family == AccountFamily.cash ||
        (a.type.family == AccountFamily.bank && a.type != AccountType.certificate));

/// Something coming that moves money in or out of cash and bank accounts.
class OutlookEvent {
  OutlookEvent(this.date, this.name, this.effects, this.icon, {this.estimate = false});
  final DateTime date;
  final String name;

  /// Account id → amount in the main currency (+ in / − out). Key -1: an
  /// amount not tied to one account (e.g. a card nobody paid yet).
  final Map<int, double> effects;
  final IconData icon;
  final bool estimate;

  double get total => effects.values.fold(0.0, (s, v) => s + v);
}

/// What is coming until [end]: future-dated entries, recurring items, card
/// payments (placed on the account that last paid that card) and loan
/// installments.
Future<List<OutlookEvent>> outlookEvents(AppState state, DateTime end) async {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final liquid = {
    for (final a in state.accounts)
      if (isSpendable(a)) a.id!: a
  };
  final events = <OutlookEvent>[];
  DateTime notBefore(DateTime d) => d.isBefore(today) ? today : d;

  Map<int, double> effect(TxType type, int accId, int? toId, double amount, double? toAmount) {
    final out = <int, double>{};
    final from = liquid[accId];
    final to = toId == null ? null : liquid[toId];
    switch (type) {
      case TxType.income:
        if (from != null) out[accId] = state.toBase(amount, from.currency);
      case TxType.expense:
        if (from != null) out[accId] = -state.toBase(amount, from.currency);
      case TxType.transfer:
        if (from != null) out[accId] = -state.toBase(amount, from.currency);
        if (to != null) {
          out[toId!] = (out[toId] ?? 0) + state.toBase(toAmount ?? amount, to.currency);
        }
    }
    out.removeWhere((_, v) => v.abs() < 0.005);
    return out;
  }

  String nameOf(TxType type, int? toId, String payee, int? catId) {
    if (type == TxType.transfer) {
      return tr('Transfer to ${state.accountById(toId)?.name ?? '?'}');
    }
    if (payee.isNotEmpty) return payee;
    return state.categoryById(catId)?.name ?? type.label;
  }

  // Entries already recorded with a future date.
  for (final t in await state.db.transactions(from: now, to: end)) {
    if (!t.date.isAfter(now)) continue;
    final e = effect(t.type, t.accountId, t.toAccountId, t.amount, t.toAmount);
    if (e.isEmpty) continue;
    events.add(OutlookEvent(t.date, nameOf(t.type, t.toAccountId, t.payee, t.categoryId),
        e, t.type == TxType.income ? Icons.south_west : Icons.north_east));
  }

  // Recurring items not confirmed yet (overdue ones count as today).
  for (final o in state.pendingOccurrences(DateTime(1970), end)) {
    final r = o.rule;
    final e = effect(r.type, r.accountId, r.toAccountId, r.amount, r.toAmount);
    if (e.isEmpty) continue;
    events.add(OutlookEvent(notBefore(o.date),
        nameOf(r.type, r.toAccountId, r.payee, r.categoryId), e, Icons.repeat));
  }

  // Credit card payments: the open statement, then each coming cycle.
  for (final c in state.cards.values) {
    final a = c.card;
    if (a.archived || a.excludeTotal || !a.hasCycle) continue;
    final payer = await state.db.lastPayerOf(a.id!);
    final key = payer != null && liquid.containsKey(payer) ? payer : -1;
    final last = c.last;
    if (last != null && !last.settled && last.remaining > 0.004) {
      events.add(OutlookEvent(notBefore(last.dueDate), tr('${a.fullName} statement'),
          {key: -state.toBase(last.remaining, a.currency)}, Icons.credit_card));
    }
    var close = c.nextClose;
    if (close == null) continue;
    var prevClose = lastCloseBefore(now, a.statementDay!);
    var first = true;
    while (true) {
      final due = dueDateAfter(close!, a.dueDay!);
      if (!due.isBefore(end)) break;
      final amt = first
          ? c.cycleSpent
          : await state.db.debitsBetween(a.id!, prevClose, close);
      if (amt > 0.004) {
        events.add(OutlookEvent(due, tr('${a.fullName} (estimate)'),
            {key: -state.toBase(amt, a.currency)}, Icons.credit_card,
            estimate: true));
      }
      first = false;
      prevClose = close;
      close = cycleCloseIn(close.year, close.month + 1, a.statementDay!);
    }
  }

  // Loan installments still to pay.
  for (final a in state.plannedLoans) {
    final t = a.loan!;
    final from = liquid[t.payAccountId];
    if (from == null) continue;
    for (final r in state.unpaidInstallments(a)) {
      if (!r.date.isBefore(end)) break;
      events.add(OutlookEvent(notBefore(r.date),
          tr('${a.name} installment ${r.index + 1}/${t.months}'),
          {from.id!: -state.toBase(r.payment, a.currency)},
          Icons.request_quote_outlined));
    }
  }

  events.sort((x, y) => x.date.compareTo(y.date));
  return events;
}

/// An account expected to go below zero soon.
class Shortfall {
  Shortfall(this.account, this.date, this.lowest, this.reason);
  final Account account;
  final DateTime date;

  /// Lowest balance in the period (main currency).
  final double lowest;

  /// What takes it below zero.
  final String reason;
}

/// Cash and bank accounts that go below zero within [days] days.
Future<List<Shortfall>> findShortfalls(AppState state, {int days = 14}) async {
  final now = DateTime.now();
  final end = DateTime(now.year, now.month, now.day + days + 1);
  final events = await outlookEvents(state, end);
  final out = <Shortfall>[];
  for (final a in state.accounts.where(isSpendable)) {
    var bal = state.toBase(a.balance, a.currency);
    if (bal < -0.5) continue; // already below zero: not a warning about the future
    DateTime? when;
    String reason = '';
    var lowest = bal;
    for (final e in events) {
      final v = e.effects[a.id];
      if (v == null) continue;
      bal += v;
      if (bal < lowest) lowest = bal;
      if (when == null && bal < -0.5) {
        when = e.date;
        reason = e.name;
      }
    }
    if (when != null) out.add(Shortfall(a, when, lowest, reason));
  }
  out.sort((x, y) => x.date.compareTo(y.date));
  return out;
}
