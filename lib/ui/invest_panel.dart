import 'package:flutter/material.dart';

import '../data/models.dart';
import '../state/app_state.dart';
import '../util/format.dart';
import 'transaction_edit.dart';
import 'widgets.dart';
import '../l10n/l10n.dart';

String _qty(double q) =>
    q == q.roundToDouble() ? q.toStringAsFixed(0) : q.toStringAsFixed(8).replaceFirst(RegExp(r'0+$'), '');

String _pct(double gain, double base) =>
    base.abs() < 0.01 ? '' : ' (${gain >= 0 ? '+' : ''}${(gain / base * 100).toStringAsFixed(1)}%)';

/// Portfolio summary for an investment account (stocks or total value).
class InvestPanel extends StatelessWidget {
  const InvestPanel({super.key, required this.account});

  final Account account;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    return FutureBuilder<double>(
      key: ValueKey('${state.version}-${account.id}'),
      future: state.invested(account),
      builder: (context, snap) {
        final invested = snap.data;
        return account.investMode == 'simple'
            ? _simple(context, state, invested)
            : _holdings(context, state, invested);
      },
    );
  }

  Widget _card(BuildContext context, List<Widget> children) => Card(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: children),
        ),
      );

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

  Widget _gainRow(BuildContext context, double worth, double? invested) {
    if (invested == null) return const SizedBox.shrink();
    final g = worth - invested;
    return _row(tr('Profit / Loss'),
        '${g >= 0 ? '+' : ''}${fmtMoney(g, account.currency)}${_pct(g, invested)}',
        bold: true, color: amountColor(context, g));
  }

  // ----- Total value mode -----

  Widget _simple(BuildContext context, AppState state, double? invested) {
    final cur = account.currency;
    final small = Theme.of(context).textTheme.bodySmall;
    return _card(context, [
      Text(tr('Portfolio'), style: Theme.of(context).textTheme.titleSmall),
      const SizedBox(height: 8),
      if (account.investValue == null)
        Text(tr('Tap Update Value and type the total your broker shows.'), style: small)
      else ...[
        _row(tr('Portfolio value'), fmtMoney(account.worth, cur), bold: true),
        if (invested != null) _row(tr('Money invested'), fmtMoney(invested, cur)),
        _gainRow(context, account.worth, invested),
        const SizedBox(height: 4),
        Text(
            tr('Value entered ${shortDateFmt.format(account.investValueAt!)}'
            '${(account.balance - (account.investBase ?? account.balance)).abs() > 0.004 ? tr(', plus deposits/withdrawals since') : ''}'),
            style: small),
      ],
      const SizedBox(height: 8),
      FilledButton.tonalIcon(
        icon: const Icon(Icons.edit_outlined),
        label: Text(tr('Update Value')),
        onPressed: () async {
          final v = await _askAmount(context, tr('Portfolio Value'),
              tr('Total shown by your broker today'), cur,
              initial: account.investValue == null ? null : account.worth);
          if (v != null) await state.setInvestValue(account, v);
        },
      ),
    ]);
  }

  // ----- Stocks mode -----

  Widget _holdings(BuildContext context, AppState state, double? invested) {
    final cur = account.currency;
    final crypto = account.type == AccountType.crypto;
    final hs = state.holdings(account.id!);
    final small = Theme.of(context).textTheme.bodySmall;
    final holdValue = hs.fold<double>(0, (s, h) => s + h.value);
    final cash = state.portfolioCash(account);
    final latest = hs
        .where((h) => h.priceAt != null && !h.manualPrice)
        .map((h) => h.priceAt!)
        .fold<DateTime?>(null, (m, d) => m == null || d.isAfter(m) ? d : m);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _card(context, [
          Row(children: [
            Expanded(
                child: Text(tr('Portfolio'), style: Theme.of(context).textTheme.titleSmall)),
            state.refreshingStocks
                ? const SizedBox(
                    width: 18, height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : IconButton(
                    tooltip: tr('Refresh Prices'),
                    icon: const Icon(Icons.refresh),
                    onPressed: () async {
                      final n = await state.refreshStockPrices();
                      if (context.mounted) {
                        showSnack(context, n > 0
                            ? tr('Updated $n price${n == 1 ? '' : 's'}')
                            : tr('No new prices (offline, or set them by hand)'));
                      }
                    },
                  ),
          ]),
          _row(tr('Portfolio value'), fmtMoney(account.worth, cur), bold: true),
          _row(crypto ? tr('Coins') : tr('Stocks'), fmtMoney(holdValue, cur)),
          _row(tr('Cash'), fmtMoney(cash, cur)),
          if (invested != null) _row(tr('Money invested'), fmtMoney(invested, cur)),
          _gainRow(context, account.worth, invested),
          if (latest != null)
            Text(tr('Prices from ${crypto ? 'Binance' : tr('Yahoo Finance')}, ${shortDateFmt.format(latest)} '
                '${TimeOfDay.fromDateTime(latest).format(context)}'),
                style: small),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            FilledButton.tonalIcon(
              icon: const Icon(Icons.add),
              label: Text(tr('Buy')),
              onPressed: () => showTradeSheet(context, account, buy: true),
            ),
            FilledButton.tonalIcon(
              icon: const Icon(Icons.remove),
              label: Text(tr('Sell')),
              onPressed: hs.isEmpty
                  ? null
                  : () => showTradeSheet(context, account, buy: false),
            ),
            OutlinedButton.icon(
              icon: const Icon(Icons.payments_outlined),
              label: Text(crypto ? tr('Reward') : tr('Dividend')),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => TransactionEditScreen(
                    initialAccountId: account.id,
                    initialType: TxType.income,
                    initialNote: crypto ? tr('Staking / earn reward') : tr('Dividend'),
                  ),
                ),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => TradesScreen(accountId: account.id!)),
              ),
              child: Text(tr('Trades')),
            ),
          ]),
        ]),
        if (hs.isNotEmpty)
          Card(
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Column(
              children: [
                for (final h in hs)
                  ListTile(
                    title: Row(children: [
                      Expanded(
                          child: Text(h.symbol,
                              style: const TextStyle(fontWeight: FontWeight.w600))),
                      Text(fmtAmount(h.value),
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                    ]),
                    subtitle: Row(children: [
                      Expanded(
                        child: Text(
                          tr('${_qty(h.qty)} × ${h.price == null ? '—' : fmtAmount(h.price!)}'
                          '${h.manualPrice ? tr(' (your price)') : ''} · avg ${fmtAmount(h.avgCost)}'),
                        ),
                      ),
                      Text(
                        '${h.gain >= 0 ? '+' : ''}${fmtAmount(h.gain)}${_pct(h.gain, h.cost)}',
                        style: TextStyle(color: amountColor(context, h.gain)),
                      ),
                    ]),
                    onTap: () => _holdingActions(context, state, h),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  Future<void> _holdingActions(
      BuildContext context, AppState state, Holding h) async {
    final c = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            title: Text(h.symbol, style: Theme.of(ctx).textTheme.titleMedium),
            subtitle: Text(tr('${_qty(h.qty)} ${account.type == AccountType.crypto ? h.symbol : 'shares'} · cost ${fmtMoney(h.cost, account.currency)}')),
          ),
          ListTile(
              leading: const Icon(Icons.add),
              title: Text(tr('Buy More')),
              onTap: () => Navigator.pop(ctx, 'buy')),
          ListTile(
              leading: const Icon(Icons.remove),
              title: Text(tr('Sell')),
              onTap: () => Navigator.pop(ctx, 'sell')),
          ListTile(
              leading: const Icon(Icons.price_change_outlined),
              title: Text(tr('Set Price')),
              subtitle: Text(tr('Kept until you choose the live price again')),
              onTap: () => Navigator.pop(ctx, 'price')),
          if (h.manualPrice)
            ListTile(
                leading: const Icon(Icons.cloud_sync_outlined),
                title: Text(tr('Use Live Price')),
                onTap: () => Navigator.pop(ctx, 'live')),
        ]),
      ),
    );
    if (c == null || !context.mounted) return;
    switch (c) {
      case 'buy':
        await showTradeSheet(context, account, buy: true, symbol: h.symbol);
      case 'sell':
        await showTradeSheet(context, account, buy: false, symbol: h.symbol);
      case 'price':
        final v = await _askAmount(context, tr('${h.symbol} Price'),
            account.type == AccountType.crypto ? tr('Price per coin') : tr('Price per share'),
            account.currency, initial: h.price);
        if (v != null) await state.setStockPrice(account, h.symbol, v);
      case 'live':
        await state.clearManualStockPrice(account, h.symbol);
    }
  }
}

Future<double?> _askAmount(BuildContext context, String title, String label,
    String cur, {double? initial}) async {
  final ctrl = TextEditingController(
      text: initial == null ? '' : initial.toStringAsFixed(2));
  final r = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: ctrl,
        autofocus: true,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(
            labelText: label, suffixText: cur, border: const OutlineInputBorder()),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Cancel'))),
        FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text), child: Text(tr('Save'))),
      ],
    ),
  );
  if (r == null) return null;
  final v = parseAmount(r);
  return v == null || v < 0 ? null : v;
}

/// Buy or sell form.
Future<void> showTradeSheet(BuildContext context, Account account,
    {required bool buy, String? symbol}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
      child: _TradeForm(account: account, buy: buy, symbol: symbol),
    ),
  );
}

class _TradeForm extends StatefulWidget {
  const _TradeForm({required this.account, required this.buy, this.symbol});

  final Account account;
  final bool buy;
  final String? symbol;

  @override
  State<_TradeForm> createState() => _TradeFormState();
}

class _TradeFormState extends State<_TradeForm> {
  late bool _buy = widget.buy;
  late final _symbol = TextEditingController(text: widget.symbol ?? '');
  final _qtyC = TextEditingController();
  final _price = TextEditingController();
  final _fees = TextEditingController();
  DateTime _date = DateTime.now();
  bool _saving = false;

  @override
  void dispose() {
    for (final c in [_symbol, _qtyC, _price, _fees]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final cur = widget.account.currency;
    final crypto = widget.account.type == AccountType.crypto;
    final held = state.holdings(widget.account.id!);
    final qty = parseAmount(_qtyC.text) ?? 0;
    final price = parseAmount(_price.text) ?? 0;
    final fees = parseAmount(_fees.text) ?? 0;
    final total = qty * price + (_buy ? fees : -fees);
    final h = held.where((h) => h.symbol == _symbol.text.trim().toUpperCase()).firstOrNull;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SegmentedButton<bool>(
              segments: [
                ButtonSegment(value: true, label: Text(tr('Buy'))),
                ButtonSegment(value: false, label: Text(tr('Sell'))),
              ],
              selected: {_buy},
              onSelectionChanged: (v) => setState(() => _buy = v.first),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _symbol,
              textCapitalization: TextCapitalization.characters,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: crypto ? tr('Coin') : tr('Stock Symbol'),
                hintText: crypto ? tr('e.g. BTC, ETH, SOL') : tr('e.g. COMI, TMGH, FWRY'),
                border: const OutlineInputBorder(),
              ),
            ),
            if (held.isNotEmpty) ...[
              const SizedBox(height: 6),
              Wrap(spacing: 6, children: [
                for (final x in held)
                  ActionChip(
                    label: Text(x.symbol),
                    onPressed: () => setState(() => _symbol.text = x.symbol),
                  ),
              ]),
            ],
            if (!_buy && h != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(tr('You hold ${_qty(h.qty)} · average ${fmtAmount(h.avgCost)}'),
                    style: Theme.of(context).textTheme.bodySmall),
              ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _qtyC,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                      labelText: crypto ? tr('Amount') : tr('Shares'),
                      border: const OutlineInputBorder()),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _price,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                      labelText: crypto ? tr('Price per Coin') : tr('Price per Share'),
                      suffixText: cur,
                      border: const OutlineInputBorder()),
                ),
              ),
            ]),
            const SizedBox(height: 12),
            TextField(
              controller: _fees,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                  labelText: tr('Fees (commission)'),
                  suffixText: cur,
                  border: const OutlineInputBorder()),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event),
              title: Text(tr('Date')),
              subtitle: Text(dayFmt.format(_date)),
              onTap: () async {
                final d = await showDatePicker(
                    context: context,
                    initialDate: _date,
                    firstDate: DateTime(2000),
                    lastDate: DateTime.now());
                if (d != null) setState(() => _date = DateTime(d.year, d.month, d.day, 12));
              },
            ),
            if (qty > 0 && price > 0)
              Text(
                  '${_buy ? tr('Total paid') : tr('You receive')} ${fmtMoneyRaw(total, cur)}'
                  '${!_buy && h != null ? tr(' · profit ${fmtAmountRaw((price - h.avgCost) * qty)}') : ''}',
                  style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _saving
                  ? null
                  : () async {
                      final sym = _symbol.text.trim().toUpperCase();
                      if (sym.isEmpty || qty <= 0 || price <= 0) {
                        showSnack(context,
                            crypto ? tr('Enter the coin, amount and price') : tr('Enter the symbol, shares and price'));
                        return;
                      }
                      setState(() => _saving = true);
                      try {
                        await state.addTrade(
                            widget.account, sym, _buy, qty, price, fees.abs(), _date);
                        if (context.mounted) Navigator.pop(context);
                      } catch (e) {
                        setState(() => _saving = false);
                        if (context.mounted) {
                          showSnack(context, e.toString().replaceFirst('Exception: ', ''));
                        }
                      }
                    },
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(_buy ? tr('Record Buy') : tr('Record Sell')),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// All buys and sells of an account; long-press to delete one.
class TradesScreen extends StatelessWidget {
  const TradesScreen({super.key, required this.accountId});

  final int accountId;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final a = state.accountById(accountId);
    final list = state.trades.where((t) => t.accountId == accountId).toList().reversed.toList();
    return Scaffold(
      appBar: AppBar(title: Text(tr('${a?.name ?? ''} Trades'))),
      body: list.isEmpty
          ? Center(child: Text(tr('No trades yet')))
          : ListView.separated(
              itemCount: list.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final t = list[i];
                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: (t.buy ? kExpenseColor : kIncomeColor).withValues(alpha: 0.15),
                    child: Text(t.buy ? 'B' : 'S',
                        style: TextStyle(color: t.buy ? kExpenseColor : kIncomeColor)),
                  ),
                  title: Text('${t.buy ? tr('Buy') : tr('Sell')} ${_qty(t.qty)} ${t.symbol} @ ${fmtAmount(t.price)}'),
                  subtitle: Text('${shortDateFmt.format(t.date)}'
                      '${t.fees > 0 ? tr(' · fees ${fmtAmount(t.fees)}') : ''}'
                      '${!t.buy ? tr(' · profit ${fmtAmount(t.realized)}') : ''}'),
                  trailing: Text(fmtAmount(t.qty * t.price)),
                  onLongPress: () async {
                    final ok = await confirmDialog(context,
                        title: tr('Delete this trade?'),
                        message: tr('Its fee and profit entries are removed too.'));
                    if (ok) await state.deleteTrade(t);
                  },
                );
              },
            ),
    );
  }
}
