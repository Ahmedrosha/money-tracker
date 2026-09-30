import 'dart:async';

import 'package:flutter/material.dart';

import '../data/db.dart';
import '../data/models.dart';
import '../state/app_state.dart';
import '../util/format.dart';
import 'transaction_edit.dart';
import 'widgets.dart';
import '../l10n/l10n.dart';

enum _Range { any, thisMonth, thisYear, last12, custom }

/// Search across every transaction, including archived accounts.
class SearchScreen extends StatefulWidget {
  const SearchScreen(
      {super.key, this.initialQuery, this.initialType, this.initialAccountId});

  /// Search inside this account only (can be cleared).
  final int? initialAccountId;

  /// Opens with this text (e.g. a payee) already searched.
  final String? initialQuery;
  final TxType? initialType;

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _ctrl = TextEditingController();
  Timer? _debounce;

  TxType? _type;
  _Range _range = _Range.any;
  DateTimeRange? _custom;
  int? _accountId;
  int? _categoryId;

  Future<SearchResult>? _future;
  String _lastKey = '';

  @override
  void initState() {
    super.initState();
    _ctrl.text = widget.initialQuery ?? '';
    _type = widget.initialType;
    _accountId = widget.initialAccountId;
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  bool get _hasCriteria =>
      _ctrl.text.trim().isNotEmpty ||
      _type != null ||
      _range != _Range.any ||
      _accountId != null ||
      _categoryId != null;

  (DateTime?, DateTime?) get _dates {
    final now = DateTime.now();
    switch (_range) {
      case _Range.any:
        return (null, null);
      case _Range.thisMonth:
        return (DateTime(now.year, now.month), DateTime(now.year, now.month + 1));
      case _Range.thisYear:
        return (DateTime(now.year), DateTime(now.year + 1));
      case _Range.last12:
        return (DateTime(now.year - 1, now.month, now.day),
            DateTime(now.year, now.month, now.day + 1));
      case _Range.custom:
        final r = _custom!;
        return (r.start, DateTime(r.end.year, r.end.month, r.end.day + 1));
    }
  }

  void _run(AppState state) {
    final key = [
      state.version, _ctrl.text.trim(), _type, _range, _custom, _accountId,
      _categoryId
    ].join('|');
    if (key == _lastKey) return;
    _lastKey = key;
    if (!_hasCriteria) {
      _future = null;
      return;
    }
    final (from, to) = _dates;
    _future = state.db.search(
      query: _ctrl.text,
      type: _type,
      from: from,
      to: to,
      accountId: _accountId,
      categoryId: _categoryId,
    );
  }

  String get _rangeLabel {
    switch (_range) {
      case _Range.any:
        return tr('Any time');
      case _Range.thisMonth:
        return tr('This Month');
      case _Range.thisYear:
        return tr('This Year');
      case _Range.last12:
        return tr('Last 12 Months');
      case _Range.custom:
        return '${shortDateFmt.format(_custom!.start)} – ${shortDateFmt.format(_custom!.end)}';
    }
  }

  Future<void> _pickRange() async {
    final choice = await showModalBottomSheet<_Range>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final (r, label) in [
              (_Range.any, tr('Any time')),
              (_Range.thisMonth, tr('This Month')),
              (_Range.thisYear, tr('This Year')),
              (_Range.last12, tr('Last 12 Months')),
              (_Range.custom, tr('Choose Dates…')),
            ])
              ListTile(
                title: Text(label),
                trailing: r == _range ? const Icon(Icons.check) : null,
                onTap: () => Navigator.pop(ctx, r),
              ),
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return;
    if (choice == _Range.custom) {
      final r = await showDateRangePicker(
        context: context,
        firstDate: DateTime(2000),
        lastDate: DateTime(2100),
        initialDateRange: _custom,
      );
      if (r == null) return;
      setState(() {
        _custom = r;
        _range = _Range.custom;
      });
    } else {
      setState(() => _range = choice);
    }
  }

  Future<void> _pickType() async {
    final choice = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
                title: Text(tr('All Types')),
                onTap: () => Navigator.pop(ctx, -1)),
            for (final t in TxType.values)
              ListTile(
                title: Text(t.label),
                trailing: t == _type ? const Icon(Icons.check) : null,
                onTap: () => Navigator.pop(ctx, t.index),
              ),
          ],
        ),
      ),
    );
    if (choice == null) return;
    setState(() {
      _type = choice == -1 ? null : TxType.values[choice];
      final c = AppScope.read(context).categoryById(_categoryId);
      if (c != null && _type != null && c.kind != _type) _categoryId = null;
    });
  }

  Widget _chip(String label, bool active, VoidCallback onTap,
      {VoidCallback? onClear}) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: InputChip(
        label: Text(label, overflow: TextOverflow.ellipsis),
        selected: active,
        onPressed: onTap,
        onDeleted: active ? onClear : null,
        showCheckmark: false,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    _run(state);
    final account = state.accountById(_accountId);
    final category = state.categoryById(_categoryId);

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: TextField(
          controller: _ctrl,
          autofocus: widget.initialQuery == null,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: tr('Search payee, note, category, account, amount'),
            border: InputBorder.none,
            suffixIcon: _ctrl.text.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () => setState(_ctrl.clear),
                  ),
          ),
          onChanged: (_) {
            _debounce?.cancel();
            _debounce = Timer(
                const Duration(milliseconds: 300), () => setState(() {}));
          },
          onSubmitted: (_) => setState(() {}),
        ),
      ),
      body: Column(
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: Row(
              children: [
                _chip(_type?.label ?? tr('Type'), _type != null, _pickType,
                    onClear: () => setState(() => _type = null)),
                _chip(_rangeLabel, _range != _Range.any, _pickRange,
                    onClear: () => setState(() => _range = _Range.any)),
                _chip(account?.fullName ?? tr('Account'), account != null,
                    () async {
                  final id = await pickAccount(context,
                      current: _accountId,
                      title: tr('Filter by Account'),
                      allowAll: true,
                      includeArchived: true);
                  if (id != null) {
                    setState(() => _accountId = id == -1 ? null : id);
                  }
                }, onClear: () => setState(() => _accountId = null)),
                _chip(category?.name ?? tr('Category'), category != null,
                    () async {
                  final id = await pickCategory(context,
                      kind: _type == TxType.income
                          ? TxType.income
                          : TxType.expense,
                      current: _categoryId);
                  if (id != null) {
                    setState(() => _categoryId = id == -1 ? null : id);
                  }
                }, onClear: () => setState(() => _categoryId = null)),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(child: _results(state)),
        ],
      ),
    );
  }

  Widget _results(AppState state) {
    if (_future == null) {
      return Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text(
            tr('Search all your transactions since the first one, '
            'including archived accounts.\n\n'
            'Several words narrow it down, e.g. "fuel platinum".'),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    return FutureBuilder<SearchResult>(
      future: _future,
      builder: (context, snap) {
        if (snap.hasError) {
          return Center(child: Text(tr('Search failed: ${snap.error}')));
        }
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final res = snap.data!;
        if (res.count == 0) {
          return Center(child: Text(tr('No matching transactions')));
        }

        double sum(String type) {
          var v = 0.0;
          res.totals[type]?.forEach((cur, amt) => v += state.toBase(amt, cur));
          return v;
        }

        final spent = sum('expense');
        final received = sum('income');
        final base = state.baseCurrency;

        final rows = <Widget>[
          Container(
            width: double.infinity,
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
            child: Text(
              [
                tr('${res.count} result${res.count == 1 ? '' : 's'}'),
                if (spent != 0) tr('spent ${fmtMoney(spent, base)}'),
                if (received != 0) tr('received ${fmtMoney(received, base)}'),
              ].join(' · '),
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
        ];
        String? month;
        for (final t in res.txns) {
          final m = monthFmt.format(t.date);
          if (m != month) {
            month = m;
            rows.add(Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Text(m,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: Theme.of(context).colorScheme.primary)),
            ));
          }
          rows.add(TxnTile(
            txn: t,
            perspectiveAccountId: _accountId,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => TransactionEditScreen(txn: t)),
            ),
          ));
          rows.add(Padding(
            padding: const EdgeInsets.fromLTRB(72, 0, 16, 6),
            child: Text(shortDateFmt.format(t.date),
                style: Theme.of(context).textTheme.bodySmall),
          ));
        }
        if (res.count > res.txns.length) {
          rows.add(Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              tr('Showing the newest ${res.txns.length} of ${res.count}. '
              'Add a word or a filter to narrow it down.'),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ));
        }
        return ListView(
            padding: const EdgeInsets.only(bottom: 32), children: rows);
      },
    );
  }
}
