import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:workmanager/workmanager.dart';

import '../data/db.dart';
import '../l10n/l10n.dart';
import '../util/format.dart';
import 'notifications.dart';
import 'rates.dart';

/// A price level to watch for one karat (per gram, main currency).
class GoldAlert {
  GoldAlert(this.code, {this.above, this.below});
  final String code; // XAU24, XAU21, XAU18
  double? above;
  double? below;

  Map<String, Object?> toJson() => {'code': code, 'above': above, 'below': below};
  static GoldAlert fromJson(Map<String, dynamic> m) => GoldAlert(m['code'] as String,
      above: (m['above'] as num?)?.toDouble(), below: (m['below'] as num?)?.toDouble());

  static List<GoldAlert> decode(String? s) {
    if (s == null || s.isEmpty) return [];
    try {
      return [for (final x in jsonDecode(s) as List) GoldAlert.fromJson(x as Map<String, dynamic>)];
    } catch (_) {
      return [];
    }
  }

  static String encode(List<GoldAlert> l) => jsonEncode([for (final a in l) a.toJson()]);
}

String karatLabel(String code) => '${code.substring(3)}K';

/// Checks the alerts against [prices] (code → price per gram). Returns the
/// notifications to show; [fired] keeps which levels already alerted (a
/// level alerts again only after the price went back).
List<(String, String)> evaluateGoldAlerts(
    List<GoldAlert> alerts, Map<String, double> prices, Set<String> fired, String base) {
  final out = <(String, String)>[];
  for (final a in alerts) {
    final p = prices[a.code];
    if (p == null) continue;
    final k = karatLabel(a.code);
    if (a.above != null) {
      final key = '${a.code}>${a.above}';
      if (p >= a.above!) {
        if (fired.add(key)) {
          out.add((tr('Gold $k is above ${fmtMoneyRaw(a.above!, base)}'),
              tr('Now ${fmtMoneyRaw(p, base)} per gram')));
        }
      } else {
        fired.remove(key);
      }
    }
    if (a.below != null) {
      final key = '${a.code}<${a.below}';
      if (p <= a.below!) {
        if (fired.add(key)) {
          out.add((tr('Gold $k is below ${fmtMoneyRaw(a.below!, base)}'),
              tr('Now ${fmtMoneyRaw(p, base)} per gram')));
        }
      } else {
        fired.remove(key);
      }
    }
  }
  return out;
}

/// Android: checks gold prices in the background a few times a day.
const goldTask = 'gold-check';

@pragma('vm:entry-point')
void goldCallbackDispatcher() {
  Workmanager().executeTask((task, input) async {
    WidgetsFlutterBinding.ensureInitialized();
    try {
      await goldBackgroundCheck();
    } catch (_) {}
    return true;
  });
}

Future<void> goldBackgroundCheck() async {
  final db = await AppDb.open();
  try {
    final alerts = GoldAlert.decode(await db.getSetting('gold_alerts'));
    if (alerts.isEmpty) return;
    final fetched = await RateService().fetchPerUsd();
    await db.saveFetchedRates(fetched);
    final rates = {for (final r in await db.rates()) r.code: r.perUsd};
    final base = await db.getSetting('base_currency') ?? 'EGP';
    final premium = double.tryParse(await db.getSetting('gold_premium') ?? '') ?? 0;
    final basePerUsd = base == 'USD' ? 1.0 : rates[base];
    if (basePerUsd == null) return;
    final prices = <String, double>{};
    for (final c in ['XAU24', 'XAU21', 'XAU18']) {
      final g = rates[c];
      if (g == null || g == 0) continue;
      prices[c] = basePerUsd / g * (1 + premium / 100);
    }
    final fired = (await db.getSetting('gold_fired') ?? '').split(',').where((x) => x.isNotEmpty).toSet();
    final msgs = evaluateGoldAlerts(alerts, prices, fired, base);
    await db.setSetting('gold_fired', fired.join(','));
    if (msgs.isEmpty) return;
    final n = Notifier();
    var i = 0;
    for (final (t, b) in msgs) {
      await n.showBudgetAlert(90000 + i++, t, b);
    }
  } finally {
    await db.close();
  }
}

/// Starts or stops the Android background check.
Future<void> scheduleGoldCheck(bool on) async {
  if (!Platform.isAndroid) return;
  try {
    await Workmanager().initialize(goldCallbackDispatcher);
    if (on) {
      await Workmanager().registerPeriodicTask(goldTask, goldTask,
          frequency: const Duration(hours: 4),
          constraints: Constraints(networkType: NetworkType.connected));
    } else {
      await Workmanager().cancelByUniqueName(goldTask);
    }
  } catch (_) {}
}
