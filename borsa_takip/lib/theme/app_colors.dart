import 'package:flutter/material.dart';

/// CLAUDE.md "UI/UX Tasarım Kuralları"ndaki Tailwind `slate` paletinin
/// Flutter karşılıkları. Çoğu yerde bunlara doğrudan değil, `main.dart`'ta
/// bu renklerle kurulan `ThemeData` (textTheme/cardTheme/colorScheme)
/// üzerinden erişilir; burası sadece tema kurulumunun ve özel border/gölge
/// gibi tema kapsamına girmeyen durumların tek kaynağı.
class AppColors {
  AppColors._();

  static const slate50 = Color(0xFFF8FAFC);
  static const slate100 = Color(0xFFF1F5F9);
  static const slate200 = Color(0xFFE2E8F0);
  static const slate400 = Color(0xFF94A3B8);
  static const slate500 = Color(0xFF64748B);
  static const slate900 = Color(0xFF0F172A);
}
