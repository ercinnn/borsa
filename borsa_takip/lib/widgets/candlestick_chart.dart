import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/candle.dart';
import '../models/forecast.dart';
import '../theme/app_colors.dart';
import '../utils/forecast_color.dart';
import '../utils/price_format.dart';
import 'glass_card.dart';

/// Mum grafiği + isteğe bağlı, altında TradingView tarzı RSI/MACD/Hacim
/// panelleri (bkz. `MarketApi.candles(includeIndicators: true)` — sadece o
/// zaman `candle.rsi`/`macd` dolu gelir; hacim ise her zaman ana `/api/candles`
/// yanıtında gelir, ayrı bir opt-in gerekmez). Panel açık/kapalıysa fark
/// etmeksizin tüm bölümler (fiyat ekseni + RSI ekseni + MACD ekseni + hacim
/// ekseni solda, mum/RSI/MACD/hacim çizimleri + tarih etiketleri sağda) TEK
/// bir yatay `SingleChildScrollView` içinde, TEK bir `slotWidth` hesabı
/// paylaşılarak dikeyde istiflenir — bu yüzden panellerin x ekseni mumlarla
/// piksel piksel hizalı kalır.
///
/// Fare imleci (web) veya sürükleme (dokunmatik) ile bir crosshair (artı imleç)
/// mumları takip eder; en üstteki OHLC şeridi imlecin altındaki mumu (veya
/// hiçbiri seçili değilse en son mumu) canlı gösterir. SMA(20)/EMA(50) fiyat
/// panelinin üzerine doğrudan bindirilir (ayrı bir panel değil, overlay).
class CandlestickChart extends StatefulWidget {
  final CandleResult result;
  // Seçilen aralıkta yeterli mum yoksa çağıran ekran (bkz.
  // utils/candle_padding.dart) başlangıç tarihini otomatik geriye çekip
  // yeniden veri çeker; result.candles'ın en baştaki bu kadarı kullanıcının
  // seçmediği "otomatik eklenen" geçmiş olur ve soluk/gölgeli çizilir.
  final int paddingCandleCount;
  // Grafik ekranındaki [GBM]/[OU]/[Trend] butonlarından biri seçiliyse
  // (bkz. HomeScreen._toggleForecast), geçmiş verinin hemen sağına kesikli
  // bir çizgiyle eklenecek tahmin — null ise (TrackingScreen'in bugünkü
  // davranışı) hiçbir şey değişmez.
  final ForecastResult? forecast;

  // `CandlestickChart.maxSlotWidth`, çağıran ekranların "bu aralık+interval yeterli mum
  // üretecek mi" hesabında (bkz. candle_padding.dart) da kullanabilmesi
  // için burada public — tek doğruluk kaynağı, sihirli sayı tekrarı olmasın.
  static const double maxSlotWidth = 46.0;
  static const double axisWidth = 64.0;

  const CandlestickChart({
    super.key,
    required this.result,
    this.paddingCandleCount = 0,
    this.forecast,
  });

  @override
  State<CandlestickChart> createState() => _CandlestickChartState();
}

class _CandlestickChartState extends State<CandlestickChart> {
  static const _chartHeight = 260.0;
  static const _indicatorHeight = 70.0;
  static const _sectionGap = 6.0;
  static const _labelHeight = 28.0;
  static const _minSlotWidth = 1.5;
  static const _smaPeriod = 20;
  static const _emaPeriod = 50;

  // Crosshair her iki eksende de en yakın muma "yapışıyor" (raw fare/dokunma
  // pozisyonunu değil, o mumun index'ini tutuyoruz) — hem web'de fare hover'ı
  // hem dokunmatikte sürükleme aynı tek state'i günceller.
  int? _hoverIndex;
  bool _showIndicators = true;
  double _minPrice = 0;
  double _maxPrice = 0;
  double _minMacd = 0;
  double _maxMacd = 0;
  double _maxVolume = 0;
  List<double?> _sma20 = const [];
  List<double?> _ema50 = const [];

  // Yatay kaydırmayı programatik olarak yönetmek (tahmin varken "bugün"ü
  // ortala, yokken "bugün"ü en sağda tut) için — bkz. _applyViewport.
  // slotWidth/geçmiş mum sayısı sadece build() içindeki LayoutBuilder'da
  // bilindiğinden, o sırada burada önbelleklenip _applyViewport'un
  // addPostFrameCallback'i tarafından okunuyor.
  final _scrollController = ScrollController();
  double _lastSlotWidth = 0;
  int _lastHistoricalCount = 0;

  @override
  void initState() {
    super.initState();
    _computeRanges();
    WidgetsBinding.instance.addPostFrameCallback((_) => _applyViewport());
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant CandlestickChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    final resultChanged = oldWidget.result != widget.result;
    final forecastChanged = oldWidget.forecast != widget.forecast;
    // Yeni sembol/aralık verisi geldiğinde eski crosshair konumu anlamsız
    // kalacağından kapatılıyor.
    if (resultChanged) {
      _hoverIndex = null;
    }
    if (resultChanged || forecastChanged) {
      _computeRanges();
      // Bir tahmin butonuna basıldığında/tahmin temizlendiğinde viewport'u
      // yeniden konumlandır (bkz. _applyViewport doc yorumu) — layout henüz
      // bu frame'de gerçekleşmediğinden bir sonraki frame'e ertelenir.
      WidgetsBinding.instance.addPostFrameCallback((_) => _applyViewport());
    }
  }

  /// X ekseni (yatay kaydırma) konumlandırma kuralı: tahmin AKTİFSE "bugün"
  /// (son gerçek mum) viewport'un tam ortasına gelecek şekilde kaydırılır
  /// (minX = bugün - görünürAralık, maxX = bugün + görünürAralık); tahmin
  /// YOKSA (kapatıldığında/temizlendiğinde de) varsayılan görünüme, yani
  /// "bugün en sağda" konumuna dönülür. `_lastSlotWidth`/
  /// `_lastHistoricalCount` build()'teki LayoutBuilder'dan önbelleklenir —
  /// bu yüzden ilk frame render olmadan (ScrollController henüz
  /// `hasClients` değilken) çağrılırsa sessizce hiçbir şey yapmaz.
  void _applyViewport() {
    if (!mounted || !_scrollController.hasClients) return;
    final slotWidth = _lastSlotWidth;
    if (slotWidth <= 0) return;
    final position = _scrollController.position;
    final maxExtent = position.maxScrollExtent;
    final double target;
    if (widget.forecast != null) {
      final boundaryX = _lastHistoricalCount * slotWidth;
      target = (boundaryX - position.viewportDimension / 2).clamp(0.0, maxExtent);
    } else {
      target = maxExtent;
    }
    _scrollController.animateTo(
      target,
      duration: const Duration(milliseconds: 450),
      curve: Curves.easeOutCubic,
    );
  }

  bool get _hasRsi => widget.result.candles.any((c) => c.rsi != null);
  bool get _hasMacd => widget.result.candles.any((c) => c.macd != null);
  bool get _hasVolume => widget.result.candles.any((c) => c.volume != null);

  // Sadece widget.result değiştiğinde çağrılır; crosshair'i hareket ettirmek
  // de build()'i yeniden çalıştırdığından, bu O(n) hesaplamaları her
  // hover/sürüklemede tekrarlamamak için sonuçlar burada saklanıyor.
  void _computeRanges() {
    final candles = widget.result.candles;
    if (candles.isEmpty) return;
    // Tahmin fiyatları (özellikle GBM/OU'nun Olasılık Konisi'ndeki %95/%5
    // sınırları) geçmiş yüksek/düşük aralığının dışına çıkabilir — fiyat
    // ekseni ve grid buna göre genişlemezse koni panelin üstünden/altından
    // taşar.
    final forecastPrices = widget.forecast?.prices ?? const <double>[];
    final forecastUpper = widget.forecast?.upperBand ?? const <double>[];
    final forecastLower = widget.forecast?.lowerBand ?? const <double>[];
    final rawMin = [...candles.map((c) => c.low), ...forecastPrices, ...forecastLower]
        .reduce((a, b) => a < b ? a : b);
    final rawMax = [...candles.map((c) => c.high), ...forecastPrices, ...forecastUpper]
        .reduce((a, b) => a > b ? a : b);
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

    _maxVolume = candles.map((c) => c.volume ?? 0).fold(0.0, (a, b) => a > b ? a : b);
    _sma20 = _simpleMovingAverage(candles, _smaPeriod);
    _ema50 = _exponentialMovingAverage(candles, _emaPeriod);
  }

  void _updateHover(Offset localPosition, double slotWidth, int candleCount) {
    final idx = (localPosition.dx / slotWidth).floor();
    // Tahmin bölgesine (ya da sınırların dışına) düşen bir konum crosshair'i
    // güncellemez — orada gerçek bir OHLC değeri yok, bkz. _handleTap'in bu
    // bölgedeki tıklamaları "viewport'u ortala" olarak ele alması.
    if (idx < 0 || idx >= candleCount) return;
    if (idx != _hoverIndex) setState(() => _hoverIndex = idx);
  }

  /// Tahmin bölgesine (kesikli çizginin üzerine ya da altına) yapılan bir
  /// tıklama viewport'u "bugün ortada" konumuna kilitler (bkz.
  /// _applyViewport) — geçmiş bölgedeki bir tıklama ise her zamanki gibi
  /// crosshair'i günceller.
  void _handleTap(Offset localPosition, double slotWidth) {
    final historicalCount = widget.result.candles.length;
    final idx = (localPosition.dx / slotWidth).floor();
    if (widget.forecast != null && idx >= historicalCount) {
      _applyViewport();
      return;
    }
    _updateHover(localPosition, slotWidth, historicalCount);
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
    final showVolume = _hasVolume;
    final hasSma = candles.length >= _smaPeriod;
    final hasEma = candles.length >= _emaPeriod;
    final ribbonCandle = candles[_hoverIndex ?? candles.length - 1];
    final forecast = widget.forecast;
    final forecastPrices = forecast?.prices ?? const <double>[];
    final forecastUpper = forecast?.upperBand ?? const <double>[];
    final forecastLower = forecast?.lowerBand ?? const <double>[];
    final forecastPeriods = forecast?.periods ?? const <String>[];
    final forecastColor = forecast == null ? null : forecastModelColor(forecast.model);
    final forecastHasCone = forecastUpper.isNotEmpty && forecastLower.isNotEmpty;

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
              if (hasSma) ...[
                const _LegendDot(color: AppColors.amber500, label: 'SMA20'),
                const SizedBox(width: 10),
              ],
              if (hasEma) ...[
                const _LegendDot(color: AppColors.cyan500, label: 'EMA50'),
                const SizedBox(width: 10),
              ],
              if (forecast != null) ...[
                _LegendDot(
                  color: forecastColor!,
                  label: 'Tahmin: ${forecast.model.shortLabel}'
                      '${forecastHasCone ? ' (Olasılık Konisi)' : ''}',
                ),
                const SizedBox(width: 10),
              ],
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
          const SizedBox(height: 6),
          _OhlcRibbon(candle: ribbonCandle, currency: widget.result.currency),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  SizedBox(
                    width: CandlestickChart.axisWidth,
                    height: _chartHeight,
                    child: _PriceAxis(minPrice: minPrice, maxPrice: maxPrice),
                  ),
                  if (showRsi) ...[
                    const SizedBox(height: _sectionGap),
                    const SizedBox(width: CandlestickChart.axisWidth, height: _indicatorHeight, child: _RsiAxis()),
                  ],
                  if (showMacd) ...[
                    const SizedBox(height: _sectionGap),
                    SizedBox(
                      width: CandlestickChart.axisWidth,
                      height: _indicatorHeight,
                      child: _MacdAxis(minMacd: _minMacd, maxMacd: _maxMacd),
                    ),
                  ],
                  if (showVolume) ...[
                    const SizedBox(height: _sectionGap),
                    SizedBox(
                      width: CandlestickChart.axisWidth,
                      height: _indicatorHeight,
                      child: _VolumeAxis(maxVolume: _maxVolume),
                    ),
                  ],
                  SizedBox(height: _sectionGap + _labelHeight),
                ],
              ),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    // Tahmin aktifse toplam slot sayısı geçmiş + tahmin
                    // adımlarının toplamı olur; bu, "bugün"ün tam ortada
                    // görünmesini sağlayan geometrik temel — geçmiş N mum +
                    // gelecek N mum eşit genişlikte bölündüğünde sınır
                    // doğal olarak %50 noktasına düşer (bkz. _applyViewport,
                    // içerik viewport'tan geniş olduğunda ek olarak kaydırma
                    // ile de merkezlenir).
                    final totalSlots = candles.length + forecastPrices.length;
                    // Tüm mumları mevcut genişliğe sığdırmak için mum
                    // başına düşen genişlik ekrana göre daraltılıyor.
                    final slotWidth = (constraints.maxWidth / totalSlots)
                        .clamp(_minSlotWidth, CandlestickChart.maxSlotWidth);
                    final candleWidth = (slotWidth * 0.7).clamp(1.0, 20.0);
                    final contentWidth = slotWidth * totalSlots;
                    // Dar mum aralıklarında her mumun altına etiket
                    // sığmayacağından, etiketler ve dikey referans
                    // çizgileri ~60px'lik gruplar halinde birleştiriliyor.
                    final labelEvery =
                        (60 / slotWidth).ceil().clamp(1, totalSlots);

                    _lastSlotWidth = slotWidth;
                    _lastHistoricalCount = candles.length;

                    void handlePointer(Offset local) =>
                        _updateHover(local, slotWidth, candles.length);

                    return SingleChildScrollView(
                      controller: _scrollController,
                      scrollDirection: Axis.horizontal,
                      child: SizedBox(
                        width: contentWidth,
                        child: MouseRegion(
                          cursor: SystemMouseCursors.precise,
                          onHover: (e) => handlePointer(e.localPosition),
                          onExit: (_) => setState(() => _hoverIndex = null),
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTapUp: (d) => _handleTap(d.localPosition, slotWidth),
                            onPanDown: (d) => handlePointer(d.localPosition),
                            onPanUpdate: (d) => handlePointer(d.localPosition),
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
                                      labelEvery: labelEvery,
                                      sma: hasSma ? _sma20 : const [],
                                      ema: hasEma ? _ema50 : const [],
                                      highlightIndex: _hoverIndex,
                                      paddingCandleCount: widget.paddingCandleCount,
                                      forecastPrices: forecastPrices,
                                      forecastUpper: forecastUpper,
                                      forecastLower: forecastLower,
                                      forecastLabel: forecast?.model.shortLabel,
                                      forecastColor: forecastColor,
                                    ),
                                    size: Size(contentWidth, _chartHeight),
                                  ),
                                ),
                                if (showRsi) ...[
                                  const SizedBox(height: _sectionGap),
                                  SizedBox(
                                    height: _indicatorHeight,
                                    child: CustomPaint(
                                      painter: _RsiPainter(
                                        candles: candles,
                                        slotWidth: slotWidth,
                                        highlightIndex: _hoverIndex,
                                      paddingCandleCount: widget.paddingCandleCount,
                                      ),
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
                                        highlightIndex: _hoverIndex,
                                      paddingCandleCount: widget.paddingCandleCount,
                                      ),
                                      size: Size(contentWidth, _indicatorHeight),
                                    ),
                                  ),
                                ],
                                if (showVolume) ...[
                                  const SizedBox(height: _sectionGap),
                                  SizedBox(
                                    height: _indicatorHeight,
                                    child: CustomPaint(
                                      painter: _VolumePainter(
                                        candles: candles,
                                        slotWidth: slotWidth,
                                        candleWidth: candleWidth,
                                        maxVolume: _maxVolume,
                                        highlightIndex: _hoverIndex,
                                      paddingCandleCount: widget.paddingCandleCount,
                                      ),
                                      size: Size(contentWidth, _indicatorHeight),
                                    ),
                                  ),
                                ],
                                SizedBox(height: _sectionGap),
                                SizedBox(
                                  height: _labelHeight,
                                  child: _PeriodLabels(
                                    periods: [
                                      for (final c in candles) c.period,
                                      ...forecastPeriods,
                                    ],
                                    slotWidth: slotWidth,
                                    labelEvery: labelEvery,
                                  ),
                                ),
                              ],
                            ),
                          ),
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

/// [candles]'ın kapanış fiyatları üzerinden basit hareketli ortalama.
/// İlk `period - 1` eleman için yeterli geçmiş olmadığından `null`.
List<double?> _simpleMovingAverage(List<Candle> candles, int period) {
  final out = List<double?>.filled(candles.length, null);
  if (candles.length < period) return out;
  double sum = 0;
  for (var i = 0; i < candles.length; i++) {
    sum += candles[i].close;
    if (i >= period) sum -= candles[i - period].close;
    if (i >= period - 1) out[i] = sum / period;
  }
  return out;
}

/// [period] büyüklüğünde bir üstel hareketli ortalama — ilk değer klasik
/// yaklaşımla ilk `period` kapanışın basit ortalamasıyla başlatılır
/// (`seed`), sonrasında standart EMA katsayısıyla (`2 / (period + 1)`)
/// devam eder.
List<double?> _exponentialMovingAverage(List<Candle> candles, int period) {
  final out = List<double?>.filled(candles.length, null);
  if (candles.length < period) return out;
  final k = 2 / (period + 1);
  double seed = 0;
  for (var i = 0; i < period; i++) {
    seed += candles[i].close;
  }
  var prev = seed / period;
  out[period - 1] = prev;
  for (var i = period; i < candles.length; i++) {
    prev = candles[i].close * k + prev * (1 - k);
    out[i] = prev;
  }
  return out;
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 2,
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(1)),
        ),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(fontSize: 10, color: AppColors.slate400)),
      ],
    );
  }
}

/// Crosshair'in altındaki mumu (yoksa en son mumu) canlı gösteren üst şerit
/// — "Financial Trading Terminal" tarzı dinamik OHLC göstergesi. Kapanış
/// rengi sadece yeşil/kırmızı değil, ▲/▼ okuyla da işaretleniyor (renk-körü
/// erişilebilirliği için — bkz. CLAUDE.md tasarım denetimi notları).
class _OhlcRibbon extends StatelessWidget {
  final Candle candle;
  final String currency;

  const _OhlcRibbon({required this.candle, required this.currency});

  @override
  Widget build(BuildContext context) {
    final isUp = candle.close >= candle.open;
    final changePct =
        candle.open == 0 ? 0.0 : (candle.close - candle.open) / candle.open * 100;
    final color = isUp ? AppColors.emerald400 : AppColors.rose500;
    final mono = GoogleFonts.robotoMono(fontSize: 11, color: AppColors.slate100);

    Widget field(String label, String value, {Color? valueColor}) {
      return Padding(
        padding: const EdgeInsets.only(right: 14),
        child: RichText(
          text: TextSpan(
            children: [
              TextSpan(
                text: '$label ',
                style: TextStyle(fontSize: 10, color: AppColors.slate400),
              ),
              TextSpan(text: value, style: mono.copyWith(color: valueColor ?? mono.color)),
            ],
          ),
        ),
      );
    }

    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Padding(
          padding: const EdgeInsets.only(right: 14),
          child: Text(candle.period,
              style: TextStyle(fontSize: 11, color: AppColors.slate400, fontWeight: FontWeight.w600)),
        ),
        field('AÇ', formatPrice(candle.open)),
        field('YÜK', formatPrice(candle.high)),
        field('DÜŞ', formatPrice(candle.low)),
        field(
          'KAP',
          '${isUp ? '▲' : '▼'} ${formatPrice(candle.close)} '
              '(${isUp ? '+' : ''}${changePct.toStringAsFixed(2)}%)',
          valueColor: color,
        ),
        if (candle.volume != null) field('HACİM', formatCompact(candle.volume!)),
      ],
    );
  }
}

class _PeriodLabels extends StatelessWidget {
  // Geçmiş mumların period'larıyla (varsa) tahmin period'larının
  // birleştirilmiş hali — bkz. CandlestickChart.build()'teki çağrı.
  final List<String> periods;
  final double slotWidth;
  final int labelEvery;

  const _PeriodLabels({
    required this.periods,
    required this.slotWidth,
    required this.labelEvery,
  });

  @override
  Widget build(BuildContext context) {
    final cells = <Widget>[];
    var i = 0;
    while (i < periods.length) {
      final span = (periods.length - i < labelEvery)
          ? periods.length - i
          : labelEvery;
      cells.add(
        SizedBox(
          width: slotWidth * span,
          child: Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                periods[i],
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

class _VolumeAxis extends StatelessWidget {
  final double maxVolume;
  const _VolumeAxis({required this.maxVolume});

  @override
  Widget build(BuildContext context) {
    final labelStyle = GoogleFonts.robotoMono(fontSize: 9, color: AppColors.slate400);
    return Column(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(formatCompact(maxVolume), style: labelStyle),
        const Text('0', style: TextStyle(fontSize: 9, color: AppColors.slate400)),
      ],
    );
  }
}

/// Tüm panel painter'ları için ortak: [highlightIndex] doluysa o mumun
/// x-merkezinde ince, panelin tam boyunu kaplayan bir crosshair çizgisi
/// çizer. Fiyat panelinin kendisi ayrıca yatay çizgi + kapanış noktası da
/// ekliyor (bkz. _CandlestickPainter) — burası alt panellerde (RSI/MACD/
/// Hacim) görsel sürekliliği sağlayan ortak parça.
void _paintCrosshairLine(Canvas canvas, Size size, double slotWidth, int? highlightIndex) {
  if (highlightIndex == null) return;
  final x = highlightIndex * slotWidth + slotWidth / 2;
  final paint = Paint()
    ..color = AppColors.slate100.withValues(alpha: 0.35)
    ..strokeWidth = 1;
  canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
}

/// Tüm panel painter'ları için ortak: [paddingCandleCount] doluysa (bkz.
/// CandlestickChart.paddingCandleCount doc yorumu), en baştaki o kadar
/// mumun arkasına hafif gölgeli bir bant + sınırda ince bir ayraç çizgisi
/// çizer — kullanıcının seçmediği, otomatik eklenen geçmişi işaretler.
/// Diğer çizimlerden (grid, mumlar, çizgiler) ÖNCE çağrılmalı ki arka
/// planda kalsın.
void _paintPaddingBand(Canvas canvas, Size size, double slotWidth, int paddingCandleCount) {
  if (paddingCandleCount <= 0) return;
  final width = (paddingCandleCount * slotWidth).clamp(0.0, size.width);
  canvas.drawRect(
    Rect.fromLTWH(0, 0, width, size.height),
    Paint()..color = AppColors.slate800.withValues(alpha: 0.35),
  );
  final dividerPaint = Paint()
    ..color = AppColors.slate400.withValues(alpha: 0.6)
    ..strokeWidth = 1;
  canvas.drawLine(Offset(width, 0), Offset(width, size.height), dividerPaint);
}

class _CandlestickPainter extends CustomPainter {
  final List<Candle> candles;
  final double minPrice;
  final double maxPrice;
  final double slotWidth;
  final double candleWidth;
  final int labelEvery;
  final List<double?> sma;
  final List<double?> ema;
  final int? highlightIndex;
  final int paddingCandleCount;
  // Tahmin aktifse (bkz. CandlestickChart.forecast), geçmiş mumların hemen
  // sağına çizilecek "orta senaryo" fiyat dizisi + model kısaltması/rengi —
  // boşsa hiçbir şey çizilmez. [forecastUpper]/[forecastLower] sadece GBM/
  // OU'nun Monte Carlo Olasılık Konisi'nde dolu (%95/%5 yüzdelik dilimler);
  // boşsa (Trend, ya da tahmin yokken) koni yerine düz bir kesikli çizgi +
  // hafif tahmin bandı çizilir.
  final List<double> forecastPrices;
  final List<double> forecastUpper;
  final List<double> forecastLower;
  final String? forecastLabel;
  final Color? forecastColor;

  _CandlestickPainter({
    required this.candles,
    required this.minPrice,
    required this.maxPrice,
    required this.slotWidth,
    required this.candleWidth,
    required this.labelEvery,
    required this.sma,
    required this.ema,
    required this.highlightIndex,
    required this.paddingCandleCount,
    this.forecastPrices = const [],
    this.forecastUpper = const [],
    this.forecastLower = const [],
    this.forecastLabel,
    this.forecastColor,
  });

  double _priceToY(double price, double height) {
    final range = maxPrice - minPrice;
    if (range == 0) return height / 2;
    return height - (price - minPrice) / range * height;
  }

  void _drawOverlayLine(Canvas canvas, Size size, List<double?> series, Color color) {
    if (series.isEmpty) return;
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.4
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round;
    final path = Path();
    var started = false;
    for (var i = 0; i < series.length; i++) {
      final v = series[i];
      if (v == null) continue;
      final x = i * slotWidth + slotWidth / 2;
      final y = _priceToY(v, size.height);
      if (!started) {
        path.moveTo(x, y);
        started = true;
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(path, paint);
  }

  void _drawPaddingLabel(Canvas canvas, Size size) {
    if (paddingCandleCount <= 0) return;
    final x = (paddingCandleCount * slotWidth).clamp(0.0, size.width);
    final tp = TextPainter(
      text: TextSpan(
        text: '← Otomatik eklendi',
        style: TextStyle(fontSize: 10, color: AppColors.slate400),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    // Ayracın sağında yer yoksa (dolgu neredeyse tüm genişliği kaplıyorsa)
    // etiket solda kalır, taşmaz.
    final left = (x + 6 + tp.width <= size.width) ? x + 6 : (x - 6 - tp.width).clamp(0.0, size.width);
    tp.paint(canvas, Offset(left, 4));
  }

  bool get _hasForecastCone => forecastUpper.isNotEmpty && forecastLower.isNotEmpty;

  // Tahmin serilerinin (medyan/üst/alt — hepsi aynı x konumlarını
  // paylaşıyor) ortak başlangıç noktası: son gerçek kapanış. Hem çizgiler
  // hem koni dolgusu buradan başlar ki geçmişle tahmin arasında görsel bir
  // kopukluk olmasın.
  Offset _forecastAnchor(Size size) =>
      Offset(candles.length * slotWidth - slotWidth / 2, _priceToY(candles.last.close, size.height));

  Path _forecastSeriesPath(Size size, List<double> series) {
    final historicalCount = candles.length;
    final anchor = _forecastAnchor(size);
    final path = Path()..moveTo(anchor.dx, anchor.dy);
    for (var i = 0; i < series.length; i++) {
      final x = (historicalCount + i) * slotWidth + slotWidth / 2;
      path.lineTo(x, _priceToY(series[i], size.height));
    }
    return path;
  }

  void _strokeDashed(Canvas canvas, Path path, Paint paint, {double dashWidth = 6, double dashGap = 4}) {
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final next = distance + dashWidth;
        canvas.drawPath(metric.extractPath(distance, next.clamp(0.0, metric.length)), paint);
        distance = next + dashGap;
      }
    }
  }

  /// [_paintPaddingBand]'ın tersi: geçmişin SOLUNA değil, tahminin
  /// (varsa) SAĞINA renkli bir dolgu çizer — kullanıcının bu bölgenin
  /// gerçek veri olmadığını bir bakışta anlaması için. Diğer çizimlerden
  /// önce çağrılmalı ki arka planda kalsın. GBM/OU'nun Monte Carlo koni
  /// verisi varsa (%95/%5 sınırları) bunların arasında kalan, zamanla
  /// genişleyen huni şeklindeki alanı "Confidence Band" olarak doldurur
  /// (opacity 0.15 — huni şekli ayrıca hesaplanmıyor, Monte Carlo
  /// varyansının gün geçtikçe büyümesinden doğal olarak ortaya çıkıyor);
  /// koni yoksa (Trend) düz, hafif bir tahmin bandı çizilir.
  void _paintForecastBackground(Canvas canvas, Size size) {
    if (forecastPrices.isEmpty || forecastColor == null || candles.isEmpty) return;
    if (_hasForecastCone) {
      final path = _forecastSeriesPath(size, forecastUpper);
      for (var i = forecastLower.length - 1; i >= 0; i--) {
        final x = (candles.length + i) * slotWidth + slotWidth / 2;
        path.lineTo(x, _priceToY(forecastLower[i], size.height));
      }
      path.close();
      canvas.drawPath(path, Paint()..color = forecastColor!.withValues(alpha: 0.15));
      return;
    }
    final startX = candles.length * slotWidth;
    if (startX >= size.width) return;
    canvas.drawRect(
      Rect.fromLTRB(startX, 0, size.width, size.height),
      Paint()..color = forecastColor!.withValues(alpha: 0.07),
    );
  }

  /// Son gerçek kapanıştan başlayıp tahmin boyunca ilerleyen kesikli
  /// çizgi(ler) + "bugün" sınırında ince bir ayraç + model adını gösteren
  /// küçük bir etiket. Koni verisi varsa (bkz. _hasForecastCone) önce ince
  /// %95/%5 kılavuz çizgileri, sonra üzerlerinde belirgin (daha kalın)
  /// medyan çizgisi çizilir — yoksa (Trend) tek bir çizgi. `path
  /// .computeMetrics()` ile elle kesikli çizgi çiziliyor — Flutter'ın kendi
  /// dashed-line API'si yok ve bu, yeni bir paket bağımlılığı eklemeden
  /// yeterli.
  void _drawForecastLines(Canvas canvas, Size size) {
    if (forecastPrices.isEmpty || forecastColor == null || candles.isEmpty) return;
    final boundaryX = candles.length * slotWidth;

    final dividerPaint = Paint()
      ..color = forecastColor!.withValues(alpha: 0.5)
      ..strokeWidth = 1;
    canvas.drawLine(Offset(boundaryX, 0), Offset(boundaryX, size.height), dividerPaint);

    if (_hasForecastCone) {
      final guidePaint = Paint()
        ..color = forecastColor!.withValues(alpha: 0.6)
        ..strokeWidth = 1
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round;
      _strokeDashed(canvas, _forecastSeriesPath(size, forecastUpper), guidePaint);
      _strokeDashed(canvas, _forecastSeriesPath(size, forecastLower), guidePaint);
    }

    final medianPaint = Paint()
      ..color = forecastColor!
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round;
    _strokeDashed(canvas, _forecastSeriesPath(size, forecastPrices), medianPaint);

    if (forecastLabel != null) {
      final tp = TextPainter(
        text: TextSpan(
          text: 'Tahmin: $forecastLabel →',
          style: TextStyle(fontSize: 10, color: forecastColor, fontWeight: FontWeight.w600),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset((boundaryX + 6).clamp(0.0, size.width - tp.width), 4));
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    _paintPaddingBand(canvas, size, slotWidth, paddingCandleCount);
    _paintForecastBackground(canvas, size);

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
    for (var i = 0; i < candles.length + forecastPrices.length; i += labelEvery) {
      final x = i * slotWidth;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), dateGridPaint);
    }

    final wickWidth = slotWidth < 4 ? 1.0 : 2.0;
    for (var i = 0; i < candles.length; i++) {
      final c = candles[i];
      final x = i * slotWidth + slotWidth / 2;
      final isUp = c.close >= c.open;
      // Otomatik eklenen (kullanıcının seçmediği) geçmiş soluk çizilir —
      // bkz. CandlestickChart.paddingCandleCount doc yorumu.
      final isPadding = i < paddingCandleCount;
      final baseColor = isUp ? AppColors.emerald400 : AppColors.rose500;
      final color = isPadding ? baseColor.withValues(alpha: 0.4) : baseColor;

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

    _drawOverlayLine(canvas, size, sma, AppColors.amber500);
    _drawOverlayLine(canvas, size, ema, AppColors.cyan500);
    _drawPaddingLabel(canvas, size);
    _drawForecastLines(canvas, size);

    if (highlightIndex != null) {
      final idx = highlightIndex!.clamp(0, candles.length - 1);
      final c = candles[idx];
      final x = idx * slotWidth + slotWidth / 2;
      final closeY = _priceToY(c.close, size.height);

      final linePaint = Paint()
        ..color = AppColors.slate100.withValues(alpha: 0.35)
        ..strokeWidth = 1;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), linePaint);
      canvas.drawLine(Offset(0, closeY), Offset(size.width, closeY), linePaint);

      final markerColor = c.close >= c.open ? AppColors.emerald400 : AppColors.rose500;
      canvas.drawCircle(Offset(x, closeY), 3.2, Paint()..color = markerColor);
      canvas.drawCircle(
        Offset(x, closeY),
        3.2,
        Paint()
          ..color = AppColors.slate950
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _CandlestickPainter oldDelegate) {
    return oldDelegate.candles != candles ||
        oldDelegate.minPrice != minPrice ||
        oldDelegate.maxPrice != maxPrice ||
        oldDelegate.slotWidth != slotWidth ||
        oldDelegate.labelEvery != labelEvery ||
        oldDelegate.sma != sma ||
        oldDelegate.ema != ema ||
        oldDelegate.highlightIndex != highlightIndex ||
        oldDelegate.paddingCandleCount != paddingCandleCount ||
        oldDelegate.forecastPrices != forecastPrices ||
        oldDelegate.forecastUpper != forecastUpper ||
        oldDelegate.forecastLower != forecastLower ||
        oldDelegate.forecastLabel != forecastLabel ||
        oldDelegate.forecastColor != forecastColor;
  }
}

class _RsiPainter extends CustomPainter {
  final List<Candle> candles;
  final double slotWidth;
  final int? highlightIndex;
  final int paddingCandleCount;

  _RsiPainter({
    required this.candles,
    required this.slotWidth,
    required this.highlightIndex,
    required this.paddingCandleCount,
  });

  double _y(double value, double height) => height - (value / 100) * height;

  @override
  void paint(Canvas canvas, Size size) {
    _paintPaddingBand(canvas, size, slotWidth, paddingCandleCount);

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

    _paintCrosshairLine(canvas, size, slotWidth, highlightIndex);
  }

  @override
  bool shouldRepaint(covariant _RsiPainter oldDelegate) {
    return oldDelegate.candles != candles ||
        oldDelegate.slotWidth != slotWidth ||
        oldDelegate.highlightIndex != highlightIndex ||
        oldDelegate.paddingCandleCount != paddingCandleCount;
  }
}

class _MacdPainter extends CustomPainter {
  final List<Candle> candles;
  final double slotWidth;
  final double candleWidth;
  final double minMacd;
  final double maxMacd;
  final int? highlightIndex;
  final int paddingCandleCount;

  _MacdPainter({
    required this.candles,
    required this.slotWidth,
    required this.candleWidth,
    required this.minMacd,
    required this.maxMacd,
    required this.highlightIndex,
    required this.paddingCandleCount,
  });

  double _y(double value, double height) {
    final range = maxMacd - minMacd;
    if (range == 0) return height / 2;
    return height - (value - minMacd) / range * height;
  }

  @override
  void paint(Canvas canvas, Size size) {
    _paintPaddingBand(canvas, size, slotWidth, paddingCandleCount);

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

    _paintCrosshairLine(canvas, size, slotWidth, highlightIndex);
  }

  @override
  bool shouldRepaint(covariant _MacdPainter oldDelegate) {
    return oldDelegate.candles != candles ||
        oldDelegate.slotWidth != slotWidth ||
        oldDelegate.minMacd != minMacd ||
        oldDelegate.maxMacd != maxMacd ||
        oldDelegate.highlightIndex != highlightIndex ||
        oldDelegate.paddingCandleCount != paddingCandleCount;
  }
}

/// Fiyat mumlarıyla aynı yükseliş/düşüş renginde, panelin alt kenarından
/// yükselen çubuklar — "Financial Trading Terminal" spec'indeki "hacim
/// çubukları" gereksiniminin karşılığı. Kendi paneli olarak, RSI/MACD ile
/// aynı desende (Candle.volume her zaman ana /api/candles yanıtında geldiği
/// için ayrı bir opt-in/toggle gerekmiyor, bkz. sınıf başı doc yorumu).
class _VolumePainter extends CustomPainter {
  final List<Candle> candles;
  final double slotWidth;
  final double candleWidth;
  final double maxVolume;
  final int? highlightIndex;
  final int paddingCandleCount;

  _VolumePainter({
    required this.candles,
    required this.slotWidth,
    required this.candleWidth,
    required this.maxVolume,
    required this.highlightIndex,
    required this.paddingCandleCount,
  });

  @override
  void paint(Canvas canvas, Size size) {
    _paintPaddingBand(canvas, size, slotWidth, paddingCandleCount);

    if (maxVolume > 0) {
      for (var i = 0; i < candles.length; i++) {
        final v = candles[i].volume;
        if (v == null) continue;
        final c = candles[i];
        final isUp = c.close >= c.open;
        final x = i * slotWidth + slotWidth / 2;
        final barHeight = (v / maxVolume) * size.height;
        final barPaint = Paint()
          ..color = (isUp ? AppColors.emerald400 : AppColors.rose500).withValues(alpha: 0.55);
        canvas.drawRect(
          Rect.fromLTRB(
            x - candleWidth / 2,
            size.height - barHeight,
            x + candleWidth / 2,
            size.height,
          ),
          barPaint,
        );
      }
    }

    _paintCrosshairLine(canvas, size, slotWidth, highlightIndex);
  }

  @override
  bool shouldRepaint(covariant _VolumePainter oldDelegate) {
    return oldDelegate.candles != candles ||
        oldDelegate.slotWidth != slotWidth ||
        oldDelegate.maxVolume != maxVolume ||
        oldDelegate.highlightIndex != highlightIndex ||
        oldDelegate.paddingCandleCount != paddingCandleCount;
  }
}
