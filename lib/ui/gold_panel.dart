import 'package:flutter/material.dart';

import '../data/models.dart';
import '../state/app_state.dart';
import '../util/currencies.dart';
import '../util/format.dart';
import 'currencies_screen.dart';
import 'widgets.dart';

/// Gold held by weight: today's price, value, what was paid and the gain.
class GoldPanel extends StatelessWidget {
  const GoldPanel({super.key, required this.account, required this.txns});

  final Account account;
  final List<Txn> txns;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final base = state.baseCurrency;
    final code = account.currency;
    final price = state.convert(1, code, base);
    // Money in (buys) minus money out (sales), in the main currency.
    var paid = 0.0;
    var gramsBought = 0.0;
    for (final t in txns) {
      if (t.isFuture || t.type != TxType.transfer) continue;
      if (t.toAccountId == account.id && t.accountId != account.id) {
        final from = state.accountById(t.accountId);
        paid += state.toBase(t.amount, from?.currency ?? base);
        gramsBought += t.toAmount ?? t.amount;
      } else if (t.accountId == account.id && t.toAccountId != account.id) {
        final to = state.accountById(t.toAccountId);
        paid -= state.toBase(t.toAmount ?? t.amount, to?.currency ?? base);
      }
    }
    final worth = price == null ? null : account.balance * price;
    final gain = worth == null ? null : worth - paid;
    final small = Theme.of(context).textTheme.bodySmall;
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
                  child: Text('Gold ${goldKarat(code)}K',
                      style: Theme.of(context).textTheme.titleSmall),
                ),
                TextButton(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const CurrenciesScreen()),
                  ),
                  child: const Text('Set Price'),
                ),
              ],
            ),
            _row('Price per gram',
                price == null ? 'Not available yet' : fmtMoney(price, base),
                note: state.isManual(code) ? 'your price' : 'from world price'),
            _row('Value now', worth == null ? '—' : fmtMoney(worth, base),
                bold: true),
            if (gramsBought > 0 || paid.abs() > 0.004) ...[
              _row('Paid (minus sales)', fmtMoney(paid, base)),
              if (gain != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      const Expanded(child: Text('Gain / loss')),
                      Text(
                        '${gain >= 0 ? '+' : ''}${fmtMoney(gain, base)}'
                        '${paid > 0 ? '  (${(gain / paid * 100).toStringAsFixed(1)}%)' : ''}',
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: amountColor(context, gain)),
                      ),
                    ],
                  ),
                ),
              if (gramsBought > 0 && paid > 0)
                Text(
                    'Average paid ${fmtMoney(paid / gramsBought, base)} per gram',
                    style: small),
            ] else
              Text(
                  'Record purchases as a transfer into this account (money out, grams in) to see what you paid and your gain.',
                  style: small),
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String value, {bool bold = false, String? note}) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            Expanded(child: Text(note == null ? label : '$label ($note)')),
            Text(value,
                style: TextStyle(
                    fontWeight: bold ? FontWeight.bold : FontWeight.normal)),
          ],
        ),
      );
}

/// Turns a gold account kept in money into one kept in grams: a new
/// account in grams, a transfer carrying the current value across (so what
/// you paid is kept), and the old account archived.
Future<void> switchGoldToWeight(
    BuildContext context, AppState state, Account old) async {
  var code = 'XAU21';
  final grams = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) => AlertDialog(
        title: const Text('Switch to Grams'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
                'This account holds ${fmtMoney(old.balance, old.currency)} (what you paid). '
                'Enter the gold you actually have:'),
            const SizedBox(height: 12),
            SegmentedButton<String>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: 'XAU24', label: Text('24K')),
                ButtonSegment(value: 'XAU21', label: Text('21K')),
                ButtonSegment(value: 'XAU18', label: Text('18K')),
              ],
              selected: {code},
              onSelectionChanged: (v) => setS(() => code = v.first),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: grams,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Grams',
                suffixText: 'g',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'A new account "${old.name} (grams)" is created, the amount you '
              'paid moves into it as the purchase cost, and this account is '
              'archived with its history.',
              style: Theme.of(ctx).textTheme.bodySmall,
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Switch')),
        ],
      ),
    ),
  );
  if (ok != true) return;
  final g = parseAmount(grams.text);
  if (g == null || g <= 0) {
    if (context.mounted) showSnack(context, 'Enter the grams you hold');
    return;
  }
  await state.switchGoldToWeight(old, code, g);
  if (context.mounted) {
    Navigator.pop(context);
    showSnack(context, 'Gold now tracked by weight: ${fmtMoney(g, code)}');
  }
}
