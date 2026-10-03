import 'package:flutter/material.dart';

import '../data/models.dart';
import '../l10n/l10n.dart';
import '../state/app_state.dart';
import '../util/format.dart';
import 'charts.dart';
import 'transaction_edit.dart';
import 'widgets.dart';

/// Spending per tag (a trip, an event…): total, dates and entries.
class _TagSum {
  _TagSum(this.tag);
  final String tag;
  double spent = 0;
  double income = 0;
  int count = 0;
  DateTime? first;
  DateTime? last;
}

Future<List<_TagSum>> _sums(AppState state) async {
  final out = <_TagSum>[];
  for (final tag in state.allTags) {
    final s = _TagSum(tag);
    for (final t in await state.db.txnsWithTag(tag)) {
      final cur = state.accountById(t.accountId)?.currency ?? state.baseCurrency;
      final v = state.toBase(t.amount, cur);
      if (t.type == TxType.expense) s.spent += v;
      if (t.type == TxType.income) s.income += v;
      s.count++;
      if (s.first == null || t.date.isBefore(s.first!)) s.first = t.date;
      if (s.last == null || t.date.isAfter(s.last!)) s.last = t.date;
    }
    if (s.count > 0) out.add(s);
  }
  out.sort((a, b) => (b.last ?? DateTime(0)).compareTo(a.last ?? DateTime(0)));
  return out;
}

String _range(DateTime? a, DateTime? b) {
  if (a == null || b == null) return '';
  if (a.year == b.year && a.month == b.month && a.day == b.day) {
    return shortDateFmt.format(a);
  }
  return '${shortDateFmt.format(a)} – ${shortDateFmt.format(b)}';
}

class TagsScreen extends StatefulWidget {
  const TagsScreen({super.key});

  @override
  State<TagsScreen> createState() => _TagsScreenState();
}

class _TagsScreenState extends State<TagsScreen> {
  Future<List<_TagSum>>? _future;
  int _version = -1;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    if (_version != state.version) {
      _version = state.version;
      _future = _sums(state);
    }
    final base = state.baseCurrency;
    return Scaffold(
      appBar: AppBar(title: Text(tr('Tags'))),
      body: FutureBuilder<List<_TagSum>>(
        future: _future,
        builder: (context, snap) {
          final list = snap.data;
          if (list == null) {
            return const Center(child: CircularProgressIndicator());
          }
          if (list.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  tr('No tags yet. Add tags such as a trip or an event when you enter an expense, then see their totals here.'),
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 32),
            children: [
              for (final s in list)
                Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: const Icon(Icons.sell_outlined),
                    title: Text(s.tag),
                    subtitle: Text(
                        '${_range(s.first, s.last)} · ${tr('${s.count} entries')}'),
                    trailing: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(fmtMoney(s.spent, base),
                            style: const TextStyle(fontWeight: FontWeight.w600)),
                        if (s.income > 0.004)
                          Text('+${fmtMoney(s.income, base)}',
                              style: Theme.of(context).textTheme.bodySmall),
                      ],
                    ),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => TagDetailScreen(tag: s.tag)),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// One tag: total, by category, and its entries.
class TagDetailScreen extends StatefulWidget {
  const TagDetailScreen({super.key, required this.tag});
  final String tag;

  @override
  State<TagDetailScreen> createState() => _TagDetailScreenState();
}

class _TagDetailScreenState extends State<TagDetailScreen> {
  Future<List<Txn>>? _future;
  int _version = -1;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    if (_version != state.version) {
      _version = state.version;
      _future = state.db.txnsWithTag(widget.tag);
    }
    final base = state.baseCurrency;
    return Scaffold(
      appBar: AppBar(title: Text('#${widget.tag}')),
      body: FutureBuilder<List<Txn>>(
        future: _future,
        builder: (context, snap) {
          final txns = snap.data;
          if (txns == null) return const Center(child: CircularProgressIndicator());
          var spent = 0.0;
          final byCat = <int?, double>{};
          DateTime? first, last;
          for (final t in txns) {
            if (first == null || t.date.isBefore(first)) first = t.date;
            if (last == null || t.date.isAfter(last)) last = t.date;
            if (t.type != TxType.expense) continue;
            final v = state.toBase(
                t.amount, state.accountById(t.accountId)?.currency ?? base);
            spent += v;
            byCat[t.categoryId] = (byCat[t.categoryId] ?? 0) + v;
          }
          final theme = Theme.of(context);
          return ListView(
            padding: const EdgeInsets.only(bottom: 32),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(tr('Spent'), style: theme.textTheme.bodySmall),
                    Text(fmtMoney(spent, base),
                        style: theme.textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.bold)),
                    Text('${_range(first, last)} · ${tr('${txns.length} entries')}',
                        style: theme.textTheme.bodySmall),
                  ],
                ),
              ),
              if (byCat.length > 1)
                DonutChart(
                  currency: base,
                  slices: [
                    for (final e in byCat.entries)
                      Slice(state.categoryById(e.key)?.name ?? tr('No category'), e.value),
                  ],
                ),
              const Divider(),
              for (final t in txns)
                TxnTile(
                  txn: t,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => TransactionEditScreen(txn: t)),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
