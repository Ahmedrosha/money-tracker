import 'dart:convert';

import 'package:http/http.dart' as http;

/// Egyptian Exchange prices from Yahoo Finance (symbols like COMI.CA).
/// Unofficial and free; when it fails, the user's own prices are used.
class StockPriceService {
  static const _hosts = ['query1.finance.yahoo.com', 'query2.finance.yahoo.com'];

  /// Latest price for an EGX symbol such as "COMI", or null.
  Future<double?> fetch(String symbol) async {
    final ticker = '${symbol.toUpperCase()}.CA';
    for (final host in _hosts) {
      try {
        final res = await http.get(
          Uri.https(host, '/v8/finance/chart/$ticker',
              {'range': '1d', 'interval': '1d'}),
          headers: {'User-Agent': 'Mozilla/5.0'},
        ).timeout(const Duration(seconds: 15));
        if (res.statusCode != 200) continue;
        final body = jsonDecode(res.body) as Map<String, dynamic>;
        final result = (body['chart']?['result'] as List?)?.first;
        final meta = result?['meta'] as Map<String, dynamic>?;
        final p = meta?['regularMarketPrice'] ?? meta?['previousClose'];
        if (p is num && p > 0) return p.toDouble();
      } catch (_) {}
    }
    return null;
  }
}
