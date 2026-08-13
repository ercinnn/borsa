import 'dart:math';

import 'package:intl/intl.dart';

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

/// Geometric Brownian Motion: [closes]'ın log-getirilerinden sürüklenme (μ)
/// ve volatilite (σ) kalibre edilir, ardından ileriye dönük TEK bir
/// stokastik simülasyon path'i üretilir (S_(t+1) = S_t · exp((μ - σ²/2) +
/// σ·Z)). Rastgelelik tohumlanmıyor — kullanıcı butona her bastığında yeni
/// bir "senaryo" görsün diye (bkz. HomeScreen._toggleForecast, aynı butona
/// tekrar basmak tahmini kapatır, üçüncü kez basmak yeni bir simülasyon
/// üretir).
List<double> gbmForecast(List<double> closes, int steps) {
  if (closes.length < 2 || steps <= 0) return const [];
  final returns = <double>[
    for (var i = 1; i < closes.length; i++)
      if (closes[i - 1] > 0 && closes[i] > 0) log(closes[i] / closes[i - 1]),
  ];
  if (returns.isEmpty) return const [];
  final mu = returns.reduce((a, b) => a + b) / returns.length;
  final variance =
      returns.map((r) => (r - mu) * (r - mu)).reduce((a, b) => a + b) / returns.length;
  final sigma = sqrt(variance);

  final rnd = Random();
  var last = closes.last;
  return [
    for (var i = 0; i < steps; i++)
      last = max(_priceFloor, last * exp((mu - 0.5 * sigma * sigma) + sigma * _standardNormal(rnd))),
  ];
}

/// Ornstein-Uhlenbeck (ortalamaya dönüş): ΔX_t = κ(θ - X_(t-1)) + ε ayrık
/// modelini X_(t-1) üzerinde basit doğrusal regresyonla kalibre eder (eğim
/// ≈ -κ, kesişim ≈ κθ), sonra ileriye dönük κ(θ - X_t) sürüklenmesi + kalıntı
/// std'sinden Gauss gürültüsüyle stokastik olarak simüle eder. κ negatif
/// çıkarsa (ortalamaya dönüş yerine ıraksama gösteren bir seri) 0'a
/// kelepçelenir — o durumda model saf rastgele yürüyüşe (sürüklenmesiz GBM
/// benzeri) düşer, hatalı/patlayıcı bir tahmin üretmez.
List<double> ouForecast(List<double> closes, int steps) {
  if (closes.length < 3 || steps <= 0) return const [];
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
  final sigma = sqrt(sqErr / n);

  final rnd = Random();
  var last = closes.last;
  return [
    for (var i = 0; i < steps; i++)
      last = max(_priceFloor, last + kappa * (theta - last) + sigma * _standardNormal(rnd)),
  ];
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
