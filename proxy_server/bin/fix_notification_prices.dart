// Tek seferlik düzeltme: monthly_low_checker.dart eskiden bildirim
// mesajlarında sabit toStringAsFixed(4) kullanıyordu, bu da çok küçük
// piyasa değerli kripto paralarda "0.0000" gösteriyordu (bkz.
// price_format.dart). Bu script Supabase'deki mevcut notifications
// satırlarını okuyup mesajı yeni formatPrice() ile yeniden üretir; ham
// `price` sütunu hiç değişmediğinden hesap her zaman doğru veriden
// yapılıyor. Sadece gerçekten değişen mesajlar PATCH edilir, bu yüzden
// tekrar çalıştırmak güvenlidir (idempotent).
import 'package:http/http.dart' as http;

import '../lib/env.dart';
import '../lib/price_format.dart';
import '../lib/supabase_client.dart';

Future<void> main() async {
  final config = SupabaseConfig(
    url: requireEnv('SUPABASE_URL'),
    serviceKey: requireEnv('SUPABASE_SERVICE_KEY'),
  );
  final client = http.Client();
  final table = SupabaseTable(client, config, 'notifications');

  const pageSize = 1000;
  var offset = 0;
  var totalChecked = 0;
  var totalUpdated = 0;

  while (true) {
    final rows = await table.select(
      columns: 'id,symbol,price,currency,message',
      filters: {'order': 'id.asc', 'limit': '$pageSize', 'offset': '$offset'},
    );
    if (rows.isEmpty) break;

    for (final row in rows) {
      final id = row['id'] as String;
      final symbol = row['symbol'] as String;
      final price = row['price'] as num;
      final currency = row['currency'] as String;
      final expected =
          '$symbol bu ayki en düşük değerine ulaştı: ${formatPrice(price)} $currency';
      if (row['message'] != expected) {
        await table.update(
          {'message': expected},
          filters: {'id': 'eq.$id'},
          prefer: 'return=minimal',
        );
        totalUpdated++;
      }
    }
    totalChecked += rows.length;
    if (rows.length < pageSize) break;
    offset += pageSize;
  }

  print('$totalChecked bildirim kontrol edildi, $totalUpdated tanesi düzeltildi.');
  client.close();
}
