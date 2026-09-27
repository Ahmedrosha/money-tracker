import 'dart:convert';

import 'package:http/http.dart' as http;

/// Fetches exchange rates as "units per 1 USD".
class RateService {
  static const _primary = 'https://open.er-api.com/v6/latest/USD';
  static const _fallback =
      'https://cdn.jsdelivr.net/npm/@fawazahmed0/currency-api@latest/v1/currencies/usd.json';

  Future<Map<String, double>> fetchPerUsd() async {
    try {
      return await _fetchPrimary();
    } catch (_) {
      return await _fetchFallback();
    }
  }

  Future<Map<String, double>> _fetchPrimary() async {
    final res = await http
        .get(Uri.parse(_primary))
        .timeout(const Duration(seconds: 15));
    if (res.statusCode != 200) {
      throw Exception('HTTP ${res.statusCode}');
    }
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    if (body['result'] != 'success') {
      throw Exception('Rate service error');
    }
    final raw = body['rates'] as Map<String, dynamic>;
    return _clean(raw, upper: false);
  }

  Future<Map<String, double>> _fetchFallback() async {
    final res = await http
        .get(Uri.parse(_fallback))
        .timeout(const Duration(seconds: 15));
    if (res.statusCode != 200) {
      throw Exception('HTTP ${res.statusCode}');
    }
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final raw = body['usd'] as Map<String, dynamic>;
    return _clean(raw, upper: true);
  }

  Map<String, double> _clean(Map<String, dynamic> raw, {required bool upper}) {
    final out = <String, double>{};
    raw.forEach((k, v) {
      final code = upper ? k.toUpperCase() : k;
      if (code.length != 3) return;
      if (v is num && v > 0) out[code] = v.toDouble();
    });
    out['USD'] = 1.0;
    return out;
  }
}
