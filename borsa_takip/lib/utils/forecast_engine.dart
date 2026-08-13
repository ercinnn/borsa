import 'dart:math';

import 'package:intl/intl.dart';

import '../models/forecast.dart';
import '../models/interval.dart';

// Fiyatların matematiksel olarak sıfıra ya da altına düşmesini (özellikle
// OU'nun toplamsal gürültüsüyle) engellemek için — gerçek bir borsa
// fiyatının alamayacağı bir değer, sadece çizim/eksen hesaplarının
// bozulmaması için bir taban.
const _priceFloor = 0.0001;

double _standardNormal(Random rnd) {
  // Box-Muller dönüşümü — dart:math'te doğrudan bir normal dağılım
  // örnekleyicisi yok.
  final u1 = 1 - rnd.nextDouble(); // (0, 1]
  final u2 = rnd.nextDouble();
  return sqrt(-2 * log(u1)) * cos(2 * pi * u2);
}

/// GBM kalibrasyonu: [closes]'ın log-getirilerinden sürüklenme (μ) ve
/// volatilite (σ) çıkarır — hem eski tek-patikalı hem yeni Monte Carlo
/// koni simülasyonu aynı kalibrasyonu paylaşsın diye ayrı bir fonksiyon.
({double mu, double sigma})? _gbmParams(List<double> closes) {
  if (closes.length < 2) return null;
  final returns = <double>[
    for (var i = 1; i < closes.length; i++)
      if (closes[i - 1] > 0 && closes[i] > 0) log(closes[i] / closes[i - 1]),
  ];
  if (returns.isEmpty) return null;
  final mu = returns.reduce((a, b) => a + b) / returns.length;
  final variance =
      returns.map((r) => (r - mu) * (r - mu)).reduce((a, b) => a + b) / returns.length;
  return (mu: mu, sigma: sqrt(variance));
}

/// OU kalibrasyonu: ΔX_t = κ(θ - X_(t-1)) + ε ayrık modelini X_(t-1)
/// üzerinde basit doğrusal regresyonla kalibre eder (eğim ≈ -κ, kesişim ≈
/// κθ). κ negatif çıkarsa (ortalamaya dönüş yerine ıraksama gösteren bir
/// seri) 0'a kelepçelenir — o durumda model saf rastgele yürüyüşe düşer,
/// hatalı/patlayıcı bir tahmin üretmez.
({double kappa, double theta, double sigma}) _ouParams(List<double> closes) {
  final xs = closes.sublist(0, closes.length - 1);
  final dxs = [for (var i = 1; i < closes.length; i++) closes[i] - closes[i - 1]];
  final n = xs.length;
  final xMean = xs.reduce((a, b) => a + b) / n;
  final dxMean = dxs.reduce((a, b) => a + b) / n;

  var num = 0.0, den = 0.0;
  for (var i = 0; i < n; i++) {
    num += (xs[i] - xMean) * (dxs[i] - dxMean);
    den += (xs[i] - xMean) * (xs[i] - xMean);
  }
  final slope = den == 0 ? 0.0 : num / den;
  final intercept = dxMean - slope * xMean;
  final kappa = (-slope).clamp(0.0, 1.0);
  final theta = kappa == 0 ? xMean : intercept / kappa;

  var sqErr = 0.0;
  for (var i = 0; i < n; i++) {
    final predicted = slope * xs[i] + intercept;
    final err = dxs[i] - predicted;
    sqErr += err * err;
  }
  return (kappa: kappa, theta: theta, sigma: sqrt(sqErr / n));
}

// Kullanıcının istediği "1.000 patika" — 1000 × adım sayısı kadar basit
// aritmetik olduğundan (ör. 30 adım × 1000 = 30.000 çarpma/toplama)
// Flutter web'de bile milisaniyeler içinde biter, ayrıca bir isolate/
// arka plan hesaplamasına gerek yok.
const _defaultSimulations = 1000;

/// Her gün adımı için [dayValues]'daki (o günün 1000 simülasyon sonucu)
/// diziyi sıralayıp 5 katmanlı Olasılık Isı Konisi'nin dolgu sınırlarını
/// (p0/p10/p30/p40/p60/p100) ve orta senaryo çizgisini (medyan/p50) okur;
/// son gün için ayrıca [_computeStats] ile özet istatistikleri hesaplar —
/// GBM ve OU fan fonksiyonlarının ortak son adımı.
ProbabilityFan _reduceDayValues(List<List<double>> dayValues, double todayClose) {
  final p0 = <double>[], p10 = <double>[], p30 = <double>[];
  final p40 = <double>[], p60 = <double>[], p100 = <double>[], median = <double>[];
  var stats = ForecastStats.zero;
  for (var d = 0; d < dayValues.length; d++) {
    final sorted = [...dayValues[d]]..sort();
    p0.add(sorted.first);
    p10.add(_percentile(sorted, 0.10));
    p30.add(_percentile(sorted, 0.30));
    p40.add(_percentile(sorted, 0.40));
    p60.add(_percentile(sorted, 0.60));
    p100.add(sorted.last);
    median.add(_percentile(sorted, 0.50));
    if (d == dayValues.length - 1) {
      stats = _computeStats(sorted, todayClose);
    }
  }
  return ProbabilityFan(
    p0: p0,
    p10: p10,
    p30: p30,
    p40: p40,
    p60: p60,
    p100: p100,
    median: median,
    stats: stats,
  );
}

double _percentile(List<double> sorted, double p) {
  final idx = (p * (sorted.length - 1)).round().clamp(0, sorted.length - 1);
  return sorted[idx];
}

/// [sortedFinalDay] (ufuk sonu — 30. gün/bar — simülasyon sonuçları,
/// zaten sıralı) üzerinden "Yapay Zeka / Kantitatif Gelecek Raporu"
/// modülünün (bkz. widgets/forecast_report_card.dart) ihtiyaç duyduğu tüm
/// özet istatistikleri tek geçişte hesaplar.
ForecastStats _computeStats(List<double> sortedFinalDay, double todayClose) {
  final n = sortedFinalDay.length;
  final mean = sortedFinalDay.reduce((a, b) => a + b) / n;
  final variance =
      sortedFinalDay.map((v) => (v - mean) * (v - mean)).reduce((a, b) => a + b) / n;
  final stdDev = sqrt(variance);
  // Çarpıklık (skewness): standartlaştırılmış sapmaların küpünün ortalaması.
  final skewness = stdDev == 0
      ? 0.0
      : sortedFinalDay.map((v) => pow((v - mean) / stdDev, 3)).reduce((a, b) => a + b) / n;
  final winCount = sortedFinalDay.where((v) => v > todayClose).length;
  final p5 = _percentile(sortedFinalDay, 0.05);
  return ForecastStats(
    mean: mean,
    volatilityPercent: todayClose == 0 ? 0.0 : stdDev / todayClose * 100,
    skewness: skewness.toDouble(),
    medianTarget: _percentile(sortedFinalDay, 0.50),
    bullTarget: sortedFinalDay.last,
    bearTarget: sortedFinalDay.first,
    winProbabilityPercent: 100 * winCount / n,
    // Value at Risk: %5 yüzdelik dilimin bugüne göre % değişimi — bir
    // kayıp olduğundan doğal olarak negatif çıkar.
    valueAtRisk95Percent: todayClose == 0 ? 0.0 : (p5 - todayClose) / todayClose * 100,
  );
}

/// Geometric Brownian Motion: [_gbmParams] ile kalibre edilen sürüklenme/
/// volatiliteyle [simulations] adet bağımsız stokastik patika (S_(t+1) =
/// S_t · exp((μ - σ²/2) + σ·Z)) simüle edip 5 katmanlı Olasılık Isı
/// Konisi'ne indirger. Rastgelelik tohumlanmıyor: kullanıcı butona her
/// bastığında yeni bir senaryo seti görsün diye (bkz.
/// HomeScreen._toggleForecast, aynı butona tekrar basmak tahmini kapatır,
/// üçüncü kez basmak yeni bir fan üretir).
ProbabilityFan gbmForecastFan(List<double> closes, int steps, {int simulations = _defaultSimulations}) {
  if (steps <= 0) return ProbabilityFan.empty;
  final params = _gbmParams(closes);
  if (params == null) return ProbabilityFan.empty;

  final rnd = Random();
  // dayValues[d]: d. gün sonunda 1000 simülasyonun ürettiği fiyat örnekleri.
  final dayValues = List.generate(steps, (_) => List<double>.filled(simulations, 0.0));
  for (var s = 0; s < simulations; s++) {
    var last = closes.last;
    for (var d = 0; d < steps; d++) {
      last = max(
        _priceFloor,
        last * exp((params.mu - 0.5 * params.sigma * params.sigma) + params.sigma * _standardNormal(rnd)),
      );
      dayValues[d][s] = last;
    }
  }
  return _reduceDayValues(dayValues, closes.last);
}

/// Ornstein-Uhlenbeck (ortalamaya dönüş): [_ouParams] ile kalibre edilen
/// κ/θ/σ'yla [simulations] adet bağımsız stokastik patika (κ(θ - X_t)
/// sürüklenmesi + Gauss gürültüsü) simüle edip GBM fanıyla aynı şekilde
/// 5 katmanlı Olasılık Isı Konisi'ne indirger.
ProbabilityFan ouForecastFan(List<double> closes, int steps, {int simulations = _defaultSimulations}) {
  if (closes.length < 3 || steps <= 0) return ProbabilityFan.empty;
  final params = _ouParams(closes);

  final rnd = Random();
  final dayValues = List.generate(steps, (_) => List<double>.filled(simulations, 0.0));
  for (var s = 0; s < simulations; s++) {
    var last = closes.last;
    for (var d = 0; d < steps; d++) {
      last = max(_priceFloor, last + params.kappa * (params.theta - last) + params.sigma * _standardNormal(rnd));
      dayValues[d][s] = last;
    }
  }
  return _reduceDayValues(dayValues, closes.last);
}

/// Holt'un doğrusal trend projeksiyonu (double exponential smoothing) —
/// diğer ikisinin aksine stokastik değil, deterministik bir "bu trend
/// sürerse" projeksiyonu: seviye ve trend bileşenleri tüm geçmiş üzerinden
/// düzleştirilip son değerden itibaren doğrusal olarak ileri taşınır.
/// [alpha]/[beta] varsayılanları standart Holt-Winters ders kitabı
/// değerleridir (ne çok gürültüye ne çok geçmişe aşırı ağırlık verir).
List<double> trendForecast(List<double> closes, int steps, {double alpha = 0.3, double beta = 0.1}) {
  if (closes.length < 2 || steps <= 0) return const [];
  var level = closes[0];
  var trend = closes[1] - closes[0];
  for (var i = 1; i < closes.length; i++) {
    final lastLevel = level;
    level = alpha * closes[i] + (1 - alpha) * (level + trend);
    trend = beta * (level - lastLevel) + (1 - beta) * trend;
  }
  return [
    for (var h = 1; h <= steps; h++) max(_priceFloor, level + h * trend),
  ];
}

// utils/candle_padding.dart'taki "mum başına kaba takvim günü" tablosuyla
// aynı ruhta (kesin olması gerekmiyor, sadece tahmin etiketlerinin
// yaklaşık olarak doğru aralıklarla ilerlemesi için) — ayrı bir dosyada
// tutuluyor çünkü candle_padding.dart'ınki geçmişe doğru başlangıç tarihi
// genişletmek için private, buradaki ise ileriye doğru etiket üretmek için.
const _daysPerBar = {
  ChartInterval.hourly: 0.3,
  ChartInterval.fourHour: 0.5,
  ChartInterval.daily: 1.4,
  ChartInterval.weekly: 7.0,
  ChartInterval.monthly: 30.0,
  ChartInterval.quarterly: 91.0,
  ChartInterval.yearly: 365.0,
};

/// Tahmin çizgisinin altındaki [_PeriodLabels] etiketleri için yaklaşık
/// gelecek tarihler — gerçek mumların aksine (bkz. models/candle.dart doc
/// yorumu, `period` sunucuda formatlanır) burada sunucu round-trip'i yok,
/// bugünden itibaren [interval]'a göre kaba bir takvim-günü adımıyla
/// hesaplanıp `dd.MM.yy` olarak formatlanır.
List<String> generateForecastPeriods(ChartInterval interval, int steps) {
  final perBar = _daysPerBar[interval] ?? 30.0;
  final fmt = DateFormat('dd.MM.yy');
  final now = DateTime.now();
  return [
    for (var i = 1; i <= steps; i++) fmt.format(now.add(Duration(days: (perBar * i).round()))),
  ];
}
