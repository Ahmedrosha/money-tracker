import 'package:local_auth/local_auth.dart';

/// Face ID / Touch ID / fingerprint, falling back to the phone's passcode.
class AppLock {
  final LocalAuthentication _auth = LocalAuthentication();

  /// Whether the phone has any screen lock the app can use.
  Future<bool> available() async {
    try {
      return await _auth.isDeviceSupported();
    } catch (_) {
      return false;
    }
  }

  /// Name for the settings screen: "Face ID", "Fingerprint", …
  Future<String> methodName() async {
    try {
      final types = await _auth.getAvailableBiometrics();
      if (types.contains(BiometricType.face)) return 'Face ID / face unlock';
      if (types.contains(BiometricType.fingerprint)) return 'Fingerprint';
      if (types.isNotEmpty) return 'Biometrics';
    } catch (_) {}
    return 'Phone passcode';
  }

  Future<bool> authenticate() async {
    try {
      return await _auth.authenticate(
        localizedReason: 'Unlock Money Tracker',
        biometricOnly: false,
        persistAcrossBackgrounding: true,
      );
    } catch (_) {
      return false;
    }
  }
}
