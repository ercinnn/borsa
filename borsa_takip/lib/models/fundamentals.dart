/// `/api/fundamentals/overview` yanıtı — bkz.
/// proxy_server/lib/yahoo_fundamentals.dart StockOverview.
class StockOverview {
  final String symbol;
  final String companyName;
  final String? sector;
  final String? country;
  final String currency;
  final double lastPrice;
  final double? marketCap;
  final double? peRatio;
  final double? pbRatio;
  final double? dividendYield;
  final DateTime updatedAt;
  /// true ise: Yahoo'dan canlı güncelleme başarısız oldu (ör. Render'ın
  /// paylaşımlı IP'si crumb endpoint'inde geçici olarak engellendi) ve bu,
  /// önceden senkronlanmış EN SON bilinen veri — bkz.
  /// proxy_server/lib/fundamentals_cache.dart'ın stale-fallback davranışı.
  final bool stale;

  const StockOverview({
    required this.symbol,
    required this.companyName,
    this.sector,
    this.country,
    required this.currency,
    required this.lastPrice,
    this.marketCap,
    this.peRatio,
    this.pbRatio,
    this.dividendYield,
    required this.updatedAt,
    this.stale = false,
  });

  factory StockOverview.fromJson(Map<String, dynamic> json) => StockOverview(
        symbol: json['symbol'] as String,
        companyName: json['companyName'] as String,
        sector: json['sector'] as String?,
        country: json['country'] as String?,
        currency: json['currency'] as String? ?? '',
        lastPrice: (json['lastPrice'] as num).toDouble(),
        marketCap: (json['marketCap'] as num?)?.toDouble(),
        peRatio: (json['peRatio'] as num?)?.toDouble(),
        pbRatio: (json['pbRatio'] as num?)?.toDouble(),
        dividendYield: (json['dividendYield'] as num?)?.toDouble(),
        updatedAt: DateTime.parse(json['updatedAt'] as String),
        stale: json['stale'] as bool? ?? false,
      );
}

class DcfAssumptions {
  final double growthRate;
  final double discountRate;
  final double terminalGrowthRate;
  final int projectionYears;

  const DcfAssumptions({
    required this.growthRate,
    required this.discountRate,
    required this.terminalGrowthRate,
    required this.projectionYears,
  });

  factory DcfAssumptions.fromJson(Map<String, dynamic> json) => DcfAssumptions(
        growthRate: (json['growthRate'] as num).toDouble(),
        discountRate: (json['discountRate'] as num).toDouble(),
        terminalGrowthRate: (json['terminalGrowthRate'] as num).toDouble(),
        projectionYears: json['projectionYears'] as int,
      );
}

/// `/api/fundamentals/fair-value` yanıtı — bkz.
/// proxy_server/lib/fundamental_analysis.dart FairValueResult.
/// BASİTLEŞTİRİLMİŞ DCF VARSAYIMLARI kullanır (bkz. [assumptions] ve
/// backend'deki computeFairValueDCF doc yorumu) — yatırım tavsiyesi değildir.
/// [error] doluysa (ör. yetersiz veri, negatif FCF) [fairValuePerShare] null'dur.
class FairValueResult {
  final String symbol;
  final double? fairValuePerShare;
  final double? upsidePct;
  final String? error;
  final DcfAssumptions assumptions;
  final DateTime computedAt;
  /// bkz. StockOverview.stale doc yorumu.
  final bool stale;

  const FairValueResult({
    required this.symbol,
    this.fairValuePerShare,
    this.upsidePct,
    this.error,
    required this.assumptions,
    required this.computedAt,
    this.stale = false,
  });

  factory FairValueResult.fromJson(Map<String, dynamic> json) => FairValueResult(
        symbol: json['symbol'] as String,
        fairValuePerShare: (json['fairValuePerShare'] as num?)?.toDouble(),
        upsidePct: (json['upsidePct'] as num?)?.toDouble(),
        error: json['error'] as String?,
        assumptions: DcfAssumptions.fromJson(json['assumptions'] as Map<String, dynamic>),
        computedAt: DateTime.parse(json['computedAt'] as String),
        stale: json['stale'] as bool? ?? false,
      );
}

class PiotroskiCriterion {
  final String name;
  /// null: bu sembol için veri yetersizliğinden hesaplanamadı (bkz. backend
  /// computePiotroskiFScore doc yorumu — banka gibi finans sektörü
  /// şirketlerinde bazı kriterler hiç hesaplanamaz).
  final bool? passed;

  const PiotroskiCriterion({required this.name, required this.passed});

  factory PiotroskiCriterion.fromJson(Map<String, dynamic> json) => PiotroskiCriterion(
        name: json['name'] as String,
        passed: json['passed'] as bool?,
      );
}

/// `/api/fundamentals/health-score` yanıtı — bkz.
/// proxy_server/lib/fundamental_analysis.dart computeAltmanZScore/
/// computePiotroskiFScore. [altmanError] doluysa (tipik olarak banka/finans
/// sektörü) [altmanZScore]/[altmanZone] null'dur. [piotroskiMaxScore], 9
/// değil bu sembol için gerçekten hesaplanabilen kriter sayısıdır.
class HealthScoreResult {
  final String symbol;
  final double? altmanZScore;
  final String? altmanZone; // 'safe' | 'grey' | 'distress'
  final String? altmanError;
  final int piotroskiScore;
  final int piotroskiMaxScore;
  final List<PiotroskiCriterion> piotroskiCriteria;
  final DateTime computedAt;
  /// bkz. StockOverview.stale doc yorumu.
  final bool stale;

  const HealthScoreResult({
    required this.symbol,
    this.altmanZScore,
    this.altmanZone,
    this.altmanError,
    required this.piotroskiScore,
    required this.piotroskiMaxScore,
    required this.piotroskiCriteria,
    required this.computedAt,
    this.stale = false,
  });

  factory HealthScoreResult.fromJson(Map<String, dynamic> json) => HealthScoreResult(
        symbol: json['symbol'] as String,
        altmanZScore: (json['altmanZScore'] as num?)?.toDouble(),
        altmanZone: json['altmanZone'] as String?,
        altmanError: json['altmanError'] as String?,
        piotroskiScore: json['piotroskiScore'] as int,
        piotroskiMaxScore: json['piotroskiMaxScore'] as int,
        piotroskiCriteria: (json['piotroskiCriteria'] as List)
            .cast<Map<String, dynamic>>()
            .map(PiotroskiCriterion.fromJson)
            .toList(),
        computedAt: DateTime.parse(json['computedAt'] as String),
        stale: json['stale'] as bool? ?? false,
      );
}

/// `/api/fundamentals/protips` yanıtı — kural bazlı (LLM yok) Türkçe özet
/// notlar, bkz. proxy_server/lib/fundamental_analysis.dart generateProTips.
class ProTipsResult {
  final String symbol;
  final List<String> tips;
  final DateTime computedAt;
  /// bkz. StockOverview.stale doc yorumu.
  final bool stale;

  const ProTipsResult({
    required this.symbol,
    required this.tips,
    required this.computedAt,
    this.stale = false,
  });

  factory ProTipsResult.fromJson(Map<String, dynamic> json) => ProTipsResult(
        symbol: json['symbol'] as String,
        tips: (json['tips'] as List).cast<String>(),
        computedAt: DateTime.parse(json['computedAt'] as String),
        stale: json['stale'] as bool? ?? false,
      );
}
