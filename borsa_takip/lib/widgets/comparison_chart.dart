import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/candle.dart';
import '../theme/app_colors.dart';
import 'glass_card.dart';

/// Renk paleti — seçilen sembol sırasına göre atanır, favori/watchlist
/// chip'lerindeki renklerle karışmasın diye ayrı: cyan → emerald → rose →
/// fuchsia, tema paletinden (bkz. app_colors.dart).
const comparisonLineColors = [
  AppColors.cyan500,
  AppColors.emerald400,
  AppColors.rose500,
  AppColors.fuchsia600,
];

/// Birden fazla sembolün fiyatını, her serinin kendi başlangıcına göre
/// yüzdesel değişime normalize ederek tek bir çizgi grafikte üst üste
/// gösterir (ör. THYAO vs BIST100). Semboller farklı takvimlerde işlem
/// görebildiğinden (BIST hafta sonu kapalı, kripto 7/24) mum sayıları farklı
/// olabilir — tam takvim hizalaması yerine, tüm serilerin SONU (bugün) aynı
/// noktaya denk gelecek şekilde en kısa serinin uzunluğuna göre geriye doğru
/// kırpılıp hizalanır (bkz. ComparisonScreen._alignSeries). Bu, tarih
/// eksenini birebir doğru göstermez ama "son N mum" karşılaştırmasını
/// anlamlı tutar.
class ComparisonChart extends StatelessWidget {
  final List<String> symbols;
  final List<List<Candle>> alignedSeries;

  const ComparisonChart({super.key, required this.symbols, required this.alignedSeries});

  @override
  Widget build(BuildContext context) {
    if (alignedSeries.isEmpty || alignedSeries.first.isEmpty) {
      return const SizedBox.shrink();
    }

    final pctSeries = <List<double>>[];
    for (final series in alignedSeries) {
      final base = series.first.close;
      pctSeries.add([for (final c in series) base == 0 ? 0 : (c.close / base - 1) * 100]);
    }
    var minPct = 0.0, maxPct = 0.0;
    for (final s in pctSeries) {
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

    final periods = alignedSeries.first.map((c) => c.period).toList();

    return GlassCard(
      padding: const EdgeInsets.all(12),
      glow: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 6,
            children: [
              for (var i = 0; i < symbols.length; i++)
                _LegendEntry(
                  color: comparisonLineColors[i % comparisonLineColors.length],
                  symbol: symbols[i],
                  pct: pctSeries[i].last,
                ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 56,
                height: 240,
                child: _PctAxis(minPct: minPct, maxPct: maxPct),
              ),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final width = constraints.maxWidth;
                    final labelEvery =
                        (60 / (width / periods.length)).ceil().clamp(1, periods.length);
                    return Column(
                      children: [
                        SizedBox(
                          height: 240,
                          width: width,
                          child: CustomPaint(
                            painter: _ComparisonPainter(
                              pctSeries: pctSeries,
                              minPct: minPct,
                              maxPct: maxPct,
                            ),
                            size: Size(width, 240),
                          ),
                        ),
                        SizedBox(
                          height: 24,
                          child: _PeriodLabelsRow(periods: periods, labelEvery: labelEvery),
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
  final String symbol;
  final double pct;
  const _LegendEntry({required this.color, required this.symbol, required this.pct});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text(symbol, style: const TextStyle(color: AppColors.slate100, fontWeight: FontWeight.w600)),
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

class _PeriodLabelsRow extends StatelessWidget {
  final List<String> periods;
  final int labelEvery;
  const _PeriodLabelsRow({required this.periods, required this.labelEvery});

  @override
  Widget build(BuildContext context) {
    final cells = <Widget>[];
    var i = 0;
    while (i < periods.length) {
      final span = (periods.length - i < labelEvery) ? periods.length - i : labelEvery;
      cells.add(Expanded(
        flex: span,
        child: Center(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(periods[i], style: const TextStyle(fontSize: 10, color: AppColors.slate400)),
          ),
        ),
      ));
      i += span;
    }
    return Row(children: cells);
  }
}

class _ComparisonPainter extends CustomPainter {
  final List<List<double>> pctSeries;
  final double minPct;
  final double maxPct;

  _ComparisonPainter({required this.pctSeries, required this.minPct, required this.maxPct});

  double _y(double pct, double height) {
    final range = maxPct - minPct;
    if (range == 0) return height / 2;
    return height - (pct - minPct) / range * height;
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
    // %0 çizgisi (başlangıç seviyesi) diğerlerinden belirgin.
    if (minPct < 0 && maxPct > 0) {
      final zeroY = _y(0, size.height);
      final zeroPaint = Paint()
        ..color = AppColors.slate400.withValues(alpha: 0.6)
        ..strokeWidth = 1;
      canvas.drawLine(Offset(0, zeroY), Offset(size.width, zeroY), zeroPaint);
    }

    for (var s = 0; s < pctSeries.length; s++) {
      final series = pctSeries[s];
      if (series.length < 2) continue;
      final color = comparisonLineColors[s % comparisonLineColors.length];
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
  }

  @override
  bool shouldRepaint(covariant _ComparisonPainter oldDelegate) {
    return oldDelegate.pctSeries != pctSeries ||
        oldDelegate.minPct != minPct ||
        oldDelegate.maxPct != maxPct;
  }
}
