import 'dart:io';

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

/// Receipt photos kept with transactions (Documents/receipts/).
class Receipts {
  static Future<Directory> dir() async {
    final docs = await getApplicationDocumentsDirectory();
    final d = Directory('${docs.path}/receipts');
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  static Future<File> file(String name) async => File('${(await dir()).path}/$name');

  /// Takes or picks a photo and keeps a small copy. Returns its name.
  static Future<String?> pick({required bool camera}) async {
    final x = await ImagePicker().pickImage(
      source: camera ? ImageSource.camera : ImageSource.gallery,
      imageQuality: 60,
      maxWidth: 1600,
    );
    if (x == null) return null;
    final name = 'r_${DateTime.now().millisecondsSinceEpoch}.jpg';
    await File(x.path).copy((await file(name)).path);
    return name;
  }

  static Future<void> delete(String name) async {
    try {
      final f = await file(name);
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }
}

/// What could be read from a receipt.
class ReceiptInfo {
  double? total;
  DateTime? date;
  String? shop;
  bool get any => total != null || date != null || shop != null;
}

/// Reads the total, date and shop name from a receipt photo (on the
/// phone; Latin letters and digits).
class ReceiptReader {
  static final _amount = RegExp(r'(\d{1,3}(?:[,\s]\d{3})+|\d+)(?:[.,](\d{1,2}))?(?!\d)');
  static final _totalWords = RegExp(
      r'grand\s*total|total\s*(?:due|amount)?|net\s*(?:total|amount)|amount\s*(?:due|paid)|to\s*pay|balance\s*due|'
      r'الإجمالي|الاجمالي|الإجمالى|المطلوب|صافي|الصافي',
      caseSensitive: false);
  static final _skipTotal = RegExp(r'sub\s*-?\s*total|items?|qty|quantity|discount|vat\s*%|tax\s*%|change|cash\s*back', caseSensitive: false);
  static final _dateDmy = RegExp(r'(\d{1,2})[/.\-](\d{1,2})[/.\-](\d{2,4})');
  static final _dateYmd = RegExp(r'(20\d{2})[/.\-](\d{1,2})[/.\-](\d{1,2})');
  static final _noise = RegExp(r'receipt|invoice|tax|vat|tel|phone|www|http|cashier|order|table|welcome|فاتورة|ضريبة',
      caseSensitive: false);

  static double? _num(String s) {
    final m = _amount.allMatches(s).toList();
    if (m.isEmpty) return null;
    final last = m.last;
    final whole = last.group(1)!.replaceAll(RegExp(r'[,\s]'), '');
    final dec = last.group(2);
    return double.tryParse(dec == null ? whole : '$whole.$dec');
  }

  static Future<ReceiptInfo> read(String path) async {
    final out = ReceiptInfo();
    final rec = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final res = await rec.processImage(InputImage.fromFilePath(path));
      final lines = <String>[
        for (final b in res.blocks)
          for (final l in b.lines) l.text.trim()
      ].where((l) => l.isNotEmpty).toList();
      parse(lines, out);
    } finally {
      await rec.close();
    }
    return out;
  }

  static void parse(List<String> lines, ReceiptInfo out) {
    // Total: a number on (or right after) a "total" line; the biggest wins.
    double? best;
    for (var i = 0; i < lines.length; i++) {
      final l = lines[i];
      if (!_totalWords.hasMatch(l) || _skipTotal.hasMatch(l)) continue;
      var v = _num(l);
      if (v == null && i + 1 < lines.length) v = _num(lines[i + 1]);
      if (v != null && v > 0 && v < 10000000 && (best == null || v > best)) best = v;
    }
    if (best == null) {
      // Otherwise the biggest amount with decimals.
      for (final l in lines) {
        if (_dateDmy.hasMatch(l) || _dateYmd.hasMatch(l)) continue;
        final m = RegExp(r'(\d[\d,]*)[.](\d{2})(?!\d)').allMatches(l);
        for (final x in m) {
          final v = double.tryParse('${x.group(1)!.replaceAll(',', '')}.${x.group(2)}');
          if (v != null && v < 10000000 && (best == null || v > best)) best = v;
        }
      }
    }
    out.total = best;

    // Date.
    final now = DateTime.now();
    for (final l in lines) {
      DateTime? d;
      final a = _dateYmd.firstMatch(l);
      if (a != null) {
        d = DateTime(int.parse(a.group(1)!), int.parse(a.group(2)!), int.parse(a.group(3)!));
      } else {
        final b = _dateDmy.firstMatch(l);
        if (b != null) {
          var y = int.parse(b.group(3)!);
          if (y < 100) y += 2000;
          final dd = int.parse(b.group(1)!), mm = int.parse(b.group(2)!);
          if (mm >= 1 && mm <= 12 && dd >= 1 && dd <= 31) d = DateTime(y, mm, dd);
        }
      }
      if (d != null && !d.isAfter(now.add(const Duration(days: 1))) &&
          now.difference(d).inDays < 400) {
        out.date = DateTime(d.year, d.month, d.day, now.hour, now.minute);
        break;
      }
    }

    // Shop: one of the first lines that reads like a name.
    for (final l in lines.take(5)) {
      final letters = l.replaceAll(RegExp(r'[^A-Za-z]'), '').length;
      if (letters < 3 || _noise.hasMatch(l)) continue;
      if (RegExp(r'\d').allMatches(l).length > letters) continue;
      out.shop = l.length > 40 ? l.substring(0, 40) : l;
      break;
    }
  }
}
