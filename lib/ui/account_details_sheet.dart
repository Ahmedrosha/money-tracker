import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/models.dart';
import '../l10n/l10n.dart';
import '../services/app_lock.dart';
import '../services/secure_store.dart';
import '../state/app_state.dart';
import 'account_edit.dart';
import 'widgets.dart';

/// Bottom sheet with an account's details: copy, call, and the full card
/// number behind Face ID / fingerprint.
Future<void> showAccountDetails(BuildContext context, Account account) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _DetailsSheet(account: account),
  );
}

class _DetailsSheet extends StatefulWidget {
  const _DetailsSheet({required this.account});

  final Account account;

  @override
  State<_DetailsSheet> createState() => _DetailsSheetState();
}

class _DetailsSheetState extends State<_DetailsSheet> {
  bool _hasNumber = false;
  String? _number; // shown after Face ID
  Timer? _hide;

  @override
  void initState() {
    super.initState();
    SecureStore.hasCardNumber(widget.account.id!).then((v) {
      if (mounted) setState(() => _hasNumber = v);
    });
  }

  @override
  void dispose() {
    _hide?.cancel();
    super.dispose();
  }

  void _copy(String text, String what) {
    Clipboard.setData(ClipboardData(text: text));
    showSnack(context, tr('$what copied'));
  }

  Future<void> _reveal() async {
    if (!await AppLock().authenticate()) return;
    final n = await SecureStore.cardNumber(widget.account.id!);
    if (!mounted || n == null) return;
    setState(() => _number = n);
    // Hide it again after a short while.
    _hide?.cancel();
    _hide = Timer(const Duration(seconds: 30), () {
      if (mounted) setState(() => _number = null);
    });
  }

  static String _groups(String digits) {
    final b = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && i % 4 == 0) b.write(' ');
      b.write(digits[i]);
    }
    return b.toString();
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final d = state.detailsOf(widget.account.id);
    final theme = Theme.of(context);

    Widget row(IconData icon, String label, String value,
            {List<Widget> actions = const []}) =>
        ListTile(
          leading: Icon(icon),
          title: Text(label, style: theme.textTheme.bodySmall),
          subtitle: SelectableText(value, style: theme.textTheme.bodyLarge),
          trailing: Row(mainAxisSize: MainAxisSize.min, children: actions),
        );

    final rows = <Widget>[
      if (d.last4.isNotEmpty)
        row(Icons.pin_outlined, tr('Last 4 Digits'), d.last4),
      if (_hasNumber)
        row(
          Icons.credit_card,
          tr('Card Number'),
          _number == null ? '•••• •••• •••• ••••' : _groups(_number!),
          actions: [
            if (_number == null)
              TextButton.icon(
                icon: const Icon(Icons.fingerprint),
                label: Text(tr('Show')),
                onPressed: _reveal,
              )
            else
              IconButton(
                tooltip: tr('Copy'),
                icon: const Icon(Icons.copy),
                onPressed: () => _copy(_number!, tr('Card number')),
              ),
          ],
        ),
      if (d.expiry.isNotEmpty)
        row(Icons.event_outlined, tr('Card Expiry'), d.expiry),
      if (d.phone.isNotEmpty)
        row(Icons.phone_outlined, tr('Bank Phone Number'), d.phone, actions: [
          IconButton(
            tooltip: tr('Call'),
            icon: const Icon(Icons.call),
            onPressed: () async {
              try {
                await launchUrl(Uri(scheme: 'tel', path: d.phone.replaceAll(' ', '')));
              } catch (_) {}
            },
          ),
        ]),
      if (d.customerNo.isNotEmpty)
        row(Icons.badge_outlined, tr('Customer Number'), d.customerNo,
            actions: [
              IconButton(
                tooltip: tr('Copy'),
                icon: const Icon(Icons.copy),
                onPressed: () => _copy(d.customerNo, tr('Customer number')),
              ),
            ]),
      if (d.iban.isNotEmpty)
        row(Icons.account_balance_outlined, 'IBAN', d.iban, actions: [
          IconButton(
            tooltip: tr('Copy'),
            icon: const Icon(Icons.copy),
            onPressed: () => _copy(d.iban.replaceAll(' ', ''), 'IBAN'),
          ),
        ]),
      if (d.notes.isNotEmpty)
        row(Icons.notes, tr('Notes'), d.notes),
    ];

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(widget.account.fullName,
                  style: theme.textTheme.titleMedium),
            ),
            if (rows.isEmpty)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(tr('No details yet. Add the last digits, expiry, bank phone, IBAN and notes in Edit Account.')),
              )
            else
              ...rows,
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: OutlinedButton.icon(
                icon: const Icon(Icons.edit_outlined),
                label: Text(tr('Edit Details')),
                onPressed: () {
                  final nav = Navigator.of(context);
                  nav.pop();
                  nav.push(MaterialPageRoute(
                      builder: (_) =>
                          AccountEditScreen(account: widget.account)));
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
