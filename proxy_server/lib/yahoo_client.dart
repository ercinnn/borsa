import 'dart:convert';

import 'package:http/http.dart' as http;

const userAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36';

class YahooException implements Exception {
  final String message;
  YahooException(this.message);

  @override
  String toString() => message;
}

class RawCandle {
  final DateTime date;
  final num open;
  final num high;
  final num low;
  final num close;
  final num? volume;

  RawCandle(this.date, this.open, this.high, this.low, this.close, [this.volume]);
}

class ChartData {
  final String currency;
  final List<RawCandle> candles;

  ChartData(this.currency, this.candles);
}

class _CacheEntry {
  final ChartData data;
  final DateTime expiresAt;
  _CacheEntry(this.data, this.expiresAt);
}

/// Aynı sembol+aralık+interval için kısa süreli sonuç cache'i: aynı grafiği
/// art arda açan kullanıcılar veya bir sonraki MonthlyLowChecker taraması
/// Yahoo'ya tekrar gitmesin diye. Kişisel ölçekte bir süreç boyunca sınırsız
/// büyümesin diye her çağrıda süresi dolmuş kayıtlar ayıklanıyor ve toplam
/// boyut bir üst sınırın üstündeyse tamamen temizleniyor.
final _cache = <String, _CacheEntry>{};
const _cacheTtl = Duration(minutes: 2);
const _cacheMaxEntries = 500;

void _pruneCache() {
  final now = DateTime.now();
  _cache.removeWhere((_, entry) => entry.expiresAt.isBefore(now));
  if (_cache.length > _cacheMaxEntries) _cache.clear();
}

/// Yahoo Finance chart uç noktasından ham mum verisi çeker ve ayrıştırır.
/// Hem /api/candles hem de aylık dip kontrol servisi tarafından paylaşılır.
Future<ChartData> fetchChart(
  http.Client client,
  String symbol,
  int period1,
  int period2,
  String interval,
) async {
  final cacheKey = '$symbol|$period1|$period2|$interval';
  _pruneCache();
  final cached = _cache[cacheKey];
  if (cached != null && cached.expiresAt.isAfter(DateTime.now())) {
    return cached.data;
  }

  final uri = Uri.https(
    'query1.finance.yahoo.com',
    '/v8/finance/chart/$symbol',
    {
      'period1': '$period1',
      'period2': '$period2',
      'interval': interval,
    },
  );

  final resp = await client.get(uri, headers: {'User-Agent': userAgent});
  if (resp.statusCode != 200) {
    throw YahooException('Yahoo chart isteği başarısız (${resp.statusCode})');
  }

  final body = jsonDecode(resp.body) as Map<String, dynamic>;
  final chart = body['chart'] as Map<String, dynamic>?;
  if (chart?['error'] != null) {
    throw YahooException('Sembol bulunamadı: $symbol');
  }
  final results = chart?['result'] as List?;
  if (results == null || results.isEmpty) {
    throw YahooException('Sembol bulunamadı: $symbol');
  }

  final result = results.first as Map<String, dynamic>;
  final meta = result['meta'] as Map<String, dynamic>? ?? {};
  final timestamps = (result['timestamp'] as List?) ?? [];
  final quoteList = ((result['indicators'] as Map<String, dynamic>?)?['quote']
          as List?)
      ?.cast<Map<String, dynamic>>();
  final quote =
      (quoteList != null && quoteList.isNotEmpty) ? quoteList.first : <String, dynamic>{};
  final opens = (quote['open'] as List?) ?? [];
  final highs = (quote['high'] as List?) ?? [];
  final lows = (quote['low'] as List?) ?? [];
  final closes = (quote['close'] as List?) ?? [];
  final volumes = (quote['volume'] as List?) ?? [];

  final candles = <RawCandle>[];
  for (var i = 0; i < timestamps.length && i < lows.length; i++) {
    final open = i < opens.length ? opens[i] : null;
    final high = i < highs.length ? highs[i] : null;
    final low = lows[i];
    final close = i < closes.length ? closes[i] : null;
    if (open == null || high == null || low == null || close == null) {
      continue;
    }
    final date = DateTime.fromMillisecondsSinceEpoch(
      (timestamps[i] as int) * 1000,
      isUtc: true,
    );
    final volume = i < volumes.length ? volumes[i] as num? : null;
    candles.add(
        RawCandle(date, open as num, high as num, low as num, close as num, volume));
  }

  final data = ChartData(meta['currency'] as String? ?? '', candles);
  _cache[cacheKey] = _CacheEntry(data, DateTime.now().add(_cacheTtl));
  return data;
}

class DividendEvent {
  final DateTime date;
  final num amount;
  DividendEvent(this.date, this.amount);
}

class DividendData {
  final String currency;
  /// Yeniden eskiye sıralı.
  final List<DividendEvent> dividends;
  DividendData(this.currency, this.dividends);
}

class _DividendCacheEntry {
  final DividendData data;
  final DateTime expiresAt;
  _DividendCacheEntry(this.data, this.expiresAt);
}

// Temettü verisi fiyat mumlarına göre çok daha seyrek değiştiğinden
// (yılda birkaç kez) fetchChart'ın 2 dakikalık cache'inden ayrı, çok daha
// uzun ömürlü kendi cache'i var — aynı sembol hem /api/dividends'ten hem de
// portföydeki her bir holding için ayrı ayrı istenebiliyor (bkz.
// portfolio_summary.dart), bu ikisi arasında da paylaşılıyor.
final _dividendCache = <String, _DividendCacheEntry>{};
const _dividendCacheTtl = Duration(hours: 6);
const _dividendCacheMaxEntries = 500;

void _pruneDividendCache() {
  final now = DateTime.now();
  _dividendCache.removeWhere((_, entry) => entry.expiresAt.isBefore(now));
  if (_dividendCache.length > _dividendCacheMaxEntries) _dividendCache.clear();
}

/// Yahoo Finance chart uç noktasını `events=div` parametresiyle çekip bir
/// sembolün tüm bilinen temettü geçmişini (tarih + hisse başı tutar) döner.
/// `/api/dividends` ve portföydeki tahmini temettü geliri hesaplaması
/// (bkz. portfolio_summary.dart) tarafından paylaşılır — fetchChart ile aynı
/// HTTP altyapısını (userAgent, hata sınıfı) kullanır ama ayrı bir istek
/// atar, çünkü fetchChart'ın normal OHLC isteği events verisini içermiyor.
Future<DividendData> fetchDividends(http.Client client, String symbol) async {
  _pruneDividendCache();
  final cached = _dividendCache[symbol];
  if (cached != null && cached.expiresAt.isAfter(DateTime.now())) {
    return cached.data;
  }

  final now = DateTime.now().toUtc();
  final period2 = now.millisecondsSinceEpoch ~/ 1000 + 86400;
  // period1=0 (Yahoo'nun tüm geçmişi) yerine son 15 yılla sınırlıyoruz: BIST
  // sembolleri için 2005 öncesi (eski TL / redenominasyon öncesi) temettü
  // tutarları milyonlarca "eski TL" olarak dönüyor ve kullanıcıya anlamsız/
  // yanıltıcı görünüyor; 15 yıl kişisel temettü takibi için zaten yeterince
  // geniş bir pencere.
  final period1 =
      now.subtract(const Duration(days: 365 * 15)).millisecondsSinceEpoch ~/ 1000;

  final uri = Uri.https(
    'query1.finance.yahoo.com',
    '/v8/finance/chart/$symbol',
    {
      'period1': '$period1',
      'period2': '$period2',
      'interval': '1mo',
      'events': 'div',
    },
  );

  final resp = await client.get(uri, headers: {'User-Agent': userAgent});
  if (resp.statusCode != 200) {
    throw YahooException('Yahoo chart isteği başarısız (${resp.statusCode})');
  }

  final body = jsonDecode(resp.body) as Map<String, dynamic>;
  final chart = body['chart'] as Map<String, dynamic>?;
  if (chart?['error'] != null) {
    throw YahooException('Sembol bulunamadı: $symbol');
  }
  final results = chart?['result'] as List?;
  if (results == null || results.isEmpty) {
    throw YahooException('Sembol bulunamadı: $symbol');
  }

  final result = results.first as Map<String, dynamic>;
  final meta = result['meta'] as Map<String, dynamic>? ?? {};
  final events = result['events'] as Map<String, dynamic>?;
  final rawDividends = events?['dividends'] as Map<String, dynamic>?;

  final dividends = <DividendEvent>[];
  if (rawDividends != null) {
    for (final entry in rawDividends.values) {
      final e = entry as Map<String, dynamic>;
      final amount = e['amount'] as num?;
      final ts = e['date'] as int?;
      if (amount == null || ts == null) continue;
      dividends.add(DividendEvent(
        DateTime.fromMillisecondsSinceEpoch(ts * 1000, isUtc: true),
        amount,
      ));
    }
  }
  dividends.sort((a, b) => b.date.compareTo(a.date));

  final data = DividendData(meta['currency'] as String? ?? '', dividends);
  _dividendCache[symbol] = _DividendCacheEntry(data, DateTime.now().add(_dividendCacheTtl));
  return data;
}
