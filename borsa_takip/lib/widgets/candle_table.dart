import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/candle.dart';
import '../theme/app_colors.dart';
import '../utils/price_format.dart';

class CandleTable extends StatelessWidget {
  final CandleResult result;

  const CandleTable({super.key, required this.result});

  @override
  Widget build(BuildContext context) {
    if (result.candles.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Text('Seçilen tarih aralığında veri bulunamadı.',
            style: TextStyle(color: AppColors.slate400)),
      );
    }

    final lowest = result.candles.reduce((a, b) => a.low < b.low ? a : b);
    final headerStyle = Theme.of(context).textTheme.labelSmall;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columns: [
          DataColumn(label: Text('DÖNEM', style: headerStyle)),
          DataColumn(label: Text('EN DÜŞÜK DEĞER', style: headerStyle), numeric: true),
        ],
        rows: [
          for (final row in result.candles)
            DataRow(
              color: row.period == lowest.period
                  ? WidgetStateProperty.all(AppColors.rose500.withValues(alpha: 0.12))
                  : null,
              cells: [
                DataCell(Text(row.period,
                    style: const TextStyle(color: AppColors.slate100))),
                DataCell(Text(
                  '${formatPrice(row.low)} ${result.currency}',
                  style: GoogleFonts.robotoMono(
                    fontWeight: row.period == lowest.period
                        ? FontWeight.w700
                        : FontWeight.w600,
                    color: row.period == lowest.period
                        ? AppColors.rose500
                        : AppColors.slate100,
                  ),
                )),
              ],
            ),
        ],
      ),
    );
  }
}
