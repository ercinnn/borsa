class BacktestTrade {
  final String type; // 'buy' | 'sell'
  final DateTime date;
  final double price;
  final int score;

  const BacktestTrade({
    required this.type,
    required this.date,
    required this.price,
    required this.score,
  });

  factory BacktestTrade.fromJson(Map<String, dynamic> json) => BacktestTrade(
        type: json['type'] as String,
        date: DateTime.parse(json['date'] as String),
        price: (json['price'] as num).toDouble(),
        score: json['score'] as int,
      );
}

class BacktestPoint {
  final DateTime date;
  final double strategyValue;
  final double buyHoldValue;

  const BacktestPoint({
    required this.date,
    required this.strategyValue,
    required this.buyHoldValue,
  });

  factory BacktestPoint.fromJson(Map<String, dynamic> json) => BacktestPoint(
        date: DateTime.parse(json['date'] as String),
        strategyValue: (json['strategyValue'] as num).toDouble(),
        buyHoldValue: (json['buyHoldValue'] as num).toDouble(),
      );
}

/// `/api/backtest` yanıtı — bkz. proxy_server/lib/backtest.dart runBacktest.
/// BASİTLEŞTİRİLMİŞ VARSAYIMLAR (bkz. runBacktest doc yorumu): işlem
/// maliyeti/kayma yok, sinyal günün kapanışından anında uygulanır, pozisyon
/// her zaman ya tamamen nakit ya tamamen hisse.
class BacktestResult {
  final String symbol;
  final String currency;
  final double initialCapital;
  final double finalValue;
  final double finalReturnPct;
  final double buyHoldFinalValue;
  final double buyHoldReturnPct;
  final List<BacktestTrade> trades;
  final List<BacktestPoint> equityCurve;

  const BacktestResult({
    required this.symbol,
    required this.currency,
    required this.initialCapital,
    required this.finalValue,
    required this.finalReturnPct,
    required this.buyHoldFinalValue,
    required this.buyHoldReturnPct,
    required this.trades,
    required this.equityCurve,
  });

  factory BacktestResult.fromJson(Map<String, dynamic> json) => BacktestResult(
        symbol: json['symbol'] as String,
        currency: json['currency'] as String? ?? '',
        initialCapital: (json['initialCapital'] as num).toDouble(),
        finalValue: (json['finalValue'] as num).toDouble(),
        finalReturnPct: (json['finalReturnPct'] as num).toDouble(),
        buyHoldFinalValue: (json['buyHoldFinalValue'] as num).toDouble(),
        buyHoldReturnPct: (json['buyHoldReturnPct'] as num).toDouble(),
        trades: (json['trades'] as List)
            .cast<Map<String, dynamic>>()
            .map(BacktestTrade.fromJson)
            .toList(),
        equityCurve: (json['equityCurve'] as List)
            .cast<Map<String, dynamic>>()
            .map(BacktestPoint.fromJson)
            .toList(),
      );
}
