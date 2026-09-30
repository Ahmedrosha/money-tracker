import 'package:flutter/material.dart';

import '../state/app_state.dart';
import '../util/currencies.dart';
import '../util/format.dart';
import 'widgets.dart';
import '../l10n/l10n.dart';

class CurrenciesScreen extends StatelessWidget {
  const CurrenciesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final base = state.baseCurrency;
    final codes = <String>{...state.usedCurrencies, 'USD'}
        .where((c) => c != base)
        .toList()
      ..sort();
    final last = state.lastRateUpdate;

    return Scaffold(
      appBar: AppBar(
        title: Text(tr('Exchange Rates')),
        actions: [
          state.refreshingRates
              ? const Padding(
                  padding: EdgeInsets.all(16),
                  child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2)),
                )
              : IconButton(
                  tooltip: tr('Refresh Online Rates'),
                  icon: const Icon(Icons.refresh),
                  onPressed: () async {
                    try {
                      await state.refreshRates();
                      if (context.mounted) showSnack(context, tr('Rates updated'));
                    } catch (e) {
                      if (context.mounted) {
                        showSnack(context, tr('Could not update rates. Check internet.'));
                      }
                    }
                  },
                ),
        ],
      ),
      body: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              last == null
                  ? tr('Online rates have not been downloaded yet. Tap refresh.')
                  : tr('Online rates updated ${shortDateFmt.format(last)} '
                      '${TimeOfDay.fromDateTime(last).format(context)}. '
                      'Tap a currency to set your own rate; manual rates are kept when refreshing.'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          if (codes.isEmpty)
            Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                  tr('Add an account in another currency and it will appear here.')),
            ),
          for (final c in codes)
            _RateTile(code: c, base: base),
        ],
      ),
    );
  }
}

class _RateTile extends StatelessWidget {
  const _RateTile({required this.code, required this.base});

  final String code;
  final String base;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final r = state.rate(code, base);
    final manual = state.isManual(code);
    return ListTile(
      title: Text(isGold(code) ? currencyName(code) : '$code — ${currencyName(code)}'),
      subtitle: Text(r == null
          ? tr('No rate yet')
          : '1 ${currencyUnit(code)} = ${fmtRate(r)} $base'),
      trailing: manual
          ? Chip(
              label: Text(tr('Manual')),
              visualDensity: VisualDensity.compact,
              backgroundColor:
                  Theme.of(context).colorScheme.tertiaryContainer,
            )
          : Text(tr('Auto')),
      onTap: () => _edit(context, state, r, manual),
    );
  }

  Future<void> _edit(
      BuildContext context, AppState state, double? current, bool manual) async {
    final ctrl = TextEditingController(
        text: current == null ? '' : fmtRate(current));
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isGold(code) ? tr('Price per Gram, ${goldKarat(code)}K') : tr('Rate for $code')),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            prefixText: '1 ${currencyUnit(code)} = ',
            suffixText: base,
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          if (manual)
            TextButton(
              onPressed: () => Navigator.pop(ctx, '__auto__'),
              child: Text(tr('Use Online Rate')),
            ),
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(tr('Cancel'))),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text),
              child: Text(tr('Save'))),
        ],
      ),
    );
    if (result == null) return;
    try {
      if (result == '__auto__') {
        await state.clearManualRate(code);
      } else {
        final v = parseAmount(result);
        if (v == null || v <= 0) {
          if (context.mounted) showSnack(context, tr('Invalid rate'));
          return;
        }
        await state.setManualRate(code, v);
      }
    } catch (e) {
      if (context.mounted) showSnack(context, e.toString());
    }
  }
}
