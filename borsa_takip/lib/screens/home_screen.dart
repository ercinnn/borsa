import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/candle.dart';
import '../models/interval.dart';
import '../models/symbol.dart';
import '../services/market_api.dart';
import '../widgets/candle_table.dart';
import '../widgets/candlestick_chart.dart';
import '../widgets/favorite_symbols_bar.dart';
import '../widgets/symbol_search_field.dart';

class HomeScreen extends StatefulWidget {
  // Bildirimler sekmesinden bir sembole tıklanınca RootShell bu ikisini
  // birlikte günceller: requestId, requestedSymbol aynı sembol için bile
  // her tıklamada arttığından didUpdateWidget yeni bir istek olduğunu
  // anlayıp otomatik grafiği getirebiliyor.
  final MarketSymbol? requestedSymbol;
  final int requestId;
  final List<String> favorites;

  const HomeScreen({
    super.key,
    this.requestedSymbol,
    this.requestId = 0,
    this.favorites = const [],
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
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

  int _handledRequestId = 0;

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
    });

    try {
      final result = await _api.candles(
        symbol: symbol.symbol,
        start: range.start,
        end: range.end,
        interval: _interval,
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

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Favoriler', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          FavoriteSymbolsBar(
            symbols: [
              for (final s in widget.favorites) MarketSymbol(symbol: s, name: s),
            ],
            selected: _selectedSymbol,
            onSelect: _selectSymbol,
          ),
          const SizedBox(height: 16),
          SymbolSearchField(api: _api, onSelect: _selectSymbol),
          const SizedBox(height: 16),
          Text('Zaman Aralığı', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final interval in ChartInterval.longTerm)
                ChoiceChip(
                  label: Text(interval.label),
                  selected: _interval == interval,
                  onSelected: (_) => _selectInterval(interval),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (_selectedSymbol != null)
                Chip(label: Text('Seçili: ${_selectedSymbol!.symbol}')),
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
              ElevatedButton.icon(
                onPressed: _selectedSymbol == null || _loading ? null : _fetch,
                icon: const Icon(Icons.show_chart),
                label: const Text('Getir'),
              ),
            ],
          ),
          const SizedBox(height: 24),
          if (_loading) const Center(child: CircularProgressIndicator()),
          if (_error != null)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(_error!),
            ),
          if (_result != null) ...[
            CandlestickChart(result: _result!),
            const SizedBox(height: 16),
            CandleTable(result: _result!),
          ],
        ],
      ),
    );
  }
}
