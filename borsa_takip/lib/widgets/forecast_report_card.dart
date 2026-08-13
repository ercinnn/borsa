import 'package:flutter/material.dart';

import '../models/forecast.dart';
import '../theme/app_colors.dart';
import '../utils/forecast_color.dart';
import '../utils/price_format.dart';
import 'glass_card.dart';

/// Grafiğin hemen altında, GBM/OU Olasılık Isı Konisi aktifken görünen
/// "Yapay Zeka / Kantitatif Gelecek Raporu" — 1000 Monte Carlo patikasının
/// ufuk sonu (bkz. ForecastStats) dağılımından türetilen dört metinsel
/// yorum + genişletildiğinde ham istatistik parametreleri. Trend modelinde
/// ya da tahmin yokken (`forecast.fan == null`) hiçbir şey render etmez —
/// deterministik bir projeksiyonun simülasyon dağılımı, dolayısıyla bu
/// istatistiklerin matematiksel temeli yok.
class ForecastReportCard extends StatelessWidget {
  final ForecastResult forecast;
  final String currency;

  const ForecastReportCard({super.key, required this.forecast, required this.currency});

  @override
  Widget build(BuildContext context) {
    final fan = forecast.fan;
    if (fan == null || fan.isEmpty) return const SizedBox.shrink();
    final stats = fan.stats;
    final color = forecastModelColor(forecast.model);
    final strategy = _Strategy.fromWinProbability(stats.winProbabilityPercent);

    return GlassCard(
      padding: EdgeInsets.zero,
      // ExpansionTile kendi Divider'larını ekliyor; GlassCard'ın kendi
      // yarı saydam/blur zemini üzerinde bu varsayılan çizgiler fazla
      // baskın durduğundan burada şeffaflaştırılıyor.
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          leading: Icon(Icons.auto_graph, color: color),
          title: Text(
            'Yapay Zeka / Kantitatif Gelecek Raporu',
            style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.slate100),
          ),
          subtitle: Text(
            strategy.label,
            style: TextStyle(color: strategy.color, fontWeight: FontWeight.w600, fontSize: 12),
          ),
          collapsedIconColor: AppColors.slate400,
          iconColor: AppColors.slate400,
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          children: [
            _ReportLine(
              label: 'Beklenen Trend',
              text: 'Önümüzdeki 30 gün içinde %50 olasılıkla hedeflenen fiyat: '
                  '${formatPrice(stats.medianTarget)} $currency. (En yüksek boğa hedefi: '
                  '${formatPrice(stats.bullTarget)} $currency, en düşük ayı hedefi: '
                  '${formatPrice(stats.bearTarget)} $currency.)',
            ),
            _ReportLine(
              label: 'Kazanma Olasılığı',
              text: 'Fiyatın mevcut seviyenin üzerinde kapatma olasılığı '
                  '%${stats.winProbabilityPercent.toStringAsFixed(0)}.',
            ),
            _ReportLine(
              label: 'Risk Değerlendirmesi (VaR)',
              text: '%95 güven aralığında yaşanabilecek maksimum olası kayıp '
                  '(Value at Risk): %${stats.valueAtRisk95Percent.toStringAsFixed(1)}.',
            ),
            _ReportLine(
              label: 'Özet Strateji Yorumu',
              text: strategy.label,
              valueColor: strategy.color,
            ),
            const SizedBox(height: 12),
            const Divider(color: AppColors.slate800),
            const SizedBox(height: 4),
            Text('DETAYLI İSTATİSTİK PARAMETRELERİ',
                style: Theme.of(context).textTheme.labelSmall),
            const SizedBox(height: 10),
            Wrap(
              spacing: 20,
              runSpacing: 10,
              children: [
                _StatChip(label: 'Ortalama', value: '${formatPrice(stats.mean)} $currency'),
                _StatChip(label: 'Volatilite', value: '%${stats.volatilityPercent.toStringAsFixed(1)}'),
                _StatChip(label: 'VaR (%95)', value: '%${stats.valueAtRisk95Percent.toStringAsFixed(1)}'),
                _StatChip(label: 'Çarpıklık (Skewness)', value: stats.skewness.toStringAsFixed(2)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Strategy {
  final String label;
  final Color color;
  const _Strategy(this.label, this.color);

  factory _Strategy.fromWinProbability(double winProbabilityPercent) {
    if (winProbabilityPercent > 55) return const _Strategy('Pozitif Trend Eğilimi', AppColors.emerald400);
    if (winProbabilityPercent >= 45) return const _Strategy('Yatay / Kararsız Piyasa', AppColors.slate400);
    return const _Strategy('Baskı / Düşüş Riski', AppColors.rose500);
  }
}

class _ReportLine extends StatelessWidget {
  final String label;
  final String text;
  final Color? valueColor;

  const _ReportLine({required this.label, required this.text, this.valueColor});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: RichText(
        text: TextSpan(
          children: [
            TextSpan(
              text: '$label: ',
              style: const TextStyle(
                  color: AppColors.slate400, fontWeight: FontWeight.w600, fontSize: 13),
            ),
            TextSpan(
              text: text,
              style: TextStyle(color: valueColor ?? AppColors.slate100, fontSize: 13, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final String label;
  final String value;

  const _StatChip({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label.toUpperCase(),
            style: const TextStyle(fontSize: 10, color: AppColors.slate400, letterSpacing: 0.5)),
        const SizedBox(height: 2),
        Text(value,
            style: const TextStyle(
                fontSize: 14, color: AppColors.slate100, fontWeight: FontWeight.w600)),
      ],
    );
  }
}
