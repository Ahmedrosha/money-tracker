import 'package:flutter/material.dart';

import '../data/models.dart';
import '../state/app_state.dart';
import '../util/format.dart';
import 'transaction_edit.dart';
import 'widgets.dart';

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
    return _row('Profit / Loss',
        '${g >= 0 ? '+' : ''}${fmtMoney(g, account.currency)}${_pct(g, invested)}',
        bold: true, color: amountColor(context, g));
  }

  // ----- Total value mode -----

  Widget _simple(BuildContext context, AppState state, double? invested) {
    final cur = account.currency;
    final small = Theme.of(context).textTheme.bodySmall;
    return _card(context, [
      Text('Portfolio', style: Theme.of(context).textTheme.titleSmall),
      const SizedBox(height: 8),
      if (account.investValue == null)
        Text('Tap Update Value and type the total your broker shows.', style: small)
      else ...[
        _row('Portfolio value', fmtMoney(account.worth, cur), bold: true),
        if (invested != null) _row('Money invested', fmtMoney(invested, cur)),
        _gainRow(context, account.worth, invested),
        const SizedBox(height: 4),
        Text(
            'Value entered ${shortDateFmt.format(account.investValueAt!)}'
            '${(account.balance - (account.investBase ?? account.balance)).abs() > 0.004 ? ', plus deposits/withdrawals since' : ''}',
            style: small),
      ],
      const SizedBox(height: 8),
      FilledButton.tonalIcon(
        icon: const Icon(Icons.edit_outlined),
        label: const Text('Update Value'),
        onPressed: () async {
          final v = await _askAmount(context, 'Portfolio Value',
              'Total shown by your broker today', cur,
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
                child: Text('Portfolio', style: Theme.of(context).textTheme.titleSmall)),
            state.refreshingStocks
                ? const SizedBox(
                    width: 18, height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : IconButton(
                    tooltip: 'Refresh Prices',
                    icon: const Icon(Icons.refresh),
                    onPressed: () async {
                      final n = await state.refreshStockPrices();
                      if (context.mounted) {
                        showSnack(context, n > 0
                            ? 'Updated $n price${n == 1 ? '' : 's'}'
                            : 'No new prices (offline, or set them by hand)');
                      }
                    },
                  ),
          ]),
          _row('Portfolio value', fmtMoney(account.worth, cur), bold: true),
          _row(crypto ? 'Coins' : 'Stocks', fmtMoney(holdValue, cur)),
          _row('Cash', fmtMoney(cash, cur)),
          if (invested != null) _row('Money invested', fmtMoney(invested, cur)),
          _gainRow(context, account.worth, invested),
          if (latest != null)
            Text('Prices from ${crypto ? 'Binance' : 'Yahoo Finance'}, ${shortDateFmt.format(latest)} '
                '${TimeOfDay.fromDateTime(latest).format(context)}',
                style: small),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            FilledButton.tonalIcon(
              icon: const Icon(Icons.add),
              label: const Text('Buy'),
              onPressed: () => showTradeSheet(context, account, buy: true),
            ),
            FilledButton.tonalIcon(
              icon: const Icon(Icons.remove),
              label: const Text('Sell'),
              onPressed: hs.isEmpty
                  ? null
                  : () => showTradeSheet(context, account, buy: false),
            ),
            OutlinedButton.icon(
              icon: const Icon(Icons.payments_outlined),
              label: Text(crypto ? 'Reward' : 'Dividend'),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => TransactionEditScreen(
                    initialAccountId: account.id,
                    initialType: TxType.income,
                    initialNote: crypto ? 'Staking / earn reward' : 'Dividend',
                  ),
                ),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => TradesScreen(accountId: account.id!)),
              ),
              child: const Text('Trades'),
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
                          '${_qty(h.qty)} × ${h.price == null ? '—' : fmtAmount(h.price!)}'
                          '${h.manualPrice ? ' (your price)' : ''} · avg ${fmtAmount(h.avgCost)}',
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
            subtitle: Text('${_qty(h.qty)} ${account.type == AccountType.crypto ? h.symbol : 'shares'} · cost ${fmtMoney(h.cost, account.currency)}'),
          ),
          ListTile(
              leading: const Icon(Icons.add),
              title: const Text('Buy More'),
              onTap: () => Navigator.pop(ctx, 'buy')),
          ListTile(
              leading: const Icon(Icons.remove),
              title: const Text('Sell'),
              onTap: () => Navigator.pop(ctx, 'sell')),
          ListTile(
              leading: const Icon(Icons.price_change_outlined),
              title: const Text('Set Price'),
              subtitle: const Text('Kept until you choose the live price again'),
              onTap: () => Navigator.pop(ctx, 'price')),
          if (h.manualPrice)
            ListTile(
                leading: const Icon(Icons.cloud_sync_outlined),
                title: const Text('Use Live Price'),
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
        final v = await _askAmount(context, '${h.symbol} Price',
            account.type == AccountType.crypto ? 'Price per coin' : 'Price per share',
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
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text), child: const Text('Save')),
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
              segments: const [
                ButtonSegment(value: true, label: Text('Buy')),
                ButtonSegment(value: false, label: Text('Sell')),
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
                labelText: crypto ? 'Coin' : 'Stock Symbol',
                hintText: crypto ? 'e.g. BTC, ETH, SOL' : 'e.g. COMI, TMGH, FWRY',
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
                child: Text('You hold ${_qty(h.qty)} · average ${fmtAmount(h.avgCost)}',
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
                      labelText: crypto ? 'Amount' : 'Shares',
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
                      labelText: crypto ? 'Price per Coin' : 'Price per Share',
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
                  labelText: 'Fees (commission)',
                  suffixText: cur,
                  border: const OutlineInputBorder()),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event),
              title: const Text('Date'),
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
                  '${_buy ? 'Total paid' : 'You receive'} ${fmtMoneyRaw(total, cur)}'
                  '${!_buy && h != null ? ' · profit ${fmtAmountRaw((price - h.avgCost) * qty)}' : ''}',
                  style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _saving
                  ? null
                  : () async {
                      final sym = _symbol.text.trim().toUpperCase();
                      if (sym.isEmpty || qty <= 0 || price <= 0) {
                        showSnack(context,
                            crypto ? 'Enter the coin, amount and price' : 'Enter the symbol, shares and price');
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
                child: Text(_buy ? 'Record Buy' : 'Record Sell'),
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
      appBar: AppBar(title: Text('${a?.name ?? ''} Trades')),
      body: list.isEmpty
          ? const Center(child: Text('No trades yet'))
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
                  title: Text('${t.buy ? 'Buy' : 'Sell'} ${_qty(t.qty)} ${t.symbol} @ ${fmtAmount(t.price)}'),
                  subtitle: Text('${shortDateFmt.format(t.date)}'
                      '${t.fees > 0 ? ' · fees ${fmtAmount(t.fees)}' : ''}'
                      '${!t.buy ? ' · profit ${fmtAmount(t.realized)}' : ''}'),
                  trailing: Text(fmtAmount(t.qty * t.price)),
                  onLongPress: () async {
                    final ok = await confirmDialog(context,
                        title: 'Delete this trade?',
                        message: 'Its fee and profit entries are removed too.');
                    if (ok) await state.deleteTrade(t);
                  },
                );
              },
            ),
    );
  }
}
