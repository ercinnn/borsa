import 'package:flutter/material.dart';

import '../models/forecast.dart';
import '../theme/app_colors.dart';

/// Her tahmin modeli için sabit bir vurgu rengi — hem tahmin çizgisinde
/// (CandlestickChart) hem model seçim butonlarında (HomeScreen) aynı renk
/// kullanılsın diye paylaşılan tek kaynak. Yeni bir renk eklemek yerine
/// zaten paletteki (SMA/EMA/MACD) renkler yeniden kullanılıyor.
Color forecastModelColor(ForecastModelType model) => switch (model) {
      ForecastModelType.gbm => AppColors.cyan500,
      ForecastModelType.ou => AppColors.amber500,
      ForecastModelType.trend => AppColors.fuchsia600,
    };

// "Tarihsel Benzerlik" özelliğinin en fazla 3 Hayalet Çizgisi için — model
// tahminlerinden (forecastModelColor) kasıtlı olarak ayrı bir palet:
// bunlar bir matematiksel modelin değil, geçmişteki 3 farklı dönemin
// izdüşümü, birbirine karışmamalı. Zaten paletteki renkler yeniden
// kullanılıyor, sırayla döngüsel (bkz. ghostLineColor).
const _ghostLineColors = [AppColors.slate100, AppColors.cyan500, AppColors.amber500];

Color ghostLineColor(int index) => _ghostLineColors[index % _ghostLineColors.length];

/// Bir "Olasılık Isı Konisi" katmanının rengi + opaklığı — bkz.
/// [probabilityFanBands] ve candlestick_chart.dart `_paintProbabilityFan`.
/// [label]/[commentary] koninin üzerinde fare gezdirildiğinde açılan
/// mini tooltip'te gösterilir (bkz. candlestick_chart.dart
/// `_ForecastBandTooltip`) — her renk tonunun kendi, birbirinden farklı
/// yorumu olsun diye rengin kendisiyle birlikte burada tutuluyor.
class ProbabilityFanBand {
  final Color color;
  final double alpha;
  final String label;
  final String commentary;
  const ProbabilityFanBand(this.color, this.alpha, this.label, this.commentary);
}

/// 5 katmanlı Olasılık Isı Konisi'nin sabit renk/opaklık paleti — sırasıyla
/// en alttan (p0) en üste (p100) doğru. Opaklıklar %30-%60 aralığında
/// (kullanıcı isteği: arka plandaki grid rahatça görülebilsin); merkez
/// katman (p40-p60, "en yüksek olasılık") en yüksek opaklıkla hafifçe öne
/// çıkarılıyor. Üst dilim (%60-%100) tek renkle gösteriliyor — spec'te
/// %60-%80 (Açık Yeşil) tanımlanıp %80-%100 boş bırakılmıştı, kullanıcı
/// onayıyla Açık Yeşil %100'e kadar genişletildi (aksi halde koninin en
/// üst %20'si renksiz kalırdı).
const probabilityFanBands = [
  ProbabilityFanBand(
    Color(0xFFB71C1C), 0.45, // p0-p10: Koyu Kırmızı (dip)
    'Uç Kötümser Senaryo (%0-%10)',
    'Fiyatın bu bölgede kalma olasılığı çok düşük, ama gerçekleşirse '
        'ciddi bir değer kaybı anlamına gelir. Modelin ürettiği en '
        'karamsar ihtimallerden biri.',
  ),
  ProbabilityFanBand(
    Color(0xFFE57373), 0.35, // p10-p30: Açık Kırmızı
    'Zayıf Senaryo (%10-%30)',
    'Fiyatın baskı altında kalıp orta (medyan) tahminin belirgin şekilde '
        'altında seyretme ihtimalini gösterir.',
  ),
  ProbabilityFanBand(
    Color(0xFF9E9E9E), 0.30, // p30-p40: Gri (nötr)
    'Nötr Bölge (%30-%40)',
    'Belirgin bir yön sinyali yok; fiyatın orta senaryonun hafifçe '
        'altında, dengeli bir seyir izleme ihtimali.',
  ),
  ProbabilityFanBand(
    Color(0xFF1B5E20), 0.55, // p40-p60: Koyu Yeşil (merkez)
    'En Olası Senaryo (%40-%60)',
    'Modelin ürettiği patikaların çoğunun toplandığı bölge — fiyatın '
        'medyan tahmine en yakın, gerçekleşme olasılığı en yüksek aralığı.',
  ),
  ProbabilityFanBand(
    Color(0xFF81C784), 0.35, // p60-p100: Açık Yeşil
    'İyimser Senaryo (%60-%100)',
    'Fiyatın orta tahminin üzerine çıkıp güçlü bir yükseliş sergileme '
        'ihtimalini temsil eder.',
  ),
];
