enum ChartInterval {
  hourly('60m', 'Saatlik'),
  fourHour('4h', '4 Saatlik'),
  daily('1d', 'Günlük'),
  weekly('1wk', 'Haftalık'),
  monthly('1mo', 'Aylık'),
  quarterly('3mo', '3 Aylık'),
  yearly('12mo', '12 Aylık');

  final String apiValue;
  final String label;

  const ChartInterval(this.apiValue, this.label);

  // Grafik sekmesi: uzun vadeli/tarihsel görünüm için gün içi aralıklar
  // anlamsız (Yahoo intraday geçmişi zaten sadece son ~730 gün ile
  // sınırlı), o yüzden orada sadece bunlar seçilebiliyor.
  static const longTerm = [daily, weekly, monthly, quarterly, yearly];

  // Takip sekmesi: tek bir sembolün güncel/kısa vadeli fiyat hareketini
  // izlemek için.
  static const intraday = [hourly, fourHour, daily];
}
