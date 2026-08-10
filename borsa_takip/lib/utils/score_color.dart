import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// 0-100 arası "alım puanı"na göre renk: düşük puan kırmızı tonlarından,
/// orta puan gri (nötr), yüksek puan yeşil tonlarına geçen 8 kademeli skala
/// (koyu kırmızı → kırmızı → turuncu → nötr/gri → açık sarı → sarı → açık
/// yeşil → koyu yeşil). Teknik sekmesindeki "Yorum (X/100)" butonu ve
/// Bildirimler sayfasındaki Puan Sıralaması listesi tarafından paylaşılır.
Color scoreColor(int score) {
  if (score < 18) return const Color(0xFF7F1D1D); // koyu kırmızı
  if (score < 30) return AppColors.rose500; // kırmızı
  if (score < 42) return const Color(0xFFF97316); // turuncu
  if (score < 58) return AppColors.slate400; // nötr (gri)
  if (score < 70) return const Color(0xFFFDE047); // açık sarı
  if (score < 82) return const Color(0xFFF59E0B); // sarı
  if (score < 90) return AppColors.emerald400; // açık yeşil
  return const Color(0xFF059669); // koyu yeşil
}

/// [scoreColor]'ın çok uçtaki (çok düşük/çok yüksek) puanlarda "ışıklı"
/// gösterim için ek bir glow gölgesi gerekip gerekmediği.
bool scoreGlows(int score) => score >= 90 || score <= 18;
