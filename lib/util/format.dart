import 'package:intl/intl.dart';

final NumberFormat _amountFmt = NumberFormat('#,##0.00', 'en_US');
final DateFormat dayFmt = DateFormat('EEE, d MMM yyyy');
final DateFormat shortDateFmt = DateFormat('d MMM yyyy');
final DateFormat monthFmt = DateFormat('MMMM yyyy');

String fmtAmount(double v) {
  // Avoid "-0.00".
  if (v.abs() < 0.005) v = 0;
  return _amountFmt.format(v);
}

String fmtMoney(double v, String currency) => '${fmtAmount(v)} $currency';

/// Parses user input like "1,234.5" or "1234,5".
double? parseAmount(String input) {
  var s = input.trim().replaceAll(' ', '');
  if (s.isEmpty) return null;
  if (s.contains(',') && s.contains('.')) {
    s = s.replaceAll(',', '');
  } else if (s.contains(',')) {
    // Treat a single comma followed by 1-2 digits as a decimal separator.
    final parts = s.split(',');
    if (parts.length == 2 && parts[1].length <= 2) {
      s = '${parts[0]}.${parts[1]}';
    } else {
      s = s.replaceAll(',', '');
    }
  }
  return double.tryParse(s);
}

String fmtRate(double v) {
  if (v >= 100) return v.toStringAsFixed(2);
  if (v >= 1) return v.toStringAsFixed(4);
  return v.toStringAsPrecision(4);
}
