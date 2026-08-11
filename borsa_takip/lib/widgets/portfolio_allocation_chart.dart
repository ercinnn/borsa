import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/app_colors.dart';

/// Portföy dağılım rengi paleti — sembol sayısı 8'i geçerse döngüsel
/// tekrarlar (bu ölçekte bir "basit portföy" için yeterli).
const portfolioPalette = [
  AppColors.cyan500,
  AppColors.emerald400,
  AppColors.fuchsia600,
  Color(0xFFF59E0B), // amber
  AppColors.rose500,
  Color(0xFF8B5CF6), // violet
  Color(0xFF14B8A6), // teal
  Color(0xFF38BDF8), // light blue
];

class AllocationSlice {
  final String symbol;
  final double valueInTry;
  const AllocationSlice({required this.symbol, required this.valueInTry});
}

/// Portföyün TL karşılığına göre dağılımını gösteren donut grafik — bir
/// çizim paketi kullanmıyor, bu projenin diğer grafiklerinde olduğu gibi
/// (bkz. widgets/candlestick_chart.dart) `CustomPainter` ile çiziliyor.
class PortfolioAllocationChart extends StatelessWidget {
  final List<AllocationSlice> slices;

  const PortfolioAllocationChart({super.key, required this.slices});

  @override
  Widget build(BuildContext context) {
    final total = slices.fold<double>(0, (sum, s) => sum + s.valueInTry);
    if (total <= 0) return const SizedBox.shrink();

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 140,
          height: 140,
          child: CustomPaint(painter: _DonutPainter(slices: slices, total: total)),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < slices.length; i++)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: portfolioPalette[i % portfolioPalette.length],
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(slices[i].symbol,
                            style: const TextStyle(color: AppColors.slate100, fontSize: 12)),
                      ),
                      Text(
                        '${(slices[i].valueInTry / total * 100).toStringAsFixed(1)}%',
                        style: GoogleFonts.robotoMono(fontSize: 12, color: AppColors.slate400),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DonutPainter extends CustomPainter {
  final List<AllocationSlice> slices;
  final double total;

  _DonutPainter({required this.slices, required this.total});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2;
    const strokeWidth = 22.0;
    var startAngle = -math.pi / 2;

    for (var i = 0; i < slices.length; i++) {
      final sweep = (slices[i].valueInTry / total) * 2 * math.pi;
      final paint = Paint()
        ..color = portfolioPalette[i % portfolioPalette.length]
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.butt;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius - strokeWidth / 2),
        startAngle,
        sweep,
        false,
        paint,
      );
      startAngle += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter oldDelegate) =>
      oldDelegate.slices != slices || oldDelegate.total != total;
}
