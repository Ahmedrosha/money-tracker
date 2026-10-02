import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/models.dart';
import '../l10n/l10n.dart';
import '../services/sms_parser.dart';
import '../services/sms_reader.dart';
import '../state/app_state.dart';
import '../util/format.dart';
import 'merchant_rules_screen.dart';
import 'transaction_edit.dart';
import 'widgets.dart';

/// Bank messages waiting to become transactions: read from SMS on Android,
/// sent in by a Shortcut or pasted on iPhone.
class SmsInboxScreen extends StatefulWidget {
  const SmsInboxScreen({super.key});

  @override
  State<SmsInboxScreen> createState() => _SmsInboxScreenState();
}

class _SmsInboxScreenState extends State<SmsInboxScreen> {
  bool _available = false; // this Android build can read SMS
  bool _granted = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    final a = await SmsReader.available();
    final g = a && await SmsReader.granted();
    if (!mounted) return;
    setState(() {
      _available = a;
      _granted = g;
    });
  }

  Future<void> _paste() async {
    final state = AppScope.read(context);
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim() ?? '';
    if (!mounted) return;
    if (text.isEmpty) {
      showSnack(context, tr('Copy a bank message first, then tap Paste'));
      return;
    }
    final added = await state.addSms('', text);
    if (!mounted) return;
    if (!added) {
      showSnack(context, tr('Not a new bank transaction (already added, or a code / declined message)'));
    }
  }

  Future<void> _turnOn() async {
    final state = AppScope.read(context);
    if (!await SmsReader.request()) {
      if (mounted) {
        showSnack(context, tr('Allow SMS access in Android settings to read bank messages'));
      }
      await _check();
      return;
    }
    await _check();
    await state.setSmsAuto(true);
  }

  Future<void> _readNow() async {
    final state = AppScope.read(context);
    setState(() => _busy = true);
    final n = await state.readAndroidSms();
    if (!mounted) return;
    setState(() => _busy = false);
    showSnack(context, n == 0 ? tr('No new bank messages') : tr('$n new bank messages'));
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final items = state.smsPending;
    final noSenders = state.smsSenders.isEmpty;
    return Scaffold(
      appBar: AppBar(
        title: Text(tr('Bank Messages')),
        actions: [
          if (_available && _granted && state.smsAuto)
            IconButton(
              tooltip: tr('Check for new messages'),
              icon: _busy
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.refresh),
              onPressed: _busy ? null : _readNow,
            ),
          IconButton(
            tooltip: tr('Merchant Rules'),
            icon: const Icon(Icons.storefront_outlined),
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const MerchantRulesScreen())),
          ),
          IconButton(
            tooltip: tr('Paste a bank message'),
            icon: const Icon(Icons.content_paste),
            onPressed: _paste,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 32),
        children: [
          if (Platform.isAndroid && _available)
            Card(
              child: SwitchListTile(
                secondary: const Icon(Icons.sms_outlined),
                title: Text(tr('Read Bank SMS Automatically')),
                subtitle: Text(noSenders
                    ? tr('First add the SMS sender name (and last 4 digits) in each account\'s details.')
                    : tr('New messages from your banks\' senders are picked up when you open the app. Nothing is saved until you add it.')),
                isThreeLine: true,
                value: state.smsAuto && _granted,
                onChanged: noSenders
                    ? null
                    : (v) => v ? _turnOn() : state.setSmsAuto(false),
              ),
            ),
          if (Platform.isAndroid && !_available)
            _hint(context, Icons.info_outline,
                tr('This copy of the app (from Google Play) can\'t read SMS. Copy a bank message and tap Paste, or use the APK from GitHub.')),
          if (Platform.isIOS)
            Card(
              child: ListTile(
                leading: const Icon(Icons.bolt_outlined),
                title: Text(tr('Add Messages Automatically (Shortcuts)')),
                subtitle: Text(tr('Set up once (iOS 16+): an automation saves each bank SMS here, without opening the app.')),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _shortcutHelp(context),
              ),
            ),
          if (items.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 48, 16, 16),
              child: Column(
                children: [
                  Icon(Icons.mark_email_read_outlined,
                      size: 48,
                      color: Theme.of(context).colorScheme.onSurfaceVariant),
                  const SizedBox(height: 12),
                  Text(tr('No bank messages waiting'),
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 6),
                  Text(
                    tr('Copy a bank SMS and tap Paste at the top to add it.'),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
            )
          else
            for (final m in items) _SmsCard(item: m),
          if (state.smsDismissed.isNotEmpty) ...[
            const SizedBox(height: 8),
            InkWell(
              onTap: () => state.toggleCollapsed('smsopen:archive'),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(4, 12, 4, 8),
                child: Row(
                  children: [
                    CollapseArrow(
                        collapsed: !state.isCollapsed('smsopen:archive')),
                    const SizedBox(width: 6),
                    const Icon(Icons.archive_outlined, size: 20),
                    const SizedBox(width: 8),
                    Text(tr('Archive (${state.smsDismissed.length})'),
                        style: Theme.of(context).textTheme.titleSmall),
                  ],
                ),
              ),
            ),
            // Closed by default; the choice is remembered.
            if (state.isCollapsed('smsopen:archive'))
              for (final m in state.smsDismissed)
                _SmsCard(item: m, archived: true),
          ],
        ],
      ),
    );
  }

  Widget _hint(BuildContext context, IconData icon, String text) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 4, 4, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 20),
            const SizedBox(width: 8),
            Expanded(child: Text(text)),
          ],
        ),
      );

  void _shortcutHelp(BuildContext context) {
    final steps = [
      tr('Open the Shortcuts app → Automation → + → Message.'),
      tr('Message Contains: EGP. Choose Run Immediately, then Next.'),
      tr('Tap New Blank Automation, search "Expense" and tap Add Bank Message. Its Message is filled with the SMS automatically. Tap Done.'),
      tr('Bank SMS are now saved quietly; they wait in Bank Messages the next time you open the app. Messages without an amount are ignored.'),
      tr('Banks that send other currencies (e.g. USD): add another automation the same way with that word.'),
    ];
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(tr('Set Up the Shortcut'),
                  style: Theme.of(ctx).textTheme.titleLarge),
              const SizedBox(height: 12),
              for (var i = 0; i < steps.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CircleAvatar(radius: 12, child: Text('${i + 1}', style: const TextStyle(fontSize: 12))),
                      const SizedBox(width: 10),
                      Expanded(child: Text(steps[i])),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SmsCard extends StatefulWidget {
  const _SmsCard({required this.item, this.archived = false});

  final SmsItem item;

  /// Dismissed earlier: can be restored or still added.
  final bool archived;

  @override
  State<_SmsCard> createState() => _SmsCardState();
}

class _SmsCardState extends State<_SmsCard> {
  bool _showText = false;

  Future<void> _add(AppState state, ParsedSms p, int? accountId,
      {bool transfer = false}) async {
    final type = transfer
        ? TxType.transfer
        : (p.credit ? TxType.income : TxType.expense);
    // Choices remembered for this merchant fill the form; nothing is saved
    // until Save.
    final rule = transfer ? null : state.ruleFor(p.payee);
    var cat = rule?.categoryId;
    if (cat != null && state.categoryById(cat)?.kind != type) cat = null;
    cat ??= transfer ? null : await state.suggestCategory(
        rule != null && rule.payee.isNotEmpty ? rule.payee : p.payee, type);
    final ruleAcc = rule?.accountId;
    final acc = accountId ??
        (ruleAcc != null && state.accountById(ruleAcc) != null ? ruleAcc : null);
    if (!mounted) return;
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => TransactionEditScreen(
          initialType: type,
          // A transfer received: this account is the destination.
          initialAccountId: transfer ? null : acc,
          initialToAccountId: transfer ? acc : null,
          initialDate: p.date,
          initialAmount: p.amount,
          initialPayee: transfer
              ? null
              : (rule != null && rule.payee.isNotEmpty ? rule.payee : p.payee),
          initialCategoryId: cat,
          initialNote: p.instaPay
              ? 'InstaPay${p.ref.isEmpty ? '' : ' · Ref ${p.ref}'}${transfer && p.payee.isNotEmpty ? ' · ${p.payee}' : ''}'
              : (p.ref.isEmpty ? null : 'Ref ${p.ref}'),
          onSaved: transfer || p.payee.isEmpty
              ? null
              : (t) => state.rememberMerchant(p.payee, t),
        ),
      ),
    );
    if (saved == true) await state.setSmsStatus(widget.item.id, 'added');
  }

  /// Two messages for one movement between your accounts: one transfer.
  Future<void> _addPair(AppState state, SmsItem other, ParsedSms p,
      int fromId, int toId) async {
    final o = SmsParser.parse(other.body, received: other.receivedAt);
    final ref = p.ref.isNotEmpty ? p.ref : o.ref;
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => TransactionEditScreen(
          initialType: TxType.transfer,
          initialAccountId: fromId,
          initialToAccountId: toId,
          initialDate: p.credit ? o.date : p.date,
          initialAmount: p.amount,
          initialNote: [
            if (p.instaPay || o.instaPay) 'InstaPay',
            if (ref.isNotEmpty) 'Ref $ref',
          ].join(' · '),
        ),
      ),
    );
    if (saved == true) {
      await state.setSmsStatus(other.id, 'added');
      await state.setSmsStatus(widget.item.id, 'added');
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final m = widget.item;
    final p = SmsParser.parse(m.body, received: m.receivedAt);
    final accountId = state.smsAccountFor(p, m.sender);
    final account = state.accountById(accountId);

    if (p.statement) return _statement(context, state, p, account);

    // Does the bank's balance match the app once this is added?
    String? check;
    if (account != null && p.amount != null && account.currency == p.currency) {
      final after = account.balance + (p.credit ? p.amount! : -p.amount!);
      if (p.balance != null && (after - p.balance!).abs() > 0.5) {
        check = tr('Bank balance after: ${fmtMoney(p.balance!, p.currency)} · app after adding: ${fmtMoney(after, p.currency)}');
      } else if (p.availableLimit != null && account.creditLimit != null) {
        final avail = account.creditLimit! + after;
        if ((avail - p.availableLimit!).abs() > 0.5) {
          check = tr('Bank available limit: ${fmtMoney(p.availableLimit!, p.currency)} · app after adding: ${fmtMoney(avail, p.currency)}');
        }
      }
    }

    // Same amount out of one of your accounts and into another today.
    final pairId = widget.archived ? null : state.smsPair[m.id];
    final pair = pairId == null
        ? null
        : state.smsPending.where((x) => x.id == pairId).firstOrNull;
    int? fromId, toId;
    if (pair != null) {
      final otherAcc = state.smsAccountFor(
          SmsParser.parse(pair.body, received: pair.receivedAt), pair.sender);
      fromId = p.credit ? otherAcc : accountId;
      toId = p.credit ? accountId : otherAcc;
    }
    final dup = widget.archived ? null : state.smsDuplicate[m.id];
    final rule = state.ruleFor(p.payee);
    final shownPayee =
        rule != null && rule.payee.isNotEmpty ? rule.payee : p.payee;

    final color = p.credit ? Colors.green.shade700 : scheme.error;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 8, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(p.credit ? Icons.south_west : Icons.north_east, color: color),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        shownPayee.isNotEmpty
                            ? shownPayee
                            : (p.credit ? tr('Money in') : tr('Money out')),
                        style: theme.textTheme.titleMedium,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${dayFmt.format(p.date!)} ${p.date!.hour.toString().padLeft(2, '0')}:${p.date!.minute.toString().padLeft(2, '0')}'
                        '${m.sender.isEmpty ? '' : ' · ${m.sender}'}',
                        style: theme.textTheme.bodySmall,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        account != null
                            ? account.fullName
                            : (p.last4.isEmpty
                                ? tr('Account: choose when adding')
                                : tr('No account ends in ${p.last4} — choose when adding')),
                        style: theme.textTheme.bodySmall?.copyWith(
                            color: account == null ? scheme.error : null),
                      ),
                    ],
                  ),
                ),
                Text(
                  '${p.credit ? '+' : '−'}${fmtMoney(p.amount!, p.currency)}',
                  style: theme.textTheme.titleMedium?.copyWith(color: color),
                ),
              ],
            ),
            if (dup != null)
              _note(
                context,
                Icons.content_copy_outlined,
                tr('Looks already added: ${_txnLabel(state, dup)}'),
                [
                  TextButton(
                    onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => TransactionEditScreen(txn: dup))),
                    child: Text(tr('View')),
                  ),
                  TextButton(
                    onPressed: () async {
                      await state.setSmsStatus(m.id, 'added');
                      if (pair != null &&
                          dup.type == TxType.transfer &&
                          state.smsDuplicate[pair.id]?.id == dup.id) {
                        await state.setSmsStatus(pair.id, 'added');
                      }
                    },
                    child: Text(tr('Already Added')),
                  ),
                ],
                scheme.tertiary,
              )
            else if (pair != null && fromId != null && toId != null)
              _note(
                context,
                Icons.swap_horiz,
                tr('Looks like a transfer between your accounts: ${state.accountById(fromId)?.name ?? ''} → ${state.accountById(toId)?.name ?? ''} (same amount, same day)'),
                [
                  FilledButton.tonal(
                    onPressed: () => _addPair(state, pair, p, fromId!, toId!),
                    child: Text(tr('Add as One Transfer')),
                  ),
                ],
                scheme.primary,
              ),
            if (check != null)
              _note(context, Icons.warning_amber_rounded, check, const [],
                  scheme.tertiary),
            if (_showText)
              Padding(
                padding: const EdgeInsets.only(top: 8, right: 6),
                child: SelectableText(m.body, style: theme.textTheme.bodySmall),
              ),
            Row(
              children: [
                TextButton(
                  onPressed: () => setState(() => _showText = !_showText),
                  child: Text(_showText ? tr('Hide Message') : tr('Show Message')),
                ),
                const Spacer(),
                _archiveButton(state),
                // Money into a credit card is a payment: a transfer.
                if (p.credit && account?.type == AccountType.creditCard)
                  FilledButton(
                    onPressed: () => _add(state, p, accountId, transfer: true),
                    child: Text(tr('Add Card Payment')),
                  )
                else ...[
                  if (p.credit)
                    TextButton(
                      onPressed: () => _add(state, p, accountId, transfer: true),
                      child: Text(tr('Transfer')),
                    ),
                  FilledButton(
                    onPressed: () => _add(state, p, accountId),
                    child: Text(tr('Add')),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _archiveButton(AppState state) => widget.archived
      ? IconButton(
          tooltip: tr('Restore'),
          icon: const Icon(Icons.unarchive_outlined),
          onPressed: () => state.setSmsStatus(widget.item.id, 'pending'),
        )
      : IconButton(
          tooltip: tr('Move to Archive'),
          icon: const Icon(Icons.archive_outlined),
          onPressed: () => state.setSmsStatus(widget.item.id, 'dismissed'),
        );

  String _txnLabel(AppState state, Txn t) {
    final what = t.type == TxType.transfer
        ? '${state.accountById(t.accountId)?.name ?? ''} → ${state.accountById(t.toAccountId)?.name ?? ''}'
        : (t.payee.isNotEmpty
            ? t.payee
            : (state.categoryById(t.categoryId)?.name ?? tr(t.type == TxType.income ? 'Income' : 'Expense')));
    final h = t.date.hour.toString().padLeft(2, '0');
    final mi = t.date.minute.toString().padLeft(2, '0');
    return '$what · ${dayFmt.format(t.date)} $h:$mi';
  }

  Widget _note(BuildContext context, IconData icon, String text,
      List<Widget> actions, Color color) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 8, right: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 6),
              Expanded(child: Text(text, style: theme.textTheme.bodySmall)),
            ],
          ),
          if (actions.isNotEmpty)
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: Wrap(spacing: 4, children: actions),
            ),
        ],
      ),
    );
  }

  /// A card's monthly statement message: compared with the app, never
  /// changes anything.
  Widget _statement(BuildContext context, AppState state, ParsedSms p,
      Account? card) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isCard = card?.type == AccountType.creditCard;
    final st = isCard ? state.statementFor(card!.id, p.dueDate) : null;
    final cur = p.currency;
    final lines = <(String, bool)>[]; // text, ok
    if (card == null || !isCard) {
      lines.add((
        p.last4.isEmpty
            ? tr('No credit card found for this message')
            : tr('No credit card ends in ${p.last4}'),
        false
      ));
    } else if (st == null) {
      lines.add((tr('The app has no statement for this due date yet'), false));
    } else if (card.currency != cur) {
      lines.add((tr('Different currency from the card in the app'), false));
    } else {
      final okAmount = (st.amount - p.amount!).abs() < 1;
      lines.add((
        okAmount
            ? tr('Statement amount matches the app')
            : tr('App statement: ${fmtMoney(st.amount, cur)} (bank: ${fmtMoney(p.amount!, cur)})'),
        okAmount
      ));
      if (p.minimumDue != null) {
        final appMin = st.amount * st.minPct / 100;
        final okMin = (appMin - p.minimumDue!).abs() < 1;
        lines.add((
          okMin
              ? tr('Minimum matches the app')
              : tr('App minimum: ${fmtMoney(appMin, cur)} (bank: ${fmtMoney(p.minimumDue!, cur)})'),
          okMin
        ));
      }
      if (p.dueDate != null) {
        final okDue = DateTime(st.dueDate.year, st.dueDate.month, st.dueDate.day) == p.dueDate;
        lines.add((
          okDue
              ? tr('Due date matches the app')
              : tr('App due date: ${dayFmt.format(st.dueDate)} (bank: ${dayFmt.format(p.dueDate!)})'),
          okDue
        ));
      }
    }
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 8, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.receipt_long_outlined, color: scheme.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(tr('Card Statement'), style: theme.textTheme.titleMedium),
                      const SizedBox(height: 2),
                      Text(
                        [
                          if (card != null) card.fullName
                          else if (p.last4.isNotEmpty) '•••• ${p.last4}',
                          if (widget.item.sender.isNotEmpty) widget.item.sender,
                        ].join(' · '),
                        style: theme.textTheme.bodySmall,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        [
                          if (p.minimumDue != null)
                            tr('Minimum ${fmtMoney(p.minimumDue!, cur)}'),
                          if (p.dueDate != null)
                            tr('Due ${dayFmt.format(p.dueDate!)}'),
                        ].join(' · '),
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                Text(fmtMoney(p.amount!, cur), style: theme.textTheme.titleMedium),
              ],
            ),
            for (final (text, ok) in lines)
              Padding(
                padding: const EdgeInsets.only(top: 6, right: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(ok ? Icons.check_circle_outline : Icons.warning_amber_rounded,
                        size: 18,
                        color: ok ? Colors.green.shade700 : scheme.tertiary),
                    const SizedBox(width: 6),
                    Expanded(child: Text(text, style: theme.textTheme.bodySmall)),
                  ],
                ),
              ),
            if (_showText)
              Padding(
                padding: const EdgeInsets.only(top: 8, right: 6),
                child: SelectableText(widget.item.body, style: theme.textTheme.bodySmall),
              ),
            Row(
              children: [
                TextButton(
                  onPressed: () => setState(() => _showText = !_showText),
                  child: Text(_showText ? tr('Hide Message') : tr('Show Message')),
                ),
                const Spacer(),
                if (!widget.archived)
                  FilledButton.tonal(
                    onPressed: () => state.setSmsStatus(widget.item.id, 'dismissed'),
                    child: Text(tr('Done')),
                  )
                else
                  _archiveButton(state),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
