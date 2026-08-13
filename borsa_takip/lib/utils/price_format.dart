/// Bir fiyatı okunur biçimde metne çevirir: varsayılan olarak noktadan
/// sonra 4 basamak gösterilir. İlk 4 basamağın tamamı sıfırsa 6 basamağa
/// çıkılır; 6 basamak da yetmezse (çok küçük piyasa değerli kripto paralar,
/// ör. 0.0000000078), basamak sayısı sıfırlardan sonra en az iki anlamlı
/// basamak görünene kadar artırılır. `proxy_server/lib/price_format.dart`
/// ile aynı mantık — iki proje ayrı pub paketi olduğundan kod paylaşılamıyor,
/// biri değişirse diğeri de güncellenmeli.
String formatPrice(num value) {
  if (value == 0 || !value.isFinite) return value.toStringAsFixed(4);

  final sign = value.isNegative ? '-' : '';
  final abs = value.abs();

  var decimals = 4;
  while (true) {
    final fixed = abs.toStringAsFixed(decimals);
    final parts = fixed.split('.');
    if (parts[0] != '0') {
      // 1 ve üzeri değerlerde basamak uzatmaya gerek yok (yuvarlama ile
      // 1'e ulaşan 0.9999... gibi değerler de bu yolla yakalanır).
      return '$sign${abs.toStringAsFixed(4)}';
    }
    final fraction = parts[1];
    final firstSignificant = fraction.indexOf(RegExp(r'[1-9]'));
    final hasEnoughPrecision =
        firstSignificant != -1 && fraction.length - firstSignificant >= 2;
    if (hasEnoughPrecision || decimals >= 18) {
      return '$sign$fixed';
    }
    decimals = decimals < 6 ? 6 : decimals + 1;
  }
}

/// Büyük hacim/tutar değerlerini K/M/B ekleriyle kısaltır (ör. 2.4M).
/// `widgets/candlestick_chart.dart`'ın hacim panel/ekseni ile
/// `widgets/bento_kpi_row.dart`'ın "Toplam Hacim" karosu arasında paylaşılır.
String formatCompact(double value) {
  final abs = value.abs();
  final sign = value.isNegative ? '-' : '';
  if (abs >= 1e9) return '$sign${(abs / 1e9).toStringAsFixed(1)}B';
  if (abs >= 1e6) return '$sign${(abs / 1e6).toStringAsFixed(1)}M';
  if (abs >= 1e3) return '$sign${(abs / 1e3).toStringAsFixed(1)}K';
  return '$sign${abs.toStringAsFixed(0)}';
}
