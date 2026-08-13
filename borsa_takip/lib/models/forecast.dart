/// Grafik sekmesindeki tahmin butonlarının ("GBM"/"OU"/"Trend") temsil
/// ettiği matematiksel model — bkz. utils/forecast_engine.dart'taki üç
/// fonksiyon (gbmForecastCone/ouForecastCone/trendForecast). Sadece hangi modelin
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

/// GBM/OU Monte Carlo simülasyonunun ufuk sonu (30. gün/bar) için özet
/// istatistikleri — bkz. utils/forecast_engine.dart `_computeStats`. Grafiğin
/// altındaki "Yapay Zeka / Kantitatif Gelecek Raporu" modülünün (bkz.
/// widgets/forecast_report_card.dart) tüm metinsel yorumları buradan
/// türetilir. Sadece GBM/OU'da dolu — Trend deterministik olduğundan bir
/// simülasyon dağılımı, dolayısıyla bu istatistiklerin matematiksel temeli
/// yok.
class ForecastStats {
  // Ufuk sonu 1000 patikanın ortalama fiyatı.
  final double mean;
  // Ufuk sonu standart sapma, bugünün kapanışına oranla % olarak (fiyat
  // biriminden bağımsız, sembol/döviz fark etmeksizin karşılaştırılabilir).
  final double volatilityPercent;
  // Dağılımın çarpıklığı (3. standartlaştırılmış moment) — pozitifse
  // dağılımın sağ kuyruğu (yüksek fiyat senaryoları) daha uzun, negatifse
  // sol kuyruğu (düşük fiyat senaryoları) daha uzun demektir.
  final double skewness;
  // %50 yüzdelik dilim (medyan) — fan.median.last ile aynı değer, rapor
  // metninde tekrar hesaplamamak için burada da tutuluyor.
  final double medianTarget;
  final double bullTarget; // ufuk sonu en yüksek (100. yüzdelik dilim) senaryo
  final double bearTarget; // ufuk sonu en düşük (0. yüzdelik dilim) senaryo
  // 1000 patikadan kaçının bugünün kapanışının ÜZERİNDE bittiğinin yüzdesi.
  final double winProbabilityPercent;
  // Value at Risk (%95 güven aralığı): ufuk sonu %5 yüzdelik dilimin
  // bugünün kapanışına göre % değişimi — negatif bir sayı ("maksimum olası
  // kayıp").
  final double valueAtRisk95Percent;

  const ForecastStats({
    required this.mean,
    required this.volatilityPercent,
    required this.skewness,
    required this.medianTarget,
    required this.bullTarget,
    required this.bearTarget,
    required this.winProbabilityPercent,
    required this.valueAtRisk95Percent,
  });

  static const zero = ForecastStats(
    mean: 0,
    volatilityPercent: 0,
    skewness: 0,
    medianTarget: 0,
    bullTarget: 0,
    bearTarget: 0,
    winProbabilityPercent: 0,
    valueAtRisk95Percent: 0,
  );
}

/// GBM/OU Monte Carlo simülasyonunun gün-gün yüzdelik dilim serileri — 5
/// katmanlı "Olasılık Isı Konisi"nin dolgu sınırları (bkz.
/// candlestick_chart.dart `_paintProbabilityFan`, utils/forecast_color.dart
/// `ProbabilityFanColors`). Katmanlar: p0-p10 (Koyu Kırmızı), p10-p30
/// (Açık Kırmızı), p30-p40 (Gri), p40-p60 (Koyu Yeşil, en yüksek olasılık),
/// p60-p100 (Açık Yeşil — üst dilim %80'de kesilmek yerine %100'e kadar
/// genişletildi, aksi halde koninin en üst %20'lik kısmı renksiz kalırdı).
/// [median] (p50) ayrıca "orta senaryo" çizgisi için ayrı çizilir.
class ProbabilityFan {
  final List<double> p0;
  final List<double> p10;
  final List<double> p30;
  final List<double> p40;
  final List<double> p60;
  final List<double> p100;
  final List<double> median;
  final ForecastStats stats;

  const ProbabilityFan({
    required this.p0,
    required this.p10,
    required this.p30,
    required this.p40,
    required this.p60,
    required this.p100,
    required this.median,
    required this.stats,
  });

  static const empty = ProbabilityFan(
    p0: [],
    p10: [],
    p30: [],
    p40: [],
    p60: [],
    p100: [],
    median: [],
    stats: ForecastStats.zero,
  );

  bool get isEmpty => median.isEmpty;
}

/// Bir tahmin butonuna basıldığında üretilen sonuç. [prices]/[periods]
/// hepsi aynı uzunlukta (geçmiş mum sayısı kadar — bkz.
/// HomeScreen._toggleForecast). [prices] her zaman dolu: GBM/OU için 1000
/// Monte Carlo patikasının %50 (medyan) yüzdelik dilimi, Trend için tek
/// deterministik projeksiyon. [fan] sadece GBM/OU'da dolu (bkz.
/// ProbabilityFan doc yorumu) — Trend'de null. CandlestickChart geçmiş
/// verinin hemen sağına [prices]'ı her zaman, [fan] doluysa 5 katmanlı
/// renkli dolguyu da birlikte çizer.
class ForecastResult {
  final ForecastModelType model;
  final List<double> prices;
  final List<String> periods;
  final ProbabilityFan? fan;

  const ForecastResult({
    required this.model,
    required this.prices,
    required this.periods,
    this.fan,
  });
}
