/// Grafik sekmesindeki tahmin butonlarının ("GBM"/"OU"/"Trend") temsil
/// ettiği matematiksel model — bkz. utils/forecast_engine.dart'taki üç
/// fonksiyon (gbmForecast/ouForecast/trendForecast). Sadece hangi modelin
/// seçili olduğunu ve kullanıcıya gösterilecek etiket/açıklamayı taşır;
/// hesaplamanın kendisi engine'de, rengi utils/forecast_color.dart'ta.
/// [description] chip'in üzerindeki kısa tooltip için (teknik isim),
/// [infoTitle]/[infoBody] ise "i" bilgi ikonuyla açılan diyalog için
/// (sıradan-insan diliyle, bkz. HomeScreen._showForecastInfoDialog).
enum ForecastModelType {
  gbm(
    'GBM',
    'Geometric Brownian Motion (Stokastik Simülasyon)',
    'GBM Nedir ve Nasıl Hesaplar?',
    'Bu model, hissenin geçmişteki ortalama yükseliş/düşüş hızını (trend) '
        've piyasadaki dalgalanma şiddetini (oynaklık) temel alır. '
        'Piyasada her gün rastgele haberler ve sürprizler olacağını kabul '
        'eder. Fiyatın geçmişteki ortalama yönünü koruyarak, gelecekte '
        'karşılaşabileceği rastgele iniş-çıkış senaryolarını simüle eder.',
  ),
  ou(
    'OU',
    'Ornstein-Uhlenbeck (Ortalamaya Dönüş)',
    'OU (Ortalamaya Dönüş) Nedir ve Nasıl Hesaplar?',
    "Bu model bir 'mıknatıs' veya 'paket lastiği' mantığıyla çalışır. "
        'Hissenin uzun vadeli bir dengesi/ortalaması olduğunu varsayar. '
        'Fiyat bu ortalamadan çok fazla uzaklaştığında (aşırı yükseldiğinde '
        'veya düştüğünde), gerilen bir lastik gibi zamanla tekrar kendi '
        'ortalama değerine doğru çekileceğini hesaplar.',
  ),
  trend(
    'Trend',
    'Üstel Trend Projeksiyonu (Holt-Winters)',
    'Trend Projeksiyonu Nedir ve Nasıl Hesaplar?',
    'Bu model yakın geçmişteki fiyat hareketlerine daha yüksek önem '
        'verir. Dün ve geçen haftaki momentumu (fiyat ivmesini) analiz '
        'ederek, hissenin mevcut yönünü bir ok gibi geleceğe doğru uzatır. '
        'Yakın zamandaki hareketlerin devam edeceğini varsayan en '
        'doğrudan tahmin yöntemidir.',
  );

  final String shortLabel;
  final String description;
  final String infoTitle;
  final String infoBody;

  const ForecastModelType(this.shortLabel, this.description, this.infoTitle, this.infoBody);
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
