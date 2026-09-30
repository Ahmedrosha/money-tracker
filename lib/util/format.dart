import 'package:intl/intl.dart';

import '../l10n/l10n.dart';
import 'calc.dart';
import 'currencies.dart';

final NumberFormat _amountFmt = NumberFormat('#,##0.00', 'en_US');
// Getters so they follow the app language when it changes.
DateFormat get dayFmt => DateFormat('EEE, d MMM yyyy');
DateFormat get shortDateFmt => DateFormat('d MMM yyyy');
DateFormat get monthFmt => DateFormat('MMMM yyyy');

/// When true, amounts on screen are shown as dots (the hide button).
bool amountsHidden = false;
const String kHiddenAmount = '••••';

/// Amount for display; dots while amounts are hidden.
String fmtAmount(double v) =>
    amountsHidden ? kHiddenAmount : ltr(fmtAmountRaw(v));

/// Always the real amount (input fields, notifications).
String fmtAmountRaw(double v) {
  // Avoid "-0.00".
  if (v.abs() < 0.005) v = 0;
  return _amountFmt.format(v);
}

String fmtMoney(double v, String currency) =>
    '${fmtAmount(v)} ${currencyUnit(currency)}';

String fmtMoneyRaw(double v, String currency) =>
    '${ltr(fmtAmountRaw(v))} ${currencyUnit(currency)}';

/// Parses user input like "1,234.5" or "1234,5".
double? parseAmount(String input) {
  var s = stripDirectionMarks(input).trim().replaceAll(' ', '');
  // Arabic-Indic digits and separators typed on an Arabic keyboard.
  const ar = '٠١٢٣٤٥٦٧٨٩';
  const fa = '۰۱۲۳۴۵۶۷۸۹';
  for (var i = 0; i < 10; i++) {
    s = s.replaceAll(ar[i], '$i').replaceAll(fa[i], '$i');
  }
  s = s.replaceAll('٫', '.').replaceAll('٬', ',');
  if (s.isEmpty) return null;
  // Typed math, e.g. "250+75" or "1200/3", is worked out (to 2 decimals).
  if (hasOperator(s)) {
    final v = evaluateExpression(s);
    return v == null ? null : (v * 100).roundToDouble() / 100;
  }
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
