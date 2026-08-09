import 'dart:convert';

import 'package:http/http.dart' as http;

/// CoinGecko'nun ücretsiz, anahtar gerektirmeyen piyasa verisi ucundan
/// piyasa değerine göre ilk [count] kriptoyu çekip Yahoo Finance uyumlu
/// "SEMBOL-USD" formatında döndürür.
Future<List<String>> fetchTopCryptoSymbols(http.Client client, int count) async {
  final uri = Uri.https('api.coingecko.com', '/api/v3/coins/markets', {
    'vs_currency': 'usd',
    'order': 'market_cap_desc',
    'per_page': '$count',
    'page': '1',
    'sparkline': 'false',
  });

  final resp = await client.get(uri);
  if (resp.statusCode != 200) {
    throw Exception('CoinGecko isteği başarısız (${resp.statusCode})');
  }

  final list = jsonDecode(resp.body) as List;
  final symbols = <String>{};
  for (final item in list) {
    final symbol = (item as Map<String, dynamic>)['symbol'] as String?;
    if (symbol == null || symbol.trim().isEmpty) continue;
    symbols.add('${symbol.trim().toUpperCase()}-USD');
  }
  return symbols.toList();
}
