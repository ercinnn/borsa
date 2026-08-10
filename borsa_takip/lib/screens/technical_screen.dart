import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../models/symbol.dart';
import '../models/technical_analysis.dart';
import '../services/market_api.dart';
import '../theme/app_colors.dart';
import '../utils/price_format.dart';
import '../widgets/glass_card.dart';
import '../widgets/symbol_search_field.dart';

/// Investing.com'un "Teknik Özet" sayfasına benzer bir analiz: kullanıcının
/// bu sekmeye eklediği her sembol için Pivot Noktaları, Hareketli Ortalamalar
/// (MA5..MA200) ve Teknik İndikatörler (RSI, STOCH, STOCHRSI, MACD, ATR, ADX,
/// CCI, Highs/Lows, UO, ROC, Williams %R, Bull/Bear Power) + üç özet kutusu
/// gösterilir. Hesaplama tamamen proxy_server'da yapılır (bkz.
/// lib/technical_analysis.dart); bu ekran sadece sonucu tablolar halinde
/// gösterir. Watchlist/Favoriler'den bağımsız kendi listesini tutar (bkz.
/// TechnicalWatchlistStore) — favorites deseniyle aynı: bildirim üretmez,
/// sadece bu sekmede hangi sembollerin analiz edileceğini belirler.
class TechnicalScreen extends StatefulWidget {
  const TechnicalScreen({super.key});

  @override
  State<TechnicalScreen> createState() => _TechnicalScreenState();
}

class _TechnicalScreenState extends State<TechnicalScreen> {
  final _api = MarketApi();
  final _dateFormat = DateFormat('dd.MM.yyyy HH:mm');

  List<String> _watchlist = [];
  bool _loadingWatchlist = true;
  String? _watchlistError;

  String? _selectedSymbol;
  bool _loadingAnalysis = false;
  String? _analysisError;
  TechnicalAnalysisResult? _result;

  @override
  void initState() {
    super.initState();
    _loadWatchlist();
  }

  Future<void> _loadWatchlist() async {
    setState(() => _loadingWatchlist = true);
    try {
      final list = await _api.getTechnicalWatchlist();
      if (!mounted) return;
      setState(() {
        _watchlist = list;
        _loadingWatchlist = false;
      });
      if (_selectedSymbol == null && list.isNotEmpty) {
        _selectSymbol(list.first);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _watchlistError = e.toString();
        _loadingWatchlist = false;
      });
    }
  }

  Future<void> _addSymbol(MarketSymbol symbol) async {
    try {
      final result = await _api.addToTechnicalWatchlist(symbol.symbol);
      if (!mounted) return;
      if (result.added && !_watchlist.contains(result.symbol)) {
        setState(() => _watchlist = [..._watchlist, result.symbol]..sort());
      }
      _selectSymbol(result.symbol);
    } catch (e) {
      if (!mounted) return;
      setState(() => _watchlistError = e.toString());
    }
  }

  Future<void> _removeSymbol(String symbol) async {
    try {
      final result = await _api.removeFromTechnicalWatchlist(symbol);
      if (!mounted) return;
      if (result.removed) {
        setState(() {
          _watchlist = _watchlist.where((s) => s != result.symbol).toList();
          if (_selectedSymbol == result.symbol) {
            _selectedSymbol = null;
            _result = null;
          }
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _watchlistError = e.toString());
    }
  }

  Future<void> _selectSymbol(String symbol) async {
    setState(() {
      _selectedSymbol = symbol;
      _loadingAnalysis = true;
      _analysisError = null;
      _result = null;
    });
    try {
      final result = await _api.technicalAnalysis(symbol);
      if (!mounted) return;
      setState(() {
        _result = result;
        _loadingAnalysis = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _analysisError = e.toString();
        _loadingAnalysis = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Teknik', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            'Eklediğin her sembol için Pivot Noktaları, Hareketli Ortalamalar '
            've Teknik İndikatörlere göre otomatik Al/Sat özeti (Investing.com '
            'tarzı, standart formüllerle bu uygulama içinde hesaplanır).',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          SymbolSearchField(api: _api, onSelect: _addSymbol),
          if (_watchlistError != null) ...[
            const SizedBox(height: 8),
            Text(_watchlistError!, style: const TextStyle(color: AppColors.rose500)),
          ],
          const SizedBox(height: 12),
          if (_loadingWatchlist)
            const Center(child: CircularProgressIndicator())
          else if (_watchlist.isEmpty)
            Text(
              'Henüz sembol eklenmedi. Yukarıdan arayıp ekleyebilirsin.',
              style: Theme.of(context).textTheme.bodySmall,
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final s in _watchlist)
                  _SymbolChip(
                    symbol: s,
                    selected: s == _selectedSymbol,
                    onSelect: () => _selectSymbol(s),
                    onRemove: () => _removeSymbol(s),
                  ),
              ],
            ),
          const SizedBox(height: 20),
          if (_loadingAnalysis) const Center(child: CircularProgressIndicator()),
          if (_analysisError != null)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.rose500.withValues(alpha: 0.15),
                border: Border.all(color: AppColors.rose500.withValues(alpha: 0.4)),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(_analysisError!, style: const TextStyle(color: AppColors.slate100)),
            ),
          if (_result != null) _TechnicalResultView(result: _result!, dateFormat: _dateFormat),
        ],
      ),
    );
  }
}

class _SymbolChip extends StatelessWidget {
  final String symbol;
  final bool selected;
  final VoidCallback onSelect;
  final VoidCallback onRemove;

  const _SymbolChip({
    required this.symbol,
    required this.selected,
    required this.onSelect,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onSelect,
      child: Container(
        padding: const EdgeInsets.only(left: 12, right: 4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: selected
              ? AppColors.cyan500.withValues(alpha: 0.2)
              : AppColors.slate900.withValues(alpha: 0.6),
          border: Border.all(
            color: selected
                ? AppColors.cyan500.withValues(alpha: 0.6)
                : AppColors.slate800.withValues(alpha: 0.8),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(symbol, style: const TextStyle(color: AppColors.slate100)),
            IconButton(
              icon: const Icon(Icons.close, size: 16, color: AppColors.slate400),
              onPressed: onRemove,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              visualDensity: VisualDensity.compact,
              tooltip: 'Listeden çıkar',
            ),
          ],
        ),
      ),
    );
  }
}

Color _signalColor(Signal? signal) => switch (signal) {
      Signal.buy => AppColors.emerald400,
      Signal.sell => AppColors.rose500,
      Signal.neutral || null => AppColors.slate400,
    };

Color _summaryColor(SummarySignal signal) => switch (signal) {
      SummarySignal.strongBuy || SummarySignal.buy => AppColors.emerald400,
      SummarySignal.strongSell || SummarySignal.sell => AppColors.rose500,
      SummarySignal.neutral => AppColors.slate400,
    };

class _SignalBadge extends StatelessWidget {
  final String label;
  final Color color;
  const _SignalBadge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _TechnicalResultView extends StatelessWidget {
  final TechnicalAnalysisResult result;
  final DateFormat dateFormat;

  const _TechnicalResultView({required this.result, required this.dateFormat});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GlassCard(
          glow: true,
          glowBullish: result.summary.overall == SummarySignal.strongBuy ||
              result.summary.overall == SummarySignal.buy,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${result.symbol} · Genel Özet',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  _SignalBadge(
                    label: result.summary.overall.label,
                    color: _summaryColor(result.summary.overall),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Son kapanış: ${formatPrice(result.lastClose)} ${result.currency} '
                '· ${dateFormat.format(result.asOf.toLocal())}',
                style: GoogleFonts.robotoMono(
                    fontSize: 12, color: AppColors.slate400),
              ),
              const SizedBox(height: 4),
              Text(
                'Bu özet, standart teknik analiz formülleriyle bu uygulama '
                'içinde hesaplanır; yatırım tavsiyesi değildir.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
        if (result.pivotPoints != null) ...[
          const SizedBox(height: 16),
          GlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Pivot Noktaları', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 12),
                _PivotRow(label: 'R3', value: result.pivotPoints!.r3),
                _PivotRow(label: 'R2', value: result.pivotPoints!.r2),
                _PivotRow(label: 'R1', value: result.pivotPoints!.r1),
                _PivotRow(label: 'Pivot', value: result.pivotPoints!.pivot, emphasize: true),
                _PivotRow(label: 'S1', value: result.pivotPoints!.s1),
                _PivotRow(label: 'S2', value: result.pivotPoints!.s2),
                _PivotRow(label: 'S3', value: result.pivotPoints!.s3),
              ],
            ),
          ),
        ],
        const SizedBox(height: 16),
        GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text('Hareketli Ortalamalar',
                        style: Theme.of(context).textTheme.titleMedium),
                  ),
                  _SignalBadge(
                    label: result.summary.movingAverages.label,
                    color: _summaryColor(result.summary.movingAverages),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columns: [
                    DataColumn(label: Text('PERİYOT', style: Theme.of(context).textTheme.labelSmall)),
                    DataColumn(label: Text('BASİT (SMA)', style: Theme.of(context).textTheme.labelSmall)),
                    DataColumn(label: Text('ÜSTEL (EMA)', style: Theme.of(context).textTheme.labelSmall)),
                  ],
                  rows: [
                    for (final row in result.movingAverages)
                      DataRow(cells: [
                        DataCell(Text('MA${row.period}',
                            style: const TextStyle(color: AppColors.slate100))),
                        DataCell(_MaCell(value: row.sma, signal: row.smaSignal)),
                        DataCell(_MaCell(value: row.ema, signal: row.emaSignal)),
                      ]),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text('Teknik İndikatörler',
                        style: Theme.of(context).textTheme.titleMedium),
                  ),
                  _SignalBadge(
                    label: result.summary.indicators.label,
                    color: _summaryColor(result.summary.indicators),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              for (final row in result.indicators)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: Text(row.name,
                            style: const TextStyle(color: AppColors.slate100)),
                      ),
                      Expanded(
                        flex: 2,
                        child: Text(
                          row.value.toStringAsFixed(row.value.abs() < 10 ? 4 : 2),
                          style: GoogleFonts.robotoMono(
                              fontSize: 13, color: AppColors.slate100),
                        ),
                      ),
                      _SignalBadge(label: row.signal.label, color: _signalColor(row.signal)),
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

class _PivotRow extends StatelessWidget {
  final String label;
  final double value;
  final bool emphasize;

  const _PivotRow({required this.label, required this.value, this.emphasize = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: 56,
            child: Text(
              label,
              style: TextStyle(
                color: emphasize ? AppColors.cyan500 : AppColors.slate400,
                fontWeight: emphasize ? FontWeight.w700 : FontWeight.w500,
                fontSize: 12,
              ),
            ),
          ),
          Text(
            formatPrice(value),
            style: GoogleFonts.robotoMono(
              color: emphasize ? AppColors.slate100 : AppColors.slate100.withValues(alpha: 0.85),
              fontWeight: emphasize ? FontWeight.w700 : FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _MaCell extends StatelessWidget {
  final double? value;
  final Signal? signal;

  const _MaCell({required this.value, required this.signal});

  @override
  Widget build(BuildContext context) {
    if (value == null) {
      return const Text('—', style: TextStyle(color: AppColors.slate400));
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(formatPrice(value!),
            style: GoogleFonts.robotoMono(fontSize: 13, color: AppColors.slate100)),
        const SizedBox(width: 8),
        _SignalBadge(label: signal!.label, color: _signalColor(signal)),
      ],
    );
  }
}
