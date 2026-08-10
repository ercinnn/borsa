import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/candle.dart';
import '../models/interval.dart';
import '../models/symbol.dart';
import '../services/market_api.dart';
import '../widgets/chart_result_section.dart';
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
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Favoriler', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 16),
                  FavoriteSymbolsBar(
                    symbols: [
                      for (final s in widget.favorites)
                        MarketSymbol(symbol: s, name: s),
                    ],
                    selected: _selectedSymbol,
                    onSelect: _selectSymbol,
                  ),
                  const SizedBox(height: 24),
                  SymbolSearchField(api: _api, onSelect: _selectSymbol),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Zaman Aralığı', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 16),
                  ChartResultSection(
                    intervals: ChartInterval.longTerm,
                    selectedInterval: _interval,
                    onSelectInterval: _selectInterval,
                    dateRange: _dateRange,
                    dateFormat: _dateFormat,
                    onPickDateRange: _pickDateRange,
                    fetchLabel: 'Getir',
                    fetchIcon: Icons.show_chart,
                    onFetch: _selectedSymbol == null || _loading ? null : _fetch,
                    loading: _loading,
                    error: _error,
                    result: _result,
                    leadingActions: [
                      if (_selectedSymbol != null)
                        Chip(label: Text('Seçili: ${_selectedSymbol!.symbol}')),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
