import 'package:http/http.dart' as http;

import 'store.dart';
import 'yahoo_client.dart';

/// İzleme listesindeki her sembol için içinde bulunulan ayın en düşük
/// değerine yeni bir dip oluşup oluşmadığını kontrol eder ve bildirim
/// üretir.
class MonthlyLowChecker {
  final http.Client client;
  final WatchlistStore watchlist;
  final NotificationStore notifications;

  MonthlyLowChecker(this.client, this.watchlist, this.notifications);

  Future<int> checkAll() async {
    var created = 0;
    for (final symbol in watchlist.symbols) {
      try {
        final didNotify = await _checkSymbol(symbol);
        if (didNotify) created++;
      } catch (_) {
        // Tek bir sembolün hatası tüm taramayı durdurmasın.
      }
      await Future.delayed(const Duration(milliseconds: 300));
    }
    return created;
  }

  Future<bool> _checkSymbol(String symbol) async {
    final now = DateTime.now().toUtc();
    final monthStart = DateTime.utc(now.year, now.month, 1);
    final period1 = monthStart.millisecondsSinceEpoch ~/ 1000;
    final period2 = now.millisecondsSinceEpoch ~/ 1000 + 86400;

    final data = await fetchChart(client, symbol, period1, period2, '1d');
    if (data.candles.length < 2) return false;

    final today = data.candles.last;
    final dateKey = _dateKey(today.date);
    if (notifications.existsFor(symbol, dateKey)) return false;

    final priorLow = data.candles
        .sublist(0, data.candles.length - 1)
        .map((c) => c.low)
        .reduce((a, b) => a < b ? a : b);

    if (today.low > priorLow) return false;

    await notifications.add({
      'id': '$symbol-$dateKey-${DateTime.now().millisecondsSinceEpoch}',
      'symbol': symbol,
      'price': today.low,
      'currency': data.currency,
      'date': dateKey,
      'createdAt': DateTime.now().toIso8601String(),
      'message':
          '$symbol bu ayki en düşük değerine ulaştı: ${today.low.toStringAsFixed(4)} ${data.currency}',
    });
    return true;
  }

  String _dateKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}
