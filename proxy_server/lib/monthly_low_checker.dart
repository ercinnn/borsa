import 'package:http/http.dart' as http;

import 'price_format.dart';
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

  // Sembolleri küçük gruplar halinde eşzamanlı işliyoruz: tamamen sıralı
  // (300ms/sembol) büyük bir watchlist'te taramayı dakikalarca sürdürüyordu;
  // grup içi eşzamanlılık bunu ~_batchSize kat hızlandırırken, gruplar
  // arasındaki gecikme Yahoo'yu tek seferde N isteğe boğmamak için korunuyor.
  static const _batchSize = 4;

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
    final entries = usersBySymbol.entries.toList();
    for (var i = 0; i < entries.length; i += _batchSize) {
      final batch = entries.sublist(
        i,
        (i + _batchSize) > entries.length ? entries.length : i + _batchSize,
      );
      final results = await Future.wait(batch.map((entry) async {
        try {
          return await _checkSymbol(entry.key, entry.value);
        } catch (_) {
          // Tek bir sembolün hatası tüm taramayı durdurmasın.
          return 0;
        }
      }));
      created += results.fold(0, (a, b) => a + b);
      if (i + _batchSize < entries.length) {
        await Future.delayed(const Duration(milliseconds: 300));
      }
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

    final alreadyNotified =
        await notifications.existingUserIdsFor(symbol, dateKey, userIds);
    final toNotify = userIds.where((id) => !alreadyNotified.contains(id));

    final createdAt = DateTime.now().toIso8601String();
    final items = [
      for (final userId in toNotify)
        {
          'id': '$userId-$symbol-$dateKey-${DateTime.now().millisecondsSinceEpoch}',
          'user_id': userId,
          'symbol': symbol,
          'price': today.low,
          'currency': data.currency,
          'date': dateKey,
          'createdAt': createdAt,
          'message':
              '$symbol bu ayki en düşük değerine ulaştı: ${formatPrice(today.low)} ${data.currency}',
        },
    ];
    await notifications.addAll(items);
    return items.length;
  }

  String _dateKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}
