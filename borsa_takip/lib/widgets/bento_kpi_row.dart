import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/candle.dart';
import '../theme/app_colors.dart';
import '../utils/price_format.dart';
import 'glass_card.dart';

/// Grafik sekmesinin "bento" özet şeridi — hero mum grafiğinin üstünde, o an
/// ekranda gösterilen aralıktan türetilen 4 KPI karosu. Hepsi zaten elde olan
/// `result.candles`'tan hesaplanıyor, ek bir API çağrısı gerektirmiyor. Dar
/// ekranlarda 2, geniş ekranlarda 4 kolona düşen, sabit genişlikte `SizedBox`
/// karolarla bir `Wrap` — bilerek `GridView` DEĞİL: `GridView` (shrinkWrap +
/// NeverScrollableScrollPhysics ile bile) kendi `Scrollable`'ını oluşturuyor,
/// ve fare tekerleği olayları Flutter'da en içteki `Scrollable`'a saplanıp
/// dışarıdaki sayfa kaydırıcısına (`SingleChildScrollView`) hiç sıçramıyor —
/// bu yüzden imleç KPI karolarının üstündeyken tüm sayfa kaydırma donuyormuş
/// gibi görünüyordu (canlı doğrulamada bulundu, bkz. HomeScreen'in bento
/// düzeni denemesi). `Wrap`'in kendi `Scrollable`'ı olmadığından bu sorun
/// tamamen ortadan kalkıyor.
class BentoKpiRow extends StatelessWidget {
  final CandleResult result;

  const BentoKpiRow({super.key, required this.result});

  @override
  Widget build(BuildContext context) {
    final candles = result.candles;
    if (candles.isEmpty) return const SizedBox.shrink();

    final first = candles.first;
    final last = candles.last;
    final totalChangePct =
        first.open == 0 ? 0.0 : (last.close - first.open) / first.open * 100;
    final isUp = totalChangePct >= 0;
    final trendColor = isUp ? AppColors.emerald400 : AppColors.rose500;

    final periodHigh = candles.reduce((a, b) => a.high > b.high ? a : b);
    // Aynı "en düşük" mantığı CandleTable'da da var (bkz. widgets/candle_table.dart)
    // — bu ekranın kendi başlığı "Aylık En Düşük Değerler" olduğundan burada
    // da bir karo olarak öne çıkarılıyor.
    final periodLow = candles.reduce((a, b) => a.low < b.low ? a : b);
    final hasVolume = candles.any((c) => c.volume != null);
    final totalVolume = candles.fold<double>(0, (sum, c) => sum + (c.volume ?? 0));

    return LayoutBuilder(
      builder: (context, constraints) {
        const spacing = 12.0;
        final crossAxisCount = constraints.maxWidth >= 640 ? 4 : 2;
        final tileWidth =
            (constraints.maxWidth - spacing * (crossAxisCount - 1)) / crossAxisCount;
        // Sabit bir en-boy oranı (eski GridView'in childAspectRatio: 2.1'i)
        // YOK bilerek — bu karo artık HomeScreen'in bento düzeninde tam sayfa
        // genişliği yerine hero sütununun (8/12) sadece bir kısmını kaplıyor,
        // dolayısıyla dar ekranlarda sabit bir oran metnin (etiket+değer+alt
        // başlık, 3 satır) sığması için gereken minimum yüksekliğin altına
        // düşüp RenderFlex taşmasına yol açabiliyordu (canlı doğrulamada
        // bulundu). Sadece genişliği sabitleyip yüksekliği içeriğe bırakmak
        // bunu her genişlikte kalıcı olarak önlüyor.
        Widget tile(Widget child) => SizedBox(width: tileWidth, child: child);

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            tile(_KpiTile(
              icon: isUp ? Icons.trending_up : Icons.trending_down,
              iconColor: trendColor,
              label: 'SON KAPANIŞ',
              value: '${formatPrice(last.close)} ${result.currency}',
              subtitle: '${isUp ? '▲' : '▼'} '
                  '${isUp ? '+' : ''}${totalChangePct.toStringAsFixed(2)}% (dönem)',
              subtitleColor: trendColor,
            )),
            tile(_KpiTile(
              icon: Icons.north,
              iconColor: AppColors.emerald400,
              label: 'DÖNEM YÜKSEK',
              value: '${formatPrice(periodHigh.high)} ${result.currency}',
              subtitle: periodHigh.period,
            )),
            tile(_KpiTile(
              icon: Icons.south,
              iconColor: AppColors.rose500,
              label: 'DÖNEM DÜŞÜK',
              value: '${formatPrice(periodLow.low)} ${result.currency}',
              subtitle: periodLow.period,
            )),
            if (hasVolume)
              tile(_KpiTile(
                icon: Icons.bar_chart,
                iconColor: AppColors.cyan500,
                label: 'TOPLAM HACİM',
                value: formatCompact(totalVolume),
                subtitle: '${candles.length} mum',
              ))
            else
              tile(_KpiTile(
                icon: Icons.candlestick_chart,
                iconColor: AppColors.cyan500,
                label: 'MUM SAYISI',
                value: '${candles.length}',
                subtitle: '${first.period} – ${last.period}',
              )),
          ],
        );
      },
    );
  }
}

class _KpiTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final String value;
  final String subtitle;
  final Color? subtitleColor;

  const _KpiTile({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.value,
    required this.subtitle,
    this.subtitleColor,
  });

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: iconColor, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label, style: Theme.of(context).textTheme.labelSmall),
                const SizedBox(height: 2),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.robotoMono(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.slate100,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, color: subtitleColor ?? AppColors.slate400),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
