import 'package:flutter/material.dart';

import '../models/candle.dart';

class CandleTable extends StatelessWidget {
  final CandleResult result;

  const CandleTable({super.key, required this.result});

  @override
  Widget build(BuildContext context) {
    if (result.candles.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Text('Seçilen tarih aralığında veri bulunamadı.'),
      );
    }

    final lowest = result.candles.reduce((a, b) => a.low < b.low ? a : b);

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columns: const [
          DataColumn(label: Text('Dönem')),
          DataColumn(label: Text('En Düşük Değer'), numeric: true),
        ],
        rows: [
          for (final row in result.candles)
            DataRow(
              color: row.period == lowest.period
                  ? WidgetStateProperty.all(
                      Theme.of(context).colorScheme.errorContainer.withValues(alpha: 0.4),
                    )
                  : null,
              cells: [
                DataCell(Text(row.period)),
                DataCell(Text(
                  '${row.low.toStringAsFixed(2)} ${result.currency}',
                  style: row.period == lowest.period
                      ? const TextStyle(fontWeight: FontWeight.bold)
                      : null,
                )),
              ],
            ),
        ],
      ),
    );
  }
}
