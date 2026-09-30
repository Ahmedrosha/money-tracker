import 'package:flutter/material.dart';

import '../data/models.dart';
import '../state/app_state.dart';
import '../util/format.dart';
import 'widgets.dart';
import '../l10n/l10n.dart';

/// Property / car / other asset: value of your share against what you paid.
class AssetPanel extends StatelessWidget {
  const AssetPanel({super.key, required this.account});

  final Account account;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final cur = account.currency;
    final share = account.assetShare ?? 100;
    final whole = account.assetValue;
    final mine = account.assetShareValue;
    final paid = account.balance;
    final gain = mine == null ? null : mine - paid;
    final small = Theme.of(context).textTheme.bodySmall;
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(tr('Current Value'), style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            if (whole == null)
              Text(
                  tr('No market value yet, so net worth counts what you paid. '
                  'Tap Update Value to enter what it is worth today.'),
                  style: small)
            else ...[
              _row(account.type == AccountType.property
                  ? tr('Whole unit') : tr('Market value'), fmtMoney(whole, cur)),
              _row(tr('Your ownership'), '${_num(share)}%'),
              _row(tr('Your share'), fmtMoney(mine!, cur), bold: true),
              _row(tr('Paid so far'), fmtMoney(paid, cur)),
              if (gain != null)
                _row(tr('Gain / loss'),
                    '${gain >= 0 ? '+' : ''}${fmtMoney(gain, cur)}'
                    '${paid.abs() > 0.01 ? ' (${(gain / paid * 100).toStringAsFixed(1)}%)' : ''}',
                    bold: true,
                    color: amountColor(context, gain)),
              if (account.assetValueAt != null)
                Text(tr('Value set ${shortDateFmt.format(account.assetValueAt!)}'),
                    style: small),
            ],
            const SizedBox(height: 8),
            FilledButton.tonalIcon(
              icon: const Icon(Icons.edit_outlined),
              label: Text(tr('Update Value')),
              onPressed: () => _update(context, state),
            ),
          ],
        ),
      ),
    );
  }

  static String _num(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();

  Future<void> _update(BuildContext context, AppState state) async {
    final value = TextEditingController(
        text: account.assetValue == null ? '' : _num(account.assetValue!));
    final share = TextEditingController(text: _num(account.assetShare ?? 100));
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Update Value')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: value,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: account.type == AccountType.property
                    ? tr('Market value of the whole unit')
                    : tr('Market value'),
                suffixText: account.currency,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: share,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: tr('Your ownership'),
                suffixText: '%',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Save'))),
        ],
      ),
    );
    if (ok != true) return;
    final v = parseAmount(value.text)?.abs();
    final s = (parseAmount(share.text)?.abs() ?? 100).clamp(0.01, 100).toDouble();
    await state.setAssetValue(account, v, s);
    if (context.mounted) showSnack(context, tr('Value updated'));
  }

  Widget _row(String l, String v, {bool bold = false, Color? color}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(children: [
          Expanded(child: Text(l)),
          Text(v,
              style: TextStyle(
                  fontWeight: bold ? FontWeight.bold : FontWeight.normal,
                  color: color)),
        ]),
      );
}
