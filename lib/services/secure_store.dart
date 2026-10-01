import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Full card numbers, kept in the phone's Keychain / Keystore only: never in
/// the database, backups or Dropbox.
class SecureStore {
  static const _store = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock_this_device),
  );

  static String _key(int accountId) => 'card_number_$accountId';

  static Future<String?> cardNumber(int accountId) async {
    try {
      return await _store.read(key: _key(accountId));
    } catch (_) {
      return null;
    }
  }

  static Future<void> setCardNumber(int accountId, String? number) async {
    try {
      if (number == null || number.isEmpty) {
        await _store.delete(key: _key(accountId));
      } else {
        await _store.write(key: _key(accountId), value: number);
      }
    } catch (_) {}
  }

  static Future<bool> hasCardNumber(int accountId) async =>
      (await cardNumber(accountId))?.isNotEmpty ?? false;

  static Future<void> clearAll() async {
    try {
      await _store.deleteAll();
    } catch (_) {}
  }
}
