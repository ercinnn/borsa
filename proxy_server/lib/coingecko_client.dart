import 'dart:convert';

import 'package:http/http.dart' as http;

import 'yahoo_client.dart' show userAgent;

// CoinGecko'nun anahtar gerektirmeyen ücretsiz ucu IP başına sıkı rate limit
// uyguluyor; özellikle Render gibi paylaşımlı bulut IP'lerinden 429 sık
// görülüyor. Sonucu bir süre önbelleğe alıp 429'da kısaca bekleyip yeniden
// deneyerek ve son başarılı sonuca düşerek dayanıklılığı artırıyoruz.
const _cacheTtl = Duration(hours: 1);

List<String>? _cachedSymbols;
int? _cachedCount;
DateTime? _cachedAt;

/// CoinGecko'nun ücretsiz, anahtar gerektirmeyen piyasa verisi ucundan
/// piyasa değerine göre ilk [count] kriptoyu çekip Yahoo Finance uyumlu
/// "SEMBOL-USD" formatında döndürür.
Future<List<String>> fetchTopCryptoSymbols(http.Client client, int count) async {
  final now = DateTime.now();
  if (_cachedSymbols != null &&
      _cachedCount == count &&
      _cachedAt != null &&
      now.difference(_cachedAt!) < _cacheTtl) {
    return _cachedSymbols!;
  }

  final uri = Uri.https('api.coingecko.com', '/api/v3/coins/markets', {
    'vs_currency': 'usd',
    'order': 'market_cap_desc',
    'per_page': '$count',
    'page': '1',
    'sparkline': 'false',
  });

  var resp = await client.get(uri, headers: {'User-Agent': userAgent});
  if (resp.statusCode == 429) {
    await Future.delayed(const Duration(seconds: 5));
    resp = await client.get(uri, headers: {'User-Agent': userAgent});
  }

  if (resp.statusCode != 200) {
    if (_cachedSymbols != null) return _cachedSymbols!;
    throw Exception('CoinGecko isteği başarısız (${resp.statusCode})');
  }

  final list = jsonDecode(resp.body) as List;
  final symbols = <String>{};
  for (final item in list) {
    final symbol = (item as Map<String, dynamic>)['symbol'] as String?;
    if (symbol == null || symbol.trim().isEmpty) continue;
    symbols.add('${symbol.trim().toUpperCase()}-USD');
  }

  final result = symbols.toList();
  _cachedSymbols = result;
  _cachedCount = count;
  _cachedAt = now;
  return result;
}
