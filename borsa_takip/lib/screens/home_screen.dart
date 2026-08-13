import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/candle.dart';
import '../models/forecast.dart';
import '../models/interval.dart';
import '../models/pattern_match.dart';
import '../models/symbol.dart';
import '../services/market_api.dart';
import '../theme/app_colors.dart';
import '../utils/candle_padding.dart';
import '../utils/forecast_color.dart';
import '../utils/forecast_engine.dart';
import '../utils/pattern_matcher.dart';
import '../widgets/bento_kpi_row.dart';
import '../widgets/candlestick_chart.dart';
import '../widgets/chart_result_section.dart';
import '../widgets/favorite_symbols_bar.dart';
import '../widgets/forecast_report_card.dart';
import '../widgets/glass_card.dart';
import '../widgets/signal_quadrant_tile.dart';
import '../widgets/symbol_search_field.dart';
import '../widgets/watchlist_tile.dart';

// Grafik sekmesinde ChartResultSection'ı saran kart zincirinin tahmini
// "chrome"u — sayfa padding'i (24×2) + bu GlassCard'ın kendi padding'i
// (24×2) + CandlestickChart'ın kendi GlassCard'ı (12×2) + fiyat ekseni
// (CandlestickChart.axisWidth) — piksel-kusursuz olması gerekmiyor, sadece
// "bu aralık+interval yeterli mum üretecek mi" kararını verirken
// MediaQuery genişliğinden ne kadar düşülmesi gerektiğine dair kaba bir
// tahmin (bkz. _estimateMinCandles, utils/candle_padding.dart).
const _chartChromeWidth = 48 + 48 + 24;

// _BentoLayout'un satır/sütun geçişiyle aynı eşik — geniş ekranda hero
// sütunu tüm genişliği değil 12 kolonluk gridin 8'ini kaplıyor (bkz. build()
// altındaki LayoutBuilder), bu yüzden _estimateMinCandles de aynı eşiğin
// altında/üstünde farklı bir genişlik varsaymalı.
const _bentoBreakpoint = 900.0;
const _bentoGap = 24.0;

// "Tarihsel Benzerlik" (Pattern Matching / DTW) özelliğinin pencere boyu —
// hem geçmişte aranan desenin hem de geleceğe izdüşürülen barların uzunluğu
// (bkz. utils/pattern_matcher.dart findHistoricalPatterns). Sabit tutuluyor
// (mevcut grafikteki mum sayısına göre değil) çünkü spec açıkça "30 bar"
// diyor; CandlestickChart'ın "bugünü ortala" kuralı yine de bozulmuyor,
// zira o kural sadece sağ uzantının uzunluğuna bakıyor, 30'a özel değil.
const _patternWindowLength = 30;

class HomeScreen extends StatefulWidget {
  // Bildirimler sekmesinden bir sembole tıklanınca RootShell bu ikisini
  // birlikte günceller: requestId, requestedSymbol aynı sembol için bile
  // her tıklamada arttığından didUpdateWidget yeni bir istek olduğunu
  // anlayıp otomatik grafiği getirebiliyor.
  final MarketSymbol? requestedSymbol;
  final int requestId;
  final List<String> favorites;
  // Seçili sembolün yanındaki yıldız butonu için — RootShell'deki tek
  // favoriler listesini günceller (bkz. main.dart _toggleFavorite), diğer
  // sekmelerdeki (Bildirimler, Favoriler) yıldızlarla aynı callback.
  final ValueChanged<String>? onToggleFavorite;

  const HomeScreen({
    super.key,
    this.requestedSymbol,
    this.requestId = 0,
    this.favorites = const [],
    this.onToggleFavorite,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

/// Grafik sekmesinde incelenen sembolü doğrudan favorilere ekleyip
/// çıkarabilmek için — Bildirimler/Favoriler sekmelerindeki yıldız
/// ikonlarıyla aynı görsel dil (dolu/boş yıldız, emerald/slate renk).
class _FavoriteToggleButton extends StatelessWidget {
  final String symbol;
  final bool isFavorite;
  final ValueChanged<String>? onToggle;

  const _FavoriteToggleButton({
    required this.symbol,
    required this.isFavorite,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onToggle == null ? null : () => onToggle!(symbol),
      icon: Icon(isFavorite ? Icons.star : Icons.star_border),
      color: isFavorite ? AppColors.emerald400 : AppColors.slate400,
      tooltip: isFavorite ? 'Favorilerden çıkar' : 'Favorilere ekle',
    );
  }
}

class _HomeScreenState extends State<HomeScreen> {
  final _api = MarketApi();
  final _dateFormat = DateFormat('dd.MM.yyyy');

  MarketSymbol? _selectedSymbol;
  DateTimeRange? _dateRange;
  ChartInterval _interval = ChartInterval.monthly;

  bool _loading = false;
  String? _error;
  CandleResult? _result;
  int _paddingCandleCount = 0;

  // [GBM]/[OU]/[Trend] tahmin butonları — bkz. _toggleForecast. Yeni bir
  // fetch (sembol/aralık/interval değişikliği) her zaman eskiyi geçersiz
  // kılar, bkz. _fetch()'in başındaki reset.
  ForecastResult? _forecast;

  // "Tarihsel Benzerlik" — bkz. _toggleHistoricalPatternMatch. _forecast'la
  // aynı anda dolu olmaz (ikisi de tek bir "sağ uzantı" konseptini paylaşır,
  // bkz. CandlestickChart._hasRightExtension); biri seçilince diğeri temizlenir.
  PatternMatchResult? _patternMatch;
  bool _patternMatchLoading = false;

  int _handledRequestId = 0;

  int _estimateMinCandles(BuildContext context) {
    final totalWidth = MediaQuery.sizeOf(context).width;
    // Geniş ekranda hero sütunu toplam genişliğin ~8/12'si (bkz.
    // _bentoBreakpoint yorumu) — sidebar'ın ayırdığı payı ve aradaki
    // boşluğu düşmezsek gerekenden çok daha fazla mum istenir, bu da
    // gereksiz "otomatik eklendi" uzatmalarına/SnackBar'lara yol açar.
    final heroWidth =
        totalWidth >= _bentoBreakpoint ? (totalWidth - _bentoGap) * 8 / 12 : totalWidth;
    final available = heroWidth - _chartChromeWidth;
    return (available / CandlestickChart.maxSlotWidth).ceil().clamp(8, 60);
  }

  static DateTimeRange _last12Months() {
    final now = DateTime.now();
    return DateTimeRange(
      start: DateTime(now.year - 1, now.month, now.day),
      end: now,
    );
  }

  @override
  void initState() {
    super.initState();
    _dateRange = _last12Months();
    if (widget.requestedSymbol != null) {
      _handledRequestId = widget.requestId;
      _selectedSymbol = widget.requestedSymbol;
      _interval = ChartInterval.monthly;
      WidgetsBinding.instance.addPostFrameCallback((_) => _fetch());
    }
  }

  @override
  void didUpdateWidget(covariant HomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.requestedSymbol == null) return;
    if (widget.requestId == _handledRequestId) return;
    _handledRequestId = widget.requestId;
    setState(() {
      _selectedSymbol = widget.requestedSymbol;
      _interval = ChartInterval.monthly;
      _dateRange = _last12Months();
    });
    _fetch();
  }

  Future<void> _pickDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
      initialDateRange: _dateRange,
    );
    if (picked != null) {
      setState(() => _dateRange = picked);
    }
  }

  Future<void> _fetch() async {
    final symbol = _selectedSymbol;
    final range = _dateRange;
    if (symbol == null || range == null) return;

    setState(() {
      _loading = true;
      _error = null;
      _result = null;
      _paddingCandleCount = 0;
      // Eski sonuca ait tahmin/desen eşleşmesi yeni veriyle anlamsız kalır.
      _forecast = null;
      _patternMatch = null;
    });

    try {
      final padded = await fetchCandlesWithMinimum(
        api: _api,
        symbol: symbol.symbol,
        start: range.start,
        end: range.end,
        interval: _interval,
        minCandles: _estimateMinCandles(context),
        includeIndicators: true,
      );
      if (!mounted) return;
      setState(() {
        _result = padded.result;
        _paddingCandleCount = padded.paddingCount;
        _loading = false;
      });
      if (padded.result.candles.isNotEmpty) {
        if (padded.wasPadded) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Seçilen aralıkta yeterli mum yoktu, grafik '
                '${_dateFormat.format(padded.effectiveStart)} tarihinden '
                'itibaren gösteriliyor.'),
          ));
        } else if (padded.historyLimited) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Bu sembol için daha eski veri bulunamadı, grafik '
                'mevcut ${padded.result.candles.length} mumla gösteriliyor.'),
          ));
        }
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  void _selectSymbol(MarketSymbol symbol) {
    setState(() => _selectedSymbol = symbol);
  }

  void _selectInterval(ChartInterval interval) {
    setState(() => _interval = interval);
    // Zaten bir sonuç varsa yeni aralığa göre otomatik yenile.
    if (_selectedSymbol != null && _dateRange != null && _result != null) {
      _fetch();
    }
  }

  /// [GBM]/[OU]/[Trend] butonlarından birine basıldığında çağrılır. Zaten
  /// seçili olan modele tekrar basmak tahmini kapatır (varsayılan görünüme
  /// dönüş — bkz. CandlestickChart._applyViewport); başka bir modele basmak
  /// önceki tahmini yenisiyle değiştirir. Adım sayısı ("N") mevcut
  /// grafikteki geçmiş mum sayısı kadar — bu hem "geçmişte görünen bar
  /// sayısı kadar" isteğini karşılıyor hem de CandlestickChart'ın "bugünü
  /// tam ortala" geometrisinin temeli (geçmiş N + gelecek N = sınır tam
  /// %50'de) — GBM/OU'nun 1000 patikalık Monte Carlo Olasılık Isı Konisi
  /// de aynı N adımı kullandığından bu kural bozulmadan çalışır.
  void _toggleForecast(ForecastModelType model) {
    if (_forecast?.model == model) {
      setState(() => _forecast = null);
      return;
    }
    final candles = _result?.candles ?? const <Candle>[];
    if (candles.isEmpty) return;
    final closes = [for (final c in candles) c.close];
    final steps = candles.length;

    List<double> median;
    ProbabilityFan? fan;
    switch (model) {
      case ForecastModelType.gbm:
        fan = gbmForecastFan(closes, steps);
        median = fan.median;
      case ForecastModelType.ou:
        fan = ouForecastFan(closes, steps);
        median = fan.median;
      case ForecastModelType.trend:
        median = trendForecast(closes, steps);
    }
    if (median.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tahmin için yeterli geçmiş veri yok.')),
      );
      return;
    }
    setState(() {
      // Tarihsel Benzerlik'le aynı anda aktif olmaz (bkz. _patternMatch
      // doc yorumu) — ikisi de aynı "sağ uzantı" konseptini paylaşıyor.
      _patternMatch = null;
      _forecast = ForecastResult(
        model: model,
        prices: median,
        periods: generateForecastPeriods(_interval, steps),
        fan: (fan != null && !fan.isEmpty) ? fan : null,
      );
    });
  }

  /// "Tarihsel Benzerlik" butonuna basıldığında çağrılır — zaten bir sonuç
  /// gösteriliyorsa kapatır (varsayılan görünüme dönüş, tıpkı
  /// _toggleForecast gibi); yoksa sembolün DateTime(2000)'den bugüne kadar
  /// TÜM geçmişini (mevcut grafikte gösterilenle sınırlı değil — bkz.
  /// spec'in "tüm geçmiş veride" isteği) `_interval`'da ayrıca çeker ve
  /// `findHistoricalPatterns` ile DTW eşleştirmesi yapar. Bu yüzden
  /// mevcut grafiğin `_result`'ından bağımsız bir API çağrısı — sadece
  /// buton tıklandığında (otomatik değil), zira potansiyel olarak büyük bir
  /// istek.
  Future<void> _toggleHistoricalPatternMatch() async {
    if (_patternMatch != null) {
      setState(() => _patternMatch = null);
      return;
    }
    final symbol = _selectedSymbol;
    if (symbol == null || _result == null || _result!.candles.isEmpty) return;

    setState(() => _patternMatchLoading = true);
    try {
      final history = await _api.candles(
        symbol: symbol.symbol,
        start: DateTime(2000),
        end: DateTime.now(),
        interval: _interval,
      );
      final matches = findHistoricalPatterns(
        history.candles,
        windowLength: _patternWindowLength,
      );
      if (!mounted) return;
      if (matches == null || matches.isEmpty) {
        setState(() => _patternMatchLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('%80 ve üzeri benzerlikte bir geçmiş dönem bulunamadı.'),
          ),
        );
        return;
      }
      setState(() {
        // GBM/OU/Trend'le aynı anda aktif olmaz.
        _forecast = null;
        _patternMatch = PatternMatchResult(
          matches: matches,
          periods: generateForecastPeriods(_interval, _patternWindowLength),
        );
        _patternMatchLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _patternMatchLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  /// "i" ikonuna basıldığında açılan, modelin ne yaptığını sıradan dille
  /// anlatan bilgi diyaloğu — ChoiceChip'in `onSelected`'ından tamamen
  /// ayrı bir `IconButton` olduğundan (bkz. _buildForecastBar, ikisi iç
  /// içe değil kardeş widget) bu modeli SEÇMEZ, sadece açıklamayı gösterir.
  void _showForecastInfoDialog(ForecastModelType model) {
    final color = forecastModelColor(model);
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.slate900,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: color.withValues(alpha: 0.4)),
        ),
        title: Row(
          children: [
            Icon(Icons.info_outline, color: color, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                model.infoTitle,
                style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 16),
              ),
            ),
          ],
        ),
        content: Text(
          model.infoBody,
          style: const TextStyle(color: AppColors.slate100, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Anladım'),
          ),
        ],
      ),
    );
  }

  Widget _buildForecastBar() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text('Tahmin:', style: Theme.of(context).textTheme.labelSmall),
        for (final model in ForecastModelType.values)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Tooltip(
                message: 'Bu modelin nasıl çalıştığını öğren',
                child: IconButton(
                  icon: const Icon(Icons.info_outline, size: 16),
                  onPressed: () => _showForecastInfoDialog(model),
                  color: forecastModelColor(model),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                  visualDensity: VisualDensity.compact,
                ),
              ),
              const SizedBox(width: 2),
              Tooltip(
                message: model.description,
                child: ChoiceChip(
                  label: Text(model.shortLabel),
                  selected: _forecast?.model == model,
                  selectedColor: forecastModelColor(model).withValues(alpha: 0.25),
                  onSelected: (_) => _toggleForecast(model),
                ),
              ),
            ],
          ),
        if (_forecast != null)
          ActionChip(
            avatar: const Icon(Icons.close, size: 16),
            label: const Text('Temizle'),
            onPressed: () => setState(() => _forecast = null),
          ),
        Tooltip(
          message: 'Geçmişte, son $_patternWindowLength barlık fiyat hareketine DTW ile '
              'en çok benzeyen dönemleri bulup geleceğe izdüşürür',
          child: ChoiceChip(
            avatar: _patternMatchLoading
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.history, size: 16),
            label: const Text('Tarihsel Benzerlik'),
            selected: _patternMatch != null,
            selectedColor: AppColors.slate100.withValues(alpha: 0.2),
            onSelected: _patternMatchLoading ? null : (_) => _toggleHistoricalPatternMatch(),
          ),
        ),
      ],
    );
  }

  /// "Tarihsel Benzerlik" aktifken grafiğin üstünde gösterilen, spec'in
  /// "En Benzer Dönem: [Tarih/Yıl] (Korelasyon: %89)" bilgi kartı isteğinin
  /// karşılığı — üç eşleşme birden bulunduğundan tek satır yerine üçü de
  /// listelenir, her biri grafikteki hayalet çizgisiyle aynı renkte
  /// noktayla eşleştirilir (bkz. ghostLineColor, candlestick_chart.dart'taki
  /// aynı renklendirme). "Korelasyon" yerine "Benzerlik" deniyor — skor
  /// DTW mesafesinden türetildiğinden (bkz. pattern_matcher.dart), klasik
  /// Pearson korelasyon katsayısıyla karıştırılmasın diye.
  Widget _buildPatternMatchCard() {
    final result = _patternMatch;
    if (result == null) return const SizedBox.shrink();
    return GlassCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Tarihsel Benzerlik Sonuçları'.toUpperCase(),
              style: Theme.of(context).textTheme.labelSmall),
          for (var i = 0; i < result.matches.length; i++)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration:
                        BoxDecoration(color: ghostLineColor(i), shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'En Benzer Dönem ${i + 1}: ${result.matches[i].periodLabel}',
                      style: const TextStyle(color: AppColors.slate100),
                    ),
                  ),
                  Text(
                    'Benzerlik: %${result.matches[i].similarityPercent.toStringAsFixed(0)}',
                    style: TextStyle(color: ghostLineColor(i), fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildChartOverlayControls() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildForecastBar(),
        if (_patternMatch != null) ...[
          const SizedBox(height: 12),
          _buildPatternMatchCard(),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final heroColumn = GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Zaman Aralığı', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 16),
          ChartResultSection(
            intervals: ChartInterval.longTerm,
            selectedInterval: _interval,
            onSelectInterval: _selectInterval,
            dateRange: _dateRange,
            dateFormat: _dateFormat,
            onPickDateRange: _pickDateRange,
            fetchLabel: 'Getir',
            fetchIcon: Icons.show_chart,
            onFetch: _selectedSymbol == null || _loading ? null : _fetch,
            loading: _loading,
            error: _error,
            result: _result,
            paddingCandleCount: _paddingCandleCount,
            resultHeader: _result == null || _result!.candles.isEmpty
                ? null
                : BentoKpiRow(result: _result!),
            forecastControls: _result == null || _result!.candles.isEmpty
                ? null
                : _buildChartOverlayControls(),
            forecast: _forecast,
            patternMatch: _patternMatch,
            forecastReport: _forecast?.fan == null
                ? null
                : ForecastReportCard(forecast: _forecast!, currency: _result?.currency ?? ''),
            leadingActions: [
              if (_selectedSymbol != null) ...[
                Chip(label: Text('Seçili: ${_selectedSymbol!.symbol}')),
                _FavoriteToggleButton(
                  symbol: _selectedSymbol!.symbol,
                  isFavorite: widget.favorites.contains(_selectedSymbol!.symbol),
                  onToggle: widget.onToggleFavorite,
                ),
              ],
            ],
          ),
        ],
      ),
    );

    // Sidebar, hero'nun aksine bir "sonuç" beklemez — favoriler listesi ve
    // seçili sembol her zaman elde olduğundan grafik daha getirilmeden önce
    // de kendi verisini gösterebilir (bkz. WatchlistTile/SignalQuadrantTile'ın
    // kendi fetch'lerini kendi yönetmesi).
    final sidebarColumn = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        WatchlistTile(
          favorites: widget.favorites,
          api: _api,
          selectedSymbol: _selectedSymbol?.symbol,
          onSelect: (s) => _selectSymbol(MarketSymbol(symbol: s, name: s)),
        ),
        const SizedBox(height: 24),
        SignalQuadrantTile(api: _api, symbol: _selectedSymbol?.symbol),
      ],
    );

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Favoriler', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 16),
                FavoriteSymbolsBar(
                  symbols: [
                    for (final s in widget.favorites)
                      MarketSymbol(symbol: s, name: s),
                  ],
                  selected: _selectedSymbol,
                  onSelect: _selectSymbol,
                ),
                const SizedBox(height: 24),
                SymbolSearchField(api: _api, onSelect: _selectSymbol),
              ],
            ),
          ),
          const SizedBox(height: 24),
          LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth >= _bentoBreakpoint) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 8, child: heroColumn),
                    const SizedBox(width: _bentoGap),
                    Expanded(flex: 4, child: sidebarColumn),
                  ],
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  heroColumn,
                  const SizedBox(height: _bentoGap),
                  sidebarColumn,
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}
