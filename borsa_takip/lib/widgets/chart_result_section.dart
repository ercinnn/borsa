import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/candle.dart';
import '../models/interval.dart';
import '../theme/app_colors.dart';
import 'candle_table.dart';
import 'candlestick_chart.dart';
import 'gradient_button.dart';

/// HomeScreen ve TrackingScreen'in ortak render bloğu: interval seçim
/// chip'leri, tarih aralığı/yenile butonları, loading/error durumu ve sonuç
/// geldiğinde mum grafiği + tablo. Sembol seçme UI'ı (arama/favoriler
/// çubuğu ya da kalıcı sembol yükleme metni) ekrana özgü olduğundan bu
/// widget'ın dışında, çağıran taraf tarafından ele alınıyor.
class ChartResultSection extends StatelessWidget {
  final List<ChartInterval> intervals;
  final ChartInterval selectedInterval;
  final ValueChanged<ChartInterval> onSelectInterval;
  final DateTimeRange? dateRange;
  final DateFormat dateFormat;
  final VoidCallback onPickDateRange;
  final String fetchLabel;
  final IconData fetchIcon;
  final VoidCallback? onFetch;
  final bool loading;
  final String? error;
  final CandleResult? result;
  // Seçilen aralıkta yeterli mum yoksa (bkz. utils/candle_padding.dart)
  // CandlestickChart'a iletilir — orada soluk/gölgeli çizilir.
  final int paddingCandleCount;
  final List<Widget> leadingActions;

  const ChartResultSection({
    super.key,
    required this.intervals,
    required this.selectedInterval,
    required this.onSelectInterval,
    required this.dateRange,
    required this.dateFormat,
    required this.onPickDateRange,
    required this.fetchLabel,
    required this.fetchIcon,
    required this.onFetch,
    required this.loading,
    required this.error,
    required this.result,
    this.paddingCandleCount = 0,
    this.leadingActions = const [],
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final interval in intervals)
              ChoiceChip(
                label: Text(interval.label),
                selected: selectedInterval == interval,
                onSelected: (_) => onSelectInterval(interval),
              ),
          ],
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            ...leadingActions,
            OutlinedButton.icon(
              onPressed: onPickDateRange,
              icon: const Icon(Icons.date_range),
              label: Text(
                dateRange == null
                    ? 'Tarih aralığı seç'
                    : '${dateFormat.format(dateRange!.start)} - '
                        '${dateFormat.format(dateRange!.end)}',
              ),
            ),
            GradientButton(
              onPressed: onFetch,
              icon: Icon(fetchIcon),
              label: fetchLabel,
            ),
          ],
        ),
        const SizedBox(height: 24),
        if (loading) const Center(child: CircularProgressIndicator()),
        if (error != null)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.rose500.withValues(alpha: 0.15),
              border: Border.all(color: AppColors.rose500.withValues(alpha: 0.4)),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(error!, style: const TextStyle(color: AppColors.slate100)),
          ),
        if (result != null) ...[
          CandlestickChart(result: result!, paddingCandleCount: paddingCandleCount),
          const SizedBox(height: 16),
          CandleTable(result: result!),
        ],
      ],
    );
  }
}
