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

  RawCandle(this.date, this.open, this.high, this.low, this.close);
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
    candles.add(RawCandle(date, open as num, high as num, low as num, close as num));
  }

  final data = ChartData(meta['currency'] as String? ?? '', candles);
  _cache[cacheKey] = _CacheEntry(data, DateTime.now().add(_cacheTtl));
  return data;
}
