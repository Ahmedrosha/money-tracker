import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../l10n/l10n.dart';
import '../state/app_state.dart';
import 'backup_screen.dart';
import 'widgets.dart';

/// Settings → Reset App: choose what to delete, optionally save a backup,
/// and type RESET to confirm.
class ResetScreen extends StatefulWidget {
  const ResetScreen({super.key});

  @override
  State<ResetScreen> createState() => _ResetScreenState();
}

class _ResetScreenState extends State<ResetScreen> {
  bool _everything = false;
  final _confirm = TextEditingController();
  bool _busy = false;

  bool get _typed => _confirm.text.trim().toUpperCase() == 'RESET';

  @override
  void dispose() {
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _reset() async {
    final state = AppScope.read(context);
    final nav = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      final docs = await getApplicationDocumentsDirectory();
      await state.resetData(everything: _everything, safetyDir: docs.path);
      nav.popUntil((r) => r.isFirst);
      messenger.showSnackBar(SnackBar(
          content: Text(_everything
              ? tr('The app was reset')
              : tr('Your data was deleted'))));
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        showSnack(context, tr('Reset failed: $e'));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final scheme = Theme.of(context).colorScheme;
    final theme = Theme.of(context);

    Widget choice(bool value, String title, String sub) => Card(
          color: _everything == value ? scheme.errorContainer : null,
          child: ListTile(
            leading: Icon(_everything == value
                ? Icons.radio_button_checked
                : Icons.radio_button_unchecked),
            title: Text(title),
            subtitle: Text(sub),
            onTap: _busy ? null : () => setState(() => _everything = value),
          ),
        );

    return Scaffold(
      appBar: AppBar(title: Text(tr('Reset App'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Text(tr('What should be deleted?'), style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          choice(
              false,
              tr('Delete My Data'),
              tr('Accounts, transactions, budgets, portfolios and recurring items. Categories, currency, language and lock settings stay.')),
          choice(
              true,
              tr('Reset Everything'),
              tr('Everything, including categories and settings — like a new install. The welcome screens show again.')),
          const SizedBox(height: 16),
          if (state.dropbox.connected)
            _Info(
              icon: Icons.cloud_off_outlined,
              text: tr('Dropbox will be disconnected first. The copy in Dropbox and your other phone are not touched.'),
            ),
          _Info(
            icon: Icons.history,
            text: tr('A copy of your current data stays on this phone. Backup & restore → Undo Last Restore brings it back.'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            icon: const Icon(Icons.save_alt),
            label: Text(tr('Save a Backup First')),
            onPressed: _busy
                ? null
                : () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const BackupScreen())),
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _confirm,
            enabled: !_busy,
            textCapitalization: TextCapitalization.characters,
            autocorrect: false,
            decoration: InputDecoration(
              labelText: tr('Type RESET to confirm'),
              border: const OutlineInputBorder(),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: scheme.error,
              foregroundColor: scheme.onError,
              minimumSize: const Size.fromHeight(48),
            ),
            icon: _busy
                ? SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: scheme.onError))
                : const Icon(Icons.delete_forever),
            label: Text(_everything
                ? tr('Reset Everything')
                : tr('Delete My Data')),
            onPressed: _typed && !_busy ? _reset : null,
          ),
        ],
      ),
    );
  }
}

class _Info extends StatelessWidget {
  const _Info({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: muted),
          const SizedBox(width: 10),
          Expanded(
              child: Text(text,
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: muted))),
        ],
      ),
    );
  }
}
