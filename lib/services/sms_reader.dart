import 'dart:io';

import 'package:flutter/services.dart';

/// Android only: reads bank SMS from the phone's inbox (the permission is
/// in the GitHub APK; the Google Play build leaves it out).
class SmsReader {
  static const _ch = MethodChannel('ewt/sms');

  /// This build can read SMS at all.
  static Future<bool> available() async {
    if (!Platform.isAndroid) return false;
    try {
      return await _ch.invokeMethod<bool>('available') ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> granted() async {
    if (!Platform.isAndroid) return false;
    try {
      return await _ch.invokeMethod<bool>('granted') ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> request() async {
    if (!Platform.isAndroid) return false;
    try {
      return await _ch.invokeMethod<bool>('request') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Messages received after [since], oldest first.
  static Future<List<(String sender, String body, DateTime at)>> inbox(
      DateTime since) async {
    if (!Platform.isAndroid) return const [];
    try {
      final list = await _ch.invokeMethod<List<Object?>>(
              'inbox', {'since': since.millisecondsSinceEpoch}) ??
          const [];
      return [
        for (final e in list)
          if (e is Map)
            (
              (e['address'] as String?) ?? '',
              (e['body'] as String?) ?? '',
              DateTime.fromMillisecondsSinceEpoch((e['date'] as num).toInt()),
            )
      ];
    } catch (_) {
      return const [];
    }
  }
}
