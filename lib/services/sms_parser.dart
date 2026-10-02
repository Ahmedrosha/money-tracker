/// Reads bank SMS such as:
///   "Your Card ending **8397 has been charged with EGP6 030.00 at MY FAWRY
///    on 30.09.2026 07:25 PM and your Available Balance is 74 779.99 EGP"
///   "Your ADCB Account ending with ****8397 was credited with IPN transfer
///    for EGP 31409.65 on 30-09 21:22 from AHMED … with Ref 49e59d25."
///   "Your credit card #1010 was charged for EGP 14.99 at STARZPLAY.COM on
///    25/09/26  at 01:03. Available limit is  7485.40 …"
/// Works on wording rather than one bank's exact template, so similar
/// messages from other banks are understood too.
class ParsedSms {
  const ParsedSms({
    this.ignore = false,
    this.credit = false,
    this.amount,
    this.currency = 'EGP',
    this.last4 = '',
    this.payee = '',
    this.date,
    this.balance,
    this.availableLimit,
    this.instaPay = false,
    this.ref = '',
  });

  /// OTP, declined payment, promotion… nothing to record.
  final bool ignore;

  /// Money in (otherwise money out).
  final bool credit;
  final double? amount;
  final String currency;

  /// Card / account ending, '' when the message has none.
  final String last4;

  /// Merchant (money out) or sender (money in).
  final String payee;
  final DateTime? date;

  /// "Available balance" after this transaction, when the bank sends it.
  final double? balance;

  /// Credit cards: "available limit" after this transaction.
  final double? availableLimit;
  final bool instaPay;
  final String ref;

  bool get usable => !ignore && amount != null && amount! > 0;
}

class SmsParser {
  static const _num = r'([0-9][0-9 ,]*(?:\.[0-9]+)?)';
  static const _cur =
      r'(?<![A-Za-z])(EGP|USD|EUR|GBP|SAR|AED|KWD|QAR|L\.?E\.?|جنيه|جم|ج\.م)(?![A-Za-z])';

  static final _amountBefore = RegExp('$_cur\\s*$_num', caseSensitive: false);
  static final _amountAfter = RegExp('$_num\\s*$_cur', caseSensitive: false);

  static final _ignore = RegExp(
      r'\bOTP\b|one[- ]time|password|passcode|verification|activation code|'
      r'\bcode is\b|declined|rejected|unsuccessful|failed|not completed|'
      r'insufficient|رمز|كلمة (?:السر|المرور)|مرفوض|لم تتم|غير ناجحة|'
      r'monthly statement|statement (?:has a )?balance|minimum due|كشف حساب|الحد الأدنى للسداد',
      caseSensitive: false);

  static final _creditWords = RegExp(
      r'credited|received|deposit|refund|reversal|reversed|incoming|'
      r'cash ?back|إيداع|ايداع|استلام|وارد|إضافة|اضافة|مرتجع|استرداد|'
      r'تم تحويل .{0,20}إليك|لحسابك|'
      r'payment (?:received|credited)|سداد .{0,40}(?:بطاقت|الائتماني)',
      caseSensitive: false);

  static final _debitWords = RegExp(
      r'charged|debited|purchase|spent|withdraw|paid|payment of|'
      r'transferred to|sent to|خصم|سحب|شراء|دفع|مدين|تحويل (?:الى|إلى)|'
      r'تحويل لحظي|من حسابك',
      caseSensitive: false);

  static final _last4 = RegExp(
      r'(?:ending(?:\s+(?:with|in))?|#|No\.?|number|رقم|المنتهي(?:ة)? بـ?)\s*[*xX•.]*\s*(\d{4})\b|'
      r'[*xX•]{2,}\s*(\d{4})\b',
      caseSensitive: false);

  static final _payeeAt = RegExp(
      r'\s(?:at|@|لدى|في)\s+(.+?)(?=\s+on\s|\s+يوم\s|\s+بتاريخ\s|\.\s|,|\s+and\s|\s+Available|\s+Avl|$)',
      caseSensitive: false);
  static final _payeeTo = RegExp(
      r'\s(?:to|إلى|الى)\s+(.+?)(?=\s+on\s|\s+with\s|\s+Ref|\s+يوم\s|\.\s|,|$)',
      caseSensitive: false);
  static final _payeeFrom = RegExp(
      r'\s(?:from|من)\s+(.+?)(?=\s+on\s|\s+with\s|\s+Ref|\s+يوم\s|\.\s|,|$)',
      caseSensitive: false);

  static final _fullDate = RegExp(
      r'(\d{1,2})[./-](\d{1,2})[./-](\d{2,4})(?:\s+(?:at\s+)?(\d{1,2}):(\d{2})(?::\d{2})?\s*([AaPp][Mm])?)?');
  static final _shortDate =
      RegExp(r'(?<![\d./-])(\d{1,2})[-/](\d{1,2})\s+(?:at\s+)?(\d{1,2}):(\d{2})\s*([AaPp][Mm])?');

  static final _balance = RegExp(
      '(?:available balance|avl\\.? bal(?:ance)?|current balance|الرصيد(?: المتاح)?)'
      '\\s*(?:is|:|=)?\\s*(?:$_cur\\s*)?$_num',
      caseSensitive: false);
  static final _limit = RegExp(
      '(?:available (?:credit )?limit|الحد المتاح)\\s*(?:is|:|=)?\\s*(?:$_cur\\s*)?$_num',
      caseSensitive: false);

  static final _instaPay =
      RegExp(r'\bIPN\b|insta ?pay|انستا ?باي|إنستاباي|تحويل لحظي', caseSensitive: false);
  static final _ref = RegExp(
      r'(?:\bRef(?:erence)?\.?\s*(?:No\.?)?|(?:ب?ال?رقم )?مرجعي)\s*[:#]?\s*([A-Za-z0-9]+)',
      caseSensitive: false);

  static double? _toDouble(String s) {
    var t = s.trim().replaceAll(' ', '').replaceAll(',', '');
    while (t.endsWith('.')) {
      t = t.substring(0, t.length - 1);
    }
    return double.tryParse(t);
  }

  static String _currency(String c) {
    final u = c.toUpperCase().replaceAll('.', '');
    if (u == 'LE' || c == 'جنيه' || c == 'جم' || c == 'ج.م') return 'EGP';
    return u;
  }

  /// Arabic-Indic digits → 0-9.
  static String _digits(String s) {
    const ar = '٠١٢٣٤٥٦٧٨٩';
    const fa = '۰۱۲۳۴۵۶۷۸۹';
    var out = s;
    for (var i = 0; i < 10; i++) {
      out = out.replaceAll(ar[i], '$i').replaceAll(fa[i], '$i');
    }
    return out.replaceAll('٫', '.').replaceAll('٬', ',');
  }

  static int _hour(String h, String? ampm) {
    var v = int.parse(h);
    if (ampm != null) {
      final pm = ampm.toLowerCase() == 'pm';
      if (pm && v < 12) v += 12;
      if (!pm && v == 12) v = 0;
    }
    return v;
  }

  static ParsedSms parse(String raw, {DateTime? received}) {
    final text = _digits(raw).replaceAll(RegExp(r'\s+'), ' ').trim();
    final when = received ?? DateTime.now();

    // Amount: first "EGP 123.45" (or "123.45 EGP").
    double? amount;
    var currency = 'EGP';
    var amountEnd = 0;
    final a1 = _amountBefore.firstMatch(text);
    final a2 = _amountAfter.firstMatch(text);
    RegExpMatch? am;
    var before = true;
    if (a1 != null && (a2 == null || a1.start <= a2.start)) {
      am = a1;
    } else if (a2 != null) {
      am = a2;
      before = false;
    }
    if (am != null) {
      amount = _toDouble(before ? am.group(2)! : am.group(1)!);
      currency = _currency(before ? am.group(1)! : am.group(2)!);
      amountEnd = am.end;
    }

    if (_ignore.hasMatch(text) || amount == null) {
      return ParsedSms(ignore: true, amount: amount, currency: currency);
    }

    // Direction: whichever kind of word comes first.
    final c = _creditWords.firstMatch(text);
    final d = _debitWords.firstMatch(text);
    final credit = c != null && (d == null || c.start < d.start);

    final l = _last4.firstMatch(text);
    final last4 = l == null ? '' : (l.group(1) ?? l.group(2) ?? '');

    // Payee: merchant after "at", or the person after "from" / "to".
    String payee = '';
    final tail = text.substring(amountEnd);
    RegExpMatch? p;
    if (credit) {
      p = _payeeFrom.firstMatch(tail) ?? _payeeFrom.firstMatch(text);
    } else {
      p = _payeeAt.firstMatch(tail) ??
          _payeeTo.firstMatch(tail) ??
          _payeeAt.firstMatch(text);
    }
    if (p != null) {
      payee = p.group(1)!.trim();
      if (payee.length > 60) payee = payee.substring(0, 60).trim();
    }

    // Date and time.
    DateTime? date;
    final fd = _fullDate.firstMatch(tail) ?? _fullDate.firstMatch(text);
    if (fd != null) {
      final day = int.parse(fd.group(1)!);
      final month = int.parse(fd.group(2)!);
      var year = int.parse(fd.group(3)!);
      if (year < 100) year += 2000;
      if (month >= 1 && month <= 12 && day >= 1 && day <= 31) {
        final h = fd.group(4) == null ? when.hour : _hour(fd.group(4)!, fd.group(6));
        final m = fd.group(5) == null ? when.minute : int.parse(fd.group(5)!);
        date = DateTime(year, month, day, h, m);
      }
    }
    if (date == null) {
      final sd = _shortDate.firstMatch(tail) ?? _shortDate.firstMatch(text);
      if (sd != null) {
        final day = int.parse(sd.group(1)!);
        final month = int.parse(sd.group(2)!);
        if (month >= 1 && month <= 12 && day >= 1 && day <= 31) {
          var dt = DateTime(when.year, month, day,
              _hour(sd.group(3)!, sd.group(5)), int.parse(sd.group(4)!));
          // "30-12" received on 2 Jan is last year.
          if (dt.isAfter(when.add(const Duration(days: 2)))) {
            dt = DateTime(when.year - 1, month, day, dt.hour, dt.minute);
          }
          date = dt;
        }
      }
    }
    // A date far from when the message arrived is probably misread.
    if (date != null && date.difference(when).inDays.abs() > 60) date = null;

    final b = _balance.firstMatch(text);
    final lim = _limit.firstMatch(text);
    final r = _ref.firstMatch(text);

    return ParsedSms(
      credit: credit,
      amount: amount,
      currency: currency,
      last4: last4,
      payee: payee,
      date: date ?? when,
      balance: b == null ? null : _toDouble(b.group(b.groupCount)!),
      availableLimit: lim == null ? null : _toDouble(lim.group(lim.groupCount)!),
      instaPay: _instaPay.hasMatch(text),
      ref: r?.group(1) ?? '',
    );
  }
}
