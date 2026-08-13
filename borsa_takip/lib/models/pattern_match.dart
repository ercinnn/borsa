/// Grafik sekmesindeki "Tarihsel Benzerlik" butonuna basıldığında
/// `utils/pattern_matcher.dart`'taki `findHistoricalPatterns()` tarafından
/// üretilen tek bir eşleşme: geçmişte, mevcut son 30 barlık fiyat hareketine
/// (log-getiri dizisine) DTW ile en çok benzeyen bir pencere ve o pencerenin
/// hemen ardından gelen 30 barın, bugünün son kapanışına normalize edilmiş
/// hali (bkz. [projectedPrices]) — grafikte soluk bir "Hayalet Çizgi" olarak
/// çizilir (bkz. widgets/candlestick_chart.dart `_drawGhostLines`).
class PatternMatch {
  // Eşleşen geçmiş pencerenin (30 bar) başlangıç/bitiş dönemi — Candle
  // .period'dan alınır (ör. "12.03.21 – 23.04.21"), grafikte ve bilgi
  // kartında insan-okunur etiket olarak kullanılır.
  final String periodLabel;
  // DTW mesafesinden türetilen 0-100 arası benzerlik skoru (bkz.
  // pattern_matcher.dart `_similarityFromDtw`) — Pearson korelasyon
  // katsayısıyla karıştırılmasın diye kasıtlı olarak "Benzerlik" adıyla
  // gösteriliyor, "Korelasyon" değil.
  final double similarityPercent;
  final List<double> projectedPrices;

  const PatternMatch({
    required this.periodLabel,
    required this.similarityPercent,
    required this.projectedPrices,
  });
}

/// Bir "Tarihsel Benzerlik" taramasının sonucu: %80 eşiğini geçen, birbiriyle
/// çakışmayan en iyi (en fazla 3) eşleşme + hepsinin paylaştığı gelecek
/// dönem etiketleri (bkz. HomeScreen._toggleHistoricalPatternMatch,
/// utils/forecast_engine.dart generateForecastPeriods'ın yeniden kullanımı).
class PatternMatchResult {
  final List<PatternMatch> matches;
  final List<String> periods;

  const PatternMatchResult({required this.matches, required this.periods});
}
