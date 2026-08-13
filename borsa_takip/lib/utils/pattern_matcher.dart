import 'dart:math';

import '../models/candle.dart';
import '../models/pattern_match.dart';

List<double> _logReturns(List<double> closes) => [
      for (var i = 1; i < closes.length; i++) log(closes[i] / closes[i - 1]),
    ];

/// Klasik Dynamic Time Warping mesafesi (O(n·m) dinamik programlama) —
/// iki log-getiri dizisi arasındaki, küçük zamanlama kaymalarına toleranslı
/// bir "şekil farkı" ölçüsü. Burada [a]/[b] her zaman aynı uzunlukta
/// (pencere boyu sabit), ama DTW yine de düz Öklid mesafesinden daha
/// sağlam: iki desen aynı yönde ama biraz farklı hızda hareket etmişse
/// (ör. biri 2 barda, diğeri 3 barda toparlanmışsa) hizalama esnekliğiyle
/// bunu düşük mesafeyle ödüllendirir.
double _dtwDistance(List<double> a, List<double> b) {
  final n = a.length, m = b.length;
  var prev = List<double>.filled(m + 1, double.infinity);
  var curr = List<double>.filled(m + 1, double.infinity);
  prev[0] = 0;
  for (var i = 1; i <= n; i++) {
    curr[0] = double.infinity;
    for (var j = 1; j <= m; j++) {
      final cost = (a[i - 1] - b[j - 1]).abs();
      final best = min(prev[j], min(curr[j - 1], prev[j - 1]));
      curr[j] = cost + best;
    }
    final tmp = prev;
    prev = curr;
    curr = tmp;
  }
  return prev[m];
}

/// DTW mesafesini 0-100 arası bir "benzerlik" yüzdesine çevirir. Mesafe,
/// karşılaştırılan [reference] deseninin kendi ortalama getiri büyüklüğüne
/// göre normalize edilir — bu sayede yüksek/düşük oynaklıklı semboller için
/// aynı ham mesafe farklı anlamlara gelmez (ör. çok oynak bir hissede 0.05
/// mesafe "neredeyse aynı" demekken, sakin bir hissede aynı 0.05 "alakasız"
/// demek olabilir). Kesin bir ders kitabı formülü değil; mesafe arttıkça
/// benzerliğin (100'den) yumuşakça 0'a yaklaştığı, sınırlı (0,100] bir
/// eğri — bilinçli bir yaklaşıklık.
double _similarityFromDtw(double distance, List<double> reference) {
  if (reference.isEmpty) return 0;
  final avgMagnitude =
      reference.map((r) => r.abs()).reduce((a, b) => a + b) / reference.length;
  final normalizer = (avgMagnitude == 0 ? 0.001 : avgMagnitude) * reference.length;
  return 100 * (1 / (1 + distance / normalizer));
}

class _ScoredWindow {
  final int start;
  final double similarity;
  _ScoredWindow(this.start, this.similarity);
}

/// Grafik sekmesindeki "Tarihsel Benzerlik" özelliğinin çekirdeği: [history]
/// (mümkün olduğunca uzun bir geçmiş — bkz. HomeScreen
/// ._toggleHistoricalPatternMatch'in ayrı, DateTime(2000)'den bugüne bir
/// fetch yapması) içinde, en son [windowLength] barın log-getiri desenine
/// DTW ile en çok benzeyen, birbiriyle ÇAKIŞMAYAN (en az [windowLength] bar
/// arayla) en fazla [topK] pencereyi bulur. Sadece benzerliği
/// [minSimilarityPercent] ve üzeri olanlar döner. Her eşleşen pencerenin
/// hemen ardından gelen [windowLength] barın kapanışları, bugünün son
/// kapanışına göre ölçeklenip (bkz. PatternMatch.projectedPrices) geleceğe
/// izdüşürülür.
///
/// Yeterli geçmiş yoksa (en az bugünkü desen + bir aday pencere + o
/// pencerenin geleceği için 3×[windowLength] bar gerekir) ya da eşiği geçen
/// hiçbir eşleşme bulunamazsa `null` döner.
List<PatternMatch>? findHistoricalPatterns(
  List<Candle> history, {
  int windowLength = 30,
  int topK = 3,
  double minSimilarityPercent = 80,
}) {
  final closes = [for (final c in history) c.close];
  final n = closes.length;
  if (n < windowLength * 3) return null;

  final currentPattern = _logReturns(closes.sublist(n - windowLength, n));

  // Aday pencere [s, s+windowLength-1]; ardından windowLength kadar
  // "gelecek" bar mevcut olmalı VE bugünkü pencereyle çakışmamalı (o yüzden
  // en geç n - 2*windowLength'te başlayabilir).
  final latestAllowedStart = n - windowLength * 2;
  final candidates = <_ScoredWindow>[];
  for (var s = 0; s <= latestAllowedStart; s++) {
    final windowReturns = _logReturns(closes.sublist(s, s + windowLength));
    final distance = _dtwDistance(currentPattern, windowReturns);
    final similarity = _similarityFromDtw(distance, currentPattern);
    if (similarity >= minSimilarityPercent) {
      candidates.add(_ScoredWindow(s, similarity));
    }
  }
  if (candidates.isEmpty) return null;
  candidates.sort((a, b) => b.similarity.compareTo(a.similarity));

  // En iyi topK'yı, komşu (neredeyse aynı) pencereleri ayrı "dönemler" gibi
  // saymamak için aralarında en az windowLength bar boşluk bırakarak seç.
  final selected = <_ScoredWindow>[];
  for (final c in candidates) {
    if (selected.length >= topK) break;
    final overlaps = selected.any((s) => (c.start - s.start).abs() < windowLength);
    if (!overlaps) selected.add(c);
  }
  if (selected.isEmpty) return null;

  final todayClose = closes.last;
  return [
    for (final s in selected)
      () {
        final matchEndIndex = s.start + windowLength - 1;
        final matchEndClose = closes[matchEndIndex];
        final scale = matchEndClose == 0 ? 1.0 : todayClose / matchEndClose;
        final future = closes.sublist(matchEndIndex + 1, matchEndIndex + 1 + windowLength);
        return PatternMatch(
          periodLabel: '${history[s.start].period} – ${history[matchEndIndex].period}',
          similarityPercent: s.similarity,
          projectedPrices: [for (final p in future) p * scale],
        );
      }(),
  ];
}
