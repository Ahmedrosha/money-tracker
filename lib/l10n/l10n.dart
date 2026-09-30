import 'ar.dart';

/// The language the app is showing: 'en' or 'ar'.
String appLang = 'en';

bool get isArabic => appLang == 'ar';

class _Template {
  _Template(this.re, this.out, this.weight);
  final RegExp re;
  final String out;
  final int weight;
}

List<_Template>? _templates;
final Map<String, String> _cache = {};
final RegExp _ph = RegExp(r'\{(\d+)\}');

List<_Template> _buildTemplates() {
  final list = <_Template>[];
  kArabic.forEach((key, value) {
    if (!_ph.hasMatch(key)) return;
    // Pure placeholders ("{0}{1}") would match anything; skip them.
    final literal = key.replaceAll(_ph, '');
    if (literal.trim().isEmpty) return;
    final buf = StringBuffer('^');
    var last = 0;
    for (final m in _ph.allMatches(key)) {
      buf.write(RegExp.escape(key.substring(last, m.start)));
      buf.write(r'([\s\S]*?)');
      last = m.end;
    }
    buf.write(RegExp.escape(key.substring(last)));
    buf.write(r'$');
    list.add(_Template(RegExp(buf.toString()), value, literal.length));
  });
  // Most specific (longest fixed text) first.
  list.sort((a, b) => b.weight.compareTo(a.weight));
  return list;
}

/// Translates an English UI string into the app language. Strings with
/// values inside ("Spent 120.00 of 500.00") are matched against templates
/// ("Spent {0} of {1}"); anything unknown is shown as it is.
String tr(String s) {
  if (appLang != 'ar' || s.isEmpty) return s;
  final exact = kArabic[s];
  if (exact != null) return exact;
  final cached = _cache[s];
  if (cached != null) return cached;
  var result = s;
  for (final t in _templates ??= _buildTemplates()) {
    final m = t.re.firstMatch(s);
    if (m == null) continue;
    result = t.out.replaceAllMapped(_ph, (x) {
      final i = int.parse(x.group(1)!) + 1;
      return i <= m.groupCount ? (m.group(i) ?? '') : '';
    });
    break;
  }
  if (_cache.length > 4000) _cache.clear();
  _cache[s] = result;
  return result;
}

/// Keeps numbers (and their minus sign) left-to-right inside Arabic text.
String ltr(String s) => isArabic ? '⁦$s⁩' : s;

/// Removes the direction marks added by [ltr].
String stripDirectionMarks(String s) =>
    s.replaceAll(RegExp('[‎‏‪-‮⁦-⁩]'), '');

const Map<String, String> _arCurrencyUnits = {
  'EGP': 'ج.م',
  'USD': r'$',
  'EUR': '€',
  'GBP': '£',
  'SAR': 'ر.س',
  'AED': 'د.إ',
  'KWD': 'د.ك',
  'QAR': 'ر.ق',
  'BHD': 'د.ب',
  'OMR': 'ر.ع',
  'JOD': 'د.أ',
};

/// Arabic unit for a currency code, or null to keep the code.
String? arabicCurrencyUnit(String code) => _arCurrencyUnits[code];

const Map<String, String> kArabicCurrencyNames = {
  'EGP': 'جنيه مصري',
  'USD': 'دولار أمريكي',
  'EUR': 'يورو',
  'GBP': 'جنيه إسترليني',
  'SAR': 'ريال سعودي',
  'AED': 'درهم إماراتي',
  'KWD': 'دينار كويتي',
  'QAR': 'ريال قطري',
  'BHD': 'دينار بحريني',
  'OMR': 'ريال عماني',
  'JOD': 'دينار أردني',
  'LBP': 'ليرة لبنانية',
  'MAD': 'درهم مغربي',
  'TND': 'دينار تونسي',
  'TRY': 'ليرة تركية',
  'CHF': 'فرنك سويسري',
  'JPY': 'ين ياباني',
  'CNY': 'يوان صيني',
  'INR': 'روبية هندية',
  'CAD': 'دولار كندي',
  'AUD': 'دولار أسترالي',
  'SEK': 'كرونة سويدية',
  'NOK': 'كرونة نرويجية',
  'DKK': 'كرونة دنماركية',
  'RUB': 'روبل روسي',
  'ZAR': 'راند جنوب أفريقي',
  'SGD': 'دولار سنغافوري',
  'HKD': 'دولار هونج كونج',
  'MYR': 'رينجت ماليزي',
  'PKR': 'روبية باكستانية',
};
