/// Common currencies offered in pickers. Any 3-letter code returned by the
/// exchange-rate service can also be used.
const Map<String, String> kCurrencyNames = {
  'EGP': 'Egyptian Pound',
  'USD': 'US Dollar',
  'EUR': 'Euro',
  'GBP': 'British Pound',
  'SAR': 'Saudi Riyal',
  'AED': 'UAE Dirham',
  'KWD': 'Kuwaiti Dinar',
  'QAR': 'Qatari Riyal',
  'BHD': 'Bahraini Dinar',
  'OMR': 'Omani Rial',
  'JOD': 'Jordanian Dinar',
  'LBP': 'Lebanese Pound',
  'MAD': 'Moroccan Dirham',
  'TND': 'Tunisian Dinar',
  'TRY': 'Turkish Lira',
  'CHF': 'Swiss Franc',
  'JPY': 'Japanese Yen',
  'CNY': 'Chinese Yuan',
  'INR': 'Indian Rupee',
  'CAD': 'Canadian Dollar',
  'AUD': 'Australian Dollar',
  'SEK': 'Swedish Krona',
  'NOK': 'Norwegian Krone',
  'DKK': 'Danish Krone',
  'RUB': 'Russian Ruble',
  'ZAR': 'South African Rand',
  'SGD': 'Singapore Dollar',
  'HKD': 'Hong Kong Dollar',
  'MYR': 'Malaysian Ringgit',
  'PKR': 'Pakistani Rupee',
};

/// Gold by weight: one "currency" per karat, measured in grams.
const List<String> kGoldCodes = ['XAU24', 'XAU21', 'XAU18'];

bool isGold(String code) => kGoldCodes.contains(code);

/// 24, 21 or 18 for gold codes.
int goldKarat(String code) => int.parse(code.substring(3));

/// Unit shown next to amounts: "g 21K" for gold, the code otherwise.
String currencyUnit(String code) => isGold(code) ? 'g ${goldKarat(code)}K' : code;

String currencyName(String code) {
  if (isGold(code)) return 'Gold ${goldKarat(code)}K (grams)';
  return kCurrencyNames[code] ?? code;
}
