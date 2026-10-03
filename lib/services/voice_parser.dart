import '../data/models.dart';
import '../l10n/l10n.dart';
import '../state/app_state.dart';

/// What a spoken sentence filled in. Anything null was not understood.
class VoiceEntry {
  TxType type = TxType.expense;
  double? amount;
  int? accountId;
  int? toAccountId;
  int? categoryId;
  String? payee;
  DateTime? date;
}

/// Understands sentences like "Spent 450 on fuel with the CIB card",
/// "Received 20000 salary in ADCB", "Transfer 5000 from CIB to cash",
/// «دفعت ٤٥٠ بنزين من بطاقة CIB». Uses the user's own account, category
/// and payee names.
class VoiceParser {
  static String _digits(String s) {
    const ar = '٠١٢٣٤٥٦٧٨٩';
    const fa = '۰۱۲۳۴۵۶۷۸۹';
    var out = s;
    for (var i = 0; i < 10; i++) {
      out = out.replaceAll(ar[i], '$i').replaceAll(fa[i], '$i');
    }
    return out.replaceAll('٫', '.').replaceAll('٬', ',');
  }

  static final _income = RegExp(
      r'\b(received|receive|got paid|earned|income|salary|refund|deposit)\b|'
      r'قبضت|استلمت|دخل|مرتب|راتب|إيداع|ايداع|استرداد',
      caseSensitive: false);
  static final _transfer = RegExp(
      r'\b(transfer|transferred|moved?|sent)\b|حولت|حوّلت|تحويل|نقلت',
      caseSensitive: false);
  static final _yesterday = RegExp(r'\byesterday\b|امبارح|أمس|امس', caseSensitive: false);
  static final _number = RegExp(r'(\d[\d,]*(?:\.\d+)?)\s*(k|thousand|الف|ألف|آلاف)?',
      caseSensitive: false);

  // Spoken Arabic numbers ("خمسمية وخمسين", "ألفين", "تلات تلاف").
  static final Map<String, int> _arWords = {
    'واحد': 1, 'واحدة': 1, 'اتنين': 2, 'اثنين': 2, 'إثنين': 2, 'اثنان': 2,
    'تلاتة': 3, 'ثلاثة': 3, 'تلات': 3, 'ثلاث': 3, 'اربعة': 4, 'أربعة': 4, 'اربع': 4, 'أربع': 4,
    'خمسة': 5, 'خمس': 5, 'ستة': 6, 'ست': 6, 'سبعة': 7, 'سبع': 7,
    'تمانية': 8, 'ثمانية': 8, 'تمن': 8, 'ثمان': 8, 'تسعة': 9, 'تسع': 9, 'عشرة': 10, 'عشر': 10,
    'حداشر': 11, 'اتناشر': 12, 'تلتاشر': 13, 'اربعتاشر': 14, 'خمستاشر': 15, 'ستاشر': 16,
    'سبعتاشر': 17, 'تمنتاشر': 18, 'تسعتاشر': 19,
    'عشرين': 20, 'تلاتين': 30, 'ثلاثين': 30, 'اربعين': 40, 'أربعين': 40, 'خمسين': 50,
    'ستين': 60, 'سبعين': 70, 'تمانين': 80, 'ثمانين': 80, 'تسعين': 90,
    'مية': 100, 'ميه': 100, 'مائة': 100, 'مئة': 100, 'ميت': 100,
    'ميتين': 200, 'مئتين': 200, 'مائتين': 200, 'متين': 200,
    'تلتمية': 300, 'ثلاثمائة': 300, 'تلاتمية': 300, 'ربعمية': 400, 'اربعمية': 400, 'أربعمائة': 400,
    'خمسمية': 500, 'خمسمائة': 500, 'ستمية': 600, 'ستمائة': 600, 'سبعمية': 700, 'سبعمائة': 700,
    'تمنمية': 800, 'ثمانمائة': 800, 'تسعمية': 900, 'تسعمائة': 900,
  };
  static const _arThousand = {'الف', 'ألف', 'آلاف', 'الاف', 'تلاف', 'ألاف'};
  static const _arTwoThousand = {'الفين', 'ألفين'};
  static const _arMillion = {'مليون', 'ملايين'};

  static double? _arabicNumber(String text) {
    var total = 0.0, current = 0.0;
    var started = false;
    for (var w in text.split(RegExp(r'\s+'))) {
      w = w.replaceAll(RegExp(r'[^\u0600-\u06FF]'), '');
      if (w.isEmpty) continue;
      if (w.length > 2 && w.startsWith('و') &&
          (_arWords.containsKey(w.substring(1)) || _arThousand.contains(w.substring(1)) ||
              _arTwoThousand.contains(w.substring(1)))) {
        w = w.substring(1);
      }
      if (w == 'و' && started) continue;
      final v = _arWords[w];
      if (v != null) {
        current += v;
        started = true;
      } else if (_arTwoThousand.contains(w)) {
        total += 2000;
        started = true;
      } else if (_arThousand.contains(w)) {
        total += (current == 0 ? 1 : current) * 1000;
        current = 0;
        started = true;
      } else if (_arMillion.contains(w)) {
        total += (current == 0 ? 1 : current) * 1000000;
        current = 0;
        started = true;
      } else if (started) {
        break;
      }
    }
    return started ? total + current : null;
  }

  static VoiceEntry parse(AppState state, String raw, List<String> payees) {
    final e = VoiceEntry();
    final text = _digits(raw).trim();
    final lower = text.toLowerCase();

    // Amount: the first number ("1,200", "450.5", "3 thousand").
    final m = _number.firstMatch(text);
    if (m != null) {
      var v = double.tryParse(m.group(1)!.replaceAll(',', ''));
      if (v != null && m.group(2) != null) v *= 1000;
      e.amount = v;
    }

    e.amount ??= _arabicNumber(text);

    if (_transfer.hasMatch(text)) {
      e.type = TxType.transfer;
    } else if (_income.hasMatch(text)) {
      e.type = TxType.income;
    }
    if (_yesterday.hasMatch(text)) {
      final n = DateTime.now();
      e.date = DateTime(n.year, n.month, n.day - 1, n.hour, n.minute);
    }

    // Accounts mentioned, in the order they are said.
    final found = <(int, int, int)>[]; // position, length, id
    for (final a in state.accounts.where((a) => !a.archived)) {
      final names = <String>{
        a.name.toLowerCase(),
        if (a.bank.isNotEmpty) a.bank.toLowerCase(),
        if (a.bank.isNotEmpty) '${a.bank} ${a.name}'.toLowerCase(),
        ...state.detailsOf(a.id).digits,
      }..removeWhere((x) => x.trim().length < 2);
      var best = (-1, 0);
      for (final n in names) {
        final i = lower.indexOf(n);
        if (i >= 0 && n.length > best.$2) best = (i, n.length);
      }
      if (best.$1 >= 0) found.add((best.$1, best.$2, a.id!));
    }
    // Several accounts share a bank: prefer cards when "card" is said.
    final saysCard = RegExp(r'\bcard\b|بطاقة|كارت|فيزا|visa', caseSensitive: false).hasMatch(text);
    found.sort((x, y) => x.$1 != y.$1 ? x.$1.compareTo(y.$1) : y.$2.compareTo(x.$2));
    final unique = <int>[];
    for (final f in found) {
      if (!unique.contains(f.$3)) unique.add(f.$3);
    }
    int? pick(List<int> ids) {
      if (ids.isEmpty) return null;
      if (saysCard) {
        final c = ids.where((id) => state.accountById(id)?.type == AccountType.creditCard);
        if (c.isNotEmpty) return c.first;
      }
      return ids.first;
    }

    if (e.type == TxType.transfer && unique.length >= 2) {
      e.accountId = unique[0];
      e.toAccountId = unique[1];
    } else {
      e.accountId = pick(unique);
    }
    if (e.accountId == null && RegExp(r'\bcash\b|كاش|نقد', caseSensitive: false).hasMatch(text)) {
      final cash = state.accounts.where((a) => !a.archived && a.type == AccountType.cash);
      if (cash.isNotEmpty) e.accountId = cash.first.id;
    }
    if (e.type == TxType.transfer) return e;

    // Payee: a known one said in the sentence (the longest wins), or the
    // words after "at".
    String? payee;
    for (final p in payees) {
      final k = p.toLowerCase();
      if (k.length < 3) continue;
      if (lower.contains(k) && (payee == null || k.length > payee.length)) payee = p;
    }
    if (payee == null) {
      final at = RegExp(r'\b(?:at|from)\s+([A-Za-z][\w&\. ]{1,30}?)(?=\s+(?:with|using|on|by|for|from|yesterday|today)\b|[.,]|$)',
              caseSensitive: false)
          .firstMatch(text);
      final name = at?.group(1)?.trim();
      if (name != null &&
          !state.accounts.any((a) => name.toLowerCase().contains(a.name.toLowerCase()))) {
        payee = name;
      }
    }
    e.payee = payee;

    // Category: the merchant's rule, then a category name said (English or
    // Arabic).
    final rule = payee == null ? null : state.ruleFor(payee);
    if (rule?.payee.isNotEmpty == true) e.payee = rule!.payee;
    var cat = rule?.categoryId;
    if (cat == null || state.categoryById(cat)?.kind != e.type) {
      cat = null;
      var bestLen = 0;
      for (final c in state.categoriesOf(e.type)) {
        for (final n in {c.name.toLowerCase(), tr(c.name).toLowerCase()}) {
          // "Fuel" also matches "fuel", "Food & Dining" matches "food".
          final first = n.split(RegExp(r'[ &/،]+')).first;
          for (final k in {n, if (first.length >= 4) first}) {
            if (k.length >= 3 && lower.contains(k) && k.length > bestLen) {
              bestLen = k.length;
              cat = c.id;
            }
          }
        }
      }
    }
    e.categoryId = cat;
    return e;
  }
}
