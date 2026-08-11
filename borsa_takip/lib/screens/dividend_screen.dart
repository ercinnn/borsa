import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../models/dividend.dart';
import '../models/symbol.dart';
import '../services/market_api.dart';
import '../theme/app_colors.dart';
import '../utils/price_format.dart';
import '../widgets/glass_card.dart';
import '../widgets/symbol_search_field.dart';

/// "Temettü" sekmesi: kullanıcının eklediği her sembol için Yahoo'dan gelen
/// son 15 yıllık temettü geçmişini (tarih + hisse başı tutar) tablo halinde
/// gösterir (bkz. proxy_server/lib/yahoo_client.dart fetchDividends).
/// Watchlist/Favoriler/Teknik'ten bağımsız kendi listesini tutar (bkz.
/// DividendWatchlistStore) — aynı desen: bildirim üretmez, sadece bu sekmede
/// hangi sembollerin gösterileceğini belirler. Portföy sekmesindeki tahmini
/// temettü geliri de aynı backend hesaplamasını (fetchDividends) kullanır
/// ama burada tek bir sembolün ham geçmişi gösterilir, adet/gelir tahmini
/// yapılmaz.
class DividendScreen extends StatefulWidget {
  const DividendScreen({super.key});

  @override
  State<DividendScreen> createState() => _DividendScreenState();
}

class _DividendScreenState extends State<DividendScreen> {
  final _api = MarketApi();
  final _dateFormat = DateFormat('dd.MM.yyyy');

  List<String> _watchlist = [];
  bool _loadingWatchlist = true;
  String? _watchlistError;

  String? _selectedSymbol;
  bool _loadingHistory = false;
  String? _historyError;
  DividendHistory? _history;

  @override
  void initState() {
    super.initState();
    _loadWatchlist();
  }

  Future<void> _loadWatchlist() async {
    setState(() => _loadingWatchlist = true);
    try {
      final list = await _api.getDividendWatchlist();
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
      final result = await _api.addToDividendWatchlist(symbol.symbol);
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
      final result = await _api.removeFromDividendWatchlist(symbol);
      if (!mounted) return;
      if (result.removed) {
        setState(() {
          _watchlist = _watchlist.where((s) => s != result.symbol).toList();
          if (_selectedSymbol == result.symbol) {
            _selectedSymbol = null;
            _history = null;
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
      _loadingHistory = true;
      _historyError = null;
      _history = null;
    });
    try {
      final history = await _api.getDividends(symbol);
      if (!mounted) return;
      setState(() {
        _history = history;
        _loadingHistory = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _historyError = e.toString();
        _loadingHistory = false;
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
          Text('Temettü', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            'Eklediğin her sembol için son 15 yıllık temettü ödeme geçmişi '
            '(tarih + hisse başı tutar), Yahoo Finance verisiyle.',
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
                  _DividendSymbolChip(
                    symbol: s,
                    selected: s == _selectedSymbol,
                    onSelect: () => _selectSymbol(s),
                    onRemove: () => _removeSymbol(s),
                  ),
              ],
            ),
          const SizedBox(height: 20),
          if (_loadingHistory) const Center(child: CircularProgressIndicator()),
          if (_historyError != null)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.rose500.withValues(alpha: 0.15),
                border: Border.all(color: AppColors.rose500.withValues(alpha: 0.4)),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(_historyError!, style: const TextStyle(color: AppColors.slate100)),
            ),
          if (_history != null) _DividendHistoryView(history: _history!, dateFormat: _dateFormat),
        ],
      ),
    );
  }
}

class _DividendSymbolChip extends StatelessWidget {
  final String symbol;
  final bool selected;
  final VoidCallback onSelect;
  final VoidCallback onRemove;

  const _DividendSymbolChip({
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

class _DividendHistoryView extends StatelessWidget {
  final DividendHistory history;
  final DateFormat dateFormat;

  const _DividendHistoryView({required this.history, required this.dateFormat});

  @override
  Widget build(BuildContext context) {
    if (history.dividends.isEmpty) {
      return GlassCard(
        child: Text(
          '${history.symbol} için son 15 yılda kayıtlı temettü ödemesi bulunamadı.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      );
    }
    return GlassCard(
      glow: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('${history.symbol} · Temettü Geçmişi',
                    style: Theme.of(context).textTheme.titleMedium),
              ),
              Text(
                'Toplam: ${formatPrice(history.totalPerShare)} ${history.currency}',
                style: GoogleFonts.robotoMono(
                    fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.emerald400),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Son 15 yıl, hisse başı tutar (Yahoo Finance).',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columns: [
                DataColumn(label: Text('TARİH', style: Theme.of(context).textTheme.labelSmall)),
                DataColumn(label: Text('TUTAR', style: Theme.of(context).textTheme.labelSmall)),
              ],
              rows: [
                for (final d in history.dividends)
                  DataRow(cells: [
                    DataCell(Text(dateFormat.format(d.date.toLocal()),
                        style: const TextStyle(color: AppColors.slate100))),
                    DataCell(Text(
                      '${formatPrice(d.amount)} ${history.currency}',
                      style: GoogleFonts.robotoMono(fontSize: 13, color: AppColors.slate100),
                    )),
                  ]),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
