import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/candle.dart';
import '../models/interval.dart';
import '../models/symbol.dart';
import '../services/market_api.dart';
import '../theme/app_colors.dart';
import '../widgets/comparison_chart.dart';
import '../widgets/glass_card.dart';
import '../widgets/gradient_button.dart';
import '../widgets/symbol_search_field.dart';

/// "Karşılaştırmalı Grafik" sekmesi: 2-4 sembolü aynı grafikte yüzdesel
/// normalize ederek üst üste gösterir (ör. THYAO vs BIST100 endeksi).
/// Backend değişikliği gerektirmez — sadece mevcut `/api/candles`'ı her
/// sembol için ayrı ayrı çağırır (bkz. MarketApi.candles). Hizalama detayı
/// için widgets/comparison_chart.dart'ın doc yorumuna bakın.
class ComparisonScreen extends StatefulWidget {
  const ComparisonScreen({super.key});

  @override
  State<ComparisonScreen> createState() => _ComparisonScreenState();
}

class _ComparisonScreenState extends State<ComparisonScreen> {
  final _api = MarketApi();
  final _dateFormat = DateFormat('dd.MM.yyyy');

  static const _maxSymbols = 4;

  final List<MarketSymbol> _symbols = [];
  DateTimeRange? _dateRange;
  ChartInterval _interval = ChartInterval.daily;

  bool _loading = false;
  String? _error;
  List<CandleResult>? _results;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _dateRange = DateTimeRange(start: DateTime(now.year - 1, now.month, now.day), end: now);
  }

  void _addSymbol(MarketSymbol symbol) {
    if (_symbols.any((s) => s.symbol == symbol.symbol)) return;
    if (_symbols.length >= _maxSymbols) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('En fazla $_maxSymbols sembol karşılaştırabilirsin.')),
      );
      return;
    }
    setState(() {
      _symbols.add(symbol);
      // _removeSymbol'daki aynı sıfırlama burada da gerekli: _results
      // (dolayısıyla ComparisonChart'a giden alignedSeries) son fetch
      // anındaki sembol sayısına göre boyutlanmış — sembol eklendikten
      // sonra yeniden "Karşılaştır"a basılmadan eski _results ile
      // gösterilmeye çalışılırsa ComparisonChart'ın legend döngüsü
      // (symbols.length'e göre) pctSeries'te (eski, daha kısa uzunlukta)
      // aralık dışı indekse erişip RangeError fırlatıyordu.
      _results = null;
    });
  }

  void _removeSymbol(MarketSymbol symbol) {
    setState(() {
      _symbols.removeWhere((s) => s.symbol == symbol.symbol);
      _results = null;
    });
  }

  Future<void> _pickDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
      initialDateRange: _dateRange,
    );
    if (picked != null) setState(() => _dateRange = picked);
  }

  Future<void> _fetch() async {
    final range = _dateRange;
    if (_symbols.length < 2 || range == null) return;
    setState(() {
      _loading = true;
      _error = null;
      _results = null;
    });
    try {
      final results = await Future.wait([
        for (final s in _symbols)
          _api.candles(symbol: s.symbol, start: range.start, end: range.end, interval: _interval),
      ]);
      if (!mounted) return;
      setState(() {
        _results = results;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  /// Serileri en kısa olanın uzunluğuna göre SONDAN (bugünden geriye)
  /// hizalar — bkz. ComparisonChart'ın doc yorumu.
  List<List<Candle>> _alignedSeries(List<CandleResult> results) {
    final minLen = results.map((r) => r.candles.length).reduce((a, b) => a < b ? a : b);
    if (minLen == 0) return [for (final _ in results) <Candle>[]];
    return [
      for (final r in results) r.candles.sublist(r.candles.length - minLen),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Karşılaştırmalı Grafik', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            '2-$_maxSymbols sembolü seçip fiyatlarını aynı başlangıç noktasından '
            'yüzdesel değişim olarak karşılaştır (ör. THYAO vs BIST100 endeksi).',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          // Diğer kontrol panelli sekmelerle (Grafik/Takip/Backtest) aynı
          // GlassCard çerçevelemesi — önceden bu bölüm çıplak duruyordu.
          GlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SymbolSearchField(api: _api, onSelect: _addSymbol),
                const SizedBox(height: 12),
                if (_symbols.isEmpty)
                  Text('Karşılaştırmak için en az 2 sembol ekle.',
                      style: Theme.of(context).textTheme.bodySmall)
                else
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (var i = 0; i < _symbols.length; i++)
                        _SymbolChip(
                          symbol: _symbols[i],
                          color: comparisonLineColors[i % comparisonLineColors.length],
                          onRemove: () => _removeSymbol(_symbols[i]),
                        ),
                    ],
                  ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final interval in ChartInterval.longTerm)
                      ChoiceChip(
                        label: Text(interval.label),
                        selected: _interval == interval,
                        onSelected: (_) => setState(() => _interval = interval),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _pickDateRange,
                      icon: const Icon(Icons.date_range),
                      label: Text(
                        _dateRange == null
                            ? 'Tarih aralığı seç'
                            : '${_dateFormat.format(_dateRange!.start)} - '
                                '${_dateFormat.format(_dateRange!.end)}',
                      ),
                    ),
                    GradientButton(
                      onPressed: _symbols.length < 2 || _loading ? null : _fetch,
                      icon: const Icon(Icons.show_chart),
                      label: 'Karşılaştır',
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          if (_loading) const Center(child: CircularProgressIndicator()),
          if (_error != null)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.rose500.withValues(alpha: 0.15),
                border: Border.all(color: AppColors.rose500.withValues(alpha: 0.4)),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(_error!, style: const TextStyle(color: AppColors.slate100)),
            ),
          if (_results != null)
            ComparisonChart(
              symbols: [for (final s in _symbols) s.symbol],
              alignedSeries: _alignedSeries(_results!),
            ),
        ],
      ),
    );
  }
}

class _SymbolChip extends StatelessWidget {
  final MarketSymbol symbol;
  final Color color;
  final VoidCallback onRemove;
  const _SymbolChip({required this.symbol, required this.color, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.only(left: 10, right: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: AppColors.slate900.withValues(alpha: 0.6),
        border: Border.all(color: color.withValues(alpha: 0.6)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 8),
          Text(symbol.symbol, style: const TextStyle(color: AppColors.slate100)),
          IconButton(
            icon: const Icon(Icons.close, size: 16, color: AppColors.slate400),
            onPressed: onRemove,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            visualDensity: VisualDensity.compact,
            tooltip: 'Karşılaştırmadan çıkar',
          ),
        ],
      ),
    );
  }
}
