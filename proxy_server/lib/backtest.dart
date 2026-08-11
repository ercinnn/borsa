import 'technical_analysis.dart';
import 'yahoo_client.dart';

class BacktestTrade {
  final String type; // 'buy' | 'sell'
  final DateTime date;
  final double price;
  final int score;
  BacktestTrade({
    required this.type,
    required this.date,
    required this.price,
    required this.score,
  });

  Map<String, dynamic> toJson() => {
        'type': type,
        'date': date.toIso8601String(),
        'price': price,
        'score': score,
      };
}

class BacktestPoint {
  final DateTime date;
  final double strategyValue;
  final double buyHoldValue;
  BacktestPoint(this.date, this.strategyValue, this.buyHoldValue);

  Map<String, dynamic> toJson() => {
        'date': date.toIso8601String(),
        'strategyValue': strategyValue,
        'buyHoldValue': buyHoldValue,
      };
}

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

  BacktestResult({
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

  Map<String, dynamic> toJson() => {
        'symbol': symbol,
        'currency': currency,
        'initialCapital': initialCapital,
        'finalValue': finalValue,
        'finalReturnPct': finalReturnPct,
        'buyHoldFinalValue': buyHoldFinalValue,
        'buyHoldReturnPct': buyHoldReturnPct,
        'trades': trades.map((t) => t.toJson()).toList(),
        'equityCurve': equityCurve.map((p) => p.toJson()).toList(),
      };
}

// computeTechnicalAnalysis'in her simüle edilen gün için baktığı geriye
// dönük pencere. _technicalHandler'ın canlı Teknik sekmesi için kullandığı
// ~500 takvim günü (~350 işlem günü) lookback'iyle aynı büyüklük mertebesi —
// o günü canlı açsaydın Teknik sekmesinin hesaplayacağı puanla tutarlı
// olsun diye. Sabit tutulduğundan (genişleyen değil) her simüle edilen
// günün maliyeti O(pencere) ile sınırlı kalır, toplam maliyet O(gün sayısı)
// olur — genişleyen bir pencere kullanılsaydı O(gün sayısı²) olurdu.
const _lookbackCandles = 260;

/// [candles] simülasyon başlangıcından (`simulationStart`) önce yeterli
/// ısınma (lookback) verisi içermelidir — bkz. bin/server.dart
/// `_backtestHandler`'ın fetch aralığını nasıl genişlettiği. Her simüle
/// edilen gün için o güne kadarki (en fazla [_lookbackCandles] barlık)
/// pencereyle `computeTechnicalAnalysis` çağrılır ve puan [buyThreshold]'a
/// ulaşınca (elde yoksa) alım, [sellThreshold]'a düşünce (elde varsa) satım
/// yapılır — "bu puan eşiğine göre alım-satım yapsaydım" simülasyonunun
/// birebir karşılığı. BASİTLEŞTİRİLMİŞ VARSAYIMLAR: işlem maliyeti/komisyon
/// yok, kayma (slippage) yok, sinyal üretilen günün KAPANIŞ fiyatından
/// anında al/sat yapılır (gerçekte bir sonraki günün açılışını beklemek
/// gerekirdi), pozisyon her zaman ya tamamen nakit ya tamamen hisse (kısmi
/// pozisyon yok).
BacktestResult runBacktest({
  required String symbol,
  required String currency,
  required List<RawCandle> candles,
  required DateTime simulationStart,
  required int buyThreshold,
  required int sellThreshold,
  required double initialCapital,
}) {
  final startIndex = candles.indexWhere((c) => !c.date.isBefore(simulationStart));
  if (startIndex == -1) {
    throw InsufficientDataException(
      '$symbol için seçilen tarih aralığında mum verisi bulunamadı.',
    );
  }
  if (startIndex < 35) {
    throw InsufficientDataException(
      '$symbol için backtest başlangıcından önce teknik analiz için yeterli '
      'geçmiş veri (ısınma periyodu) yok.',
    );
  }

  var cash = initialCapital;
  var shares = 0.0;
  var holding = false;
  final trades = <BacktestTrade>[];
  final equityCurve = <BacktestPoint>[];

  final buyHoldShares = initialCapital / candles[startIndex].close.toDouble();

  for (var i = startIndex; i < candles.length; i++) {
    final windowStart = (i + 1 - _lookbackCandles).clamp(0, i + 1);
    final window = candles.sublist(windowStart, i + 1);
    final today = candles[i];
    final price = today.close.toDouble();

    final analysis = computeTechnicalAnalysis(symbol, currency, window);
    final score = analysis.summary.score;

    if (!holding && score >= buyThreshold) {
      shares = cash / price;
      cash = 0;
      holding = true;
      trades.add(BacktestTrade(type: 'buy', date: today.date, price: price, score: score));
    } else if (holding && score <= sellThreshold) {
      cash = shares * price;
      shares = 0;
      holding = false;
      trades.add(BacktestTrade(type: 'sell', date: today.date, price: price, score: score));
    }

    final strategyValue = holding ? shares * price : cash;
    final buyHoldValue = buyHoldShares * price;
    equityCurve.add(BacktestPoint(today.date, strategyValue, buyHoldValue));
  }

  final lastPrice = candles.last.close.toDouble();
  final finalValue = holding ? shares * lastPrice : cash;
  final finalReturnPct = (finalValue - initialCapital) / initialCapital * 100;
  final buyHoldFinalValue = buyHoldShares * lastPrice;
  final buyHoldReturnPct = (buyHoldFinalValue - initialCapital) / initialCapital * 100;

  return BacktestResult(
    symbol: symbol,
    currency: currency,
    initialCapital: initialCapital,
    finalValue: finalValue,
    finalReturnPct: finalReturnPct,
    buyHoldFinalValue: buyHoldFinalValue,
    buyHoldReturnPct: buyHoldReturnPct,
    trades: trades,
    equityCurve: equityCurve,
  );
}
