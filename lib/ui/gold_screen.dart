import 'package:flutter/material.dart';

import '../data/models.dart';
import '../l10n/l10n.dart';
import '../services/gold.dart';
import '../state/app_state.dart';
import '../util/currencies.dart';
import '../util/format.dart';
import 'widgets.dart';

/// Gold prices per karat, your gold's gain, and price alerts.
class GoldScreen extends StatefulWidget {
  const GoldScreen({super.key});

  @override
  State<GoldScreen> createState() => _GoldScreenState();
}

class _GoldScreenState extends State<GoldScreen> {
  late final Map<String, (TextEditingController, TextEditingController)> _c;
  late final TextEditingController _premium;
  Future<List<(Account, double, double)>>? _holdings;
  int _version = -1;

  @override
  void initState() {
    super.initState();
    final state = AppScope.read(context);
    String t(double? v) => v == null ? '' : v.toStringAsFixed(0);
    _c = {
      for (final code in kGoldCodes)
        code: (
          TextEditingController(text: t(state.goldAlerts.where((a) => a.code == code).firstOrNull?.above)),
          TextEditingController(text: t(state.goldAlerts.where((a) => a.code == code).firstOrNull?.below)),
        ),
    };
    _premium = TextEditingController(
        text: state.goldPremium == 0 ? '' : state.goldPremium.toString().replaceFirst(RegExp(r'\.0$'), ''));
  }

  @override
  void dispose() {
    for (final p in _c.values) {
      p.$1.dispose();
      p.$2.dispose();
    }
    _premium.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final state = AppScope.read(context);
    final alerts = <GoldAlert>[
      for (final code in kGoldCodes)
        if (parseAmount(_c[code]!.$1.text) != null || parseAmount(_c[code]!.$2.text) != null)
          GoldAlert(code,
              above: parseAmount(_c[code]!.$1.text)?.abs(), below: parseAmount(_c[code]!.$2.text)?.abs()),
    ];
    await state.saveGold(alerts, parseAmount(_premium.text) ?? 0);
    if (mounted) showSnack(context, tr('Saved'));
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    if (_version != state.version) {
      _version = state.version;
      _holdings = state.goldHoldings();
    }
    final base = state.baseCurrency;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(tr('Gold')),
        actions: [
          state.refreshingRates
              ? const Padding(
                  padding: EdgeInsets.all(16),
                  child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)))
              : IconButton(
                  tooltip: tr('Refresh Online Rates'),
                  icon: const Icon(Icons.refresh),
                  onPressed: () async {
                    try {
                      await state.refreshRates();
                    } catch (_) {
                      if (context.mounted) showSnack(context, tr("Couldn't refresh — no internet"));
                    }
                  },
                ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Text(tr('Price per gram'), style: theme.textTheme.titleSmall),
          const SizedBox(height: 6),
          Row(
            children: [
              for (final code in kGoldCodes)
                Expanded(
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(karatLabel(code), style: theme.textTheme.bodySmall),
                          FittedBox(
                            child: Text(
                              state.goldPrice(code) == null ? '—' : fmtAmount(state.goldPrice(code)!),
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                            ),
                          ),
                          Text(currencyUnit(base), style: theme.textTheme.bodySmall),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _premium,
            keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
            decoration: InputDecoration(
              labelText: tr('Local premium %'),
              helperText: tr('World price at the online rate, plus this to match shop prices in Egypt'),
              border: const OutlineInputBorder(),
            ),
          ),
          FutureBuilder<List<(Account, double, double)>>(
            future: _holdings,
            builder: (context, snap) {
              final list = snap.data ?? const [];
              if (list.isEmpty) return const SizedBox.shrink();
              final value = list.fold<double>(0, (s, e) => s + e.$2);
              final cost = list.fold<double>(0, (s, e) => s + e.$3);
              final grams = <String, double>{};
              for (final (a, _, _) in list) {
                grams[a.currency] = (grams[a.currency] ?? 0) + a.balance;
              }
              final gain = value - cost;
              return Card(
                margin: const EdgeInsets.only(top: 16),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(tr('Your Gold'), style: theme.textTheme.titleSmall),
                      Text(grams.entries
                          .map((e) => '${e.value.toStringAsFixed(2)} g ${karatLabel(e.key)}')
                          .join(' · ')),
                      const SizedBox(height: 6),
                      Text(tr('Worth ${fmtMoney(value, base)}'),
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                      if (cost > 0.004)
                        Text(
                          tr('Bought for ${fmtMoney(cost, base)} · ${gain >= 0 ? '+' : ''}${fmtMoney(gain, base)} (${gain >= 0 ? '+' : ''}${(gain / cost * 100).toStringAsFixed(1)}%)'),
                          style: TextStyle(color: gain >= 0 ? kIncomeColor : kExpenseColor),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 20),
          Text(tr('Price Alerts'), style: theme.textTheme.titleSmall),
          Text(tr('A notification when the price per gram goes above or below a level.'),
              style: theme.textTheme.bodySmall),
          const SizedBox(height: 8),
          for (final code in kGoldCodes)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  SizedBox(width: 44, child: Text(karatLabel(code), style: const TextStyle(fontWeight: FontWeight.bold))),
                  Expanded(
                    child: TextField(
                      controller: _c[code]!.$1,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                          labelText: tr('Above'), isDense: true, border: const OutlineInputBorder()),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _c[code]!.$2,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                          labelText: tr('Below'), isDense: true, border: const OutlineInputBorder()),
                    ),
                  ),
                ],
              ),
            ),
          Text(
            tr('Android checks a few times a day in the background. iPhone checks when you open the app.'),
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          FilledButton(onPressed: _save, child: Text(tr('Save'))),
        ],
      ),
    );
  }
}
