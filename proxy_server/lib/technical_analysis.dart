import 'dart:math';

import 'yahoo_client.dart';

/// Tek bir gösterge/hareketli-ortalama satırı için 3 durumlu sinyal.
enum Signal { buy, sell, neutral }

extension SignalJson on Signal {
  String get json => switch (this) {
        Signal.buy => 'buy',
        Signal.sell => 'sell',
        Signal.neutral => 'neutral',
      };
}

/// Özet kutuları (Hareketli Ortalamalar / Göstergeler / Genel) için 5 kademeli
/// sinyal — Investing.com'un "Güçlü Al..Güçlü Sat" gösterimiyle aynı ölçek.
enum SummarySignal { strongBuy, buy, neutral, sell, strongSell }

extension SummarySignalJson on SummarySignal {
  String get json => switch (this) {
        SummarySignal.strongBuy => 'strongBuy',
        SummarySignal.buy => 'buy',
        SummarySignal.neutral => 'neutral',
        SummarySignal.sell => 'sell',
        SummarySignal.strongSell => 'strongSell',
      };

  /// Bildirim mesajları için (bkz. technical_score_cache.dart) — frontend'in
  /// kendi `SummarySignal.label`'ıyla aynı Türkçe etiketler.
  String get turkishLabel => switch (this) {
        SummarySignal.strongBuy => 'Güçlü Al',
        SummarySignal.buy => 'Al',
        SummarySignal.neutral => 'Nötr',
        SummarySignal.sell => 'Sat',
        SummarySignal.strongSell => 'Güçlü Sat',
      };
}

/// [buy]/[sell] sayısının [total]'a oranına göre 5 kademeli özet üretir.
/// Investing.com'un tam algoritması yayınlanmadığından bu, yaygın teknik
/// analiz sitelerinde kullanılan standart bir "oy sayımı" yöntemidir —
/// Investing.com'un birebir aynısı olduğu iddia edilmez.
SummarySignal _summarize(int buy, int sell, int total) =>
    summarySignalForScore(_scoreOf(buy, sell, total));

/// 0-100 arası bir puanı 5 kademeli özete çevirir — [_summarize] ile aynı
/// eşikler, ama doğrudan bir puandan (ör. [TechnicalScoreCache]'te
/// önbelleklenmiş bir önceki/yeni puan karşılaştırması) başlamak için
/// dışa açık.
SummarySignal summarySignalForScore(int score) {
  final ratio = score / 100;
  if (ratio >= 0.8) return SummarySignal.strongBuy;
  if (ratio >= 0.6) return SummarySignal.buy;
  if (ratio > 0.4) return SummarySignal.neutral;
  if (ratio > 0.2) return SummarySignal.sell;
  return SummarySignal.strongSell;
}

/// [buy]/[sell]/[total] oy sayımını 0-100 arası bir "alım puanına" çevirir:
/// 50 tam nötr, 100 tüm sinyaller Al, 0 tüm sinyaller Sat. "Yorum (X/100)"
/// butonundaki X buradan gelir (bkz. bin/server.dart _technicalHandler).
int _scoreOf(int buy, int sell, int total) {
  if (total == 0) return 50;
  final ratio = (buy - sell) / total; // -1..1
  return (50 + 50 * ratio).round().clamp(0, 100);
}

class PivotPoints {
  final double r3, r2, r1, pivot, s1, s2, s3;
  PivotPoints({
    required this.r3,
    required this.r2,
    required this.r1,
    required this.pivot,
    required this.s1,
    required this.s2,
    required this.s3,
  });

  Map<String, dynamic> toJson() => {
        'r3': r3,
        'r2': r2,
        'r1': r1,
        'pivot': pivot,
        's1': s1,
        's2': s2,
        's3': s3,
      };
}

class MovingAverageRow {
  final int period;
  final double? sma;
  final Signal? smaSignal;
  final double? ema;
  final Signal? emaSignal;
  MovingAverageRow({
    required this.period,
    this.sma,
    this.smaSignal,
    this.ema,
    this.emaSignal,
  });

  Map<String, dynamic> toJson() => {
        'period': period,
        'sma': sma,
        'smaSignal': smaSignal?.json,
        'ema': ema,
        'emaSignal': emaSignal?.json,
      };
}

class IndicatorRow {
  final String name;
  final double value;
  final Signal signal;
  IndicatorRow(this.name, this.value, this.signal);

  Map<String, dynamic> toJson() =>
      {'name': name, 'value': value, 'signal': signal.json};
}

class TechnicalSummary {
  final SummarySignal movingAverages;
  final SummarySignal indicators;
  final SummarySignal overall;
  /// Hareketli ortalamalar + göstergelerin birleşik oy sayımından 0-100
  /// arası "alım puanı" (bkz. `_scoreOf`) — "Yorum (X/100)" butonundaki X.
  final int score;
  TechnicalSummary({
    required this.movingAverages,
    required this.indicators,
    required this.overall,
    required this.score,
  });

  Map<String, dynamic> toJson() => {
        'movingAverages': movingAverages.json,
        'indicators': indicators.json,
        'overall': overall.json,
        'score': score,
      };
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

  TechnicalAnalysisResult({
    required this.symbol,
    required this.currency,
    required this.lastClose,
    required this.asOf,
    required this.pivotPoints,
    required this.movingAverages,
    required this.indicators,
    required this.summary,
  });

  Map<String, dynamic> toJson() => {
        'symbol': symbol,
        'currency': currency,
        'lastClose': lastClose,
        'asOf': asOf.toIso8601String(),
        'pivotPoints': pivotPoints?.toJson(),
        'movingAverages': movingAverages.map((m) => m.toJson()).toList(),
        'indicators': indicators.map((i) => i.toJson()).toList(),
        'summary': summary.toJson(),
      };
}

class InsufficientDataException implements Exception {
  final String message;
  InsufficientDataException(this.message);
  @override
  String toString() => message;
}

const _maPeriods = [5, 10, 20, 50, 100, 200];

/// Investing.com'un "Teknik Özet" sayfasındaki Pivot Noktaları, Hareketli
/// Ortalamalar ve Teknik İndikatörler bölümlerinin (RSI, STOCH, STOCHRSI,
/// MACD, ATR, ADX, CCI, Highs/Lows, UO, ROC, Williams %R, Bull/Bear Power)
/// standart formüllerle yeniden hesaplanmış hali. Investing.com'un tam algo-
/// ritması/eşik değerleri yayınlanmadığından burada literatürdeki en yaygın
/// eşikler kullanıldı (bkz. her göstergenin yanındaki yorum); bu nedenle
/// sonuçlar Investing.com'la genel eğilimde örtüşür ama birebir aynı
/// olmayabilir. En az 210 günlük mum gerektirir (MA200 için); daha kısa
/// geçmişi olan (ör. yeni listelenmiş) semboller için eksik satırlar
/// (sma/ema/signal `null`) döner ve özet hesaplaması yalnızca hesaplanabilen
/// satırları sayar.
TechnicalAnalysisResult computeTechnicalAnalysis(
  String symbol,
  String currency,
  List<RawCandle> candles,
) {
  if (candles.length < 35) {
    throw InsufficientDataException(
      '$symbol için teknik analiz yapmaya yetecek kadar geçmiş veri yok '
      '(en az ~35 günlük mum gerekli, ${candles.length} bulundu).',
    );
  }

  final highs = candles.map((c) => c.high.toDouble()).toList();
  final lows = candles.map((c) => c.low.toDouble()).toList();
  final closes = candles.map((c) => c.close.toDouble()).toList();
  final n = closes.length;
  final lastClose = closes[n - 1];

  // --- Pivot Noktaları (klasik formül, bir önceki tam günün H/L/C'sinden) ---
  PivotPoints? pivotPoints;
  if (candles.length >= 2) {
    final prev = candles[n - 2];
    final ph = prev.high.toDouble(), pl = prev.low.toDouble(), pc = prev.close.toDouble();
    final pp = (ph + pl + pc) / 3;
    pivotPoints = PivotPoints(
      pivot: pp,
      r1: 2 * pp - pl,
      s1: 2 * pp - ph,
      r2: pp + (ph - pl),
      s2: pp - (ph - pl),
      r3: ph + 2 * (pp - pl),
      s3: pl - 2 * (ph - pp),
    );
  }

  // --- Hareketli Ortalamalar (Basit + Üstel), sinyal: kapanış > MA => Al ---
  final movingAverages = <MovingAverageRow>[];
  for (final period in _maPeriods) {
    double? sma;
    Signal? smaSignal;
    double? ema;
    Signal? emaSignal;
    if (n >= period) {
      sma = _sma(closes, period, n);
      smaSignal = _trendSignal(lastClose - sma);
      final emaSeries = _emaSeries(closes, period);
      ema = emaSeries.last;
      emaSignal = _trendSignal(lastClose - ema);
    }
    movingAverages.add(MovingAverageRow(
      period: period,
      sma: sma,
      smaSignal: smaSignal,
      ema: ema,
      emaSignal: emaSignal,
    ));
  }

  final indicators = <IndicatorRow>[];

  // --- RSI(14): <30 aşırı satım (Al), >70 aşırı alım (Sat) ---
  final rsiSeries = _rsiSeries(closes, 14);
  final rsi = rsiSeries[n - 1];
  if (rsi != null) {
    indicators.add(IndicatorRow('RSI(14)', rsi,
        rsi < 30 ? Signal.buy : (rsi > 70 ? Signal.sell : Signal.neutral)));
  }

  // --- STOCH(9,6): %K(9) periyodu, %D(6) ile yumuşatılmış; <20 Al, >80 Sat ---
  if (n >= 14) {
    final kSeries = _stochKSeries(highs, lows, closes, 9, n - 6, n);
    final k = kSeries.last;
    final d = kSeries.reduce((a, b) => a + b) / kSeries.length;
    indicators.add(IndicatorRow('STOCH(9,6) %K', k,
        k < 20 ? Signal.buy : (k > 80 ? Signal.sell : Signal.neutral)));
    indicators.add(IndicatorRow('STOCH(9,6) %D', d,
        d < 20 ? Signal.buy : (d > 80 ? Signal.sell : Signal.neutral)));
  }

  // --- STOCHRSI(14): RSI(14) serisinin kendi üzerinde stokastik formülü ---
  final validRsi = rsiSeries.whereType<double>().toList();
  if (validRsi.length >= 14) {
    final last14 = validRsi.sublist(validRsi.length - 14);
    final rsiMin = last14.reduce(min);
    final rsiMax = last14.reduce(max);
    final stochRsi =
        rsiMax == rsiMin ? 50.0 : (last14.last - rsiMin) / (rsiMax - rsiMin) * 100;
    indicators.add(IndicatorRow(
        'STOCHRSI(14)',
        stochRsi,
        stochRsi < 20 ? Signal.buy : (stochRsi > 80 ? Signal.sell : Signal.neutral)));
  }

  // --- MACD(12,26), sinyal çizgisi EMA(9): MACD > sinyal => Al ---
  if (n >= 35) {
    final ema12 = _emaSeries(closes, 12);
    final ema26 = _emaSeries(closes, 26);
    final macdSeries = <double>[
      for (var i = 25; i < n; i++) ema12[i] - ema26[i],
    ];
    final signalSeries = _emaSeriesGeneric(macdSeries, 9);
    final macd = macdSeries.last;
    final macdSignalLine = signalSeries.last;
    indicators.add(IndicatorRow(
        'MACD(12,26)', macd, macd > macdSignalLine ? Signal.buy : Signal.sell));
  }

  // --- ATR(14): oynaklık ölçüsü, yön belirtmez — bilgi amaçlı gösterilir ---
  final trueRanges = _trueRanges(highs, lows, closes);
  if (trueRanges.length >= 14) {
    final atr = _wilderSmoothFinal(trueRanges, 14);
    indicators.add(IndicatorRow('ATR(14)', atr, Signal.neutral));
  }

  // --- ADX(14) + DI+/DI-: ADX>25 iken DI+ > DI- => Al, DI- > DI+ => Sat ---
  if (n >= 30) {
    final plusDM = <double>[], minusDM = <double>[];
    for (var i = 1; i < n; i++) {
      final upMove = highs[i] - highs[i - 1];
      final downMove = lows[i - 1] - lows[i];
      plusDM.add(upMove > downMove && upMove > 0 ? upMove : 0);
      minusDM.add(downMove > upMove && downMove > 0 ? downMove : 0);
    }
    if (plusDM.length >= 28) {
      final smoothedPlusDM = _wilderSmoothSeries(plusDM, 14);
      final smoothedMinusDM = _wilderSmoothSeries(minusDM, 14);
      final smoothedTr = _wilderSmoothSeries(trueRanges, 14);
      final len = [smoothedPlusDM.length, smoothedMinusDM.length, smoothedTr.length]
          .reduce(min);
      final plusDi = <double>[], minusDi = <double>[];
      for (var i = 0; i < len; i++) {
        final tr = smoothedTr[i];
        plusDi.add(tr == 0 ? 0 : 100 * smoothedPlusDM[i] / tr);
        minusDi.add(tr == 0 ? 0 : 100 * smoothedMinusDM[i] / tr);
      }
      final dx = <double>[
        for (var i = 0; i < len; i++)
          (plusDi[i] + minusDi[i]) == 0
              ? 0.0
              : 100 * (plusDi[i] - minusDi[i]).abs() / (plusDi[i] + minusDi[i]),
      ];
      if (dx.length >= 14) {
        final adx = _wilderSmoothFinal(dx, 14);
        final finalPlusDi = plusDi.last;
        final finalMinusDi = minusDi.last;
        final signal = adx <= 25
            ? Signal.neutral
            : (finalPlusDi > finalMinusDi ? Signal.buy : Signal.sell);
        indicators.add(IndicatorRow('ADX(14)', adx, signal));
      }
    }
  }

  // --- CCI(14): >100 Al (yükseliş kırılımı), <-100 Sat ---
  if (n >= 14) {
    final typicalPrices = [
      for (var i = 0; i < n; i++) (highs[i] + lows[i] + closes[i]) / 3,
    ];
    final tpSma = _sma(typicalPrices, 14, n);
    var meanDeviation = 0.0;
    for (var i = n - 14; i < n; i++) {
      meanDeviation += (typicalPrices[i] - tpSma).abs();
    }
    meanDeviation /= 14;
    final cci = meanDeviation == 0
        ? 0.0
        : (typicalPrices[n - 1] - tpSma) / (0.015 * meanDeviation);
    indicators.add(IndicatorRow('CCI(14)', cci,
        cci > 100 ? Signal.buy : (cci < -100 ? Signal.sell : Signal.neutral)));
  }

  // --- Highs/Lows(14): son 14 barda yükselen tepe/dip ortalaması ---
  if (n >= 15) {
    var sum = 0.0;
    for (var i = n - 14; i < n; i++) {
      final dHigh = highs[i] - highs[i - 1];
      final dLow = lows[i] - lows[i - 1];
      sum += (dHigh > 0 ? dHigh : 0) + (dLow < 0 ? dLow : 0);
    }
    final highsLows = sum / 14;
    indicators.add(IndicatorRow(
        'Highs/Lows(14)',
        highsLows,
        highsLows > 0 ? Signal.buy : (highsLows < 0 ? Signal.sell : Signal.neutral)));
  }

  // --- UO (Ultimate Oscillator, 7/14/28): >70 Sat, <30 Al ---
  if (n >= 29) {
    double avgRatio(int period) {
      var bpSum = 0.0, trSum = 0.0;
      for (var i = n - period; i < n; i++) {
        final priorClose = closes[i - 1];
        final bp = closes[i] - min(lows[i], priorClose);
        final tr = max(highs[i], priorClose) - min(lows[i], priorClose);
        bpSum += bp;
        trSum += tr;
      }
      return trSum == 0 ? 0 : bpSum / trSum;
    }

    final uo = 100 * (4 * avgRatio(7) + 2 * avgRatio(14) + avgRatio(28)) / 7;
    indicators.add(IndicatorRow(
        'UO', uo, uo > 70 ? Signal.sell : (uo < 30 ? Signal.buy : Signal.neutral)));
  }

  // --- ROC(12): pozitif => Al, negatif => Sat ---
  if (n >= 13) {
    final roc = (closes[n - 1] - closes[n - 13]) / closes[n - 13] * 100;
    indicators.add(IndicatorRow(
        'ROC(12)', roc, roc > 0 ? Signal.buy : (roc < 0 ? Signal.sell : Signal.neutral)));
  }

  // --- Williams %R(14): <-80 Al (aşırı satım), >-20 Sat (aşırı alım) ---
  if (n >= 14) {
    final hh14 = _highestHigh(highs, 14, n);
    final ll14 = _lowestLow(lows, 14, n);
    final williamsR =
        hh14 == ll14 ? -50.0 : (hh14 - closes[n - 1]) / (hh14 - ll14) * -100;
    indicators.add(IndicatorRow(
        'Williams %R(14)',
        williamsR,
        williamsR < -80 ? Signal.buy : (williamsR > -20 ? Signal.sell : Signal.neutral)));
  }

  // --- Bull/Bear Power(13) (Elder): net (Bull+Bear) > 0 => Al ---
  if (n >= 13) {
    final ema13 = _emaSeries(closes, 13);
    final bullPower = highs[n - 1] - ema13.last;
    final bearPower = lows[n - 1] - ema13.last;
    final net = bullPower + bearPower;
    indicators.add(IndicatorRow('Bull/Bear Power(13)', net,
        net > 0 ? Signal.buy : (net < 0 ? Signal.sell : Signal.neutral)));
  }

  // --- Özetler ---
  var maBuy = 0, maSell = 0, maTotal = 0;
  for (final row in movingAverages) {
    if (row.smaSignal != null) {
      maTotal++;
      if (row.smaSignal == Signal.buy) maBuy++;
      if (row.smaSignal == Signal.sell) maSell++;
    }
    if (row.emaSignal != null) {
      maTotal++;
      if (row.emaSignal == Signal.buy) maBuy++;
      if (row.emaSignal == Signal.sell) maSell++;
    }
  }
  var indBuy = 0, indSell = 0, indTotal = 0;
  for (final row in indicators) {
    if (row.name.startsWith('ATR')) continue; // yön belirtmiyor, sayıma girmiyor
    indTotal++;
    if (row.signal == Signal.buy) indBuy++;
    if (row.signal == Signal.sell) indSell++;
  }
  final maSummary = _summarize(maBuy, maSell, maTotal);
  final indSummary = _summarize(indBuy, indSell, indTotal);
  final overallBuy = maBuy + indBuy;
  final overallSell = maSell + indSell;
  final overallTotal = maTotal + indTotal;
  final overallSummary = _summarize(overallBuy, overallSell, overallTotal);

  return TechnicalAnalysisResult(
    symbol: symbol,
    currency: currency,
    lastClose: lastClose,
    asOf: candles.last.date,
    pivotPoints: pivotPoints,
    movingAverages: movingAverages,
    indicators: indicators,
    summary: TechnicalSummary(
      movingAverages: maSummary,
      indicators: indSummary,
      overall: overallSummary,
      score: _scoreOf(overallBuy, overallSell, overallTotal),
    ),
  );
}

Signal _trendSignal(double diff) {
  if (diff > 0) return Signal.buy;
  if (diff < 0) return Signal.sell;
  return Signal.neutral;
}

double _sma(List<double> values, int period, int endIndexExclusive) {
  final start = endIndexExclusive - period;
  var sum = 0.0;
  for (var i = start; i < endIndexExclusive; i++) {
    sum += values[i];
  }
  return sum / period;
}

/// [values]'in tamamı için EMA serisi döner; ilk `period-1` eleman geçerli
/// değildir (SMA ile tohumlanan `period-1` indeksinden itibaren anlamlıdır),
/// ama çağıran taraf yalnızca son elemanla (`.last`) ilgilendiğinden bu proje
/// kapsamında sorun oluşturmuyor.
List<double> _emaSeries(List<double> values, int period) =>
    _emaSeriesGeneric(values, period);

List<double> _emaSeriesGeneric(List<double> values, int period) {
  final k = 2 / (period + 1);
  final ema = List<double>.filled(values.length, values.isEmpty ? 0 : values[0]);
  var sum = 0.0;
  for (var i = 0; i < period && i < values.length; i++) {
    sum += values[i];
  }
  if (values.length < period) return ema;
  ema[period - 1] = sum / period;
  for (var i = period; i < values.length; i++) {
    ema[i] = values[i] * k + ema[i - 1] * (1 - k);
  }
  return ema;
}

/// [rsiSeries]/[macdSeriesFor]'ın kullandığı MACD sonucu: her liste
/// [closes] ile aynı uzunlukta, henüz hesaplanamayan indeksler `null`.
typedef MacdSeries = ({List<double?> macd, List<double?> signal, List<double?> histogram});

/// `/api/candles`'ın "TradingView tarzı" RSI paneli için tam RSI(14) zaman
/// serisi (bkz. bin/server.dart `_candlesHandler`, `indicators=rsi` param).
/// Teknik sekmesindeki [computeTechnicalAnalysis] yalnızca SON değerle
/// ilgilenir; bu, mum grafiğinin altına çizilecek tüm geçmişi döner.
List<double?> rsiSeries(List<double> closes, {int period = 14}) => _rsiSeries(closes, period);

/// Aynı şekilde MACD(12,26,9) için tam zaman serisi (MACD çizgisi, sinyal
/// çizgisi, histogram) — `/api/candles`'ın MACD paneli için.
MacdSeries macdSeriesFor(
  List<double> closes, {
  int fastPeriod = 12,
  int slowPeriod = 26,
  int signalPeriod = 9,
}) {
  final n = closes.length;
  final macd = List<double?>.filled(n, null);
  final signal = List<double?>.filled(n, null);
  final histogram = List<double?>.filled(n, null);
  if (n < slowPeriod) return (macd: macd, signal: signal, histogram: histogram);

  final emaFast = _emaSeriesGeneric(closes, fastPeriod);
  final emaSlow = _emaSeriesGeneric(closes, slowPeriod);
  for (var i = slowPeriod - 1; i < n; i++) {
    macd[i] = emaFast[i] - emaSlow[i];
  }

  final validMacd = macd.sublist(slowPeriod - 1).cast<double>();
  if (validMacd.length < signalPeriod) return (macd: macd, signal: signal, histogram: histogram);
  final signalValid = _emaSeriesGeneric(validMacd, signalPeriod);
  for (var i = signalPeriod - 1; i < validMacd.length; i++) {
    final idx = slowPeriod - 1 + i;
    signal[idx] = signalValid[i];
    histogram[idx] = macd[idx]! - signalValid[i];
  }
  return (macd: macd, signal: signal, histogram: histogram);
}

/// Wilder'ın RSI için standart yumuşatma yöntemi: ilk değer basit ortalama,
/// sonrakiler `(önceki*(n-1)+yeni)/n` ile güncellenir.
List<double?> _rsiSeries(List<double> closes, int period) {
  final n = closes.length;
  final rsi = List<double?>.filled(n, null);
  if (n <= period) return rsi;
  var gainSum = 0.0, lossSum = 0.0;
  for (var i = 1; i <= period; i++) {
    final change = closes[i] - closes[i - 1];
    if (change >= 0) {
      gainSum += change;
    } else {
      lossSum -= change;
    }
  }
  var avgGain = gainSum / period;
  var avgLoss = lossSum / period;
  rsi[period] = avgLoss == 0 ? 100 : 100 - (100 / (1 + avgGain / avgLoss));
  for (var i = period + 1; i < n; i++) {
    final change = closes[i] - closes[i - 1];
    final gain = change > 0 ? change : 0.0;
    final loss = change < 0 ? -change : 0.0;
    avgGain = (avgGain * (period - 1) + gain) / period;
    avgLoss = (avgLoss * (period - 1) + loss) / period;
    rsi[i] = avgLoss == 0 ? 100 : 100 - (100 / (1 + avgGain / avgLoss));
  }
  return rsi;
}

double _lowestLow(List<double> lows, int period, int endIndexExclusive) {
  final start = endIndexExclusive - period;
  var m = lows[start];
  for (var i = start; i < endIndexExclusive; i++) {
    if (lows[i] < m) m = lows[i];
  }
  return m;
}

double _highestHigh(List<double> highs, int period, int endIndexExclusive) {
  final start = endIndexExclusive - period;
  var m = highs[start];
  for (var i = start; i < endIndexExclusive; i++) {
    if (highs[i] > m) m = highs[i];
  }
  return m;
}

/// [fromIndex]..[toIndexExclusive] aralığındaki her bar için %K(period)
/// değerini döner (STOCH ve STOCHRSI'nin %D/aralık hesapları için).
List<double> _stochKSeries(
  List<double> highs,
  List<double> lows,
  List<double> closes,
  int period,
  int fromIndex,
  int toIndexExclusive,
) {
  final result = <double>[];
  for (var i = fromIndex; i < toIndexExclusive; i++) {
    final hh = _highestHigh(highs, period, i + 1);
    final ll = _lowestLow(lows, period, i + 1);
    final range = hh - ll;
    result.add(range == 0 ? 50 : (closes[i] - ll) / range * 100);
  }
  return result;
}

List<double> _trueRanges(List<double> highs, List<double> lows, List<double> closes) {
  final tr = <double>[];
  for (var i = 1; i < closes.length; i++) {
    final hl = highs[i] - lows[i];
    final hc = (highs[i] - closes[i - 1]).abs();
    final lc = (lows[i] - closes[i - 1]).abs();
    tr.add([hl, hc, lc].reduce(max));
  }
  return tr;
}

/// [series]'in tamamını Wilder yöntemiyle yumuşatıp yalnızca son değeri
/// döner (ATR ve ADX'in nihai değeri için).
double _wilderSmoothFinal(List<double> series, int period) =>
    _wilderSmoothSeries(series, period).last;

/// Wilder yumuşatmasının tüm zaman serisini döner (ADX, DX serisi üzerinde
/// ikinci bir yumuşatma gerektirdiğinden bu gerekli).
List<double> _wilderSmoothSeries(List<double> series, int period) {
  final out = <double>[];
  var avg = 0.0;
  for (var i = 0; i < period; i++) {
    avg += series[i];
  }
  avg /= period;
  out.add(avg);
  for (var i = period; i < series.length; i++) {
    avg = (avg * (period - 1) + series[i]) / period;
    out.add(avg);
  }
  return out;
}
