class Candle {
  final String period;
  final double open;
  final double high;
  final double low;
  final double close;

  const Candle({
    required this.period,
    required this.open,
    required this.high,
    required this.low,
    required this.close,
  });

  factory Candle.fromJson(Map<String, dynamic> json) {
    return Candle(
      period: json['period'] as String,
      open: (json['open'] as num).toDouble(),
      high: (json['high'] as num).toDouble(),
      low: (json['low'] as num).toDouble(),
      close: (json['close'] as num).toDouble(),
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
