import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/candle.dart';
import '../models/forecast.dart';
import '../models/interval.dart';
import '../models/symbol.dart';
import '../services/market_api.dart';
import '../theme/app_colors.dart';
import '../utils/candle_padding.dart';
import '../utils/forecast_color.dart';
import '../utils/forecast_engine.dart';
import '../widgets/bento_kpi_row.dart';
import '../widgets/candlestick_chart.dart';
import '../widgets/chart_result_section.dart';
import '../widgets/favorite_symbols_bar.dart';
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
      // Eski sonuca ait tahmin yeni veriyle anlamsız kalır.
      _forecast = null;
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
  /// %50'de).
  void _toggleForecast(ForecastModelType model) {
    if (_forecast?.model == model) {
      setState(() => _forecast = null);
      return;
    }
    final candles = _result?.candles ?? const <Candle>[];
    if (candles.isEmpty) return;
    final closes = [for (final c in candles) c.close];
    final steps = candles.length;
    final prices = switch (model) {
      ForecastModelType.gbm => gbmForecast(closes, steps),
      ForecastModelType.ou => ouForecast(closes, steps),
      ForecastModelType.trend => trendForecast(closes, steps),
    };
    if (prices.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tahmin için yeterli geçmiş veri yok.')),
      );
      return;
    }
    setState(() {
      _forecast = ForecastResult(
        model: model,
        prices: prices,
        periods: generateForecastPeriods(_interval, steps),
      );
    });
  }

  Widget _buildForecastBar() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text('Tahmin:', style: Theme.of(context).textTheme.labelSmall),
        for (final model in ForecastModelType.values)
          Tooltip(
            message: model.description,
            child: ChoiceChip(
              label: Text(model.shortLabel),
              selected: _forecast?.model == model,
              selectedColor: forecastModelColor(model).withValues(alpha: 0.25),
              onSelected: (_) => _toggleForecast(model),
            ),
          ),
        if (_forecast != null)
          ActionChip(
            avatar: const Icon(Icons.close, size: 16),
            label: const Text('Temizle'),
            onPressed: () => setState(() => _forecast = null),
          ),
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
                : _buildForecastBar(),
            forecast: _forecast,
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
