import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/candle.dart';
import '../models/interval.dart';
import '../models/symbol.dart';
import '../services/market_api.dart';
import '../utils/candle_padding.dart';
import '../widgets/candlestick_chart.dart';
import '../widgets/chart_result_section.dart';

// bkz. home_screen.dart'taki aynı isimli sabitin doc yorumu — burada
// TrackingScreen'in kendi "chrome"u: sayfa padding'i (16×2) + CandlestickChart
// GlassCard'ı (12×2) + fiyat ekseni (ChartResultSection burada ayrıca bir
// GlassCard'a sarılmıyor, HomeScreen'den farklı olarak).
const _chartChromeWidth = 32 + 24;

class TrackingScreen extends StatefulWidget {
  // Favoriler sekmesinden takip ikonuna basılınca RootShell bu ikisini
  // birlikte günceller; requestId aynı sembol için bile her tıklamada
  // arttığından didUpdateWidget yeni bir istek olduğunu anlayabiliyor
  // (bkz. HomeScreen'deki bildirim->grafik deseni, home_screen.dart).
  final MarketSymbol? requestedSymbol;
  final int requestId;

  const TrackingScreen({super.key, this.requestedSymbol, this.requestId = 0});

  @override
  State<TrackingScreen> createState() => _TrackingScreenState();
}

class _TrackingScreenState extends State<TrackingScreen> {
  final _api = MarketApi();
  final _dateFormat = DateFormat('dd.MM.yyyy');

  MarketSymbol? _selectedSymbol;
  DateTimeRange? _dateRange;
  ChartInterval _interval = ChartInterval.hourly;

  bool _loading = false;
  bool _loadingPersisted = true;
  String? _error;
  CandleResult? _result;
  int _paddingCandleCount = 0;

  int _handledRequestId = 0;

  int _estimateMinCandles(BuildContext context) {
    final available = MediaQuery.sizeOf(context).width - _chartChromeWidth;
    return (available / CandlestickChart.maxSlotWidth).ceil().clamp(8, 60);
  }

  static DateTimeRange _last7Days() {
    final now = DateTime.now();
    return DateTimeRange(start: now.subtract(const Duration(days: 7)), end: now);
  }

  @override
  void initState() {
    super.initState();
    _dateRange = _last7Days();
    if (widget.requestedSymbol != null) {
      _handledRequestId = widget.requestId;
      _selectedSymbol = widget.requestedSymbol;
      _loadingPersisted = false;
      // initState içinde setState çağrılamayacağından (widget henüz build
      // edilmedi), fetch ve kalıcı-kayıt ilk frame sonrasına erteleniyor.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _api.setTrackedSymbol(widget.requestedSymbol!.symbol).catchError((e) {
          debugPrint('Takip edilen sembol kaydedilemedi: $e');
        });
        _fetch();
      });
    } else {
      _loadPersistedSymbol();
    }
  }

  @override
  void didUpdateWidget(covariant TrackingScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.requestedSymbol == null) return;
    if (widget.requestId == _handledRequestId) return;
    _handledRequestId = widget.requestId;
    setState(() => _selectedSymbol = widget.requestedSymbol);
    _api.setTrackedSymbol(widget.requestedSymbol!.symbol).catchError((e) {
      debugPrint('Takip edilen sembol kaydedilemedi: $e');
    });
    _fetch();
  }

  Future<void> _loadPersistedSymbol() async {
    try {
      final symbol = await _api.getTrackedSymbol();
      if (!mounted) return;
      if (symbol != null) {
        setState(() => _selectedSymbol = MarketSymbol(symbol: symbol, name: symbol));
        _fetch();
      }
    } catch (e) {
      // Kullanıcı Favoriler'den manuel seçebilir, ama en azından neden boş
      // göründüğünü bilsin.
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Kaydedilmiş sembol yüklenemedi: $e')),
      );
    } finally {
      if (mounted) setState(() => _loadingPersisted = false);
    }
  }

  Future<void> _pickDateRange() async {
    // firstDate Grafik sekmesiyle aynı (DateTime(2000)): saat/4 saatlik gibi
    // gün-içi aralıklar zaten Yahoo'nun kendi ~730 günlük geçmiş sınırına
    // takılıyor (bkz. CLAUDE.md "Known rough edges"), ama haftalık/aylık/
    // 3 aylık için daha eski bir başlangıç seçilebilmesi gerekiyor.
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

  void _selectInterval(ChartInterval interval) {
    setState(() => _interval = interval);
    if (_selectedSymbol != null && _dateRange != null) {
      _fetch();
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Takip', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            'Favoriler sekmesinde bir sembolün yanındaki takip ikonuna '
            'basarak buraya ekleyebilirsin. Aralık saat başı, 4 saatlik, '
            'günlük, haftalık, aylık veya 3 aylık olarak değiştirilebilir.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          if (_loadingPersisted)
            const Center(child: CircularProgressIndicator())
          else ...[
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  _selectedSymbol == null
                      ? 'Henüz takip edilen bir sembol yok.'
                      : 'Takip edilen: ${_selectedSymbol!.symbol}',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
            const SizedBox(height: 16),
            ChartResultSection(
              intervals: ChartInterval.tracking,
              selectedInterval: _interval,
              onSelectInterval: _selectInterval,
              dateRange: _dateRange,
              dateFormat: _dateFormat,
              onPickDateRange: _pickDateRange,
              fetchLabel: 'Yenile',
              fetchIcon: Icons.refresh,
              onFetch: _selectedSymbol == null || _loading ? null : _fetch,
              loading: _loading,
              error: _error,
              result: _result,
              paddingCandleCount: _paddingCandleCount,
            ),
          ],
        ],
      ),
    );
  }
}
