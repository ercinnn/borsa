import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/candle.dart';
import '../models/interval.dart';
import '../models/symbol.dart';
import '../services/market_api.dart';
import '../widgets/candle_table.dart';
import '../widgets/candlestick_chart.dart';

class TrackingScreen extends StatefulWidget {
  // Favoriler sekmesinden takip ikonuna basılınca RootShell bu ikisini
  // birlikte günceller; requestId aynı sembol için bile her tıklamada
  // arttığından didUpdateWidget yeni bir istek olduğunu anlayabiliyor
  // (bkz. HomeScreen'deki bildirim->grafik deseni, home_screen.dart).
  final MarketSymbol? requestedSymbol;
  final int requestId;

  const TrackingScreen({super.key, this.requestedSymbol, this.requestId = 0});

  @override
  State<TrackingScreen> createState() => _TrackingScreenState();
}

class _TrackingScreenState extends State<TrackingScreen> {
  final _api = MarketApi();
  final _dateFormat = DateFormat('dd.MM.yyyy');

  MarketSymbol? _selectedSymbol;
  DateTimeRange? _dateRange;
  ChartInterval _interval = ChartInterval.hourly;

  bool _loading = false;
  bool _loadingPersisted = true;
  String? _error;
  CandleResult? _result;

  int _handledRequestId = 0;

  static DateTimeRange _last7Days() {
    final now = DateTime.now();
    return DateTimeRange(start: now.subtract(const Duration(days: 7)), end: now);
  }

  @override
  void initState() {
    super.initState();
    _dateRange = _last7Days();
    if (widget.requestedSymbol != null) {
      _handledRequestId = widget.requestId;
      _selectedSymbol = widget.requestedSymbol;
      _loadingPersisted = false;
      // initState içinde setState çağrılamayacağından (widget henüz build
      // edilmedi), fetch ve kalıcı-kayıt ilk frame sonrasına erteleniyor.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _api.setTrackedSymbol(widget.requestedSymbol!.symbol).catchError((_) {});
        _fetch();
      });
    } else {
      _loadPersistedSymbol();
    }
  }

  @override
  void didUpdateWidget(covariant TrackingScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.requestedSymbol == null) return;
    if (widget.requestId == _handledRequestId) return;
    _handledRequestId = widget.requestId;
    setState(() => _selectedSymbol = widget.requestedSymbol);
    _api.setTrackedSymbol(widget.requestedSymbol!.symbol).catchError((_) {});
    _fetch();
  }

  Future<void> _loadPersistedSymbol() async {
    try {
      final symbol = await _api.getTrackedSymbol();
      if (!mounted) return;
      if (symbol != null) {
        setState(() => _selectedSymbol = MarketSymbol(symbol: symbol, name: symbol));
        _fetch();
      }
    } catch (_) {
      // Sessiz geç: kalıcı sembol yüklenemezse kullanıcı Favoriler'den
      // manuel seçebilir.
    } finally {
      if (mounted) setState(() => _loadingPersisted = false);
    }
  }

  Future<void> _pickDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
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

  void _selectInterval(ChartInterval interval) {
    setState(() => _interval = interval);
    if (_selectedSymbol != null && _dateRange != null) {
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
          Text('Takip', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            'Favoriler sekmesinde bir sembolün yanındaki takip ikonuna '
            'basarak buraya ekleyebilirsin. Aralık saat başı, 4 saatlik '
            'veya günlük olarak değiştirilebilir.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          if (_loadingPersisted)
            const Center(child: CircularProgressIndicator())
          else ...[
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  _selectedSymbol == null
                      ? 'Henüz takip edilen bir sembol yok.'
                      : 'Takip edilen: ${_selectedSymbol!.symbol}',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final interval in ChartInterval.intraday)
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
                  icon: const Icon(Icons.refresh),
                  label: const Text('Yenile'),
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
        ],
      ),
    );
  }
}
