import 'package:flutter/material.dart';

/// CLAUDE.md "UI/UX Tasarım Kuralları" → "Modern BIST/Borsa Analitik (Koyu &
/// Tech Tema)"ndaki Tailwind `slate`/`emerald`/`cyan`/`rose`/`fuchsia`
/// paletinin Flutter karşılıkları. Çoğu yerde bunlara doğrudan değil,
/// `main.dart`'ta bu renklerle kurulan `ThemeData` üzerinden erişilir;
/// burası tema kurulumunun ve gradyan/glow gölgesi gibi tema kapsamına
/// girmeyen (ör. `GlassCard`, mum grafiği) durumların tek kaynağı.
class AppColors {
  AppColors._();

  // Arka planlar (madde 1: `bg-slate-950`, kart `bg-slate-900/60`,
  // `border-slate-800/80`).
  static const slate950 = Color(0xFF020617);
  static const slate900 = Color(0xFF0F172A);
  static const slate800 = Color(0xFF1E293B);

  // Tipografi (madde 3: veri metni `text-slate-100`, etiket `text-slate-400`).
  static const slate400 = Color(0xFF94A3B8);
  static const slate100 = Color(0xFFF1F5F9);

  // Ana vurgu / Yükseliş: `from-emerald-400 to-cyan-500` (madde 2).
  static const emerald400 = Color(0xFF34D399);
  static const cyan500 = Color(0xFF06B6D4);

  // İkincil vurgu / Düşüş: `from-rose-500 to-fuchsia-600` (madde 2).
  static const rose500 = Color(0xFFF43F5E);
  static const fuchsia600 = Color(0xFFC026D3);

  // Mum grafiğindeki SMA/EMA overlay çizgileri için — yükseliş/düşüş
  // renkleriyle (emerald/rose) karışmasın diye üçüncü, nötr bir vurgu.
  static const amber500 = Color(0xFFF59E0B);

  static const bullishGradient = LinearGradient(
    colors: [emerald400, cyan500],
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
  );
  static const bearishGradient = LinearGradient(
    colors: [rose500, fuchsia600],
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
  );

  /// Kart/rozet/grafik gibi öne çıkan elemanlar için "tech glow" gölgesi
  /// (madde 2: `shadow-[0_0_15px_rgba(color,0.15)]`). `bullish: false` için
  /// rose glow döner.
  static List<BoxShadow> glow({bool bullish = true}) {
    final color = bullish ? emerald400 : rose500;
    return [
      BoxShadow(color: color.withValues(alpha: 0.15), blurRadius: 15),
    ];
  }

  /// Cam efektli kart border'ı (madde 1: `border-slate-800/80`).
  static final glassBorder = Border.all(color: slate800.withValues(alpha: 0.8));

  /// Cam efektli kart arka planı (madde 1: `bg-slate-900/60`).
  static final glassFill = slate900.withValues(alpha: 0.6);
}
