import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../data/db.dart';
import '../state/app_state.dart';
import '../util/format.dart';
import 'widgets.dart';

class BackupScreen extends StatefulWidget {
  const BackupScreen({super.key});

  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> {
  bool _busy = false;

  Future<String> _makeBackup() async {
    final state = AppScope.read(context);
    final dir = await getTemporaryDirectory();
    return state.createBackup(dir.path);
  }

  Future<void> _share() async {
    setState(() => _busy = true);
    try {
      final path = await _makeBackup();
      await Share.shareXFiles([XFile(path)],
          subject: 'Money Tracker backup', text: 'Money Tracker backup');
    } catch (e) {
      if (mounted) showSnack(context, 'Backup failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveToPhone() async {
    setState(() => _busy = true);
    try {
      final path = await _makeBackup();
      final bytes = await File(path).readAsBytes();
      final saved = await FilePicker.platform.saveFile(
        dialogTitle: 'Save backup',
        fileName: path.split('/').last,
        bytes: bytes,
      );
      if (mounted && saved != null) showSnack(context, 'Backup saved');
    } catch (e) {
      if (mounted) showSnack(context, 'Backup failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restore() async {
    final state = AppScope.read(context);
    final res = await FilePicker.platform.pickFiles(
      dialogTitle: 'Choose a Money Tracker backup (.db)',
      type: FileType.any,
    );
    final path = res?.files.single.path;
    if (path == null || !mounted) return;

    BackupInfo info;
    try {
      info = await AppDb.inspect(path);
    } catch (e) {
      if (mounted) {
        showSnack(context, 'This file is not a Money Tracker backup');
      }
      return;
    }
    if (!mounted) return;
    final range = info.first == null
        ? 'no transactions'
        : '${shortDateFmt.format(info.first!)} → ${shortDateFmt.format(info.last!)}';
    final ok = await confirmDialog(
      context,
      title: 'Replace all data?',
      message: 'The backup contains ${info.accounts} accounts and '
          '${info.transactions} transactions ($range).\n\n'
          'Everything currently in the app will be replaced. A copy of your '
          'current data is kept on the phone so you can undo this.',
      ok: 'Restore',
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    try {
      final docs = await getApplicationDocumentsDirectory();
      await state.restoreFrom(path, docs.path);
      if (mounted) showSnack(context, 'Restored ${info.transactions} transactions');
    } catch (e) {
      if (mounted) showSnack(context, 'Restore failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _undoRestore() async {
    final docs = await getApplicationDocumentsDirectory();
    final files = Directory(docs.path)
        .listSync()
        .whereType<File>()
        .where((f) => f.path.split('/').last.startsWith('before-restore-'))
        .toList()
      ..sort((a, b) => b.path.compareTo(a.path));
    if (!mounted) return;
    if (files.isEmpty) {
      showSnack(context, 'No earlier data saved');
      return;
    }
    final f = files.first;
    final ms = int.tryParse(
        f.path.split('before-restore-').last.replaceAll('.db', ''));
    final when = ms == null
        ? ''
        : ' from ${shortDateFmt.format(DateTime.fromMillisecondsSinceEpoch(ms))}';
    final ok = await confirmDialog(context,
        title: 'Undo last restore?',
        message: 'Go back to the data you had before the last restore$when.',
        ok: 'Undo');
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    try {
      await AppScope.read(context).restoreFrom(f.path, docs.path);
      await f.delete();
      if (mounted) showSnack(context, 'Previous data brought back');
    } catch (e) {
      if (mounted) showSnack(context, 'Undo failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final last = state.lastBackup;
    return Scaffold(
      appBar: AppBar(title: const Text('Backup & restore')),
      body: AbsorbPointer(
        absorbing: _busy,
        child: ListView(
          children: [
            if (_busy) const LinearProgressIndicator(),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                last == null
                    ? 'You have not made a backup yet. Your data exists only on this phone.'
                    : 'Last backup: ${dayFmt.format(last)}',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
            ListTile(
              leading: const Icon(Icons.cloud_upload_outlined),
              title: const Text('Back up & share'),
              subtitle: const Text('Save to Google Drive, email, WhatsApp…'),
              onTap: _share,
            ),
            ListTile(
              leading: const Icon(Icons.save_alt),
              title: const Text('Back up to phone storage'),
              subtitle: const Text('Choose a folder, e.g. Downloads'),
              onTap: _saveToPhone,
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.restore),
              title: const Text('Restore from backup'),
              subtitle: const Text('Replaces all current data'),
              onTap: _restore,
            ),
            ListTile(
              leading: const Icon(Icons.undo),
              title: const Text('Undo last restore'),
              subtitle: const Text('Bring back the data from before restoring'),
              onTap: _undoRestore,
            ),
          ],
        ),
      ),
    );
  }
}
