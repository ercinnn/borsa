class DividendEvent {
  final DateTime date;
  final double amount;

  const DividendEvent({required this.date, required this.amount});

  factory DividendEvent.fromJson(Map<String, dynamic> json) => DividendEvent(
        date: DateTime.parse(json['date'] as String),
        amount: (json['amount'] as num).toDouble(),
      );
}

/// `/api/dividends` yanıtı — bkz. proxy_server/lib/yahoo_client.dart
/// fetchDividends. [dividends] yeniden eskiye sıralıdır, son 15 yılla
/// sınırlıdır (bkz. fetchDividends doc yorumu).
class DividendHistory {
  final String symbol;
  final String currency;
  final List<DividendEvent> dividends;
  final double totalPerShare;

  const DividendHistory({
    required this.symbol,
    required this.currency,
    required this.dividends,
    required this.totalPerShare,
  });

  factory DividendHistory.fromJson(Map<String, dynamic> json) => DividendHistory(
        symbol: json['symbol'] as String,
        currency: json['currency'] as String? ?? '',
        dividends: (json['dividends'] as List)
            .cast<Map<String, dynamic>>()
            .map(DividendEvent.fromJson)
            .toList(),
        totalPerShare: (json['totalPerShare'] as num).toDouble(),
      );
}
