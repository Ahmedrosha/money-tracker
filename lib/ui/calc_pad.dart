import 'package:flutter/material.dart';

import '../util/calc.dart';
import '../util/format.dart';

/// Opens the calculator keypad for [controller]. The field keeps the
/// expression while typing; "Done" (or =) replaces it with the result.
Future<void> showCalcPad(
  BuildContext context,
  TextEditingController controller, {
  String? currency,
  VoidCallback? onChanged,
}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (_) => _CalcPad(
        controller: controller, currency: currency, onChanged: onChanged),
  );
}

/// Plain number text for a result: no trailing zeros, max 2 decimals.
String calcResultText(double v) {
  final r = (v * 100).roundToDouble() / 100;
  var s = r.toStringAsFixed(2);
  if (s.endsWith('.00')) s = s.substring(0, s.length - 3);
  if (s.contains('.') && s.endsWith('0')) s = s.substring(0, s.length - 1);
  return s;
}

class _CalcPad extends StatefulWidget {
  const _CalcPad({required this.controller, this.currency, this.onChanged});

  final TextEditingController controller;
  final String? currency;
  final VoidCallback? onChanged;

  @override
  State<_CalcPad> createState() => _CalcPadState();
}

class _CalcPadState extends State<_CalcPad> {
  String get _text => widget.controller.text;

  void _set(String t) {
    widget.controller.text = t;
    widget.controller.selection = TextSelection.collapsed(offset: t.length);
    widget.onChanged?.call();
    setState(() {});
  }

  static const _ops = ['+', '−', '×', '÷'];

  void _press(String k) {
    var t = _text;
    switch (k) {
      case 'C':
        _set('');
        return;
      case '⌫':
        if (t.isNotEmpty) _set(t.substring(0, t.length - 1));
        return;
      case '=':
        _equals();
        return;
      case '.':
        // Only one dot per number.
        final lastNum = t.split(RegExp(r'[+\-−×÷*/]')).last;
        if (lastNum.contains('.')) return;
        _set(t + (lastNum.isEmpty ? '0.' : '.'));
        return;
    }
    if (_ops.contains(k)) {
      if (t.isEmpty) {
        if (k == '−') _set('-'); // negative amount (refund)
        return;
      }
      // Replace a trailing operator instead of stacking them.
      final last = t[t.length - 1];
      if (_ops.contains(last) || last == '-' && t.length > 1) {
        t = t.substring(0, t.length - 1);
      }
      _set('$t$k');
      return;
    }
    _set(t + k);
  }

  /// Works out the expression and puts the result in the field.
  bool _equals() {
    final t = _text.trim();
    if (t.isEmpty) return true;
    if (!hasOperator(t)) return true;
    final v = evaluateExpression(t);
    if (v == null) return false;
    _set(calcResultText(v));
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final t = _text;
    final preview = hasOperator(t) ? evaluateExpression(t) : null;

    Widget key(String k, {Color? bg, Color? fg, int flex = 1}) => Expanded(
          flex: flex,
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: SizedBox(
              height: 56,
              child: FilledButton.tonal(
                style: FilledButton.styleFrom(
                  backgroundColor: bg,
                  foregroundColor: fg,
                  padding: EdgeInsets.zero,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: () => _press(k),
                child: Text(k, style: const TextStyle(fontSize: 22)),
              ),
            ),
          ),
        );

    final opBg = scheme.secondaryContainer;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Display
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      t.isEmpty ? '0' : t,
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                  ),
                  Text(
                    preview != null
                        ? '= ${fmtAmountRaw(preview)}${widget.currency == null ? '' : ' ${widget.currency}'}'
                        : (widget.currency ?? ''),
                    style: TextStyle(color: scheme.primary),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Row(children: [
              key('C', fg: scheme.error),
              key('⌫'),
              key('÷', bg: opBg),
              key('×', bg: opBg),
            ]),
            Row(children: [key('7'), key('8'), key('9'), key('−', bg: opBg)]),
            Row(children: [key('4'), key('5'), key('6'), key('+', bg: opBg)]),
            Row(children: [key('1'), key('2'), key('3'), key('=', bg: opBg)]),
            Row(children: [
              key('0', flex: 2),
              key('.'),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: SizedBox(
                    height: 56,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        padding: EdgeInsets.zero,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                      onPressed: () {
                        if (_equals()) Navigator.pop(context);
                      },
                      child: const Icon(Icons.check),
                    ),
                  ),
                ),
              ),
            ]),
          ],
        ),
      ),
    );
  }
}
