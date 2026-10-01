import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../state/app_state.dart';
import '../util/format.dart';

/// Colors for pie slices, in order.
const kSliceColors = [
  Color(0xFF26A69A),
  Color(0xFFF0B54A),
  Color(0xFFEF6A6A),
  Color(0xFF7C9CFF),
  Color(0xFFC18CFF),
  Color(0xFF5FCF8A),
  Color(0xFFFF9E57),
  Color(0xFF4FC3F7),
];
const kOtherSliceColor = Color(0xFF8A9A98);

class Slice {
  const Slice(this.label, this.value, {this.onTap});
  final String label;
  final double value;
  final VoidCallback? onTap;
}

/// Donut chart with the total in the middle and a legend beside it.
/// Small slices beyond [maxSlices] are combined into "Other".
class DonutChart extends StatelessWidget {
  const DonutChart({
    super.key,
    required this.slices,
    required this.currency,
    this.size = 150,
    this.maxSlices = 6,
  });

  final List<Slice> slices;
  final String currency;
  final double size;
  final int maxSlices;

  @override
  Widget build(BuildContext context) {
    final list = slices.where((s) => s.value > 0.004).toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    if (list.isEmpty) return const SizedBox.shrink();
    final shown = list.take(maxSlices).toList();
    final rest = list.skip(maxSlices).fold<double>(0, (s, x) => s + x.value);
    if (rest > 0.004) shown.add(Slice(tr('Other'), rest));
    final total = shown.fold<double>(0, (s, x) => s + x.value);
    Color colorOf(int i) => i >= maxSlices
        ? kOtherSliceColor
        : kSliceColors[i % kSliceColors.length];
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Row(
        children: [
          SizedBox(
            width: size,
            height: size,
            child: CustomPaint(
              painter: _DonutPainter(
                [for (final s in shown) s.value / total],
                [for (var i = 0; i < shown.length; i++) colorOf(i)],
                theme.colorScheme.surface,
              ),
              child: Center(
                child: Padding(
                  padding: EdgeInsets.all(size * 0.2),
                  child: FittedBox(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(fmtAmount(total).split('.').first,
                            style: theme.textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w700)),
                        Text(currency, style: theme.textTheme.bodySmall),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < shown.length; i++)
                  InkWell(
                    onTap: shown[i].onTap,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Row(
                        children: [
                          Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                                color: colorOf(i),
                                borderRadius: BorderRadius.circular(3)),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(shown[i].label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall),
                          ),
                          Text(
                            ltr('${(shown[i].value / total * 100).toStringAsFixed(shown[i].value / total < 0.1 ? 1 : 0)}%'),
                            style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DonutPainter extends CustomPainter {
  _DonutPainter(this.fractions, this.colors, this.gapColor);
  final List<double> fractions;
  final List<Color> colors;
  final Color gapColor;

  @override
  void paint(Canvas canvas, Size size) {
    final r = math.min(size.width, size.height) / 2;
    final stroke = r * 0.34;
    final rect = Rect.fromCircle(
        center: Offset(size.width / 2, size.height / 2), radius: r - stroke / 2);
    var start = -math.pi / 2;
    for (var i = 0; i < fractions.length; i++) {
      final sweep = fractions[i] * 2 * math.pi;
      final p = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..color = colors[i];
      canvas.drawArc(rect, start, sweep, false, p);
      // Thin gap between slices.
      if (fractions.length > 1) {
        final g = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke + 1
          ..color = gapColor;
        canvas.drawArc(rect, start + sweep - 0.012, 0.012, false, g);
      }
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(_DonutPainter old) =>
      old.fractions != fractions || old.colors != colors;
}

/// A short note at the top of a report explaining what it shows. Tap ⓘ to
/// hide or show it (remembered).
class ReportExplained extends StatelessWidget {
  const ReportExplained({
    super.key,
    required this.id,
    required this.text,
    required this.child,
  });

  final String id;
  final String text;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final hidden = state.isCollapsed('rinfo:$id');
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        Material(
          color: hidden ? Colors.transparent : scheme.secondaryContainer.withValues(alpha: 0.55),
          child: InkWell(
            onTap: () => state.toggleCollapsed('rinfo:$id'),
            child: Padding(
              padding: EdgeInsets.fromLTRB(16, hidden ? 4 : 10, 8, hidden ? 0 : 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!hidden)
                    Expanded(
                      child: Text(tr(text),
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: scheme.onSecondaryContainer, height: 1.35)),
                    )
                  else
                    const Spacer(),
                  Icon(hidden ? Icons.info_outline : Icons.expand_less,
                      size: 18, color: scheme.onSurfaceVariant),
                ],
              ),
            ),
          ),
        ),
        Expanded(child: child),
      ],
    );
  }
}
