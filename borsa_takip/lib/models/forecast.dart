/// Grafik sekmesindeki tahmin butonlarının ("GBM"/"OU"/"Trend") temsil
/// ettiği matematiksel model — bkz. utils/forecast_engine.dart'taki üç
/// fonksiyon (gbmForecast/ouForecast/trendForecast). Sadece hangi modelin
/// seçili olduğunu ve kullanıcıya gösterilecek etiket/açıklamayı taşır;
/// hesaplamanın kendisi engine'de, rengi utils/forecast_color.dart'ta.
enum ForecastModelType {
  gbm('GBM', 'Geometric Brownian Motion (Stokastik Simülasyon)'),
  ou('OU', 'Ornstein-Uhlenbeck (Ortalamaya Dönüş)'),
  trend('Trend', 'Üstel Trend Projeksiyonu (Holt-Winters)');

  final String shortLabel;
  final String description;

  const ForecastModelType(this.shortLabel, this.description);
}

/// Bir tahmin butonuna basıldığında üretilen sonuç: [prices] ile [periods]
/// birebir eşleşir (ikisi de aynı uzunlukta, geçmiş mum sayısı kadar —
/// bkz. HomeScreen._toggleForecast). CandlestickChart bunu geçmiş verinin
/// hemen sağına, kesikli bir çizgiyle çizer.
class ForecastResult {
  final ForecastModelType model;
  final List<double> prices;
  final List<String> periods;

  const ForecastResult({
    required this.model,
    required this.prices,
    required this.periods,
  });
}
