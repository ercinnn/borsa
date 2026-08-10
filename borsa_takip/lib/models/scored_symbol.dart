class ScoredSymbol {
  final String symbol;
  final int score;
  final String currency;
  final double lastClose;
  final DateTime asOf;

  const ScoredSymbol({
    required this.symbol,
    required this.score,
    required this.currency,
    required this.lastClose,
    required this.asOf,
  });

  factory ScoredSymbol.fromJson(Map<String, dynamic> json) => ScoredSymbol(
        symbol: json['symbol'] as String,
        score: (json['score'] as num).toInt(),
        currency: json['currency'] as String? ?? '',
        lastClose: (json['lastClose'] as num).toDouble(),
        asOf: DateTime.parse(json['asOf'] as String),
      );
}

/// `/api/technical-scores` yanıtı — bkz. proxy_server/bin/server.dart
/// `_technicalScoresHandler`. [pendingCount], filtrelenen sembollerden kaçının
/// puanının arka planda henüz hesaplanmadığını (bkz. TechnicalScoreCache);
/// [refreshing] o an bir arka plan taramasının sürüp sürmediğini gösterir.
class ScoredSymbolPage {
  final List<ScoredSymbol> items;
  final int page;
  final int totalPages;
  final int total;
  final int pendingCount;
  final bool refreshing;

  const ScoredSymbolPage({
    required this.items,
    required this.page,
    required this.totalPages,
    required this.total,
    required this.pendingCount,
    required this.refreshing,
  });

  factory ScoredSymbolPage.fromJson(Map<String, dynamic> json) => ScoredSymbolPage(
        items: (json['items'] as List)
            .cast<Map<String, dynamic>>()
            .map(ScoredSymbol.fromJson)
            .toList(),
        page: json['page'] as int,
        totalPages: json['totalPages'] as int,
        total: json['total'] as int,
        pendingCount: json['pendingCount'] as int? ?? 0,
        refreshing: json['refreshing'] as bool? ?? false,
      );
}
