import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../models/backtest.dart';
import '../models/symbol.dart';
import '../services/market_api.dart';
import '../theme/app_colors.dart';
import '../utils/price_format.dart';
import '../widgets/backtest_chart.dart';
import '../widgets/glass_card.dart';
import '../widgets/gradient_button.dart';
import '../widgets/symbol_search_field.dart';

/// "Backtest" sekmesi: "bu puan eşiğine göre alım-satım yapsaydım geçmişte
/// nasıl performans verirdi" simülasyonu. Hesaplama tamamen proxy_server'da
/// yapılır (bkz. proxy_server/lib/backtest.dart runBacktest) — bu ekran
/// yalnızca parametreleri toplayıp sonucu gösterir. Watchlist/Portföy/
/// Teknik'ten bağımsız: kendi geçici seçimini tutar (persist edilmez, her
/// ziyarette sıfırdan kurulur) — Temettü/Teknik'in aksine burada "hangi
/// sembolleri takip ediyorum" diye kalıcı bir liste kavramı yok, her
/// çalıştırma kendi başına bir deney.
class BacktestScreen extends StatefulWidget {
  const BacktestScreen({super.key});

  @override
  State<BacktestScreen> createState() => _BacktestScreenState();
}

class _BacktestScreenState extends State<BacktestScreen> {
  final _api = MarketApi();
  final _dateFormat = DateFormat('dd.MM.yyyy');
  final _buyController = TextEditingController(text: '60');
  final _sellController = TextEditingController(text: '40');
  final _capitalController = TextEditingController(text: '10000');

  MarketSymbol? _selectedSymbol;
  DateTimeRange? _dateRange;

  bool _loading = false;
  String? _error;
  BacktestResult? _result;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _dateRange = DateTimeRange(start: DateTime(now.year - 2, now.month, now.day), end: now);
  }

  @override
  void dispose() {
    _buyController.dispose();
    _sellController.dispose();
    _capitalController.dispose();
    super.dispose();
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

  Future<void> _run() async {
    final symbol = _selectedSymbol;
    final range = _dateRange;
    if (symbol == null || range == null) return;

    final buyThreshold = int.tryParse(_buyController.text.trim());
    final sellThreshold = int.tryParse(_sellController.text.trim());
    final initialCapital =
        double.tryParse(_capitalController.text.trim().replaceAll(',', '.'));

    if (buyThreshold == null || buyThreshold < 0 || buyThreshold > 100) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Geçerli bir alım eşiği gir (0-100).')));
      return;
    }
    if (sellThreshold == null || sellThreshold < 0 || sellThreshold > 100) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Geçerli bir satım eşiği gir (0-100).')));
      return;
    }
    if (buyThreshold <= sellThreshold) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Alım eşiği, satım eşiğinden büyük olmalı.')));
      return;
    }
    if (initialCapital == null || initialCapital <= 0) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Geçerli bir başlangıç sermayesi gir.')));
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
      _result = null;
    });
    try {
      final result = await _api.runBacktest(
        symbol: symbol.symbol,
        start: range.start,
        end: range.end,
        buyThreshold: buyThreshold,
        sellThreshold: sellThreshold,
        initialCapital: initialCapital,
      );
      if (!mounted) return;
      setState(() {
        _result = result;
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

  @override
  Widget build(BuildContext context) {
    final range = _dateRange;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Backtest', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            'Bu puan eşiğine göre alım-satım yapsaydın geçmişte nasıl performans '
            'verirdi? Teknik puan [alım eşiğine] ulaşınca (elde yoksa) al, '
            '[satım eşiğine] düşünce (elde varsa) sat; sonucu "al ve tut" ile '
            'karşılaştır. Yatırım tavsiyesi değildir; işlem maliyeti/kayma hesaba '
            'katılmaz.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          GlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SymbolSearchField(
                  api: _api,
                  onSelect: (s) => setState(() => _selectedSymbol = s),
                ),
                if (_selectedSymbol != null) ...[
                  const SizedBox(height: 8),
                  Text('Seçili: ${_selectedSymbol!.symbol}',
                      style: const TextStyle(color: AppColors.slate100, fontWeight: FontWeight.w600)),
                ],
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _pickDateRange,
                  icon: const Icon(Icons.date_range, size: 18),
                  label: Text(
                    range == null
                        ? 'Tarih aralığı seç'
                        : '${_dateFormat.format(range.start)} – ${_dateFormat.format(range.end)}',
                  ),
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
                        controller: _buyController,
                        keyboardType: TextInputType.number,
                        style: const TextStyle(color: AppColors.slate100),
                        decoration: const InputDecoration(labelText: 'Alım eşiği (0-100)'),
                      ),
                    ),
                    SizedBox(
                      width: 140,
                      child: TextField(
                        controller: _sellController,
                        keyboardType: TextInputType.number,
                        style: const TextStyle(color: AppColors.slate100),
                        decoration: const InputDecoration(labelText: 'Satım eşiği (0-100)'),
                      ),
                    ),
                    SizedBox(
                      width: 160,
                      child: TextField(
                        controller: _capitalController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        style: const TextStyle(color: AppColors.slate100),
                        decoration: const InputDecoration(labelText: 'Başlangıç sermayesi'),
                      ),
                    ),
                    GradientButton(
                      onPressed: _selectedSymbol == null || _loading ? null : _run,
                      loading: _loading,
                      icon: const Icon(Icons.play_arrow),
                      label: 'Çalıştır',
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
          if (_loading) const Center(child: CircularProgressIndicator()),
          if (_result != null) _BacktestResultView(result: _result!, dateFormat: _dateFormat),
        ],
      ),
    );
  }
}

class _BacktestResultView extends StatelessWidget {
  final BacktestResult result;
  final DateFormat dateFormat;
  const _BacktestResultView({required this.result, required this.dateFormat});

  @override
  Widget build(BuildContext context) {
    final beatMarket = result.finalReturnPct >= result.buyHoldReturnPct;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 4),
        GlassCard(
          glow: true,
          glowBullish: result.finalReturnPct >= 0,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _MetricColumn(
                  label: 'Strateji Getirisi',
                  pct: result.finalReturnPct,
                  value: '${formatPrice(result.finalValue)} ${result.currency}',
                ),
              ),
              Expanded(
                child: _MetricColumn(
                  label: 'Al ve Tut Getirisi',
                  pct: result.buyHoldReturnPct,
                  value: '${formatPrice(result.buyHoldFinalValue)} ${result.currency}',
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          beatMarket
              ? 'Strateji, aynı dönemde al-ve-tut\'u geride bıraktı.'
              : 'Strateji, aynı dönemde al-ve-tut\'un gerisinde kaldı.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 16),
        BacktestChart(result: result),
        const SizedBox(height: 16),
        GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('İşlemler (${result.trades.length})',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              if (result.trades.isEmpty)
                Text('Seçilen dönemde hiç al/sat sinyali oluşmadı.',
                    style: Theme.of(context).textTheme.bodySmall)
              else
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    columns: [
                      DataColumn(label: Text('TARİH', style: Theme.of(context).textTheme.labelSmall)),
                      DataColumn(label: Text('TİP', style: Theme.of(context).textTheme.labelSmall)),
                      DataColumn(label: Text('FİYAT', style: Theme.of(context).textTheme.labelSmall)),
                      DataColumn(label: Text('PUAN', style: Theme.of(context).textTheme.labelSmall)),
                    ],
                    rows: [
                      for (final t in result.trades)
                        DataRow(cells: [
                          DataCell(Text(dateFormat.format(t.date.toLocal()),
                              style: const TextStyle(color: AppColors.slate100))),
                          DataCell(_TradeTypeBadge(type: t.type)),
                          DataCell(Text(
                            '${formatPrice(t.price)} ${result.currency}',
                            style: GoogleFonts.robotoMono(fontSize: 13, color: AppColors.slate100),
                          )),
                          DataCell(Text(
                            '${t.score}',
                            style: GoogleFonts.robotoMono(fontSize: 13, color: AppColors.slate400),
                          )),
                        ]),
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

class _MetricColumn extends StatelessWidget {
  final String label;
  final double pct;
  final String value;
  const _MetricColumn({required this.label, required this.pct, required this.value});

  @override
  Widget build(BuildContext context) {
    final color = pct >= 0 ? AppColors.emerald400 : AppColors.rose500;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelSmall),
        const SizedBox(height: 4),
        Text(
          '${pct >= 0 ? '+' : ''}${pct.toStringAsFixed(2)}%',
          style: GoogleFonts.robotoMono(fontSize: 22, fontWeight: FontWeight.w700, color: color),
        ),
        const SizedBox(height: 2),
        Text(value, style: GoogleFonts.robotoMono(fontSize: 12, color: AppColors.slate400)),
      ],
    );
  }
}

class _TradeTypeBadge extends StatelessWidget {
  final String type;
  const _TradeTypeBadge({required this.type});

  @override
  Widget build(BuildContext context) {
    final isBuy = type == 'buy';
    final color = isBuy ? AppColors.emerald400 : AppColors.rose500;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        isBuy ? 'AL' : 'SAT',
        style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700),
      ),
    );
  }
}
