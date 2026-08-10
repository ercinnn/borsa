import 'package:flutter/material.dart';

import '../models/candle.dart';

class CandlestickChart extends StatefulWidget {
  final CandleResult result;

  const CandlestickChart({super.key, required this.result});

  @override
  State<CandlestickChart> createState() => _CandlestickChartState();
}

class _CandlestickChartState extends State<CandlestickChart> {
  static const _chartHeight = 260.0;
  static const _labelHeight = 28.0;
  static const _axisWidth = 64.0;
  static const _minSlotWidth = 1.5;
  static const _maxSlotWidth = 46.0;
  static const _popupWidth = 148.0;

  int? _selectedIndex;
  double _minPrice = 0;
  double _maxPrice = 0;

  @override
  void initState() {
    super.initState();
    _computePriceRange();
  }

  @override
  void didUpdateWidget(covariant CandlestickChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Yeni sembol/aralık verisi geldiğinde eski mumun popup'ı anlamsız
    // kalacağından kapatılıyor.
    if (oldWidget.result != widget.result) {
      _selectedIndex = null;
      _computePriceRange();
    }
  }

  // Sadece widget.result değiştiğinde çağrılır; bir muma tıklayıp popup
  // açmak da build()'i yeniden çalıştırdığından, bu O(n) hesaplamayı her
  // tıklamada tekrarlamamak için sonuç burada saklanıyor.
  void _computePriceRange() {
    final candles = widget.result.candles;
    if (candles.isEmpty) return;
    final rawMin = candles.map((c) => c.low).reduce((a, b) => a < b ? a : b);
    final rawMax = candles.map((c) => c.high).reduce((a, b) => a > b ? a : b);
    final pad = (rawMax - rawMin) * 0.08 == 0 ? 1.0 : (rawMax - rawMin) * 0.08;
    _minPrice = rawMin - pad;
    _maxPrice = rawMax + pad;
  }

  @override
  Widget build(BuildContext context) {
    final candles = widget.result.candles;
    if (candles.isEmpty) {
      return const SizedBox.shrink();
    }
    final minPrice = _minPrice;
    final maxPrice = _maxPrice;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${widget.result.symbol} · Mum Grafik',
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
                      // Dar mum aralıklarında her mumun altına etiket
                      // sığmayacağından, etiketler ve dikey referans
                      // çizgileri ~60px'lik gruplar halinde birleştiriliyor.
                      final labelEvery =
                          (60 / slotWidth).ceil().clamp(1, candles.length);

                      return SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: SizedBox(
                          width: contentWidth,
                          child: Column(
                            children: [
                              SizedBox(
                                height: _chartHeight,
                                child: Stack(
                                  clipBehavior: Clip.none,
                                  children: [
                                    GestureDetector(
                                      behavior: HitTestBehavior.opaque,
                                      onTapUp: (details) {
                                        final idx =
                                            (details.localPosition.dx / slotWidth)
                                                .floor()
                                                .clamp(0, candles.length - 1);
                                        setState(() {
                                          _selectedIndex = idx;
                                        });
                                      },
                                      child: CustomPaint(
                                        painter: _CandlestickPainter(
                                          candles: candles,
                                          minPrice: minPrice,
                                          maxPrice: maxPrice,
                                          slotWidth: slotWidth,
                                          candleWidth: candleWidth,
                                          labelEvery: labelEvery,
                                        ),
                                        size: Size(contentWidth, _chartHeight),
                                      ),
                                    ),
                                    if (_selectedIndex != null)
                                      _CandleInfoPopup(
                                        candle: candles[_selectedIndex!],
                                        left: ((_selectedIndex! + 0.5) * slotWidth -
                                                _popupWidth / 2)
                                            .clamp(
                                          0.0,
                                          (contentWidth - _popupWidth)
                                              .clamp(0.0, double.infinity),
                                        ),
                                        width: _popupWidth,
                                        onClose: () =>
                                            setState(() => _selectedIndex = null),
                                      ),
                                  ],
                                ),
                              ),
                              SizedBox(
                                height: _labelHeight,
                                child: _PeriodLabels(
                                  candles: candles,
                                  slotWidth: slotWidth,
                                  labelEvery: labelEvery,
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

class _CandleInfoPopup extends StatelessWidget {
  final Candle candle;
  final double left;
  final double width;
  final VoidCallback onClose;

  const _CandleInfoPopup({
    required this.candle,
    required this.left,
    required this.width,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: left,
      top: 4,
      width: width,
      child: Card(
        elevation: 4,
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      candle.period,
                      style: const TextStyle(
                          fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                  ),
                  GestureDetector(
                    onTap: onClose,
                    child: const Icon(Icons.close, size: 14),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text('Yüksek: ${candle.high.toStringAsFixed(2)}',
                  style: const TextStyle(fontSize: 11, color: Color(0xFF1B8A5A))),
              Text('Düşük: ${candle.low.toStringAsFixed(2)}',
                  style: const TextStyle(fontSize: 11, color: Color(0xFFC62828))),
            ],
          ),
        ),
      ),
    );
  }
}

class _PeriodLabels extends StatelessWidget {
  final List<Candle> candles;
  final double slotWidth;
  final int labelEvery;

  const _PeriodLabels({
    required this.candles,
    required this.slotWidth,
    required this.labelEvery,
  });

  @override
  Widget build(BuildContext context) {
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
  final int labelEvery;

  _CandlestickPainter({
    required this.candles,
    required this.minPrice,
    required this.maxPrice,
    required this.slotWidth,
    required this.candleWidth,
    required this.labelEvery,
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

    // _PeriodLabels ile aynı grup sınırlarında, o tarihe denk gelen ince
    // dikey referans çizgileri.
    final dateGridPaint = Paint()
      ..color = Colors.grey.withValues(alpha: 0.18)
      ..strokeWidth = 1;
    for (var i = 0; i < candles.length; i += labelEvery) {
      final x = i * slotWidth;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), dateGridPaint);
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
        oldDelegate.slotWidth != slotWidth ||
        oldDelegate.labelEvery != labelEvery;
  }
}
