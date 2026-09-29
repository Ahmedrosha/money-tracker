import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/db.dart';
import '../services/dropbox.dart';
import '../state/app_state.dart';
import '../util/format.dart';
import 'widgets.dart';

String dropboxStatus(DropboxSync d) {
  if (!d.connected) return 'Not connected';
  if (d.busy) return 'Uploading…';
  if (d.lastError != null) return d.lastError!;
  final l = d.lastSync;
  if (l == null) return 'Connected, not uploaded yet';
  final ago = DateTime.now().difference(l);
  final when = ago.inMinutes < 1
      ? 'just now'
      : ago.inMinutes < 60
          ? '${ago.inMinutes} min ago'
          : ago.inHours < 24
              ? '${ago.inHours} h ago'
              : shortDateFmt.format(l);
  return 'Synced $when${d.pending ? ' · change waiting' : ''}';
}

class DropboxScreen extends StatelessWidget {
  const DropboxScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    return ListenableBuilder(
      listenable: state.dropbox,
      builder: (context, _) {
        final d = state.dropbox;
        return Scaffold(
          appBar: AppBar(title: const Text('Dropbox')),
          body: ListView(
            padding: const EdgeInsets.symmetric(vertical: 8),
            children: [
              ListTile(
                leading: Icon(
                  d.connected ? Icons.cloud_done : Icons.cloud_off,
                  color: d.connected
                      ? (d.lastError == null ? kIncomeColor : kExpenseColor)
                      : null,
                ),
                title: Text(d.connected ? 'Connected' : 'Not connected'),
                subtitle: Text(dropboxStatus(d)),
                trailing: d.busy
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : null,
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(
                  'Your data is uploaded to Dropbox → Apps → your app folder '
                  '→ money-tracker.db when you open the app, a few seconds '
                  'after any change, and when you leave the app. Dropbox '
                  'keeps older versions of the file for 30 days.',
                ),
              ),
              const Divider(),
              if (!d.connected)
                ListTile(
                  leading: const Icon(Icons.link),
                  title: const Text('Connect Dropbox'),
                  subtitle: const Text('Opens Dropbox to approve access'),
                  onTap: () => _connect(context, d),
                ),
              if (d.connected) ...[
                ListTile(
                  leading: const Icon(Icons.cloud_upload_outlined),
                  title: const Text('Upload Now'),
                  onTap: d.busy ? null : d.syncNow,
                ),
                ListTile(
                  leading: const Icon(Icons.cloud_download_outlined),
                  title: const Text('Restore from Dropbox'),
                  subtitle: const Text('Replaces the data on this phone'),
                  onTap: () => restoreFromDropbox(context),
                ),
                ListTile(
                  leading: const Icon(Icons.link_off),
                  title: const Text('Disconnect'),
                  subtitle:
                      const Text('Stops uploading; the file stays in Dropbox'),
                  onTap: () async {
                    final ok = await confirmDialog(context,
                        title: 'Disconnect Dropbox?',
                        message:
                            'The app stops uploading. Files already in Dropbox are kept.',
                        ok: 'Disconnect');
                    if (ok) await d.disconnect();
                  },
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Future<void> _connect(BuildContext context, DropboxSync d) async {
    final url = d.authorizeUrl();
    final opened = await launchUrl(url, mode: LaunchMode.externalApplication);
    if (!context.mounted) return;
    if (!opened) {
      showSnack(context, 'Could not open the browser');
      return;
    }
    final ctrl = TextEditingController();
    final code = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Paste the Dropbox code'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
                '1. In the Dropbox page, tap Continue, then Allow.\n'
                '2. Dropbox shows a code — copy it.\n'
                '3. Come back here and paste it.'),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Access Code',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text),
              child: const Text('Connect')),
        ],
      ),
    );
    if (code == null || code.trim().isEmpty) return;
    try {
      await d.finishConnect(code);
      if (context.mounted) showSnack(context, 'Dropbox connected');
    } catch (e) {
      if (context.mounted) {
        showSnack(context, e.toString().replaceFirst('Exception: ', ''));
      }
    }
  }
}

/// Downloads the Dropbox copy and, after confirmation, replaces local data.
Future<void> restoreFromDropbox(BuildContext context) async {
  final state = AppScope.read(context);
  try {
    final tmp = await getTemporaryDirectory();
    final path = await state.dropbox.download(tmp.path);
    if (!context.mounted) return;
    if (path == null) {
      showSnack(context, 'No copy in Dropbox yet');
      return;
    }
    final info = await AppDb.inspect(path);
    if (!context.mounted) return;
    final range = info.first == null
        ? 'no transactions'
        : '${shortDateFmt.format(info.first!)} → ${shortDateFmt.format(info.last!)}';
    final ok = await confirmDialog(
      context,
      title: 'Replace all data?',
      message: 'The Dropbox copy has ${info.accounts} accounts and '
          '${info.transactions} transactions ($range).\n\n'
          'Everything on this phone will be replaced. A copy of the current '
          'data is kept so you can undo it from Backup & restore.',
      ok: 'Restore',
    );
    if (!ok) return;
    final docs = await getApplicationDocumentsDirectory();
    await state.restoreFrom(path, docs.path);
    if (context.mounted) {
      showSnack(context, 'Restored ${info.transactions} transactions');
    }
  } catch (e) {
    if (context.mounted) {
      showSnack(context, 'Restore failed: ${e.toString().replaceFirst('Exception: ', '')}');
    }
  }
}
