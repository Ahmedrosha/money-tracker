import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

/// Keeps a copy of the database in the user's Dropbox (App folder).
///
/// Sign-in uses OAuth 2 with PKCE, so no app secret is stored in the app.
/// Tokens are kept in a separate file (not in the database), so backups
/// shared elsewhere never contain Dropbox credentials.
class DropboxSync extends ChangeNotifier {
  DropboxSync(this._makeBackup, this._replace);

  static const appKey = '946fznr3wi6ivdw';
  static const remotePath = '/money-tracker.db';
  static const historyDir = '/history';
  static const _debounce = Duration(seconds: 10);

  /// Writes a fresh copy of the database and returns its path.
  final Future<String> Function() _makeBackup;

  /// Replaces the data on this phone with the database file at a path.
  final Future<void> Function(String path) _replace;

  /// Dropbox revision of the copy this phone last uploaded or downloaded.
  String? _rev;

  /// Changes on this phone not in Dropbox yet.
  bool _dirty = false;

  /// Both this phone and Dropbox changed; waiting for the user to choose.
  SyncConflict? conflict;

  /// Set after this phone took the newer copy from Dropbox (for a message).
  DateTime? updatedFromDropbox;

  String? _refreshToken;
  String? _accessToken;
  DateTime? _expiresAt;
  String? _verifier;

  DateTime? lastSync;
  String? lastError;
  bool busy = false;
  bool _pending = false;
  Timer? _timer;

  bool get connected => _refreshToken != null;
  bool get pending => _pending;

  Future<File> _file() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/dropbox.json');
  }

  Future<void> init() async {
    try {
      final f = await _file();
      if (!await f.exists()) return;
      final m = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      _refreshToken = m['refresh_token'] as String?;
      _rev = m['rev'] as String?;
      _dirty = m['dirty'] as bool? ?? false;
      final ls = m['last_sync'] as int?;
      lastSync = ls == null ? null : DateTime.fromMillisecondsSinceEpoch(ls);
    } catch (_) {}
  }

  Future<void> _persist() async {
    final f = await _file();
    if (_refreshToken == null) {
      if (await f.exists()) await f.delete();
      return;
    }
    await f.writeAsString(jsonEncode({
      'refresh_token': _refreshToken,
      'last_sync': lastSync?.millisecondsSinceEpoch,
      'rev': _rev,
      'dirty': _dirty,
    }));
  }

  // ---------------- Sign-in ----------------

  /// The Dropbox page where the user approves access. Dropbox then shows a
  /// code that the user pastes into [finishConnect].
  Uri authorizeUrl() {
    final rnd = Random.secure();
    final bytes = List<int>.generate(48, (_) => rnd.nextInt(256));
    _verifier = base64UrlEncode(bytes).replaceAll('=', '');
    final challenge = base64UrlEncode(
            sha256.convert(ascii.encode(_verifier!)).bytes)
        .replaceAll('=', '');
    return Uri.https('www.dropbox.com', '/oauth2/authorize', {
      'client_id': appKey,
      'response_type': 'code',
      'code_challenge': challenge,
      'code_challenge_method': 'S256',
      'token_access_type': 'offline',
    });
  }

  Future<void> finishConnect(String code) async {
    if (_verifier == null) throw Exception('Start the connection again');
    final res = await http.post(
      Uri.parse('https://api.dropboxapi.com/oauth2/token'),
      body: {
        'code': code.trim(),
        'grant_type': 'authorization_code',
        'client_id': appKey,
        'code_verifier': _verifier!,
      },
    ).timeout(const Duration(seconds: 30));
    if (res.statusCode != 200) {
      throw Exception('Dropbox refused the code (${res.statusCode}). '
          'Codes work once and expire quickly; please try again.');
    }
    final m = jsonDecode(res.body) as Map<String, dynamic>;
    _refreshToken = m['refresh_token'] as String?;
    _accessToken = m['access_token'] as String?;
    _expiresAt = DateTime.now()
        .add(Duration(seconds: (m['expires_in'] as num? ?? 14400).toInt() - 60));
    _verifier = null;
    if (_refreshToken == null) throw Exception('No refresh token received');
    await _persist();
    notifyListeners();
    await syncNow();
  }

  Future<void> disconnect() async {
    final token = _accessToken;
    _timer?.cancel();
    _refreshToken = null;
    _accessToken = null;
    _expiresAt = null;
    _pending = false;
    _rev = null;
    _dirty = false;
    conflict = null;
    lastError = null;
    await _persist();
    notifyListeners();
    if (token != null) {
      try {
        await http.post(Uri.parse('https://api.dropboxapi.com/2/auth/token/revoke'),
            headers: {'Authorization': 'Bearer $token'});
      } catch (_) {}
    }
  }

  Future<String> _token() async {
    if (_accessToken != null &&
        _expiresAt != null &&
        DateTime.now().isBefore(_expiresAt!)) {
      return _accessToken!;
    }
    final res = await http.post(
      Uri.parse('https://api.dropboxapi.com/oauth2/token'),
      body: {
        'grant_type': 'refresh_token',
        'refresh_token': _refreshToken!,
        'client_id': appKey,
      },
    ).timeout(const Duration(seconds: 30));
    if (res.statusCode == 400 || res.statusCode == 401) {
      // Access was revoked from Dropbox's side.
      _refreshToken = null;
      await _persist();
      throw Exception('Dropbox access was removed. Connect again.');
    }
    if (res.statusCode != 200) {
      throw Exception('Dropbox sign-in failed (${res.statusCode})');
    }
    final m = jsonDecode(res.body) as Map<String, dynamic>;
    _accessToken = m['access_token'] as String;
    _expiresAt = DateTime.now()
        .add(Duration(seconds: (m['expires_in'] as num? ?? 14400).toInt() - 60));
    return _accessToken!;
  }

  // ---------------- Sync ----------------

  /// Call after any change on this phone: syncs once things have been
  /// quiet for a few seconds, so a burst of edits becomes one upload.
  void scheduleUpload() {
    if (!connected) return;
    _pending = true;
    if (!_dirty) {
      _dirty = true;
      _persist();
    }
    _timer?.cancel();
    _timer = Timer(_debounce, syncNow);
    notifyListeners();
  }

  /// Sync right away if something is waiting (e.g. app going to the
  /// background).
  Future<void> flush() async {
    if (_pending) {
      _timer?.cancel();
      await syncNow();
    }
  }

  /// Latest copy wins:
  /// - Dropbox has a newer copy and this phone has no new changes → take it.
  /// - This phone has changes and Dropbox hasn't changed → upload them.
  /// - Both changed → [conflict]; the user chooses which copy to keep.
  Future<void> syncNow() async {
    if (!connected || conflict != null) return;
    if (busy) {
      _pending = true;
      return;
    }
    busy = true;
    _pending = false;
    _timer?.cancel();
    notifyListeners();
    String? incoming;
    String? incomingRev;
    try {
      final token = await _token();
      final meta = await _metadata(token);
      final remoteRev = meta?.rev;
      if (remoteRev != null && remoteRev != _rev) {
        // Another phone uploaded since this one last synced.
        final path = await _download(token, 'dropbox-incoming.db');
        if (!_dirty && _rev != null) {
          incoming = path;
          incomingRev = remoteRev;
        } else {
          conflict = SyncConflict(path, remoteRev, meta!.modified);
        }
      } else if (_dirty || remoteRev == null) {
        await _uploadMain(token, remoteRev);
      }
      lastSync = DateTime.now();
      lastError = null;
      await _persist();
    } on _RevChanged {
      // Someone uploaded in between; the next check sorts it out.
      _pending = true;
    } catch (e) {
      lastError = e is SocketException || e is TimeoutException
          ? 'No internet, will retry'
          : e.toString().replaceFirst('Exception: ', '');
      _pending = connected && _dirty;
    } finally {
      busy = false;
      notifyListeners();
    }
    if (incoming != null) {
      await _replace(incoming);
      _rev = incomingRev;
      _dirty = false;
      _pending = false;
      updatedFromDropbox = DateTime.now();
      await _persist();
      notifyListeners();
    }
    // Changes made while syncing: send them too.
    if (_pending && lastError == null && conflict == null) scheduleUpload();
  }

  /// Conflict: keep what's on this phone and replace the Dropbox copy.
  /// The Dropbox copy is saved in the history folder first.
  Future<void> keepThisPhone() async {
    final c = conflict;
    if (c == null) return;
    busy = true;
    notifyListeners();
    try {
      final token = await _token();
      await _put(token, await File(c.path).readAsBytes(),
          '$historyDir/money-tracker-${_stamp(DateTime.now())}-replaced.db',
          const {'.tag': 'overwrite'});
      conflict = null;
      _dirty = true;
      await _uploadMain(token, c.rev);
      lastSync = DateTime.now();
      lastError = null;
      await _persist();
    } catch (e) {
      lastError = e.toString().replaceFirst('Exception: ', '');
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  /// Conflict: take the Dropbox copy. This phone's data is saved in the
  /// Dropbox history folder first.
  Future<void> useDropboxCopy() async {
    final c = conflict;
    if (c == null) return;
    busy = true;
    notifyListeners();
    try {
      final token = await _token();
      final local = await _makeBackup();
      await _put(token, await File(local).readAsBytes(),
          '$historyDir/money-tracker-${_stamp(DateTime.now())}-this-phone.db',
          const {'.tag': 'overwrite'});
      conflict = null;
      busy = false;
      await _replace(c.path);
      _rev = c.rev;
      _dirty = false;
      _pending = false;
      lastSync = DateTime.now();
      lastError = null;
      await _persist();
    } catch (e) {
      lastError = e.toString().replaceFirst('Exception: ', '');
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  /// After a manual restore from Dropbox: this phone now matches [rev].
  Future<void> adopt(String? rev) async {
    _rev = rev;
    _dirty = false;
    _pending = false;
    _timer?.cancel();
    await _persist();
    notifyListeners();
  }

  static String _two(int n) => n.toString().padLeft(2, '0');
  static String _day(DateTime d) => '${d.year}-${_two(d.month)}-${_two(d.day)}';
  static String _stamp(DateTime d) =>
      '${_day(d)}_${_two(d.hour)}${_two(d.minute)}';

  Future<({String rev, DateTime? modified})?> _metadata(String token) async {
    final res = await http
        .post(
          Uri.parse('https://api.dropboxapi.com/2/files/get_metadata'),
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({'path': remotePath}),
        )
        .timeout(const Duration(seconds: 30));
    if (res.statusCode == 409) return null; // no copy yet
    if (res.statusCode == 401) _accessToken = null;
    if (res.statusCode != 200) {
      throw Exception('Dropbox check failed (${res.statusCode})');
    }
    final m = jsonDecode(res.body) as Map<String, dynamic>;
    return (
      rev: m['rev'] as String,
      modified: DateTime.tryParse(m['server_modified'] as String? ?? '')?.toLocal(),
    );
  }

  /// Uploads this phone's data as the main copy, only if Dropbox still has
  /// [expectedRev] (null = no copy yet). Also keeps a dated copy.
  Future<void> _uploadMain(String token, String? expectedRev) async {
    final path = await _makeBackup();
    final bytes = await File(path).readAsBytes();
    final changedDuring = _pending;
    final rev = await _put(
      token,
      bytes,
      remotePath,
      expectedRev == null
          ? const {'.tag': 'add'}
          : {'.tag': 'update', 'update': expectedRev},
    );
    _rev = rev;
    // Edits made while uploading still need to go up.
    _dirty = _pending || changedDuring;
    // One dated copy per day in the history folder.
    try {
      final today = _day(DateTime.now());
      await _put(token, bytes, '$historyDir/money-tracker-$today.db',
          const {'.tag': 'overwrite'});
      if (_prunedOn != today) {
        _prunedOn = today;
        await _pruneHistory(token);
      }
    } catch (_) {}
    try {
      await File(path).delete();
    } catch (_) {}
  }

  String? _prunedOn;

  /// Keeps every daily copy for 60 days; before that, one per month (the
  /// first of that month). Copies saved when choosing between phones are
  /// never removed.
  Future<void> _pruneHistory(String token) async {
    final names = <String>[];
    var res = await http.post(
      Uri.parse('https://api.dropboxapi.com/2/files/list_folder'),
      headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'},
      body: jsonEncode({'path': historyDir}),
    ).timeout(const Duration(seconds: 30));
    while (res.statusCode == 200) {
      final m = jsonDecode(res.body) as Map<String, dynamic>;
      for (final e in (m['entries'] as List)) {
        names.add((e as Map<String, dynamic>)['name'] as String);
      }
      if (m['has_more'] != true) break;
      res = await http.post(
        Uri.parse('https://api.dropboxapi.com/2/files/list_folder/continue'),
        headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'},
        body: jsonEncode({'cursor': m['cursor']}),
      ).timeout(const Duration(seconds: 30));
    }
    final daily = RegExp(r'^money-tracker-(\d{4})-(\d{2})-(\d{2})\.db$');
    final cutoff = DateTime.now().subtract(const Duration(days: 60));
    final keptMonth = <String>{};
    final dated = <(DateTime, String)>[];
    for (final n in names) {
      final m = daily.firstMatch(n);
      if (m == null) continue;
      dated.add((
        DateTime(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!)),
        n
      ));
    }
    dated.sort((a, b) => a.$1.compareTo(b.$1));
    final remove = <String>[];
    for (final (d, n) in dated) {
      if (!d.isBefore(cutoff)) continue;
      final month = '${d.year}-${d.month}';
      if (keptMonth.add(month)) continue; // earliest of its month stays
      remove.add('$historyDir/$n');
    }
    if (remove.isEmpty) return;
    await http.post(
      Uri.parse('https://api.dropboxapi.com/2/files/delete_batch'),
      headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'},
      body: jsonEncode({
        'entries': [for (final p in remove) {'path': p}]
      }),
    ).timeout(const Duration(seconds: 30));
  }

  /// Uploads [bytes] to [path]; returns the new revision.
  Future<String> _put(String token, List<int> bytes, String path,
      Map<String, String> mode) async {
    final res = await http
        .post(
          Uri.parse('https://content.dropboxapi.com/2/files/upload'),
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/octet-stream',
            'Dropbox-API-Arg': jsonEncode({
              'path': path,
              'mode': mode,
              'autorename': false,
              'mute': true,
            }),
          },
          body: bytes,
        )
        .timeout(const Duration(minutes: 2));
    if (res.statusCode == 401) _accessToken = null;
    if (res.statusCode == 409 && path == remotePath) throw _RevChanged();
    if (res.statusCode != 200) {
      throw Exception('Upload failed (${res.statusCode})');
    }
    return (jsonDecode(res.body) as Map<String, dynamic>)['rev'] as String;
  }

  Future<String> _download(String token, String name) async {
    final r = await _get(token);
    if (r == null) throw Exception('The Dropbox copy disappeared');
    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/$name';
    await File(path).writeAsBytes(r.bytes);
    return path;
  }

  Future<({List<int> bytes, String? rev})?> _get(String token) async {
    final res = await http
        .post(
          Uri.parse('https://content.dropboxapi.com/2/files/download'),
          headers: {
            'Authorization': 'Bearer $token',
            'Dropbox-API-Arg': jsonEncode({'path': remotePath}),
          },
        )
        .timeout(const Duration(minutes: 2));
    if (res.statusCode == 409) return null; // not found
    if (res.statusCode == 401) _accessToken = null;
    if (res.statusCode != 200) {
      throw Exception('Download failed (${res.statusCode})');
    }
    String? rev;
    try {
      final h = res.headers['dropbox-api-result'];
      if (h != null) rev = (jsonDecode(h) as Map<String, dynamic>)['rev'] as String?;
    } catch (_) {}
    return (bytes: res.bodyBytes, rev: rev);
  }

  // ---------------- Manual download ----------------

  /// Downloads the Dropbox copy into [dir]; returns its path and revision,
  /// or null when there is no copy yet.
  Future<({String path, String? rev})?> download(String dir) async {
    final r = await _get(await _token());
    if (r == null) return null;
    final path = '$dir/dropbox-restore.db';
    await File(path).writeAsBytes(r.bytes);
    return (path: path, rev: r.rev);
  }
}

class _RevChanged implements Exception {}

/// Both phones changed since they last synced.
class SyncConflict {
  /// The Dropbox copy, downloaded to a temporary file.
  final String path;
  final String rev;
  final DateTime? modified;
  const SyncConflict(this.path, this.rev, this.modified);
}
