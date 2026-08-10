import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/candle.dart';
import '../theme/app_colors.dart';
import '../utils/price_format.dart';
import 'glass_card.dart';

/// Mum grafiği + isteğe bağlı, altında TradingView tarzı RSI/MACD panelleri
/// (bkz. `MarketApi.candles(includeIndicators: true)` — sadece o zaman
/// `candle.rsi`/`macd` dolu gelir). Panel açık/kapalıysa fark etmeksizin
/// tüm bölümler (fiyat ekseni + RSI ekseni + MACD ekseni solda, mum/RSI/MACD
/// çizimleri + tarih etiketleri sağda) TEK bir yatay `SingleChildScrollView`
/// içinde, TEK bir `slotWidth` hesabı paylaşılarak dikeyde istiflenir — bu
/// yüzden panellerin x ekseni mumlarla piksel piksel hizalı kalır.
class CandlestickChart extends StatefulWidget {
  final CandleResult result;

  const CandlestickChart({super.key, required this.result});

  @override
  State<CandlestickChart> createState() => _CandlestickChartState();
}

class _CandlestickChartState extends State<CandlestickChart> {
  static const _chartHeight = 260.0;
  static const _indicatorHeight = 70.0;
  static const _sectionGap = 6.0;
  static const _labelHeight = 28.0;
  static const _axisWidth = 64.0;
  static const _minSlotWidth = 1.5;
  static const _maxSlotWidth = 46.0;
  static const _popupWidth = 148.0;

  int? _selectedIndex;
  bool _showIndicators = true;
  double _minPrice = 0;
  double _maxPrice = 0;
  double _minMacd = 0;
  double _maxMacd = 0;

  @override
  void initState() {
    super.initState();
    _computeRanges();
  }

  @override
  void didUpdateWidget(covariant CandlestickChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Yeni sembol/aralık verisi geldiğinde eski mumun popup'ı anlamsız
    // kalacağından kapatılıyor.
    if (oldWidget.result != widget.result) {
      _selectedIndex = null;
      _computeRanges();
    }
  }

  bool get _hasRsi => widget.result.candles.any((c) => c.rsi != null);
  bool get _hasMacd => widget.result.candles.any((c) => c.macd != null);

  // Sadece widget.result değiştiğinde çağrılır; bir muma tıklayıp popup
  // açmak da build()'i yeniden çalıştırdığından, bu O(n) hesaplamayı her
  // tıklamada tekrarlamamak için sonuç burada saklanıyor.
  void _computeRanges() {
    final candles = widget.result.candles;
    if (candles.isEmpty) return;
    final rawMin = candles.map((c) => c.low).reduce((a, b) => a < b ? a : b);
    final rawMax = candles.map((c) => c.high).reduce((a, b) => a > b ? a : b);
    final pad = (rawMax - rawMin) * 0.08 == 0 ? 1.0 : (rawMax - rawMin) * 0.08;
    _minPrice = rawMin - pad;
    _maxPrice = rawMax + pad;

    final macdValues = <double>[
      for (final c in candles) ...[
        if (c.macd != null) c.macd!,
        if (c.macdSignal != null) c.macdSignal!,
        if (c.macdHistogram != null) c.macdHistogram!,
      ],
    ];
    if (macdValues.isNotEmpty) {
      final rawMinMacd = macdValues.reduce((a, b) => a < b ? a : b);
      final rawMaxMacd = macdValues.reduce((a, b) => a > b ? a : b);
      final macdPad = (rawMaxMacd - rawMinMacd) * 0.1 == 0 ? 1.0 : (rawMaxMacd - rawMinMacd) * 0.1;
      _minMacd = rawMinMacd - macdPad;
      _maxMacd = rawMaxMacd + macdPad;
    }
  }

  @override
  Widget build(BuildContext context) {
    final candles = widget.result.candles;
    if (candles.isEmpty) {
      return const SizedBox.shrink();
    }
    final minPrice = _minPrice;
    final maxPrice = _maxPrice;
    final showRsi = _showIndicators && _hasRsi;
    final showMacd = _showIndicators && _hasMacd;

    return GlassCard(
      padding: const EdgeInsets.all(12),
      glow: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${widget.result.symbol} · Mum Grafik'.toUpperCase(),
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ),
              if (_hasRsi || _hasMacd)
                IconButton(
                  icon: Icon(
                    _showIndicators ? Icons.visibility_off : Icons.ssid_chart,
                    size: 16,
                    color: AppColors.slate400,
                  ),
                  onPressed: () => setState(() => _showIndicators = !_showIndicators),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                  visualDensity: VisualDensity.compact,
                  tooltip: _showIndicators ? 'RSI/MACD panelini gizle' : 'RSI/MACD panelini göster',
                ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  SizedBox(
                    width: _axisWidth,
                    height: _chartHeight,
                    child: _PriceAxis(minPrice: minPrice, maxPrice: maxPrice),
                  ),
                  if (showRsi) ...[
                    const SizedBox(height: _sectionGap),
                    const SizedBox(width: _axisWidth, height: _indicatorHeight, child: _RsiAxis()),
                  ],
                  if (showMacd) ...[
                    const SizedBox(height: _sectionGap),
                    SizedBox(
                      width: _axisWidth,
                      height: _indicatorHeight,
                      child: _MacdAxis(minMacd: _minMacd, maxMacd: _maxMacd),
                    ),
                  ],
                  SizedBox(height: _sectionGap + _labelHeight),
                ],
              ),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    // Tüm mumları mevcut genişliğe sığdırmak için mum
                    // başına düşen genişlik ekrana göre daraltılıyor.
                    final slotWidth = (constraints.maxWidth / candles.length)
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
                            if (showRsi) ...[
                              const SizedBox(height: _sectionGap),
                              SizedBox(
                                height: _indicatorHeight,
                                child: CustomPaint(
                                  painter: _RsiPainter(candles: candles, slotWidth: slotWidth),
                                  size: Size(contentWidth, _indicatorHeight),
                                ),
                              ),
                            ],
                            if (showMacd) ...[
                              const SizedBox(height: _sectionGap),
                              SizedBox(
                                height: _indicatorHeight,
                                child: CustomPaint(
                                  painter: _MacdPainter(
                                    candles: candles,
                                    slotWidth: slotWidth,
                                    candleWidth: candleWidth,
                                    minMacd: _minMacd,
                                    maxMacd: _maxMacd,
                                  ),
                                  size: Size(contentWidth, _indicatorHeight),
                                ),
                              ),
                            ],
                            SizedBox(height: _sectionGap),
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
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.slate900.withValues(alpha: 0.95),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.slate800.withValues(alpha: 0.8)),
        ),
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
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: AppColors.slate100),
                  ),
                ),
                GestureDetector(
                  onTap: onClose,
                  child: const Icon(Icons.close, size: 14, color: AppColors.slate400),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text('Yüksek: ${formatPrice(candle.high)}',
                style: GoogleFonts.robotoMono(
                    fontSize: 11, color: AppColors.emerald400)),
            Text('Düşük: ${formatPrice(candle.low)}',
                style: GoogleFonts.robotoMono(fontSize: 11, color: AppColors.rose500)),
            if (candle.rsi != null) ...[
              const SizedBox(height: 4),
              Text('RSI: ${candle.rsi!.toStringAsFixed(1)}',
                  style: GoogleFonts.robotoMono(fontSize: 11, color: AppColors.cyan500)),
            ],
          ],
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
                style: const TextStyle(fontSize: 10, color: AppColors.slate400),
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
            formatPrice(maxPrice - (maxPrice - minPrice) * i / (ticks - 1)),
            style: GoogleFonts.robotoMono(fontSize: 10, color: AppColors.slate400),
          ),
      ],
    );
  }
}

/// RSI her zaman 0-100 sabit ölçekte olduğundan (veriden bağımsız), sadece
/// 70/50/30 referans etiketleri gösterilir.
class _RsiAxis extends StatelessWidget {
  const _RsiAxis();

  @override
  Widget build(BuildContext context) {
    const labelStyle = TextStyle(fontSize: 9, color: AppColors.slate400);
    return const Column(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text('70', style: labelStyle),
        Text('50', style: labelStyle),
        Text('30', style: labelStyle),
      ],
    );
  }
}

class _MacdAxis extends StatelessWidget {
  final double minMacd;
  final double maxMacd;
  const _MacdAxis({required this.minMacd, required this.maxMacd});

  @override
  Widget build(BuildContext context) {
    final labelStyle = GoogleFonts.robotoMono(fontSize: 9, color: AppColors.slate400);
    return Column(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(maxMacd.toStringAsFixed(1), style: labelStyle),
        const Text('0', style: TextStyle(fontSize: 9, color: AppColors.slate400)),
        Text(minMacd.toStringAsFixed(1), style: labelStyle),
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
      ..color = AppColors.slate800.withValues(alpha: 0.5)
      ..strokeWidth = 1;
    for (var i = 0; i <= 4; i++) {
      final y = size.height * i / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    // _PeriodLabels ile aynı grup sınırlarında, o tarihe denk gelen ince
    // dikey referans çizgileri.
    final dateGridPaint = Paint()
      ..color = AppColors.slate800.withValues(alpha: 0.35)
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
      final color = isUp ? AppColors.emerald400 : AppColors.rose500;

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

class _RsiPainter extends CustomPainter {
  final List<Candle> candles;
  final double slotWidth;

  _RsiPainter({required this.candles, required this.slotWidth});

  double _y(double value, double height) => height - (value / 100) * height;

  @override
  void paint(Canvas canvas, Size size) {
    final refPaint = Paint()
      ..color = AppColors.slate800.withValues(alpha: 0.5)
      ..strokeWidth = 1;
    for (final level in [30.0, 50.0, 70.0]) {
      final y = _y(level, size.height);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), refPaint);
    }

    final linePaint = Paint()
      ..color = AppColors.cyan500
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round;
    final path = Path();
    var started = false;
    for (var i = 0; i < candles.length; i++) {
      final rsi = candles[i].rsi;
      if (rsi == null) continue;
      final x = i * slotWidth + slotWidth / 2;
      final y = _y(rsi, size.height);
      if (!started) {
        path.moveTo(x, y);
        started = true;
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(path, linePaint);
  }

  @override
  bool shouldRepaint(covariant _RsiPainter oldDelegate) {
    return oldDelegate.candles != candles || oldDelegate.slotWidth != slotWidth;
  }
}

class _MacdPainter extends CustomPainter {
  final List<Candle> candles;
  final double slotWidth;
  final double candleWidth;
  final double minMacd;
  final double maxMacd;

  _MacdPainter({
    required this.candles,
    required this.slotWidth,
    required this.candleWidth,
    required this.minMacd,
    required this.maxMacd,
  });

  double _y(double value, double height) {
    final range = maxMacd - minMacd;
    if (range == 0) return height / 2;
    return height - (value - minMacd) / range * height;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final zeroY = _y(0, size.height);
    final zeroPaint = Paint()
      ..color = AppColors.slate800.withValues(alpha: 0.6)
      ..strokeWidth = 1;
    canvas.drawLine(Offset(0, zeroY), Offset(size.width, zeroY), zeroPaint);

    for (var i = 0; i < candles.length; i++) {
      final h = candles[i].macdHistogram;
      if (h == null) continue;
      final x = i * slotWidth + slotWidth / 2;
      final y = _y(h, size.height);
      final barPaint = Paint()..color = (h >= 0 ? AppColors.emerald400 : AppColors.rose500)
          .withValues(alpha: 0.6);
      final rect = Rect.fromLTRB(
        x - candleWidth / 2,
        h >= 0 ? y : zeroY,
        x + candleWidth / 2,
        h >= 0 ? zeroY : y,
      );
      canvas.drawRect(rect, barPaint);
    }

    void drawLine(double? Function(Candle) selector, Color color) {
      final paint = Paint()
        ..color = color
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round;
      final path = Path();
      var started = false;
      for (var i = 0; i < candles.length; i++) {
        final v = selector(candles[i]);
        if (v == null) continue;
        final x = i * slotWidth + slotWidth / 2;
        final y = _y(v, size.height);
        if (!started) {
          path.moveTo(x, y);
          started = true;
        } else {
          path.lineTo(x, y);
        }
      }
      canvas.drawPath(path, paint);
    }

    drawLine((c) => c.macd, AppColors.cyan500);
    drawLine((c) => c.macdSignal, AppColors.fuchsia600);
  }

  @override
  bool shouldRepaint(covariant _MacdPainter oldDelegate) {
    return oldDelegate.candles != candles ||
        oldDelegate.slotWidth != slotWidth ||
        oldDelegate.minMacd != minMacd ||
        oldDelegate.maxMacd != maxMacd;
  }
}
