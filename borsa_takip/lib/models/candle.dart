class Candle {
  final String period;
  final double open;
  final double high;
  final double low;
  final double close;
  // RSI/MACD paneli (bkz. widgets/candlestick_chart.dart) — yalnızca
  // `MarketApi.candles(includeIndicators: true)` ile istendiğinde dolu
  // gelir, aksi halde null (bkz. bin/server.dart _candlesHandler
  // `indicators` parametresi).
  final double? rsi;
  final double? macd;
  final double? macdSignal;
  final double? macdHistogram;

  const Candle({
    required this.period,
    required this.open,
    required this.high,
    required this.low,
    required this.close,
    this.rsi,
    this.macd,
    this.macdSignal,
    this.macdHistogram,
  });

  factory Candle.fromJson(Map<String, dynamic> json) {
    return Candle(
      period: json['period'] as String,
      open: (json['open'] as num).toDouble(),
      high: (json['high'] as num).toDouble(),
      low: (json['low'] as num).toDouble(),
      close: (json['close'] as num).toDouble(),
      rsi: (json['rsi'] as num?)?.toDouble(),
      macd: (json['macd'] as num?)?.toDouble(),
      macdSignal: (json['macdSignal'] as num?)?.toDouble(),
      macdHistogram: (json['macdHistogram'] as num?)?.toDouble(),
    );
  }
}

class CandleResult {
  final String symbol;
  final String currency;
  final List<Candle> candles;

  const CandleResult({
    required this.symbol,
    required this.currency,
    required this.candles,
  });

  factory CandleResult.fromJson(Map<String, dynamic> json) {
    final list = (json['candles'] as List)
        .cast<Map<String, dynamic>>()
        .map(Candle.fromJson)
        .toList();
    return CandleResult(
      symbol: json['symbol'] as String,
      currency: json['currency'] as String? ?? '',
      candles: list,
    );
  }
}
