import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/models.dart';
import '../l10n/l10n.dart';
import '../services/sms_parser.dart';
import '../services/sms_reader.dart';
import '../state/app_state.dart';
import '../util/format.dart';
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
                subtitle: Text(tr('Set up once: a Shortcuts automation sends each bank SMS here.')),
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
    const link = 'ewtracker://sms?from=SENDER&text=MESSAGE';
    final steps = [
      tr('Open the Shortcuts app → Automation → + (New Automation) → Message.'),
      tr('Message Contains: EGP (or the bank\'s name). Choose Run Immediately, then Next.'),
      tr('New Blank Automation → add the action "URL Encode". Tap its input and pick Shortcut Input → Content.'),
      tr('Add "Text" and type ewtracker://sms?text= then insert the URL Encoded Text variable right after it.'),
      tr('Add "Open URLs" and pick the Text from the step before. Done.'),
      tr('Each matching SMS now opens the app and waits in Bank Messages for you to add it. Messages without an amount are ignored.'),
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
              const SizedBox(height: 8),
              Text(tr('Link format'), style: Theme.of(ctx).textTheme.labelLarge),
              const SizedBox(height: 4),
              Row(
                children: [
                  const Expanded(child: SelectableText(link)),
                  IconButton(
                    tooltip: tr('Copy'),
                    icon: const Icon(Icons.copy),
                    onPressed: () {
                      Clipboard.setData(const ClipboardData(text: 'ewtracker://sms?text='));
                      showSnack(ctx, tr('Copied'));
                    },
                  ),
                ],
              ),
              Text(
                tr('Adding &from= with the sender is optional; the app also matches by the last 4 digits.'),
                style: Theme.of(ctx).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SmsCard extends StatefulWidget {
  const _SmsCard({required this.item});

  final SmsItem item;

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
    final cat = transfer ? null : await state.suggestCategory(p.payee, type);
    if (!mounted) return;
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => TransactionEditScreen(
          initialType: type,
          // A transfer received: this account is the destination.
          initialAccountId: transfer ? null : accountId,
          initialToAccountId: transfer ? accountId : null,
          initialDate: p.date,
          initialAmount: p.amount,
          initialPayee: transfer ? null : p.payee,
          initialCategoryId: cat,
          initialNote: p.instaPay
              ? 'InstaPay${p.ref.isEmpty ? '' : ' · Ref ${p.ref}'}${transfer && p.payee.isNotEmpty ? ' · ${p.payee}' : ''}'
              : (p.ref.isEmpty ? null : 'Ref ${p.ref}'),
        ),
      ),
    );
    if (saved == true) await state.setSmsStatus(widget.item.id, 'added');
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
                        p.payee.isNotEmpty
                            ? p.payee
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
            if (check != null)
              Padding(
                padding: const EdgeInsets.only(top: 8, right: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.warning_amber_rounded, size: 18, color: scheme.tertiary),
                    const SizedBox(width: 6),
                    Expanded(child: Text(check, style: theme.textTheme.bodySmall)),
                  ],
                ),
              ),
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
                IconButton(
                  tooltip: tr('Dismiss'),
                  icon: const Icon(Icons.close),
                  onPressed: () => state.setSmsStatus(m.id, 'dismissed'),
                ),
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
            ),
          ],
        ),
      ),
    );
  }
}
