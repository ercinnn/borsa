class PortfolioHoldingResult {
  final String symbol;
  final double quantity;
  final double costBasis;
  final String currency;
  final double? currentPrice;
  final double? currentValue;
  final double? costValue;
  final double? pnl;
  final double? pnlPct;
  final double? valueInTry;
  /// Son 15 yılda ödenen hisse başı temettülerin toplamı, holding'in kendi
  /// para biriminde (bkz. proxy_server/lib/yahoo_client.dart fetchDividends).
  final double? totalDividendPerShare;
  /// quantity × totalDividendPerShare. BASİTLEŞTİRİLMİŞ BİR TAHMİNDİR:
  /// pozisyonu ne zaman satın aldığın hesaba katılmaz (bkz.
  /// proxy_server/lib/portfolio_summary.dart doc yorumu).
  final double? estimatedDividendIncome;
  /// estimatedDividendIncome'ın TRY karşılığı — valueInTry ile aynı kural.
  final double? estimatedDividendIncomeTry;
  final String? error;

  const PortfolioHoldingResult({
    required this.symbol,
    required this.quantity,
    required this.costBasis,
    required this.currency,
    this.currentPrice,
    this.currentValue,
    this.costValue,
    this.pnl,
    this.pnlPct,
    this.valueInTry,
    this.totalDividendPerShare,
    this.estimatedDividendIncome,
    this.estimatedDividendIncomeTry,
    this.error,
  });

  factory PortfolioHoldingResult.fromJson(Map<String, dynamic> json) => PortfolioHoldingResult(
        symbol: json['symbol'] as String,
        quantity: (json['quantity'] as num).toDouble(),
        costBasis: (json['costBasis'] as num).toDouble(),
        currency: json['currency'] as String? ?? '',
        currentPrice: (json['currentPrice'] as num?)?.toDouble(),
        currentValue: (json['currentValue'] as num?)?.toDouble(),
        costValue: (json['costValue'] as num?)?.toDouble(),
        pnl: (json['pnl'] as num?)?.toDouble(),
        pnlPct: (json['pnlPct'] as num?)?.toDouble(),
        valueInTry: (json['valueInTry'] as num?)?.toDouble(),
        totalDividendPerShare: (json['totalDividendPerShare'] as num?)?.toDouble(),
        estimatedDividendIncome: (json['estimatedDividendIncome'] as num?)?.toDouble(),
        estimatedDividendIncomeTry:
            (json['estimatedDividendIncomeTry'] as num?)?.toDouble(),
        error: json['error'] as String?,
      );
}

/// `/api/portfolio` yanıtı — bkz. proxy_server/lib/portfolio_summary.dart.
/// Toplamlar her zaman TRY cinsindendir: BIST pozisyonları zaten TRY, ABD
/// hisseleri/kripto (USD) `usdTryRate` ile çevrilir. [unconvertedCount],
/// TRY/USD dışında bir para biriminde olup toplama dahil edilemeyen pozisyon
/// sayısıdır (pratikte neredeyse hiç olmaz, ama sıfır değilse kullanıcıya
/// belirtilir).
class PortfolioSummary {
  final List<PortfolioHoldingResult> holdings;
  final double totalValueTry;
  final double totalCostTry;
  final double totalPnlTry;
  final double? totalPnlPct;
  final double? usdTryRate;
  final int unconvertedCount;
  /// Tüm holding'lerin estimatedDividendIncomeTry toplamı.
  final double totalDividendIncomeTry;

  const PortfolioSummary({
    required this.holdings,
    required this.totalValueTry,
    required this.totalCostTry,
    required this.totalPnlTry,
    required this.totalPnlPct,
    required this.usdTryRate,
    required this.unconvertedCount,
    required this.totalDividendIncomeTry,
  });

  factory PortfolioSummary.fromJson(Map<String, dynamic> json) => PortfolioSummary(
        holdings: (json['holdings'] as List)
            .cast<Map<String, dynamic>>()
            .map(PortfolioHoldingResult.fromJson)
            .toList(),
        totalValueTry: (json['totalValueTry'] as num).toDouble(),
        totalCostTry: (json['totalCostTry'] as num).toDouble(),
        totalPnlTry: (json['totalPnlTry'] as num).toDouble(),
        totalPnlPct: (json['totalPnlPct'] as num?)?.toDouble(),
        usdTryRate: (json['usdTryRate'] as num?)?.toDouble(),
        unconvertedCount: json['unconvertedCount'] as int? ?? 0,
        totalDividendIncomeTry: (json['totalDividendIncomeTry'] as num?)?.toDouble() ?? 0,
      );
}
