import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/db.dart';
import '../services/dropbox.dart';
import '../state/app_state.dart';
import '../util/format.dart';
import 'widgets.dart';
import '../l10n/l10n.dart';

String dropboxStatus(DropboxSync d) {
  if (!d.connected) return tr('Not connected');
  if (d.conflict != null) return tr('Waiting for you to choose which copy to keep');
  if (d.busy) return tr('Syncing…');
  if (d.lastError != null) return d.lastError!;
  final l = d.lastSync;
  if (l == null) return tr('Connected, not uploaded yet');
  final ago = DateTime.now().difference(l);
  final when = ago.inMinutes < 1
      ? tr('just now')
      : ago.inMinutes < 60
          ? tr('${ago.inMinutes} min ago')
          : ago.inHours < 24
              ? tr('${ago.inHours} h ago')
              : shortDateFmt.format(l);
  return tr('Synced $when${d.pending ? tr(' · change waiting') : ''}');
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
          appBar: AppBar(title: Text(tr('Dropbox'))),
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
                title: Text(d.connected ? tr('Connected') : tr('Not connected')),
                subtitle: Text(dropboxStatus(d)),
                trailing: d.busy
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : null,
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(
                  tr('Syncs with Dropbox → Apps → your app folder → '
                  'money-tracker.db. Connect the same Dropbox on your other '
                  'phone to use both: when you open the app, it takes the '
                  'newer copy from Dropbox; your changes go up a few seconds '
                  'after you make them and when you leave the app. If both '
                  'phones changed, the app asks which copy to keep.\n\n'
                  'History: a dated copy for each day is kept in the '
                  'history folder (money-tracker-YYYY-MM-DD.db).'),
                ),
              ),
              const Divider(),
              if (!d.connected)
                ListTile(
                  leading: const Icon(Icons.link),
                  title: Text(tr('Connect Dropbox')),
                  subtitle: Text(tr('Opens Dropbox to approve access')),
                  onTap: () => _connect(context, d),
                ),
              if (d.connected) ...[
                ListTile(
                  leading: const Icon(Icons.cloud_upload_outlined),
                  title: Text(tr('Sync Now')),
                  onTap: d.busy ? null : d.syncNow,
                ),
                ListTile(
                  leading: const Icon(Icons.cloud_download_outlined),
                  title: Text(tr('Restore from Dropbox')),
                  subtitle: Text(tr('Replaces the data on this phone')),
                  onTap: () => restoreFromDropbox(context),
                ),
                ListTile(
                  leading: const Icon(Icons.link_off),
                  title: Text(tr('Disconnect')),
                  subtitle:
                      Text(tr('Stops uploading; the file stays in Dropbox')),
                  onTap: () async {
                    final ok = await confirmDialog(context,
                        title: tr('Disconnect Dropbox?'),
                        message:
                            tr('The app stops uploading. Files already in Dropbox are kept.'),
                        ok: tr('Disconnect'));
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
      showSnack(context, tr('Could not open the browser'));
      return;
    }
    final ctrl = TextEditingController();
    final code = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Paste the Dropbox code')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
                tr('1. In the Dropbox page, tap Continue, then Allow.\n'
                '2. Dropbox shows a code — copy it.\n'
                '3. Come back here and paste it.')),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              autofocus: true,
              decoration: InputDecoration(
                labelText: tr('Access Code'),
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(tr('Cancel'))),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text),
              child: Text(tr('Connect'))),
        ],
      ),
    );
    if (code == null || code.trim().isEmpty) return;
    try {
      await d.finishConnect(code);
      if (context.mounted) showSnack(context, tr('Dropbox connected'));
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
    final got = await state.dropbox.download(tmp.path);
    if (!context.mounted) return;
    final path = got?.path;
    if (got == null || path == null) {
      showSnack(context, tr('No copy in Dropbox yet'));
      return;
    }
    final info = await AppDb.inspect(path);
    if (!context.mounted) return;
    final range = info.first == null
        ? tr('no transactions')
        : '${shortDateFmt.format(info.first!)} → ${shortDateFmt.format(info.last!)}';
    final ok = await confirmDialog(
      context,
      title: tr('Replace all data?'),
      message: tr('The Dropbox copy has ${info.accounts} accounts and '
          '${info.transactions} transactions ($range).\n\n'
          'Everything on this phone will be replaced. A copy of the current '
          'data is kept so you can undo it from Backup & restore.'),
      ok: tr('Restore'),
    );
    if (!ok) return;
    await state.restoreFromDropboxFile(path, got.rev);
    if (context.mounted) {
      showSnack(context, tr('Restored ${info.transactions} transactions'));
    }
  } catch (e) {
    if (context.mounted) {
      showSnack(context, tr('Restore failed: ${e.toString().replaceFirst('Exception: ', '')}'));
    }
  }
}
