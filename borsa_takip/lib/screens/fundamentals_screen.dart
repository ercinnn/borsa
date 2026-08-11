import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../models/fundamentals.dart';
import '../models/symbol.dart';
import '../services/market_api.dart';
import '../theme/app_colors.dart';
import '../utils/price_format.dart';
import '../widgets/glass_card.dart';
import '../widgets/symbol_search_field.dart';

/// "Temel Analiz" sekmesi: DCF ile Adil Değer, Piotroski F-Score, Altman
/// Z-Score ve kural bazlı ProTips özetleri (bkz. proxy_server/lib/
/// fundamental_analysis.dart). Hesaplama tamamen proxy_server'da yapılır ve
/// Supabase'de 24 saat önbelleklenir (bkz. fundamentals_cache.dart) — bu
/// ekran sadece sonucu gösterir. Teknik sekmesiyle AYNI izleme listesini
/// (`TechnicalWatchlistStore`) paylaşır — kendi ayrı bir listesi yok,
/// bilinçli bir tasarım kararı (aynı sembol seti için hem teknik hem
/// fundamental bakış açısı).
class FundamentalsScreen extends StatefulWidget {
  const FundamentalsScreen({super.key});

  @override
  State<FundamentalsScreen> createState() => _FundamentalsScreenState();
}

class _FundamentalsScreenState extends State<FundamentalsScreen> {
  final _api = MarketApi();
  final _dateFormat = DateFormat('dd.MM.yyyy HH:mm');

  List<String> _watchlist = [];
  bool _loadingWatchlist = true;
  String? _watchlistError;

  String? _selectedSymbol;
  bool _loadingData = false;
  String? _dataError;
  StockOverview? _overview;
  FairValueResult? _fairValue;
  HealthScoreResult? _healthScore;
  ProTipsResult? _proTips;

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
            _overview = null;
            _fairValue = null;
            _healthScore = null;
            _proTips = null;
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
      _loadingData = true;
      _dataError = null;
      _overview = null;
      _fairValue = null;
      _healthScore = null;
      _proTips = null;
    });
    try {
      final results = await Future.wait([
        _api.getFundamentalOverview(symbol),
        _api.getFairValue(symbol),
        _api.getHealthScore(symbol),
        _api.getFundamentalProTips(symbol),
      ]);
      if (!mounted) return;
      setState(() {
        _overview = results[0] as StockOverview;
        _fairValue = results[1] as FairValueResult;
        _healthScore = results[2] as HealthScoreResult;
        _proTips = results[3] as ProTipsResult;
        _loadingData = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _dataError = e.toString();
        _loadingData = false;
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
          Text('Temel Analiz', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            'DCF ile basitleştirilmiş Adil Değer, Piotroski F-Score ve Altman '
            'Z-Score — yatırım tavsiyesi değildir. Teknik sekmesiyle aynı '
            'izleme listesini kullanır.',
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
                  _FundamentalsSymbolChip(
                    symbol: s,
                    selected: s == _selectedSymbol,
                    onSelect: () => _selectSymbol(s),
                    onRemove: () => _removeSymbol(s),
                  ),
              ],
            ),
          const SizedBox(height: 20),
          if (_loadingData) const Center(child: CircularProgressIndicator()),
          if (_dataError != null)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.rose500.withValues(alpha: 0.15),
                border: Border.all(color: AppColors.rose500.withValues(alpha: 0.4)),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(_dataError!, style: const TextStyle(color: AppColors.slate100)),
            ),
          if (_overview != null)
            _FundamentalsResultView(
              overview: _overview!,
              fairValue: _fairValue!,
              healthScore: _healthScore!,
              proTips: _proTips!,
              dateFormat: _dateFormat,
            ),
        ],
      ),
    );
  }
}

class _FundamentalsSymbolChip extends StatelessWidget {
  final String symbol;
  final bool selected;
  final VoidCallback onSelect;
  final VoidCallback onRemove;

  const _FundamentalsSymbolChip({
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

Color _altmanColor(String? zone) => switch (zone) {
      'safe' => AppColors.emerald400,
      'distress' => AppColors.rose500,
      _ => AppColors.slate400,
    };

String _altmanLabel(String? zone) => switch (zone) {
      'safe' => 'Güvenli Bölge',
      'grey' => 'Gri Bölge',
      'distress' => 'Riskli Bölge',
      _ => '—',
    };

class _FundamentalsResultView extends StatelessWidget {
  final StockOverview overview;
  final FairValueResult fairValue;
  final HealthScoreResult healthScore;
  final ProTipsResult proTips;
  final DateFormat dateFormat;

  const _FundamentalsResultView({
    required this.overview,
    required this.fairValue,
    required this.healthScore,
    required this.proTips,
    required this.dateFormat,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GlassCard(
          glow: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${overview.symbol} · ${overview.companyName}',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(
                [overview.sector, overview.country].where((s) => s != null).join(' · '),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              Text(
                '${formatPrice(overview.lastPrice)} ${overview.currency}',
                style: GoogleFonts.robotoMono(
                    fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.slate100),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 20,
                runSpacing: 8,
                children: [
                  _StatEntry('Piyasa Değeri', overview.marketCap),
                  _StatEntry('F/K', overview.peRatio, isRatio: true),
                  _StatEntry('PD/DD', overview.pbRatio, isRatio: true),
                  if (overview.dividendYield != null)
                    _StatEntry('Temettü Verimi', overview.dividendYield! * 100,
                        suffix: '%', isRatio: true),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Adil Değer (DCF)', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              if (fairValue.error != null)
                Text(fairValue.error!, style: const TextStyle(color: AppColors.slate400))
              else ...[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Adil Değer', style: Theme.of(context).textTheme.labelSmall),
                          const SizedBox(height: 2),
                          Text(
                            '${formatPrice(fairValue.fairValuePerShare!)} ${overview.currency}',
                            style: GoogleFonts.robotoMono(
                                fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.slate100),
                          ),
                        ],
                      ),
                    ),
                    if (fairValue.upsidePct != null)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text('Güncel Fiyata Göre', style: Theme.of(context).textTheme.labelSmall),
                          const SizedBox(height: 2),
                          Text(
                            '${fairValue.upsidePct! >= 0 ? '+' : ''}${fairValue.upsidePct!.toStringAsFixed(1)}%',
                            style: GoogleFonts.robotoMono(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: fairValue.upsidePct! >= 0
                                  ? AppColors.emerald400
                                  : AppColors.rose500,
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 10),
              Text(
                'Varsayımlar: büyüme %${(fairValue.assumptions.growthRate * 100).toStringAsFixed(1)}, '
                'iskonto oranı %${(fairValue.assumptions.discountRate * 100).toStringAsFixed(0)}, '
                'terminal büyüme %${(fairValue.assumptions.terminalGrowthRate * 100).toStringAsFixed(1)}, '
                '${fairValue.assumptions.projectionYears} yıl projeksiyon — basitleştirilmiş '
                'sabit varsayımlardır, gerçek WACC değildir.',
                style: const TextStyle(fontSize: 11, color: AppColors.slate400),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Finansal Sağlık', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Altman Z-Score', style: Theme.of(context).textTheme.labelSmall),
                        const SizedBox(height: 4),
                        if (healthScore.altmanError != null)
                          Text(healthScore.altmanError!,
                              style: const TextStyle(fontSize: 12, color: AppColors.slate400))
                        else
                          Row(
                            children: [
                              Text(
                                healthScore.altmanZScore!.toStringAsFixed(2),
                                style: GoogleFonts.robotoMono(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                    color: _altmanColor(healthScore.altmanZone)),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: _altmanColor(healthScore.altmanZone).withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                      color: _altmanColor(healthScore.altmanZone).withValues(alpha: 0.4)),
                                ),
                                child: Text(
                                  _altmanLabel(healthScore.altmanZone),
                                  style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: _altmanColor(healthScore.altmanZone)),
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('Piotroski F-Score', style: Theme.of(context).textTheme.labelSmall),
                      const SizedBox(height: 4),
                      Text(
                        '${healthScore.piotroskiScore}/${healthScore.piotroskiMaxScore}',
                        style: GoogleFonts.robotoMono(
                            fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.slate100),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),
              for (final c in healthScore.piotroskiCriteria) _PiotroskiRow(criterion: c),
            ],
          ),
        ),
        const SizedBox(height: 16),
        GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('ProTips', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(
                'Kural bazlı otomatik özet (yapay zeka kullanılmaz), yatırım tavsiyesi değildir.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 10),
              for (final tip in proTips.tips)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('•  ', style: TextStyle(color: AppColors.cyan500)),
                      Expanded(
                        child: Text(tip, style: const TextStyle(color: AppColors.slate100)),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 4),
              Text(
                'Son güncelleme: ${dateFormat.format(overview.updatedAt.toLocal())}',
                style: const TextStyle(fontSize: 11, color: AppColors.slate400),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PiotroskiRow extends StatelessWidget {
  final PiotroskiCriterion criterion;
  const _PiotroskiRow({required this.criterion});

  @override
  Widget build(BuildContext context) {
    final IconData icon;
    final Color color;
    if (criterion.passed == null) {
      icon = Icons.remove;
      color = AppColors.slate400;
    } else if (criterion.passed!) {
      icon = Icons.check;
      color = AppColors.emerald400;
    } else {
      icon = Icons.close;
      color = AppColors.rose500;
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(criterion.name, style: const TextStyle(color: AppColors.slate100)),
          ),
        ],
      ),
    );
  }
}

class _StatEntry extends StatelessWidget {
  final String label;
  final double? value;
  final String suffix;
  final bool isRatio;

  const _StatEntry(this.label, this.value, {this.suffix = '', this.isRatio = false});

  @override
  Widget build(BuildContext context) {
    final text = value == null
        ? '—'
        : (isRatio ? value!.toStringAsFixed(2) : _formatCompact(value!)) + suffix;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelSmall),
        const SizedBox(height: 2),
        Text(text,
            style: GoogleFonts.robotoMono(
                fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.slate100)),
      ],
    );
  }

  static String _formatCompact(double v) {
    if (v.abs() >= 1e12) return '${(v / 1e12).toStringAsFixed(2)}T';
    if (v.abs() >= 1e9) return '${(v / 1e9).toStringAsFixed(2)}B';
    if (v.abs() >= 1e6) return '${(v / 1e6).toStringAsFixed(2)}M';
    return formatPrice(v);
  }
}
