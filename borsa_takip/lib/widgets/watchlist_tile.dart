import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/candle.dart';
import '../models/interval.dart';
import '../services/market_api.dart';
import '../theme/app_colors.dart';
import '../utils/price_format.dart';
import 'glass_card.dart';

/// Bento düzeninin yan sütunundaki izleme listesi karosu — Favoriler
/// listesinden (en fazla [_maxSymbols]) her sembol için son fiyat, günlük
/// yüzde değişim ve son 30 günün küçük bir çizgi grafiğini (sparkline)
/// gösterir. `RootShell`'in tek `_favorites` listesini kullanır (bkz.
/// HomeScreen'in `favorites` prop'u) — ayrı bir izleme listesi kavramı
/// değil, sadece favorilerin bu ekrandaki bir başka görünümü. Satıra
/// tıklamak [onSelect] üzerinden hero grafiğin sembolünü değiştirir, aynı
/// `FavoriteSymbolsBar`'ın yaptığı gibi.
class WatchlistTile extends StatefulWidget {
  final List<String> favorites;
  final MarketApi api;
  final String? selectedSymbol;
  final ValueChanged<String> onSelect;

  const WatchlistTile({
    super.key,
    required this.favorites,
    required this.api,
    required this.selectedSymbol,
    required this.onSelect,
  });

  @override
  State<WatchlistTile> createState() => _WatchlistTileState();
}

class _WatchlistTileState extends State<WatchlistTile> {
  // Bento karosu kompakt bir özet olması gerektiğinden (tam liste zaten
  // Favoriler sekmesinde var) ve her sembol ayrı bir /api/candles çağrısı
  // gerektirdiğinden, çok büyük bir favori listesinde bile istek sayısını
  // sınırlı tutmak için ilk N tanesi gösteriliyor.
  static const _maxSymbols = 6;

  bool _loading = false;
  final Map<String, CandleResult?> _data = {};
  List<String> _shown = const [];

  @override
  void initState() {
    super.initState();
    _shown = widget.favorites.take(_maxSymbols).toList();
    _fetch();
  }

  @override
  void didUpdateWidget(covariant WatchlistTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    final shown = widget.favorites.take(_maxSymbols).toList();
    if (shown.length != _shown.length || !shown.every(_shown.contains)) {
      _shown = shown;
      _fetch();
    }
  }

  Future<void> _fetch() async {
    if (_shown.isEmpty) return;
    setState(() => _loading = true);
    final now = DateTime.now();
    final start = now.subtract(const Duration(days: 30));
    final results = await Future.wait([
      for (final symbol in _shown)
        widget.api
            .candles(symbol: symbol, start: start, end: now, interval: ChartInterval.daily)
            .then<CandleResult?>((r) => r)
            .catchError((_) => null),
    ]);
    if (!mounted) return;
    setState(() {
      _data
        ..clear()
        ..addEntries([for (var i = 0; i < _shown.length; i++) MapEntry(_shown[i], results[i])]);
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.visibility, color: AppColors.cyan500, size: 18),
              const SizedBox(width: 8),
              Text('İzleme Listesi', style: Theme.of(context).textTheme.titleSmall),
              const Spacer(),
              if (_loading)
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (_shown.isEmpty)
            Text(
              'Favoriler sekmesinden birkaç sembol ekleyerek burada '
              'fiyatlarını takip edebilirsin.',
              style: Theme.of(context).textTheme.bodySmall,
            )
          else
            for (final symbol in _shown) ...[
              _WatchlistRow(
                symbol: symbol,
                result: _data[symbol],
                selected: symbol == widget.selectedSymbol,
                onTap: () => widget.onSelect(symbol),
              ),
              if (symbol != _shown.last) const Divider(height: 16, color: AppColors.slate800),
            ],
        ],
      ),
    );
  }
}

class _WatchlistRow extends StatelessWidget {
  final String symbol;
  final CandleResult? result;
  final bool selected;
  final VoidCallback onTap;

  const _WatchlistRow({
    required this.symbol,
    required this.result,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final candles = result?.candles ?? const <Candle>[];
    final last = candles.isEmpty ? null : candles.last;
    final prev = candles.length >= 2 ? candles[candles.length - 2] : null;
    final changePct = (last != null && prev != null && prev.close != 0)
        ? (last.close - prev.close) / prev.close * 100
        : null;
    final isUp = (changePct ?? 0) >= 0;
    final trendColor = changePct == null ? AppColors.slate400 : (isUp ? AppColors.emerald400 : AppColors.rose500);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? AppColors.cyan500.withValues(alpha: 0.12) : null,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Expanded(
              flex: 3,
              child: Text(
                symbol,
                style: const TextStyle(color: AppColors.slate100, fontWeight: FontWeight.w600),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            SizedBox(
              width: 44,
              height: 22,
              child: candles.length >= 2 ? _Sparkline(candles: candles, color: trendColor) : null,
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 3,
              child: last == null
                  ? const _RowSkeleton()
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          formatPrice(last.close),
                          style: GoogleFonts.robotoMono(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppColors.slate100,
                          ),
                        ),
                        if (changePct != null)
                          Text(
                            '${isUp ? '+' : ''}${changePct.toStringAsFixed(2)}%',
                            style: TextStyle(fontSize: 11, color: trendColor),
                          ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RowSkeleton extends StatelessWidget {
  const _RowSkeleton();

  @override
  Widget build(BuildContext context) {
    return const Text('—', style: TextStyle(color: AppColors.slate400));
  }
}

class _Sparkline extends StatelessWidget {
  final List<Candle> candles;
  final Color color;

  const _Sparkline({required this.candles, required this.color});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _SparklinePainter(closes: [for (final c in candles) c.close], color: color),
      size: Size.infinite,
    );
  }
}

class _SparklinePainter extends CustomPainter {
  final List<double> closes;
  final Color color;

  _SparklinePainter({required this.closes, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    if (closes.length < 2) return;
    final min = closes.reduce((a, b) => a < b ? a : b);
    final max = closes.reduce((a, b) => a > b ? a : b);
    final range = (max - min).abs() < 1e-9 ? 1.0 : max - min;
    final dx = size.width / (closes.length - 1);

    final path = Path();
    for (var i = 0; i < closes.length; i++) {
      final x = dx * i;
      final y = size.height - ((closes[i] - min) / range) * size.height;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant _SparklinePainter oldDelegate) =>
      oldDelegate.closes != closes || oldDelegate.color != color;
}
