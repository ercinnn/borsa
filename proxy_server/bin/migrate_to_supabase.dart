// Tek seferlik migrasyon: yerel data/watchlist.json ve data/notifications.json
// dosyalarındaki mevcut veriyi Supabase'e aktarır. Tekrar çalıştırmak
// güvenlidir (ignore-duplicates ile idempotent).
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../lib/env.dart';
import '../lib/supabase_client.dart';

Future<void> main() async {
  final config = SupabaseConfig(
    url: requireEnv('SUPABASE_URL'),
    serviceKey: requireEnv('SUPABASE_SERVICE_KEY'),
  );
  final client = http.Client();

  final watchlistFile = File('data/watchlist.json');
  if (await watchlistFile.exists()) {
    final symbols =
        (jsonDecode(await watchlistFile.readAsString()) as List).cast<String>();
    final table = SupabaseTable(client, config, 'watchlist');
    await table.insert(
      [for (final s in symbols) {'symbol': s}],
      onConflict: 'symbol',
      prefer: 'resolution=ignore-duplicates,return=minimal',
    );
    print('watchlist: ${symbols.length} sembol gönderildi.');
  } else {
    print('data/watchlist.json bulunamadı, atlanıyor.');
  }

  final notificationsFile = File('data/notifications.json');
  if (await notificationsFile.exists()) {
    final items = (jsonDecode(await notificationsFile.readAsString()) as List)
        .cast<Map<String, dynamic>>();
    final table = SupabaseTable(client, config, 'notifications');
    await table.insert(
      items,
      onConflict: 'id',
      prefer: 'resolution=ignore-duplicates,return=minimal',
    );
    print('notifications: ${items.length} bildirim gönderildi.');
  } else {
    print('data/notifications.json bulunamadı, atlanıyor.');
  }

  client.close();
}
