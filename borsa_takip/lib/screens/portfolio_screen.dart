import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/portfolio.dart';
import '../models/symbol.dart';
import '../services/market_api.dart';
import '../theme/app_colors.dart';
import '../utils/price_format.dart';
import '../widgets/glass_card.dart';
import '../widgets/gradient_button.dart';
import '../widgets/portfolio_allocation_chart.dart';
import '../widgets/symbol_search_field.dart';

/// "Portföy" sekmesi: kullanıcının "şu sembolden şu adet, şu maliyetten
/// aldım" şeklinde girdiği pozisyonları, anlık kâr/zarar + toplam portföy
/// değeri + dağılım grafiğiyle gösterir. Hesaplama backend'de yapılır (bkz.
/// proxy_server/lib/portfolio_summary.dart) — TRY olmayan pozisyonlar
/// (ör. ABD hisseleri/kripto, USD) o anki USD/TRY kuruyla TL'ye çevrilip
/// tek bir toplama dahil edilir. Aynı sembolü tekrar eklemek mevcut
/// pozisyonu YENİ adet/maliyetle tamamen değiştirir (basit tutmak için
/// ağırlıklı ortalama birleştirmesi yapılmaz) — "Düzenle" bu yüzden formu
/// mevcut değerlerle doldurup aynı "Ekle" akışını kullanır.
class PortfolioScreen extends StatefulWidget {
  const PortfolioScreen({super.key});

  @override
  State<PortfolioScreen> createState() => _PortfolioScreenState();
}

class _PortfolioScreenState extends State<PortfolioScreen> {
  final _api = MarketApi();
  final _quantityController = TextEditingController();
  final _costController = TextEditingController();

  MarketSymbol? _selectedSymbol;
  bool _loading = true;
  bool _submitting = false;
  String? _error;
  PortfolioSummary? _summary;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _quantityController.dispose();
    _costController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final summary = await _api.getPortfolio();
      if (!mounted) return;
      setState(() {
        _summary = summary;
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

  Future<void> _submit() async {
    final symbol = _selectedSymbol;
    if (symbol == null) return;
    final quantity = double.tryParse(_quantityController.text.trim().replaceAll(',', '.'));
    final cost = double.tryParse(_costController.text.trim().replaceAll(',', '.'));
    if (quantity == null || quantity <= 0) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Geçerli bir adet gir.')));
      return;
    }
    if (cost == null || cost < 0) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Geçerli bir maliyet gir.')));
      return;
    }
    setState(() => _submitting = true);
    try {
      await _api.addPortfolioHolding(symbol: symbol.symbol, quantity: quantity, costBasis: cost);
      _quantityController.clear();
      _costController.clear();
      if (!mounted) return;
      setState(() => _selectedSymbol = null);
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _editHolding(PortfolioHoldingResult h) {
    setState(() {
      _selectedSymbol = MarketSymbol(symbol: h.symbol, name: h.symbol);
      _quantityController.text = _trimNumber(h.quantity);
      _costController.text = _trimNumber(h.costBasis);
    });
  }

  Future<void> _remove(String symbol) async {
    try {
      await _api.removePortfolioHolding(symbol);
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  static String _trimNumber(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();

  @override
  Widget build(BuildContext context) {
    final summary = _summary;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Portföy', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            'Elindeki sembolleri adet ve maliyetiyle ekle; anlık kâr/zarar ve '
            'toplam portföy değeri TL cinsinden hesaplanır (ABD/kripto pozisyonları '
            'güncel USD/TRY kuruyla çevrilir).',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          GlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_selectedSymbol == null ? 'Pozisyon Ekle' : 'Düzenle: ${_selectedSymbol!.symbol}',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 12),
                SymbolSearchField(
                  api: _api,
                  onSelect: (s) => setState(() => _selectedSymbol = s),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    SizedBox(
                      width: 140,
                      child: TextField(
                        controller: _quantityController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        style: const TextStyle(color: AppColors.slate100),
                        decoration: const InputDecoration(labelText: 'Adet'),
                      ),
                    ),
                    SizedBox(
                      width: 160,
                      child: TextField(
                        controller: _costController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        style: const TextStyle(color: AppColors.slate100),
                        decoration: const InputDecoration(labelText: 'Birim maliyet'),
                      ),
                    ),
                    GradientButton(
                      onPressed: _selectedSymbol == null || _submitting ? null : _submit,
                      loading: _submitting,
                      icon: const Icon(Icons.add),
                      label: 'Ekle',
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
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
          if (_loading)
            const Center(child: CircularProgressIndicator())
          else if (summary == null || summary.holdings.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text('Henüz pozisyon eklenmedi.', style: Theme.of(context).textTheme.bodySmall),
            )
          else ...[
            _SummaryCard(summary: summary),
            const SizedBox(height: 16),
            GlassCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Dağılım', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 12),
                  PortfolioAllocationChart(
                    slices: [
                      for (final h in summary.holdings)
                        if (h.valueInTry != null)
                          AllocationSlice(symbol: h.symbol, valueInTry: h.valueInTry!),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            for (final h in summary.holdings)
              _HoldingTile(holding: h, onEdit: () => _editHolding(h), onRemove: () => _remove(h.symbol)),
          ],
        ],
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final PortfolioSummary summary;
  const _SummaryCard({required this.summary});

  @override
  Widget build(BuildContext context) {
    final pnlColor = summary.totalPnlTry >= 0 ? AppColors.emerald400 : AppColors.rose500;
    return GlassCard(
      glow: true,
      glowBullish: summary.totalPnlTry >= 0,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Toplam Portföy Değeri', style: Theme.of(context).textTheme.labelSmall),
          const SizedBox(height: 4),
          Text(
            '${formatPrice(summary.totalValueTry)} TRY',
            style: GoogleFonts.robotoMono(
                fontSize: 24, fontWeight: FontWeight.w700, color: AppColors.slate100),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(summary.totalPnlTry >= 0 ? Icons.trending_up : Icons.trending_down,
                  color: pnlColor, size: 16),
              const SizedBox(width: 4),
              Text(
                '${summary.totalPnlTry >= 0 ? '+' : ''}${formatPrice(summary.totalPnlTry)} TRY '
                '(${summary.totalPnlPct == null ? '—' : '${summary.totalPnlPct! >= 0 ? '+' : ''}${summary.totalPnlPct!.toStringAsFixed(2)}%'})',
                style: GoogleFonts.robotoMono(
                    fontSize: 13, fontWeight: FontWeight.w700, color: pnlColor),
              ),
            ],
          ),
          if (summary.usdTryRate != null) ...[
            const SizedBox(height: 8),
            Text('USD/TRY: ${summary.usdTryRate!.toStringAsFixed(2)}',
                style: GoogleFonts.robotoMono(fontSize: 11, color: AppColors.slate400)),
          ],
          if (summary.unconvertedCount > 0) ...[
            const SizedBox(height: 4),
            Text(
              '${summary.unconvertedCount} pozisyon TL/USD dışında bir para biriminde '
              'olduğundan toplama dahil edilmedi.',
              style: const TextStyle(fontSize: 11, color: AppColors.slate400),
            ),
          ],
        ],
      ),
    );
  }
}

class _HoldingTile extends StatelessWidget {
  final PortfolioHoldingResult holding;
  final VoidCallback onEdit;
  final VoidCallback onRemove;

  const _HoldingTile({required this.holding, required this.onEdit, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    final h = holding;
    final hasPnl = h.pnl != null;
    final pnlColor = !hasPnl
        ? AppColors.slate400
        : (h.pnl! >= 0 ? AppColors.emerald400 : AppColors.rose500);
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
                  Text(h.symbol,
                      style: const TextStyle(color: AppColors.slate100, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(
                    '${_trim(h.quantity)} adet × ${formatPrice(h.costBasis)} ${h.currency}',
                    style: GoogleFonts.robotoMono(fontSize: 11, color: AppColors.slate400),
                  ),
                  if (h.error != null)
                    Text(h.error!, style: const TextStyle(fontSize: 11, color: AppColors.rose500))
                  else if (h.currentValue != null)
                    Text(
                      'Güncel: ${formatPrice(h.currentValue!)} ${h.currency}',
                      style: GoogleFonts.robotoMono(fontSize: 11, color: AppColors.slate400),
                    ),
                ],
              ),
            ),
            if (hasPnl)
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${h.pnl! >= 0 ? '+' : ''}${formatPrice(h.pnl!)} ${h.currency}',
                    style: GoogleFonts.robotoMono(
                        fontSize: 13, fontWeight: FontWeight.w700, color: pnlColor),
                  ),
                  Text(
                    h.pnlPct == null
                        ? '—'
                        : '${h.pnlPct! >= 0 ? '+' : ''}${h.pnlPct!.toStringAsFixed(2)}%',
                    style: GoogleFonts.robotoMono(fontSize: 11, color: pnlColor),
                  ),
                ],
              ),
            IconButton(
              icon: const Icon(Icons.edit_outlined, size: 18, color: AppColors.slate400),
              onPressed: onEdit,
              tooltip: 'Düzenle',
              visualDensity: VisualDensity.compact,
            ),
            IconButton(
              icon: const Icon(Icons.close, size: 18, color: AppColors.slate400),
              onPressed: onRemove,
              tooltip: 'Portföyden çıkar',
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
      ),
    );
  }

  static String _trim(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();
}
