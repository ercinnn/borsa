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

// 429'da art arda denenen bekleme süreleri; toplamda ~26sn, bir buton
// tıklamasının makul karşılayabileceği bir üst sınır.
const _retryDelays = [
  Duration(seconds: 3),
  Duration(seconds: 8),
  Duration(seconds: 15),
];

// CoinGecko'nun `/coins/markets` ucunun belgelenmemiş ama canlı doğrulanmış
// üst sınırı: `per_page` 250'yi aşarsa hata DÖNMÜYOR, sessizce varsayılan
// değere (100) düşüyor — `crypto300` preset'i eklendiğinde bu yüzden
// `per_page=300` istemek "300 sembol" yerine sessizce sadece 100 sembol
// (ve zaten watchlist'te olan bir alt küme) döndürüyordu, "0 yeni sembol
// eklendi" olarak fark edildi. `count` bu sınırı aşarsa, her biri en fazla
// bu boyutta sabit `per_page` ile birden fazla sayfa çekip son sayfayı
// ihtiyaç kadar kırpıyoruz — `page` parametresi CoinGecko'da her istekte
// O İSTEĞİN `per_page`'ine göre ofsetleniyor, bu yüzden sayfalar arasında
// `per_page`'i sabit tutmak zorunludur (aksi halde ör. page=2,per_page=50
// rank 251-300 değil rank 51-100 döner).
const _maxPerPage = 250;

/// CoinGecko'nun piyasa verisi ucundan piyasa değerine göre ilk [count]
/// kriptoyu çekip Yahoo Finance uyumlu "SEMBOL-USD" formatında döndürür.
/// [apiKey] verilirse CoinGecko'nun ücretsiz "Demo" plan header'ı
/// (`x-cg-demo-api-key`) eklenir; bu, anahtarsız uca göre çok daha yüksek
/// bir rate limit sağlar. Anahtar yoksa anahtarsız, düşük limitli uç
/// kullanılmaya devam eder.
Future<List<String>> fetchTopCryptoSymbols(
  http.Client client,
  int count, {
  String? apiKey,
}) async {
  final now = DateTime.now();
  if (_cachedSymbols != null &&
      _cachedCount == count &&
      _cachedAt != null &&
      now.difference(_cachedAt!) < _cacheTtl) {
    return _cachedSymbols!;
  }

  final headers = {
    'User-Agent': userAgent,
    if (apiKey != null && apiKey.isNotEmpty) 'x-cg-demo-api-key': apiKey,
  };

  final perPage = count > _maxPerPage ? _maxPerPage : count;
  final totalPages = (count / perPage).ceil();
  final symbols = <String>{};

  for (var page = 1; page <= totalPages; page++) {
    final uri = Uri.https('api.coingecko.com', '/api/v3/coins/markets', {
      'vs_currency': 'usd',
      'order': 'market_cap_desc',
      'per_page': '$perPage',
      'page': '$page',
      'sparkline': 'false',
    });

    var resp = await client.get(uri, headers: headers);
    for (final delay in _retryDelays) {
      if (resp.statusCode != 429) break;
      await Future.delayed(delay);
      resp = await client.get(uri, headers: headers);
    }

    if (resp.statusCode != 200) {
      // Bu sayfa başarısız oldu ama önceki sayfalardan zaten sembol
      // topladıysak (ör. 300 istenip ilk 250 alınabildiyse) elimizdekiyle
      // devam ediyoruz — hepsini atıp statik yedeğe düşmek yerine.
      if (symbols.isNotEmpty) break;
      if (_cachedSymbols != null) return _cachedSymbols!;
      throw Exception('CoinGecko isteği başarısız (${resp.statusCode})');
    }

    final list = jsonDecode(resp.body) as List;
    if (list.isEmpty) break; // CoinGecko'da daha fazla sayfa kalmadı

    final remaining = count - (page - 1) * perPage;
    for (final item in list.take(remaining)) {
      final symbol = (item as Map<String, dynamic>)['symbol'] as String?;
      if (symbol == null || symbol.trim().isEmpty) continue;
      symbols.add('${symbol.trim().toUpperCase()}-USD');
    }
  }

  final result = symbols.toList();
  _cachedSymbols = result;
  _cachedCount = count;
  _cachedAt = now;
  return result;
}
