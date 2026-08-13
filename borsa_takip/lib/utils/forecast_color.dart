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
