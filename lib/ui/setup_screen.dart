import 'package:flutter/material.dart';

import '../data/models.dart';
import '../l10n/l10n.dart';
import '../state/app_state.dart';
import '../util/currencies.dart';
import '../util/format.dart';
import 'backup_screen.dart';
import 'dropbox_screen.dart';
import 'settings_screen.dart';
import 'widgets.dart';

/// Welcome screens shown once on a new install: language, main currency,
/// how to start (fresh, backup, Dropbox or sample data) and extras.
class SetupScreen extends StatelessWidget {
  const SetupScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final step = state.setupStep;
    final Widget page;
    switch (step) {
      case 0:
        page = const _LanguageStep();
      case 1:
        page = const _CurrencyStep();
      case 2:
        page = const _StartStep();
      case 3:
        page = const _AccountsStep();
      default:
        page = const _ExtrasStep();
    }
    return PopScope(
      canPop: step == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && step > 0) {
          state.setSetupStep(step == 4 ? 2 : step - 1);
        }
      },
      child: Scaffold(
        body: SafeArea(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: KeyedSubtree(key: ValueKey(step), child: page),
          ),
        ),
      ),
    );
  }
}

/// Common layout: title, text, content and the buttons at the bottom.
class _StepLayout extends StatelessWidget {
  const _StepLayout({
    required this.title,
    this.text,
    required this.children,
    this.next,
    this.nextLabel,
    this.back,
    this.header,
  });

  final String title;
  final String? text;
  final List<Widget> children;
  final VoidCallback? next;
  final String? nextLabel;
  final VoidCallback? back;
  final Widget? header;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 32, 24, 16),
            children: [
              if (header != null) header!,
              Text(title,
                  style: theme.textTheme.headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w600)),
              if (text != null) ...[
                const SizedBox(height: 8),
                Text(text!,
                    style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant)),
              ],
              const SizedBox(height: 24),
              ...children,
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Row(
            children: [
              if (back != null)
                TextButton(onPressed: back, child: Text(tr('Back'))),
              const Spacer(),
              if (next != null)
                FilledButton(
                    onPressed: next, child: Text(nextLabel ?? tr('Next'))),
            ],
          ),
        ),
      ],
    );
  }
}

String _languageName(String code) {
  switch (code) {
    case 'en':
      return 'English';
    case 'ar':
      return 'العربية';
    default:
      return tr('Phone Language');
  }
}

class _LanguageStep extends StatelessWidget {
  const _LanguageStep();

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final scheme = Theme.of(context).colorScheme;
    return _StepLayout(
      header: Padding(
        padding: const EdgeInsets.only(bottom: 20),
        child: Align(
          alignment: AlignmentDirectional.centerStart,
          child: Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: scheme.primary,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Icon(Icons.account_balance_wallet_outlined,
                size: 40, color: scheme.onPrimary),
          ),
        ),
      ),
      title: tr('Welcome to Expense & Wealth Tracker'),
      text: tr('Track spending, cards, loans, investments and everything you own — in one place, on your phone.'),
      next: () => state.setSetupStep(1),
      children: [
        Text(isArabic ? 'اللغة · Language' : 'Language · اللغة',
            style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 4),
        for (final code in const ['system', 'en', 'ar'])
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(state.language == code
                ? Icons.radio_button_checked
                : Icons.radio_button_unchecked),
            title: Text(_languageName(code)),
            onTap: () => state.setLanguage(code),
          ),
      ],
    );
  }
}

class _CurrencyStep extends StatelessWidget {
  const _CurrencyStep();

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    return _StepLayout(
      title: tr('Main Currency'),
      text: tr('Totals and net worth are shown in this currency. Each account can still have its own currency.'),
      back: () => state.setSetupStep(0),
      next: () => state.setSetupStep(2),
      children: [
        Card(
          child: ListTile(
            leading: const Icon(Icons.flag_outlined),
            title: Text(state.baseCurrency),
            subtitle: Text(currencyName(state.baseCurrency)),
            trailing: Text(tr('Change')),
            onTap: () async {
              final c =
                  await pickCurrency(context, current: state.baseCurrency);
              if (c != null) await state.setBaseCurrency(c);
            },
          ),
        ),
      ],
    );
  }
}

class _StartStep extends StatefulWidget {
  const _StartStep();

  @override
  State<_StartStep> createState() => _StartStepState();
}

class _StartStepState extends State<_StartStep> {
  bool _busy = false;

  /// Backup or Dropbox screens: done when data came in.
  Future<void> _open(Widget screen) async {
    final state = AppScope.read(context);
    await Navigator.push(
        context, MaterialPageRoute(builder: (_) => screen));
    if (state.accounts.isNotEmpty) {
      state.setSetupStep(4);
    }
  }

  Future<void> _sample() async {
    final state = AppScope.read(context);
    setState(() => _busy = true);
    try {
      await state.loadSampleData();
      state.setSetupStep(4);
    } catch (e) {
      if (mounted) showSnack(context, '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    Widget option(IconData icon, String title, String sub, VoidCallback onTap) =>
        Card(
          child: ListTile(
            leading: Icon(icon),
            title: Text(title),
            subtitle: Text(sub),
            trailing: const Icon(Icons.chevron_right),
            onTap: _busy ? null : onTap,
          ),
        );
    return _StepLayout(
      title: tr('How do you want to start?'),
      back: () => state.setSetupStep(1),
      children: [
        option(Icons.add_circle_outline, tr('Start Fresh'),
            tr('Add your cash, bank accounts and cards'),
            () => state.setSetupStep(3)),
        option(Icons.restore, tr('Restore a Backup File'),
            tr('A backup saved from this app (Drive, WhatsApp, email…)'),
            () => _open(const BackupScreen())),
        option(Icons.cloud_sync_outlined, tr('Connect Dropbox'),
            tr('Use the same data as your other phone'),
            () => _open(const DropboxScreen())),
        option(Icons.auto_awesome_outlined, tr('Try With Sample Data'),
            tr('Explore with example accounts; remove them later from Settings'),
            _sample),
        if (_busy)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          ),
      ],
    );
  }
}

class _Starter {
  _Starter(this.type, this.name, this.on, {this.bank = ''})
      : nameCtrl = TextEditingController(text: name),
        bankCtrl = TextEditingController(text: bank);

  final AccountType type;
  final String name;
  final String bank;
  bool on;
  final TextEditingController nameCtrl;
  final TextEditingController bankCtrl;
  final TextEditingController amountCtrl = TextEditingController();
}

class _AccountsStep extends StatefulWidget {
  const _AccountsStep();

  @override
  State<_AccountsStep> createState() => _AccountsStepState();
}

class _AccountsStepState extends State<_AccountsStep> {
  late final List<_Starter> _items = [
    _Starter(AccountType.cash, tr('Wallet'), true),
    _Starter(AccountType.bank, tr('Current Account'), true),
    _Starter(AccountType.savings, tr('Savings Account'), false),
    _Starter(AccountType.creditCard, tr('Credit Card'), false),
  ];
  bool _saving = false;

  @override
  void dispose() {
    for (final i in _items) {
      i.nameCtrl.dispose();
      i.bankCtrl.dispose();
      i.amountCtrl.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final state = AppScope.read(context);
    setState(() => _saving = true);
    try {
      for (final i in _items.where((i) => i.on)) {
        final name = i.nameCtrl.text.trim();
        if (name.isEmpty) continue;
        await state.addStarterAccount(
            name, i.type, parseAmount(i.amountCtrl.text) ?? 0,
            bank: i.bankCtrl.text.trim());
      }
      state.setSetupStep(4);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final unit = currencyUnit(state.baseCurrency);
    return _StepLayout(
      title: tr('Your Accounts'),
      text: tr('Tick the ones you have and enter today\'s balance. You can add more, and edit these, any time.'),
      back: () => state.setSetupStep(2),
      next: _saving ? null : _save,
      children: [
        for (final i in _items)
          Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, 12, 8),
              child: Column(
                children: [
                  CheckboxListTile(
                    contentPadding: const EdgeInsetsDirectional.only(start: 8),
                    value: i.on,
                    onChanged: (v) => setState(() => i.on = v ?? false),
                    title: Text(i.type.label),
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                  if (i.on) ...[
                    Padding(
                      padding: const EdgeInsetsDirectional.only(start: 12),
                      child: Column(
                        children: [
                          TextField(
                            controller: i.nameCtrl,
                            decoration: InputDecoration(
                                labelText: tr('Name'), isDense: true),
                          ),
                          if (i.type != AccountType.cash) ...[
                            const SizedBox(height: 8),
                            TextField(
                              controller: i.bankCtrl,
                              decoration: InputDecoration(
                                  labelText: tr('Bank'),
                                  hintText: tr('e.g. CIB, NBE, Banque Misr'),
                                  isDense: true),
                            ),
                          ],
                          const SizedBox(height: 8),
                          TextField(
                            controller: i.amountCtrl,
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true, signed: true),
                            decoration: InputDecoration(
                                labelText: i.type.isLiability
                                    ? tr('Amount owed today')
                                    : tr('Balance today'),
                                suffixText: unit,
                                isDense: true),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _ExtrasStep extends StatefulWidget {
  const _ExtrasStep();

  @override
  State<_ExtrasStep> createState() => _ExtrasStepState();
}

class _ExtrasStepState extends State<_ExtrasStep> {
  bool _asked = false;
  bool _finishing = false;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    return _StepLayout(
      title: tr('Almost Done'),
      text: tr('Two optional extras. Both can be changed later in Settings.'),
      back: () => state.setSetupStep(2),
      nextLabel: tr('Start Using the App'),
      next: _finishing
          ? null
          : () async {
              setState(() => _finishing = true);
              await state.completeSetup();
            },
      children: [
        const Card(child: AppLockTile()),
        Card(
          child: ListTile(
            leading: const Icon(Icons.notifications_outlined),
            title: Text(tr('Reminders')),
            subtitle: Text(tr('Card payments due, recurring items and budget alerts')),
            trailing: _asked
                ? const Icon(Icons.check)
                : TextButton(
                    onPressed: () async {
                      await state.db.setSetting('notif_asked', '1');
                      await state.notifier.requestPermission();
                      await state.rescheduleReminders();
                      if (mounted) setState(() => _asked = true);
                    },
                    child: Text(tr('Allow'))),
          ),
        ),
        if (state.hasSampleData)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
                tr('Sample data is loaded. Remove it any time from Settings → Clear Sample Data.'),
                style: Theme.of(context).textTheme.bodySmall),
          ),
      ],
    );
  }
}
