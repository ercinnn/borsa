import 'package:flutter/material.dart';

/// `RootShell`'in alt gezinme çubuğundaki bir sekmenin sabit kimliği
/// (`key`), o çubuktaki kısa etiketi (`navLabel`), AppBar başlığı
/// (`title`) ve ikonu. Hem `main.dart`'taki `ScrollableBottomNav`/
/// `IndexedStack` sıralaması hem de Ayarlar sekmesindeki aç/kapa listesi
/// bu tek listeyi kullanır — sekme meta verisi üç ayrı yerde tekrar
/// tanımlanmasın diye.
class RootTab {
  final String key;
  final String navLabel;
  final String title;
  final IconData icon;

  const RootTab({
    required this.key,
    required this.navLabel,
    required this.title,
    required this.icon,
  });
}

/// Ayarlar sekmesinden kapatılabilen sekmeler, alt gezinme çubuğundaki
/// sırayla. Ayarlar sekmesinin kendisi ([settingsRootTab]) kasıtlı olarak
/// bu listede değil — kapatılamaz, aksi halde kullanıcı sekmeleri tekrar
/// açacak yeri kaybeder.
const List<RootTab> toggleableRootTabs = [
  RootTab(
    key: 'chart',
    navLabel: 'Grafik',
    title: 'Grafik ve Aylık En Düşük Değerler',
    icon: Icons.show_chart,
  ),
  RootTab(
    key: 'notifications',
    navLabel: 'Bildirimler',
    title: 'Bildirimler',
    icon: Icons.notifications,
  ),
  RootTab(key: 'favorites', navLabel: 'Favoriler', title: 'Favoriler', icon: Icons.star),
  RootTab(key: 'tracking', navLabel: 'Takip', title: 'Takip', icon: Icons.insights),
  RootTab(key: 'technical', navLabel: 'Teknik', title: 'Teknik', icon: Icons.query_stats),
  RootTab(
    key: 'comparison',
    navLabel: 'Karşılaştır',
    title: 'Karşılaştır',
    icon: Icons.compare_arrows,
  ),
  RootTab(key: 'portfolio', navLabel: 'Portföy', title: 'Portföy', icon: Icons.pie_chart),
  RootTab(key: 'dividend', navLabel: 'Temettü', title: 'Temettü', icon: Icons.payments),
  RootTab(
    key: 'backtest',
    navLabel: 'Backtest',
    title: 'Backtest',
    icon: Icons.history_toggle_off,
  ),
];

const settingsRootTab =
    RootTab(key: 'settings', navLabel: 'Ayarlar', title: 'Ayarlar', icon: Icons.settings);
