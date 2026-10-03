import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../data/models.dart';
import '../l10n/l10n.dart';
import '../services/export_excel.dart';
import '../state/app_state.dart';
import '../util/format.dart';
import 'widgets.dart';

/// Shares an Excel file made by [make]; shows a message if it fails.
Future<void> shareExcel(BuildContext context, Future<String> Function() make) async {
  try {
    final path = await make();
    await Share.shareXFiles([XFile(path)]);
  } catch (e) {
    if (context.mounted) showSnack(context, tr('Could not export: $e'));
  }
}

enum _Range { thisMonth, lastMonth, thisYear, lastYear, all, custom }

/// Settings → Export to Excel: transactions for a period.
class ExportScreen extends StatefulWidget {
  const ExportScreen({super.key});

  @override
  State<ExportScreen> createState() => _ExportScreenState();
}

class _ExportScreenState extends State<ExportScreen> {
  _Range _range = _Range.thisMonth;
  DateTime? _from;
  DateTime? _to;
  int? _account;
  final Set<TxType> _types = {TxType.expense, TxType.income, TxType.transfer};
  bool _busy = false;

  (DateTime, DateTime) _period() {
    final n = DateTime.now();
    switch (_range) {
      case _Range.thisMonth:
        return (DateTime(n.year, n.month, 1), DateTime(n.year, n.month + 1, 1));
      case _Range.lastMonth:
        return (DateTime(n.year, n.month - 1, 1), DateTime(n.year, n.month, 1));
      case _Range.thisYear:
        return (DateTime(n.year, 1, 1), DateTime(n.year + 1, 1, 1));
      case _Range.lastYear:
        return (DateTime(n.year - 1, 1, 1), DateTime(n.year, 1, 1));
      case _Range.all:
        return (DateTime(2000), DateTime(n.year + 50));
      case _Range.custom:
        final f = _from ?? DateTime(n.year, n.month, 1);
        final t = _to ?? n;
        return (DateTime(f.year, f.month, f.day), DateTime(t.year, t.month, t.day + 1));
    }
  }

  Future<void> _pickRange() async {
    final n = DateTime.now();
    final r = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(n.year + 5),
      initialDateRange: _from == null || _to == null
          ? DateTimeRange(start: DateTime(n.year, n.month, 1), end: n)
          : DateTimeRange(start: _from!, end: _to!),
    );
    if (r != null) {
      setState(() {
        _range = _Range.custom;
        _from = r.start;
        _to = r.end;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final (from, to) = _period();
    String label(_Range r) => switch (r) {
          _Range.thisMonth => tr('This month'),
          _Range.lastMonth => tr('Last month'),
          _Range.thisYear => tr('This year'),
          _Range.lastYear => tr('Last year'),
          _Range.all => tr('Everything'),
          _Range.custom => _range == _Range.custom
              ? '${shortDateFmt.format(from)} – ${shortDateFmt.format(to.subtract(const Duration(days: 1)))}'
              : tr('Choose dates…'),
        };
    return Scaffold(
      appBar: AppBar(title: Text(tr('Export to Excel'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(tr('Period'), style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final r in _Range.values)
                ChoiceChip(
                  label: Text(label(r)),
                  selected: _range == r,
                  onSelected: (_) => r == _Range.custom
                      ? _pickRange()
                      : setState(() => _range = r),
                ),
            ],
          ),
          const SizedBox(height: 16),
          LabeledDropdown<int>(
            label: tr('Account'),
            value: _account ?? -1,
            items: [
              DropdownMenuItem(value: -1, child: Text(tr('All accounts'))),
              for (final a in state.accounts)
                DropdownMenuItem(
                    value: a.id!, child: Text(a.fullName, overflow: TextOverflow.ellipsis)),
            ],
            onChanged: (v) => setState(() => _account = v == null || v == -1 ? null : v),
          ),
          const SizedBox(height: 16),
          Text(tr('Include'), style: Theme.of(context).textTheme.titleSmall),
          Wrap(
            spacing: 8,
            children: [
              for (final t in TxType.values)
                FilterChip(
                  label: Text(t.label),
                  selected: _types.contains(t),
                  onSelected: (v) => setState(() => v ? _types.add(t) : _types.remove(t)),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            tr('The file has a Transactions sheet (with amounts in your main currency, tags and notes) and a Summary sheet by category and by month.'),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            icon: _busy
                ? const SizedBox(
                    width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.table_view_outlined),
            label: Text(tr('Export')),
            onPressed: _busy || _types.isEmpty
                ? null
                : () async {
                    setState(() => _busy = true);
                    await shareExcel(
                        context,
                        () => ExcelExport.transactions(state,
                            from: from, to: to, accountId: _account, types: {..._types}));
                    if (mounted) setState(() => _busy = false);
                  },
          ),
        ],
      ),
    );
  }
}
