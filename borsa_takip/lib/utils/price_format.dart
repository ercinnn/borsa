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
