/// Bir hareketli ortalama/gösterge satırı için 3 durumlu sinyal (bkz.
/// proxy_server/lib/technical_analysis.dart — backend'deki `Signal` enum'ı
/// ile birebir aynı JSON string değerleri).
enum Signal {
  buy,
  sell,
  neutral;

  static Signal? fromJson(String? value) => switch (value) {
        'buy' => Signal.buy,
        'sell' => Signal.sell,
        'neutral' => Signal.neutral,
        _ => null,
      };
}

/// Özet kutuları için 5 kademeli sinyal (Investing.com'un "Güçlü Al..Güçlü
/// Sat" ölçeği).
enum SummarySignal {
  strongBuy,
  buy,
  neutral,
  sell,
  strongSell;

  static SummarySignal fromJson(String? value) => switch (value) {
        'strongBuy' => SummarySignal.strongBuy,
        'buy' => SummarySignal.buy,
        'sell' => SummarySignal.sell,
        'strongSell' => SummarySignal.strongSell,
        _ => SummarySignal.neutral,
      };

  /// 0-100 arası bir puanı 5 kademeli özete çevirir — proxy_server/lib/
  /// technical_analysis.dart'taki `summarySignalForScore` ile aynı eşikler
  /// (bkz. o dosyanın doc yorumu). Puan Sıralaması listesi (bkz.
  /// widgets/score_ranking_section.dart) sadece renkle değil bu metinsel
  /// etiketle de kademeyi gösterir — renk-körü erişilebilirliği için.
  static SummarySignal forScore(int score) {
    final ratio = score / 100;
    if (ratio >= 0.8) return SummarySignal.strongBuy;
    if (ratio >= 0.6) return SummarySignal.buy;
    if (ratio > 0.4) return SummarySignal.neutral;
    if (ratio > 0.2) return SummarySignal.sell;
    return SummarySignal.strongSell;
  }

  String get label => switch (this) {
        SummarySignal.strongBuy => 'Güçlü Al',
        SummarySignal.buy => 'Al',
        SummarySignal.neutral => 'Nötr',
        SummarySignal.sell => 'Sat',
        SummarySignal.strongSell => 'Güçlü Sat',
      };
}

extension SignalLabel on Signal {
  String get label => switch (this) {
        Signal.buy => 'Al',
        Signal.sell => 'Sat',
        Signal.neutral => 'Nötr',
      };
}

class PivotPoints {
  final double r3, r2, r1, pivot, s1, s2, s3;
  const PivotPoints({
    required this.r3,
    required this.r2,
    required this.r1,
    required this.pivot,
    required this.s1,
    required this.s2,
    required this.s3,
  });

  factory PivotPoints.fromJson(Map<String, dynamic> json) => PivotPoints(
        r3: (json['r3'] as num).toDouble(),
        r2: (json['r2'] as num).toDouble(),
        r1: (json['r1'] as num).toDouble(),
        pivot: (json['pivot'] as num).toDouble(),
        s1: (json['s1'] as num).toDouble(),
        s2: (json['s2'] as num).toDouble(),
        s3: (json['s3'] as num).toDouble(),
      );
}

class MovingAverageRow {
  final int period;
  final double? sma;
  final Signal? smaSignal;
  final double? ema;
  final Signal? emaSignal;
  const MovingAverageRow({
    required this.period,
    this.sma,
    this.smaSignal,
    this.ema,
    this.emaSignal,
  });

  factory MovingAverageRow.fromJson(Map<String, dynamic> json) => MovingAverageRow(
        period: json['period'] as int,
        sma: (json['sma'] as num?)?.toDouble(),
        smaSignal: Signal.fromJson(json['smaSignal'] as String?),
        ema: (json['ema'] as num?)?.toDouble(),
        emaSignal: Signal.fromJson(json['emaSignal'] as String?),
      );
}

class IndicatorRow {
  final String name;
  final double value;
  final Signal signal;
  const IndicatorRow({required this.name, required this.value, required this.signal});

  factory IndicatorRow.fromJson(Map<String, dynamic> json) => IndicatorRow(
        name: json['name'] as String,
        value: (json['value'] as num).toDouble(),
        signal: Signal.fromJson(json['signal'] as String?) ?? Signal.neutral,
      );
}

class TechnicalSummary {
  final SummarySignal movingAverages;
  final SummarySignal indicators;
  final SummarySignal overall;
  /// Hareketli ortalamalar + göstergelerin birleşik oy sayımından 0-100
  /// arası "alım puanı" — "Yorum (X/100)" butonundaki X.
  final int score;
  const TechnicalSummary({
    required this.movingAverages,
    required this.indicators,
    required this.overall,
    required this.score,
  });

  factory TechnicalSummary.fromJson(Map<String, dynamic> json) => TechnicalSummary(
        movingAverages: SummarySignal.fromJson(json['movingAverages'] as String?),
        indicators: SummarySignal.fromJson(json['indicators'] as String?),
        overall: SummarySignal.fromJson(json['overall'] as String?),
        score: (json['score'] as num?)?.toInt() ?? 50,
      );
}

class TechnicalAnalysisResult {
  final String symbol;
  final String currency;
  final double lastClose;
  final DateTime asOf;
  final PivotPoints? pivotPoints;
  final List<MovingAverageRow> movingAverages;
  final List<IndicatorRow> indicators;
  final TechnicalSummary summary;

  const TechnicalAnalysisResult({
    required this.symbol,
    required this.currency,
    required this.lastClose,
    required this.asOf,
    required this.pivotPoints,
    required this.movingAverages,
    required this.indicators,
    required this.summary,
  });

  factory TechnicalAnalysisResult.fromJson(Map<String, dynamic> json) {
    final pivotJson = json['pivotPoints'] as Map<String, dynamic>?;
    return TechnicalAnalysisResult(
      symbol: json['symbol'] as String,
      currency: json['currency'] as String? ?? '',
      lastClose: (json['lastClose'] as num).toDouble(),
      asOf: DateTime.parse(json['asOf'] as String),
      pivotPoints: pivotJson == null ? null : PivotPoints.fromJson(pivotJson),
      movingAverages: (json['movingAverages'] as List)
          .cast<Map<String, dynamic>>()
          .map(MovingAverageRow.fromJson)
          .toList(),
      indicators: (json['indicators'] as List)
          .cast<Map<String, dynamic>>()
          .map(IndicatorRow.fromJson)
          .toList(),
      summary: TechnicalSummary.fromJson(json['summary'] as Map<String, dynamic>),
    );
  }
}
