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
  DropboxSync(this._makeBackup);

  static const appKey = '946fznr3wi6ivdw';
  static const remotePath = '/money-tracker.db';
  static const _debounce = Duration(seconds: 10);

  /// Writes a fresh copy of the database and returns its path.
  final Future<String> Function() _makeBackup;

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

  // ---------------- Upload ----------------

  /// Call after any change: uploads once things have been quiet for a
  /// few seconds, so a burst of edits becomes one upload.
  void scheduleUpload() {
    if (!connected) return;
    _pending = true;
    _timer?.cancel();
    _timer = Timer(_debounce, syncNow);
    notifyListeners();
  }

  /// Upload right away if something is waiting (e.g. app going to the
  /// background).
  Future<void> flush() async {
    if (_pending) {
      _timer?.cancel();
      await syncNow();
    }
  }

  Future<void> syncNow() async {
    if (!connected) return;
    if (busy) {
      _pending = true;
      return;
    }
    busy = true;
    _pending = false;
    _timer?.cancel();
    notifyListeners();
    try {
      final path = await _makeBackup();
      final bytes = await File(path).readAsBytes();
      final token = await _token();
      final res = await http
          .post(
            Uri.parse('https://content.dropboxapi.com/2/files/upload'),
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/octet-stream',
              'Dropbox-API-Arg': jsonEncode({
                'path': remotePath,
                'mode': 'overwrite',
                'mute': true,
              }),
            },
            body: bytes,
          )
          .timeout(const Duration(minutes: 2));
      if (res.statusCode == 401) _accessToken = null;
      if (res.statusCode != 200) {
        throw Exception('Upload failed (${res.statusCode})');
      }
      lastSync = DateTime.now();
      lastError = null;
      await _persist();
      try {
        await File(path).delete();
      } catch (_) {}
    } catch (e) {
      lastError = e is SocketException || e is TimeoutException
          ? 'No internet, will retry'
          : e.toString().replaceFirst('Exception: ', '');
      _pending = connected;
    } finally {
      busy = false;
      notifyListeners();
    }
    // Changes made while uploading: send them too.
    if (_pending && lastError == null) scheduleUpload();
  }

  // ---------------- Download ----------------

  /// Downloads the Dropbox copy into [dir] and returns the file path, or
  /// null when there is no copy yet.
  Future<String?> download(String dir) async {
    final token = await _token();
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
    if (res.statusCode != 200) {
      throw Exception('Download failed (${res.statusCode})');
    }
    final path = '$dir/dropbox-restore.db';
    await File(path).writeAsBytes(res.bodyBytes);
    return path;
  }
}
