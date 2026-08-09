import 'package:flutter/material.dart';

import '../models/candle.dart';

class CandlestickChart extends StatelessWidget {
  final CandleResult result;

  const CandlestickChart({super.key, required this.result});

  static const _chartHeight = 260.0;
  static const _labelHeight = 28.0;
  static const _axisWidth = 64.0;
  static const _minSlotWidth = 1.5;
  static const _maxSlotWidth = 46.0;

  @override
  Widget build(BuildContext context) {
    final candles = result.candles;
    if (candles.isEmpty) {
      return const SizedBox.shrink();
    }

    final rawMin = candles.map((c) => c.low).reduce((a, b) => a < b ? a : b);
    final rawMax = candles.map((c) => c.high).reduce((a, b) => a > b ? a : b);
    final pad = (rawMax - rawMin) * 0.08 == 0 ? 1.0 : (rawMax - rawMin) * 0.08;
    final minPrice = rawMin - pad;
    final maxPrice = rawMax + pad;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${result.symbol} · Mum Grafik',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: _axisWidth,
                  height: _chartHeight,
                  child: _PriceAxis(minPrice: minPrice, maxPrice: maxPrice),
                ),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      // Tüm mumları mevcut genişliğe sığdırmak için mum
                      // başına düşen genişlik ekrana göre daraltılıyor.
                      final slotWidth =
                          (constraints.maxWidth / candles.length)
                              .clamp(_minSlotWidth, _maxSlotWidth);
                      final candleWidth = (slotWidth * 0.7).clamp(1.0, 20.0);
                      final contentWidth = slotWidth * candles.length;

                      return SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: SizedBox(
                          width: contentWidth,
                          child: Column(
                            children: [
                              SizedBox(
                                height: _chartHeight,
                                child: CustomPaint(
                                  painter: _CandlestickPainter(
                                    candles: candles,
                                    minPrice: minPrice,
                                    maxPrice: maxPrice,
                                    slotWidth: slotWidth,
                                    candleWidth: candleWidth,
                                  ),
                                  size: Size(contentWidth, _chartHeight),
                                ),
                              ),
                              SizedBox(
                                height: _labelHeight,
                                child: _PeriodLabels(
                                  candles: candles,
                                  slotWidth: slotWidth,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PeriodLabels extends StatelessWidget {
  final List<Candle> candles;
  final double slotWidth;

  const _PeriodLabels({required this.candles, required this.slotWidth});

  @override
  Widget build(BuildContext context) {
    // Dar mum aralıklarında her mumun altına etiket sığmayacağından,
    // etiketler yaklaşık 60px'lik gruplar halinde birleştirilip gösteriliyor.
    final labelEvery = (60 / slotWidth).ceil().clamp(1, candles.length);
    final cells = <Widget>[];
    var i = 0;
    while (i < candles.length) {
      final span = (candles.length - i < labelEvery)
          ? candles.length - i
          : labelEvery;
      cells.add(
        SizedBox(
          width: slotWidth * span,
          child: Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                candles[i].period,
                style: const TextStyle(fontSize: 10),
              ),
            ),
          ),
        ),
      );
      i += span;
    }
    return Row(children: cells);
  }
}

class _PriceAxis extends StatelessWidget {
  final double minPrice;
  final double maxPrice;

  const _PriceAxis({required this.minPrice, required this.maxPrice});

  @override
  Widget build(BuildContext context) {
    const ticks = 5;
    return Column(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (var i = 0; i < ticks; i++)
          Text(
            (maxPrice - (maxPrice - minPrice) * i / (ticks - 1))
                .toStringAsFixed(2),
            style: const TextStyle(fontSize: 10, color: Colors.grey),
          ),
      ],
    );
  }
}

class _CandlestickPainter extends CustomPainter {
  final List<Candle> candles;
  final double minPrice;
  final double maxPrice;
  final double slotWidth;
  final double candleWidth;

  _CandlestickPainter({
    required this.candles,
    required this.minPrice,
    required this.maxPrice,
    required this.slotWidth,
    required this.candleWidth,
  });

  double _priceToY(double price, double height) {
    final range = maxPrice - minPrice;
    if (range == 0) return height / 2;
    return height - (price - minPrice) / range * height;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = Colors.grey.withValues(alpha: 0.2)
      ..strokeWidth = 1;
    for (var i = 0; i <= 4; i++) {
      final y = size.height * i / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    final wickWidth = slotWidth < 4 ? 1.0 : 2.0;
    for (var i = 0; i < candles.length; i++) {
      final c = candles[i];
      final x = i * slotWidth + slotWidth / 2;
      final isUp = c.close >= c.open;
      final color = isUp ? const Color(0xFF1B8A5A) : const Color(0xFFC62828);

      final wickPaint = Paint()
        ..color = color
        ..strokeWidth = wickWidth;
      canvas.drawLine(
        Offset(x, _priceToY(c.high, size.height)),
        Offset(x, _priceToY(c.low, size.height)),
        wickPaint,
      );

      final bodyTop = _priceToY(isUp ? c.close : c.open, size.height);
      final bodyBottom = _priceToY(isUp ? c.open : c.close, size.height);
      final bodyPaint = Paint()..color = color;
      final rect = Rect.fromLTRB(
        x - candleWidth / 2,
        bodyTop,
        x + candleWidth / 2,
        bodyBottom == bodyTop ? bodyTop + 1 : bodyBottom,
      );
      canvas.drawRect(rect, bodyPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _CandlestickPainter oldDelegate) {
    return oldDelegate.candles != candles ||
        oldDelegate.minPrice != minPrice ||
        oldDelegate.maxPrice != maxPrice ||
        oldDelegate.slotWidth != slotWidth;
  }
}
