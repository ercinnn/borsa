import 'package:http/http.dart' as http;

import 'store.dart';
import 'yahoo_client.dart';

/// İzleme listesindeki her sembol için içinde bulunulan ayın en düşük
/// değerine yeni bir dip oluşup oluşmadığını kontrol eder ve bildirim
/// üretir. Çok kullanıcılı: aynı sembolü birden fazla kullanıcı izliyorsa
/// Yahoo'dan yalnızca bir kez çekilir, sonuç izleyen her kullanıcı için
/// ayrı ayrı değerlendirilir (kendi bildirimi kendi hesabına yazılır).
class MonthlyLowChecker {
  final http.Client client;
  final WatchlistStore watchlist;
  final NotificationStore notifications;

  MonthlyLowChecker(this.client, this.watchlist, this.notifications);

  Future<int> checkAll() async {
    final rows = await watchlist.allRows();
    final usersBySymbol = <String, List<String>>{};
    for (final row in rows) {
      final userId = row['user_id'] as String?;
      if (userId == null) continue; // henüz kimse tarafından sahiplenilmemiş
      final symbol = row['symbol'] as String;
      usersBySymbol.putIfAbsent(symbol, () => []).add(userId);
    }

    var created = 0;
    for (final entry in usersBySymbol.entries) {
      try {
        created += await _checkSymbol(entry.key, entry.value);
      } catch (_) {
        // Tek bir sembolün hatası tüm taramayı durdurmasın.
      }
      await Future.delayed(const Duration(milliseconds: 300));
    }
    return created;
  }

  Future<int> _checkSymbol(String symbol, List<String> userIds) async {
    final now = DateTime.now().toUtc();
    final monthStart = DateTime.utc(now.year, now.month, 1);
    final period1 = monthStart.millisecondsSinceEpoch ~/ 1000;
    final period2 = now.millisecondsSinceEpoch ~/ 1000 + 86400;

    final data = await fetchChart(client, symbol, period1, period2, '1d');
    if (data.candles.length < 2) return 0;

    final today = data.candles.last;
    final dateKey = _dateKey(today.date);

    final priorLow = data.candles
        .sublist(0, data.candles.length - 1)
        .map((c) => c.low)
        .reduce((a, b) => a < b ? a : b);

    if (today.low > priorLow) return 0;

    var created = 0;
    for (final userId in userIds) {
      if (await notifications.existsFor(userId, symbol, dateKey)) continue;
      await notifications.add(userId, {
        'id': '$userId-$symbol-$dateKey-${DateTime.now().millisecondsSinceEpoch}',
        'symbol': symbol,
        'price': today.low,
        'currency': data.currency,
        'date': dateKey,
        'createdAt': DateTime.now().toIso8601String(),
        'message':
            '$symbol bu ayki en düşük değerine ulaştı: ${today.low.toStringAsFixed(4)} ${data.currency}',
      });
      created++;
    }
    return created;
  }

  String _dateKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}
