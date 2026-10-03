import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../data/models.dart';
import '../state/app_state.dart';
import '../util/format.dart';
import 'transaction_edit.dart';
import 'widgets.dart';
import '../l10n/l10n.dart';

/// Records one installment after a short confirmation.
Future<void> payLoan(BuildContext context, Account loan, LoanRow row) async {
  final state = AppScope.read(context);
  final t = loan.loan!;
  var from = t.payAccountId;
  final cur = loan.currency;
  // Due date if it has passed, otherwise today (paying ahead).
  final now = DateTime.now();
  var when = row.date.isAfter(now)
      ? now
      : DateTime(row.date.year, row.date.month, row.date.day, now.hour, now.minute);
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) => AlertDialog(
        title: Text(tr('Installment ${row.index + 1} of ${t.months}')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(tr('${loan.fullName} · due ${shortDateFmt.format(row.date)}')),
            const SizedBox(height: 12),
            Text(fmtMoney(row.payment, cur),
                style: Theme.of(ctx)
                    .textTheme
                    .headlineSmall
                    ?.copyWith(fontWeight: FontWeight.bold)),
            if (row.interest > 0)
              Text(
                  tr('Principal ${fmtAmount(row.principal)} · interest ${fmtAmount(row.interest)}'),
                  style: Theme.of(ctx).textTheme.bodySmall),
            const SizedBox(height: 16),
            AccountField(
              label: tr('Pay From'),
              value: from,
              onChanged: (v) => setS(() => from = v),
            ),
            const SizedBox(height: 12),
            InkWell(
              borderRadius: BorderRadius.circular(4),
              onTap: () async {
                final d = await showDatePicker(
                  context: ctx,
                  initialDate: when,
                  firstDate: DateTime(2000),
                  lastDate: DateTime(2100),
                  helpText: tr('Date you paid'),
                );
                if (d != null) {
                  setS(() => when = DateTime(d.year, d.month, d.day, when.hour, when.minute));
                }
              },
              child: InputDecorator(
                decoration: InputDecoration(
                  labelText: tr('Paid on'),
                  border: const OutlineInputBorder(),
                  suffixIcon: const Icon(Icons.calendar_today),
                ),
                child: Text(dayFmt.format(when)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(tr('Cancel'))),
          FilledButton(
              onPressed: from == null ? null : () => Navigator.pop(ctx, true),
              child: Text(tr('Record Payment'))),
        ],
      ),
    ),
  );
  if (ok != true || from == null) return;
  await state.payLoanInstallment(loan, row, fromAccountId: from, date: when);
  if (context.mounted) showSnack(context, tr('Installment ${row.index + 1} recorded'));
}

/// Progress, next installment and payoff date of a loan with a plan.
class LoanPanel extends StatelessWidget {
  const LoanPanel({super.key, required this.account});

  final Account account;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final t = account.loan!;
    final rows = t.schedule();
    final cur = account.currency;
    final unpaid = state.unpaidInstallments(account);
    final paidN = rows.length - unpaid.length;
    final totalAmt = rows.fold<double>(0, (s, r) => s + r.payment);
    final left = unpaid.fold<double>(0, (s, r) => s + r.payment);
    final paidAmt = totalAmt - left;
    final interestLeft = unpaid.fold<double>(0, (s, r) => s + r.interest);
    final next = unpaid.isEmpty ? null : unpaid.first;
    final now = DateTime.now();
    final overdue = next != null &&
        next.date.isBefore(DateTime(now.year, now.month, now.day + 1));
    final scheme = Theme.of(context).colorScheme;
    final small = Theme.of(context).textTheme.bodySmall;
    final payFrom = state.accountById(t.payAccountId);
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(tr('$paidN of ${t.months} installments paid'),
                      style: Theme.of(context).textTheme.titleSmall),
                ),
                Text('${totalAmt > 0 ? (paidAmt / totalAmt * 100).toStringAsFixed(0) : 0}%',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: totalAmt > 0 ? (paidAmt / totalAmt).clamp(0.0, 1.0) : 0,
                minHeight: 10,
                backgroundColor: scheme.surfaceContainerHighest,
              ),
            ),
            const SizedBox(height: 8),
            _row(tr('Paid so far'), fmtMoney(paidAmt, cur)),
            _row(tr('Left to pay'), fmtMoney(left, cur), bold: true),
            if (t.mode == LoanMode.interest || t.spreadsCost)
              _row(tr('Interest still to pay'), fmtMoney(interestLeft, cur)),
            _row(tr('Months left'), '${t.months - paidN}'),
            _row(tr('Paid off'), shortDateFmt.format(rows.last.date)),
            if (t.spreadsCost)
              Text(
                  tr('Borrowed ${fmtMoney(t.received!, cur)} · interest ${fmtMoney(t.totalToRepay - t.received!, cur)}, recorded on each due date'),
                  style: small),
            if (t.mode == LoanMode.interest)
              Text(
                  tr('Borrowed ${fmtMoney(t.principal, cur)} at ${t.rate}% ${t.flat ? tr('flat') : tr('declining')}'),
                  style: small),
            const Divider(height: 24),
            if (next == null)
              Row(children: [
                const Icon(Icons.celebration_outlined, color: kIncomeColor),
                const SizedBox(width: 8),
                Text(tr('Fully paid'), style: small),
              ])
            else
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                            '${overdue ? tr('Due') : tr('Next')}: ${fmtMoney(next.payment, cur)}',
                            style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: overdue ? kExpenseColor : null)),
                        Text(
                            '${dayFmt.format(next.date)}'
                            '${payFrom == null ? '' : tr(' · from ${payFrom.name}')}',
                            style: small),
                      ],
                    ),
                  ),
                  FilledButton.tonal(
                    onPressed: () => payLoan(context, account, next),
                    child: Text(tr('Pay')),
                  ),
                ],
              ),
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                icon: const Icon(Icons.list_alt),
                label: Text(tr('Full Schedule')),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => LoanScheduleScreen(accountId: account.id!)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(String l, String v, {bool bold = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(children: [
          Expanded(child: Text(l)),
          Text(v,
              style: TextStyle(
                  fontWeight: bold ? FontWeight.bold : FontWeight.normal)),
        ]),
      );
}

/// "01 October 2026".
String dayLongFmt(DateTime d) =>
    DateFormat('dd MMMM yyyy').format(d);

/// Every installment with its status.
class LoanScheduleScreen extends StatelessWidget {
  const LoanScheduleScreen({super.key, required this.accountId});

  final int accountId;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final a = state.accountById(accountId);
    if (a == null || a.loan == null) {
      return Scaffold(body: Center(child: Text(tr('Loan not found'))));
    }
    final t = a.loan!;
    final rows = t.schedule();
    final cur = a.currency;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day + 1);
    final interest = t.mode == LoanMode.interest || t.spreadsCost;
    return FutureBuilder<Map<int, List<Txn>>>(
      // Reloads after every change (state.version).
      key: ValueKey(state.version),
      future: state.db.loanPayments(a.id!, a.fullName),
      builder: (context, snap) {
        final payments = snap.data ?? const <int, List<Txn>>{};
        return _schedule(context, state, a, t, rows, cur, today, interest, payments);
      },
    );
  }

  Widget _schedule(BuildContext context, AppState state, Account a, LoanTerms t,
      List<LoanRow> rows, String cur, DateTime today, bool interest,
      Map<int, List<Txn>> payments) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('${a.name} Schedule'))),
      body: ListView.separated(
        padding: const EdgeInsets.only(bottom: 32),
        itemCount: rows.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, i) {
          final r = rows[i];
          final paid = state.installmentPaid(a, i);
          final entries = payments[i] ?? const <Txn>[];
          final paidOn = entries.isEmpty ? null : entries.first.date;
          final due = !paid && r.date.isBefore(today);
          final isNext = !paid && i == state.nextInstallment(a)?.index;
          return ListTile(
            leading: CircleAvatar(
              backgroundColor: paid
                  ? kIncomeColor.withValues(alpha: 0.15)
                  : due
                      ? kExpenseColor.withValues(alpha: 0.15)
                      : null,
              child: paid
                  ? const Icon(Icons.check, color: kIncomeColor)
                  : Text('${i + 1}',
                      style: TextStyle(color: due ? kExpenseColor : null)),
            ),
            title: Row(
              children: [
                Text(fmtMoney(r.payment, cur),
                    style: TextStyle(
                        fontWeight: isNext ? FontWeight.bold : FontWeight.normal)),
                // The bank's first / last installment differs.
                if (rows.length > 1 &&
                    (i == 0 || i == rows.length - 1) &&
                    (r.payment - rows[i == 0 ? 1 : i - 1].payment).abs() > 0.004)
                  TagChip(i == 0 ? tr('First') : tr('Last')),
              ],
            ),
            subtitle: Text(
                '${paid ? tr('Due ${shortDateFmt.format(r.date)}') : shortDateFmt.format(r.date)} · '
                '${paid ? (paidOn == null ? tr('Paid') : tr('Paid on ${dayLongFmt(paidOn)}')) : due ? tr('Due') : tr('Upcoming')}'
                '${interest ? tr('\nPrincipal ${fmtAmount(r.principal)} · interest ${fmtAmount(r.interest)}') : ''}'),
            isThreeLine: interest,
            trailing: Text(tr('Left ${fmtAmount(r.balanceAfter)}'),
                style: Theme.of(context).textTheme.bodySmall),
            onTap: paid
                ? () => _openPayment(context, state, r, entries)
                : (isNext ? () => payLoan(context, a, r) : null),
          );
        },
      ),
    );
  }

  /// A paid installment: open its entry, or choose between payment and
  /// interest.
  Future<void> _openPayment(BuildContext context, AppState state, LoanRow r,
      List<Txn> entries) async {
    if (entries.isEmpty) {
      showSnack(context, tr('No payment recorded for this installment'));
      return;
    }
    void open(Txn t) => Navigator.push(context,
        MaterialPageRoute(builder: (_) => TransactionEditScreen(txn: t)));
    if (entries.length == 1) {
      open(entries.first);
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(tr('Installment ${r.index + 1}')),
              subtitle: Text(tr('Paid on ${dayLongFmt(entries.first.date)}')),
            ),
            for (final t in entries)
              TxnTile(
                txn: t,
                onTap: () {
                  Navigator.pop(ctx);
                  open(t);
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
