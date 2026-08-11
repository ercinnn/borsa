import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../models/backtest.dart';
import '../theme/app_colors.dart';
import 'glass_card.dart';

/// Backtest sonucundaki equity curve'ü (strateji vs buy&hold), her ikisi de
/// başlangıç sermayesine göre % getiriye normalize edilmiş halde tek bir
/// çizgi grafikte gösterir. `widgets/comparison_chart.dart` ile aynı
/// CustomPainter deseni (bu proje hiçbir yerde charting paketi kullanmıyor)
/// ama sabit iki seri (strateji: cyan, buy&hold: soluk slate — referans
/// çizgisi olduğu belli olsun diye) ile sadeleştirilmiş hali.
class BacktestChart extends StatelessWidget {
  final BacktestResult result;
  const BacktestChart({super.key, required this.result});

  @override
  Widget build(BuildContext context) {
    final points = result.equityCurve;
    if (points.length < 2) return const SizedBox.shrink();

    final strategyPct = [
      for (final p in points) (p.strategyValue / result.initialCapital - 1) * 100,
    ];
    final buyHoldPct = [
      for (final p in points) (p.buyHoldValue / result.initialCapital - 1) * 100,
    ];

    var minPct = 0.0, maxPct = 0.0;
    for (final s in [strategyPct, buyHoldPct]) {
      for (final v in s) {
        if (v < minPct) minPct = v;
        if (v > maxPct) maxPct = v;
      }
    }
    if (minPct == maxPct) {
      minPct -= 1;
      maxPct += 1;
    }
    final pad = (maxPct - minPct) * 0.08;
    minPct -= pad;
    maxPct += pad;

    final dateFormat = DateFormat('dd.MM.yy');
    final labels = [for (final p in points) dateFormat.format(p.date.toLocal())];

    return GlassCard(
      padding: const EdgeInsets.all(12),
      glow: true,
      glowBullish: result.finalReturnPct >= 0,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 6,
            children: [
              _LegendEntry(
                  color: AppColors.cyan500, label: 'Strateji', pct: strategyPct.last),
              _LegendEntry(
                  color: AppColors.slate400, label: 'Al ve Tut', pct: buyHoldPct.last),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 64,
                height: 240,
                child: _PctAxis(minPct: minPct, maxPct: maxPct),
              ),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final width = constraints.maxWidth;
                    final labelEvery =
                        (60 / (width / labels.length)).ceil().clamp(1, labels.length);
                    return Column(
                      children: [
                        SizedBox(
                          height: 240,
                          width: width,
                          child: CustomPaint(
                            painter: _BacktestPainter(
                              strategyPct: strategyPct,
                              buyHoldPct: buyHoldPct,
                              minPct: minPct,
                              maxPct: maxPct,
                            ),
                            size: Size(width, 240),
                          ),
                        ),
                        SizedBox(
                          height: 24,
                          child: _LabelsRow(labels: labels, labelEvery: labelEvery),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LegendEntry extends StatelessWidget {
  final Color color;
  final String label;
  final double pct;
  const _LegendEntry({required this.color, required this.label, required this.pct});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(color: AppColors.slate100, fontWeight: FontWeight.w600)),
        const SizedBox(width: 6),
        Text(
          '${pct >= 0 ? '+' : ''}${pct.toStringAsFixed(2)}%',
          style: GoogleFonts.robotoMono(
            color: pct >= 0 ? AppColors.emerald400 : AppColors.rose500,
            fontWeight: FontWeight.w700,
            fontSize: 12,
          ),
        ),
      ],
    );
  }
}

class _PctAxis extends StatelessWidget {
  final double minPct;
  final double maxPct;
  const _PctAxis({required this.minPct, required this.maxPct});

  @override
  Widget build(BuildContext context) {
    const ticks = 5;
    return Column(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (var i = 0; i < ticks; i++)
          Text(
            '${(maxPct - (maxPct - minPct) * i / (ticks - 1)).toStringAsFixed(1)}%',
            style: GoogleFonts.robotoMono(fontSize: 10, color: AppColors.slate400),
          ),
      ],
    );
  }
}

class _LabelsRow extends StatelessWidget {
  final List<String> labels;
  final int labelEvery;
  const _LabelsRow({required this.labels, required this.labelEvery});

  @override
  Widget build(BuildContext context) {
    final cells = <Widget>[];
    var i = 0;
    while (i < labels.length) {
      final span = (labels.length - i < labelEvery) ? labels.length - i : labelEvery;
      cells.add(Expanded(
        flex: span,
        child: Center(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(labels[i], style: const TextStyle(fontSize: 10, color: AppColors.slate400)),
          ),
        ),
      ));
      i += span;
    }
    return Row(children: cells);
  }
}

class _BacktestPainter extends CustomPainter {
  final List<double> strategyPct;
  final List<double> buyHoldPct;
  final double minPct;
  final double maxPct;

  _BacktestPainter({
    required this.strategyPct,
    required this.buyHoldPct,
    required this.minPct,
    required this.maxPct,
  });

  double _y(double pct, double height) {
    final range = maxPct - minPct;
    if (range == 0) return height / 2;
    return height - (pct - minPct) / range * height;
  }

  void _drawLine(Canvas canvas, Size size, List<double> series, Color color) {
    if (series.length < 2) return;
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round;
    final path = Path();
    final stepX = size.width / (series.length - 1);
    for (var i = 0; i < series.length; i++) {
      final x = stepX * i;
      final y = _y(series[i], size.height);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(path, paint);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = AppColors.slate800.withValues(alpha: 0.5)
      ..strokeWidth = 1;
    for (var i = 0; i <= 4; i++) {
      final y = size.height * i / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }
    if (minPct < 0 && maxPct > 0) {
      final zeroY = _y(0, size.height);
      final zeroPaint = Paint()
        ..color = AppColors.slate400.withValues(alpha: 0.6)
        ..strokeWidth = 1;
      canvas.drawLine(Offset(0, zeroY), Offset(size.width, zeroY), zeroPaint);
    }

    _drawLine(canvas, size, buyHoldPct, AppColors.slate400);
    _drawLine(canvas, size, strategyPct, AppColors.cyan500);
  }

  @override
  bool shouldRepaint(covariant _BacktestPainter oldDelegate) {
    return oldDelegate.strategyPct != strategyPct ||
        oldDelegate.buyHoldPct != buyHoldPct ||
        oldDelegate.minPct != minPct ||
        oldDelegate.maxPct != maxPct;
  }
}
