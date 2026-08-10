import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/scored_symbol.dart';
import '../services/market_api.dart';
import '../theme/app_colors.dart';
import '../utils/price_format.dart';
import '../utils/score_color.dart';
import 'glass_card.dart';

/// Bildirimler sayfasındaki "Puan Sıralaması" sekmesi: izleme listesindeki
/// sembolleri Teknik sekmesindeki "alım puanına" (0-100, bkz.
/// technical_analysis.dart) göre sıralar. BIST/ABD/Kripto kategori
/// filtreleri birlikte açılıp kapatılabilir (ör. sadece BIST+Kripto),
/// sıralama yönü (yüksekten düşüğe / düşükten yükseğe) değiştirilebilir,
/// sonuç 50'şerlik sayfalar halinde gösterilir. Kendi `MarketApi()`
/// örneğini ve tüm state'ini (filtre/sıralama/sayfa/sonuç) kendi tutar —
/// NotificationsScreen'e sadece bir sekme olarak eklenir.
class ScoreRankingSection extends StatefulWidget {
  const ScoreRankingSection({super.key});

  @override
  State<ScoreRankingSection> createState() => _ScoreRankingSectionState();
}

class _ScoreRankingSectionState extends State<ScoreRankingSection> {
  final _api = MarketApi();

  Set<String> _categories = {'bist', 'us', 'crypto'};
  bool _descending = true;
  int _page = 1;

  bool _loading = true;
  bool _refreshing = false;
  String? _error;
  ScoredSymbolPage? _result;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({int? page}) async {
    setState(() => _loading = true);
    try {
      final result = await _api.getTechnicalScores(
        categories: _categories,
        descending: _descending,
        page: page ?? _page,
      );
      if (!mounted) return;
      setState(() {
        _result = result;
        _page = result.page;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  void _toggleCategory(String key) {
    setState(() {
      final next = Set<String>.from(_categories);
      if (next.contains(key)) {
        // Son kalan filtreyi kaldırmaya izin verme — boş sonuç kafa karıştırır.
        if (next.length > 1) next.remove(key);
      } else {
        next.add(key);
      }
      _categories = next;
    });
    _load(page: 1);
  }

  void _toggleSort() {
    setState(() => _descending = !_descending);
    _load(page: 1);
  }

  Future<void> _refresh() async {
    setState(() => _refreshing = true);
    try {
      await _api.refreshTechnicalScores();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Puan hesaplama arka planda başlatıldı. İzleme listesi büyükse '
            'birkaç dakika sürebilir, listeyi daha sonra yenileyin.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_error != null)
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.rose500.withValues(alpha: 0.15),
              border: Border.all(color: AppColors.rose500.withValues(alpha: 0.4)),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(_error!, style: const TextStyle(color: AppColors.slate100)),
          ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _CategoryChip(
                label: 'BIST', selected: _categories.contains('bist'),
                onTap: () => _toggleCategory('bist')),
            _CategoryChip(
                label: 'ABD', selected: _categories.contains('us'),
                onTap: () => _toggleCategory('us')),
            _CategoryChip(
                label: 'Kripto', selected: _categories.contains('crypto'),
                onTap: () => _toggleCategory('crypto')),
            OutlinedButton.icon(
              onPressed: _toggleSort,
              icon: Icon(_descending ? Icons.arrow_downward : Icons.arrow_upward, size: 16),
              label: Text(_descending ? 'Yüksekten Düşüğe' : 'Düşükten Yükseğe'),
            ),
            OutlinedButton.icon(
              onPressed: _refreshing ? null : _refresh,
              icon: _refreshing
                  ? const SizedBox(
                      width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.refresh, size: 16),
              label: const Text('Puanları Yenile'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (_loading)
          const Center(child: CircularProgressIndicator())
        else if (_result == null || _result!.items.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text(
              _result != null && _result!.pendingCount > 0
                  ? 'Bu filtreye uyan sembollerin puanı henüz hesaplanmadı '
                      '(${_result!.pendingCount} sembol bekliyor). "Puanları Yenile" ile '
                      'hesaplamayı başlatabilirsin.'
                  : 'Bu filtreye uyan izlenen sembol yok.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          )
        else ...[
          if (_result!.pendingCount > 0)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                '${_result!.pendingCount} sembolün puanı henüz hesaplanmadı, listede '
                'görünmüyor.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          for (final s in _result!.items) _ScoredSymbolTile(item: s),
          const SizedBox(height: 8),
          _Pagination(
            page: _result!.page,
            totalPages: _result!.totalPages,
            total: _result!.total,
            onPageChanged: (p) => _load(page: p),
          ),
        ],
      ],
    );
  }
}

class _CategoryChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _CategoryChip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return FilterChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
    );
  }
}

class _ScoredSymbolTile extends StatelessWidget {
  final ScoredSymbol item;
  const _ScoredSymbolTile({required this.item});

  @override
  Widget build(BuildContext context) {
    final color = scoreColor(item.score);
    final glow = scoreGlows(item.score);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GlassCard(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.symbol,
                      style: const TextStyle(
                          color: AppColors.slate100, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(
                    '${formatPrice(item.lastClose)} ${item.currency}',
                    style: GoogleFonts.robotoMono(fontSize: 12, color: AppColors.slate400),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.slate900.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: color.withValues(alpha: 0.6)),
                boxShadow: glow
                    ? [BoxShadow(color: color.withValues(alpha: 0.6), blurRadius: 14)]
                    : null,
              ),
              child: Text(
                '${item.score}/100',
                style: GoogleFonts.robotoMono(
                    color: color, fontWeight: FontWeight.w800, fontSize: 13),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Pagination extends StatelessWidget {
  final int page;
  final int totalPages;
  final int total;
  final ValueChanged<int> onPageChanged;

  const _Pagination({
    required this.page,
    required this.totalPages,
    required this.total,
    required this.onPageChanged,
  });

  @override
  Widget build(BuildContext context) {
    if (totalPages <= 1) return const SizedBox.shrink();
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          onPressed: page > 1 ? () => onPageChanged(page - 1) : null,
          icon: const Icon(Icons.chevron_left),
        ),
        Text('Sayfa $page / $totalPages · Toplam $total sembol',
            style: const TextStyle(color: AppColors.slate400)),
        IconButton(
          onPressed: page < totalPages ? () => onPageChanged(page + 1) : null,
          icon: const Icon(Icons.chevron_right),
        ),
      ],
    );
  }
}
