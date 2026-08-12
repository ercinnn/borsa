import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';

import '../lib/backtest.dart';
import '../lib/coingecko_client.dart';
import '../lib/env.dart';
import '../lib/fundamentals_cache.dart';
import '../lib/monthly_low_checker.dart';
import '../lib/preset_lists.dart';
import '../lib/portfolio_summary.dart';
import '../lib/store.dart';
import '../lib/supabase_client.dart';
import '../lib/technical_analysis.dart';
import '../lib/technical_score_cache.dart';
import '../lib/yahoo_client.dart';

final _httpClient = http.Client();
final _coingeckoApiKey = env('COINGECKO_API_KEY');
final _adminSyncSecret = env('ADMIN_SYNC_SECRET');

Middleware _cors() {
  const headers = {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Methods': 'GET, POST, DELETE, OPTIONS',
    'Access-Control-Allow-Headers': 'Content-Type, Authorization',
  };

  return (Handler innerHandler) {
    return (Request request) async {
      if (request.method == 'OPTIONS') {
        return Response.ok('', headers: headers);
      }
      final response = await innerHandler(request);
      return response.change(headers: headers);
    };
  };
}

Response _json(Object data, {int status = 200}) {
  return Response(
    status,
    body: jsonEncode(data),
    headers: {'Content-Type': 'application/json'},
  );
}

/// Handler'ların çoğu (ör. `_watchlistGetHandler`, body `jsonDecode` çağrıları)
/// kendi try/catch'ini yapmaz; bu son-çare middleware'i olmadan Supabase'in
/// fırlattığı ham `Exception` (bkz. supabase_client.dart) veya bozuk bir JSON
/// body'nin `FormatException`'ı client'a stack trace/iç detay olarak sızardı.
Middleware _errorHandling() {
  return (Handler innerHandler) {
    return (Request request) async {
      try {
        return await innerHandler(request);
      } catch (e, st) {
        stderr.writeln('Beklenmeyen hata (${request.method} ${request.requestedUri}): $e\n$st');
        return _json({'error': 'Sunucu hatası, lütfen daha sonra tekrar deneyin.'},
            status: 500);
      }
    };
  };
}

Future<Response> _searchHandler(Request request) async {
  final q = request.url.queryParameters['q'];
  if (q == null || q.trim().isEmpty) {
    return _json({'error': 'q parametresi gerekli'}, status: 400);
  }

  final uri = Uri.https('query1.finance.yahoo.com', '/v1/finance/search', {
    'q': q,
    'quotesCount': '10',
    'newsCount': '0',
  });

  try {
    final resp =
        await _httpClient.get(uri, headers: {'User-Agent': userAgent});
    if (resp.statusCode != 200) {
      return _json(
        {'error': 'Yahoo arama isteği başarısız (${resp.statusCode})'},
        status: 502,
      );
    }
    final body = jsonDecode(resp.body) as Map<String, dynamic>;
    final quotes = (body['quotes'] as List? ?? []);
    final results = quotes
        .whereType<Map<String, dynamic>>()
        .where((q) => q['symbol'] != null)
        .map((q) => {
              'symbol': q['symbol'],
              'name': q['shortname'] ?? q['longname'] ?? q['symbol'],
              'exchange': q['exchDisp'] ?? '',
              'type': q['quoteType'] ?? '',
            })
        .toList();

    // Yahoo'nun arama endpoint'i isim/kelime bazlı fuzzy eşleşme yapıyor ve
    // sonucu sabit quotesCount=10 ile kesiyor; bu yüzden örn. "GARAN" sorgusu
    // GARAN.IS'i döndürmez (kelime kökü "Garan" birçok Avrupa fonunun adıyla
    // -"Garantita", "Garantizado" vb.- çakışıp GARAN.IS'i top-10'un dışına
    // itiyor), oysa tam "GARAN.IS" yazınca doğru sonucu veriyor. Bilinen
    // BIST200/US200/crypto300 sembollerini burada prefiks eşleştirip Yahoo'nun
    // sonucunda yoksa başa ekliyoruz, böylece küratörlü listedeki semboller
    // Yahoo'nun sıralama tuhaflıklarından bağımsız her zaman aranabilir olur.
    // Kripto listesi bulk-add'deki crypto300 preset'iyle aynı kaynağı
    // (fetchTopCryptoSymbols, 1 saatlik cache) ve aynı statik yedeği
    // (cryptoFallbackSymbols) paylaşıyor.
    final existingSymbols =
        results.map((r) => (r['symbol'] as String).toUpperCase()).toSet();
    final upperQuery = q.trim().toUpperCase();
    bool matchesQuery(String symbol) =>
        symbol.split('.').first.startsWith(upperQuery) ||
        symbol.startsWith(upperQuery);
    final localMatches = <Map<String, dynamic>>[];
    for (final sym in bist200Symbols) {
      if (matchesQuery(sym) && existingSymbols.add(sym)) {
        localMatches.add(
            {'symbol': sym, 'name': sym, 'exchange': 'BIST', 'type': 'EQUITY'});
      }
    }
    for (final sym in usPopular200Symbols) {
      if (matchesQuery(sym) && existingSymbols.add(sym)) {
        localMatches.add(
            {'symbol': sym, 'name': sym, 'exchange': 'US', 'type': 'EQUITY'});
      }
    }
    List<String> cryptoSymbols;
    try {
      cryptoSymbols = await fetchTopCryptoSymbols(_httpClient, 300,
          apiKey: _coingeckoApiKey);
    } catch (e) {
      cryptoSymbols = cryptoFallbackSymbols;
    }
    for (final sym in cryptoSymbols) {
      if (matchesQuery(sym) && existingSymbols.add(sym)) {
        localMatches.add({
          'symbol': sym,
          'name': sym,
          'exchange': 'Crypto',
          'type': 'CRYPTOCURRENCY',
        });
      }
    }
    results.insertAll(0, localMatches);

    return _json({'results': results});
  } catch (e) {
    stderr.writeln('Arama hatası: $e');
    return _json({'error': 'Arama sırasında bir hata oluştu.'}, status: 502);
  }
}

// Desteklenen aralık kodları ve bunlara karşılık gelen Yahoo interval
// parametreleri. '12mo' ve '4h' Yahoo'da yok; sırasıyla 1 aylık ve 60
// dakikalık mumlar çekilip sunucu tarafında birleştiriliyor (bkz. aşağıdaki
// sentezleme mantığı).
const _yahooIntervalFor = {
  '60m': '60m',
  '4h': '60m',
  '1d': '1d',
  '1wk': '1wk',
  '1mo': '1mo',
  '3mo': '3mo',
  '12mo': '1mo',
};

String _twoDigits(int n) => n.toString().padLeft(2, '0');

// Tüm tarihler UTC (bkz. yahoo_client.dart RawCandle.date); saat/dakika
// etiketleri de UTC olarak gösteriliyor, borsa yerel saatine çevrilmiyor.
String _formatPeriod(String interval, DateTime start, DateTime end) {
  switch (interval) {
    case '60m':
    case '4h':
      return '${_twoDigits(start.day)}.${_twoDigits(start.month)} '
          '${_twoDigits(start.hour)}:${_twoDigits(start.minute)}';
    case '1d':
    case '1wk':
      return '${_twoDigits(start.day)}.${_twoDigits(start.month)}.'
          '${start.year.toString().substring(2)}';
    case '1mo':
      return '${_twoDigits(start.month)}.${start.year.toString().substring(2)}';
    case '3mo':
      final quarter = ((start.month - 1) ~/ 3) + 1;
      return 'Q$quarter ${start.year.toString().substring(2)}';
    case '12mo':
      return start.year == end.year
          ? '${start.year}'
          : '${start.year}-${end.year}';
    default:
      return '${start.year}-${_twoDigits(start.month)}-${_twoDigits(start.day)}';
  }
}

Future<Response> _candlesHandler(Request request) async {
  final params = request.url.queryParameters;
  final symbol = params['symbol'];
  final start = params['start'];
  final end = params['end'];
  final interval = params['interval'] ?? '1mo';

  if (symbol == null || symbol.trim().isEmpty) {
    return _json({'error': 'symbol parametresi gerekli'}, status: 400);
  }
  if (start == null || end == null) {
    return _json({'error': 'start ve end parametreleri gerekli'}, status: 400);
  }
  final yahooInterval = _yahooIntervalFor[interval];
  if (yahooInterval == null) {
    return _json({'error': 'Geçersiz interval: $interval'}, status: 400);
  }

  final DateTime startDate;
  final DateTime endDate;
  try {
    startDate = DateTime.parse(start);
    // Bitiş gününü tam kapsamak için bir gün ekleniyor.
    endDate = DateTime.parse(end).add(const Duration(days: 1));
  } catch (e) {
    return _json({'error': 'Geçersiz tarih formatı, YYYY-MM-DD kullanın'},
        status: 400);
  }

  final period1 = startDate.toUtc().millisecondsSinceEpoch ~/ 1000;
  final period2 = endDate.toUtc().millisecondsSinceEpoch ~/ 1000;

  try {
    final data =
        await fetchChart(_httpClient, symbol, period1, period2, yahooInterval);
    final raw = data.candles;

    // 12 aylık görünüm için 1 aylık mumlar 12'şerli gruplar halinde
    // birleştiriliyor (Yahoo doğrudan yıllık interval desteklemiyor).
    final candles = <Map<String, dynamic>>[];
    if (interval == '12mo') {
      for (var i = 0; i < raw.length; i += 12) {
        final chunk = raw.sublist(i, i + 12 > raw.length ? raw.length : i + 12);
        if (chunk.isEmpty) continue;
        final open = chunk.first.open;
        final close = chunk.last.close;
        final high = chunk.map((c) => c.high).reduce((a, b) => a > b ? a : b);
        final low = chunk.map((c) => c.low).reduce((a, b) => a < b ? a : b);
        candles.add({
          'period': _formatPeriod(interval, chunk.first.date, chunk.last.date),
          'open': open,
          'high': high,
          'low': low,
          'close': close,
        });
      }
    } else if (interval == '4h') {
      // Sabit-sayıda-mum gruplama (12mo'daki gibi) gün içi verilerde işe
      // yaramıyor: tatil/hafta sonu boşlukları ve borsa açılış-kapanış
      // saatleri yüzünden art arda 4 ham mum her zaman aynı 4 saatlik
      // duvar-saati dilimine denk gelmeyebiliyor. Bunun yerine her mumu
      // UTC'de 4 saatlik dilimlere (00-04, 04-08, ...) yuvarlayıp o dilime
      // göre grupluyoruz.
      final buckets = <int, List<RawCandle>>{};
      for (final c in raw) {
        final bucketHour = (c.date.hour ~/ 4) * 4;
        final bucketStart = DateTime.utc(
            c.date.year, c.date.month, c.date.day, bucketHour);
        buckets.putIfAbsent(
            bucketStart.millisecondsSinceEpoch, () => []).add(c);
      }
      final sortedKeys = buckets.keys.toList()..sort();
      for (final key in sortedKeys) {
        final chunk = buckets[key]!;
        final open = chunk.first.open;
        final close = chunk.last.close;
        final high = chunk.map((c) => c.high).reduce((a, b) => a > b ? a : b);
        final low = chunk.map((c) => c.low).reduce((a, b) => a < b ? a : b);
        candles.add({
          'period': _formatPeriod(interval, chunk.first.date, chunk.last.date),
          'open': open,
          'high': high,
          'low': low,
          'close': close,
        });
      }
    } else {
      for (final c in raw) {
        candles.add({
          'period': _formatPeriod(interval, c.date, c.date),
          'open': c.open,
          'high': c.high,
          'low': c.low,
          'close': c.close,
        });
      }
    }

    // TradingView tarzı RSI/MACD paneli (bkz. borsa_takip'te
    // widgets/candlestick_chart.dart): `indicators=rsi,macd` verilirse,
    // (grup/senteleme sonrası) gösterilen aynı mum serisi üzerinden tam
    // zaman serisi hesaplanıp her muma eklenir — Teknik sekmesindeki
    // computeTechnicalAnalysis yalnızca son değerle ilgilenirken, burada
    // grafiğin tamamı için gerekiyor (bkz. technical_analysis.dart
    // rsiSeries/macdSeriesFor).
    final indicatorsParam = params['indicators'];
    if (indicatorsParam != null && indicatorsParam.trim().isNotEmpty && candles.isNotEmpty) {
      final wanted = indicatorsParam.split(',').map((s) => s.trim()).toSet();
      final closes = [for (final c in candles) (c['close'] as num).toDouble()];
      if (wanted.contains('rsi')) {
        final rsi = rsiSeries(closes);
        for (var i = 0; i < candles.length; i++) {
          candles[i]['rsi'] = rsi[i];
        }
      }
      if (wanted.contains('macd')) {
        final macd = macdSeriesFor(closes);
        for (var i = 0; i < candles.length; i++) {
          candles[i]['macd'] = macd.macd[i];
          candles[i]['macdSignal'] = macd.signal[i];
          candles[i]['macdHistogram'] = macd.histogram[i];
        }
      }
    }

    return _json({
      'symbol': symbol,
      'currency': data.currency,
      'candles': candles,
    });
  } on YahooException catch (e) {
    return _json({'error': e.message}, status: 404);
  } catch (e) {
    stderr.writeln('Candle verisi alınırken hata: $e');
    return _json({'error': 'Veri alınırken bir hata oluştu.'}, status: 502);
  }
}

/// Investing.com'daki "Teknik Özet" sayfasına benzer bir analiz: Pivot
/// Noktaları, Hareketli Ortalamalar (MA5..MA200) ve Teknik İndikatörler
/// (RSI, STOCH, STOCHRSI, MACD, ATR, ADX, CCI, Highs/Lows, UO, ROC,
/// Williams %R, Bull/Bear Power) + üç özet kutusu (bkz.
/// lib/technical_analysis.dart). MA200 için yeterli geçmiş sağlansın diye
/// ~500 takvim günü (tatil/hafta sonu boşluklarıyla BIST/ABD için ~250+ işlem
/// günü) geriye gidiliyor. `/api/candles` gibi public — sembole özgü, kullanıcı
/// verisi içermiyor.
Future<Response> _technicalHandler(Request request) async {
  final symbol = request.url.queryParameters['symbol'];
  if (symbol == null || symbol.trim().isEmpty) {
    return _json({'error': 'symbol parametresi gerekli'}, status: 400);
  }

  final now = DateTime.now().toUtc();
  final period2 = now.millisecondsSinceEpoch ~/ 1000 + 86400;
  final period1 =
      now.subtract(const Duration(days: 500)).millisecondsSinceEpoch ~/ 1000;

  try {
    final data = await fetchChart(_httpClient, symbol, period1, period2, '1d');
    final result = computeTechnicalAnalysis(symbol, data.currency, data.candles);
    return _json(result.toJson());
  } on YahooException catch (e) {
    return _json({'error': e.message}, status: 404);
  } on InsufficientDataException catch (e) {
    return _json({'error': e.message}, status: 422);
  } catch (e) {
    stderr.writeln('Teknik analiz hatası: $e');
    return _json({'error': 'Teknik analiz hesaplanırken bir hata oluştu.'},
        status: 502);
  }
}

/// Bir sembolün son 15 yıllık temettü geçmişini (tarih + hisse başı tutar)
/// döner (bkz. lib/yahoo_client.dart fetchDividends). `/api/technical` gibi
/// public — sembole özgü, kullanıcı verisi içermiyor. `totalPerShare`,
/// portföydeki tahmini temettü geliri hesaplamasıyla aynı basit toplamı
/// (bkz. portfolio_summary.dart) burada da tek seferlik gösterim için sağlar.
Future<Response> _dividendsHandler(Request request) async {
  final symbol = request.url.queryParameters['symbol'];
  if (symbol == null || symbol.trim().isEmpty) {
    return _json({'error': 'symbol parametresi gerekli'}, status: 400);
  }

  try {
    final data = await fetchDividends(_httpClient, symbol);
    final totalPerShare =
        data.dividends.fold<num>(0, (sum, d) => sum + d.amount);
    return _json({
      'symbol': symbol.trim().toUpperCase(),
      'currency': data.currency,
      'dividends': [
        for (final d in data.dividends)
          {'date': d.date.toIso8601String(), 'amount': d.amount},
      ],
      'totalPerShare': totalPerShare,
    });
  } on YahooException catch (e) {
    return _json({'error': e.message}, status: 404);
  } catch (e) {
    stderr.writeln('Temettü verisi alınırken hata: $e');
    return _json({'error': 'Temettü verisi alınırken bir hata oluştu.'},
        status: 502);
  }
}

// yahoo_fundamentals.dart'ın kendi retry/timeout katmanları olsa da (bkz. o
// dosyanın doc yorumları), bunların iç içe ne kadar sürebileceğini kesin
// olarak öngörmek zor — burada kullanıcıya giden HTTP yanıtı için ayrı, sert
// bir üst sınır koyuyoruz. Süre dolarsa hata döndürmek yerine DB'de o an ne
// varsa onunla devam ediyoruz (aşağıdaki catch, [_withFreshFundamentals]).
const _fundamentalsRequestTimeout = Duration(seconds: 25);

/// Temel Analiz uç noktalarının hepsinin ortak akışı: [cache.ensureFresh]
/// (DB'de 24 saatten eski/eksikse Yahoo'dan çekip yeniden hesaplar) sonrası
/// ilgili Store'dan okuyup 404/YahooException/InsufficientDataException'ı
/// düzgün HTTP koduna çevirir.
Future<Response> _withFreshFundamentals(
  String symbol,
  FundamentalsCache cache,
  Future<Response> Function() onFresh,
) async {
  try {
    await cache.ensureFresh(symbol).timeout(_fundamentalsRequestTimeout);
    return await onFresh();
  } on TimeoutException {
    // Yahoo tarafı beklenenden yavaş/tıkalı kaldı — kullanıcıyı süresiz
    // bekletmek yerine DB'de o an ne varsa (stale veri ya da hiçbir şey)
    // onunla devam ediyoruz. Arka plandaki yenileme denemesi
    // (FundamentalsCache._inFlightRefreshes) kesilmez, sonraki istekte
    // tamamlanmış olabilir.
    return await onFresh();
  } on YahooException catch (e) {
    return _json({'error': e.message}, status: 404);
  } on InsufficientDataException catch (e) {
    return _json({'error': e.message}, status: 422);
  } catch (e) {
    stderr.writeln('Temel analiz hatası ($symbol): $e');
    return _json({'error': 'Temel analiz hesaplanırken bir hata oluştu.'}, status: 502);
  }
}

Future<Response> _fundamentalsOverviewHandler(
  Request request, FundamentalsCache cache, StockStore stocks) async {
  final symbol = request.url.queryParameters['symbol'];
  if (symbol == null || symbol.trim().isEmpty) {
    return _json({'error': 'symbol parametresi gerekli'}, status: 400);
  }
  return _withFreshFundamentals(symbol, cache, () async {
    final row = await stocks.getBySymbol(symbol);
    if (row == null) return _json({'error': 'Sembol bulunamadı: $symbol'}, status: 404);
    return _json({
      'symbol': row['symbol'],
      'companyName': row['company_name'],
      'sector': row['sector'],
      'country': row['country'],
      'currency': row['currency'],
      'lastPrice': row['last_price'],
      'marketCap': row['market_cap'],
      'peRatio': row['pe_ratio'],
      'pbRatio': row['pb_ratio'],
      'dividendYield': row['dividend_yield'],
      'updatedAt': row['updated_at'],
      'stale': !cache.isFresh(row['updated_at'] as String?),
    });
  });
}

Future<Response> _fundamentalsFairValueHandler(
  Request request, FundamentalsCache cache, StockScoreStore scores) async {
  final symbol = request.url.queryParameters['symbol'];
  if (symbol == null || symbol.trim().isEmpty) {
    return _json({'error': 'symbol parametresi gerekli'}, status: 400);
  }
  return _withFreshFundamentals(symbol, cache, () async {
    final row = await scores.getBySymbol(symbol);
    if (row == null) return _json({'error': 'Sembol bulunamadı: $symbol'}, status: 404);
    return _json({
      'symbol': row['symbol'],
      'fairValuePerShare': row['fair_value_per_share'],
      'upsidePct': row['fair_value_upside_pct'],
      'error': row['fair_value_error'],
      'assumptions': row['dcf_assumptions'],
      'computedAt': row['computed_at'],
      'stale': !cache.isFresh(row['computed_at'] as String?),
    });
  });
}

Future<Response> _fundamentalsHealthScoreHandler(
  Request request, FundamentalsCache cache, StockScoreStore scores) async {
  final symbol = request.url.queryParameters['symbol'];
  if (symbol == null || symbol.trim().isEmpty) {
    return _json({'error': 'symbol parametresi gerekli'}, status: 400);
  }
  return _withFreshFundamentals(symbol, cache, () async {
    final row = await scores.getBySymbol(symbol);
    if (row == null) return _json({'error': 'Sembol bulunamadı: $symbol'}, status: 404);
    return _json({
      'symbol': row['symbol'],
      'altmanZScore': row['altman_z_score'],
      'altmanZone': row['altman_zone'],
      'altmanError': row['altman_error'],
      'piotroskiScore': row['piotroski_score'],
      'piotroskiMaxScore': row['piotroski_max_score'],
      'piotroskiCriteria': row['piotroski_criteria'],
      'computedAt': row['computed_at'],
      'stale': !cache.isFresh(row['computed_at'] as String?),
    });
  });
}

Future<Response> _fundamentalsProTipsHandler(
  Request request, FundamentalsCache cache, StockScoreStore scores) async {
  final symbol = request.url.queryParameters['symbol'];
  if (symbol == null || symbol.trim().isEmpty) {
    return _json({'error': 'symbol parametresi gerekli'}, status: 400);
  }
  return _withFreshFundamentals(symbol, cache, () async {
    final row = await scores.getBySymbol(symbol);
    if (row == null) return _json({'error': 'Sembol bulunamadı: $symbol'}, status: 404);
    return _json({
      'symbol': row['symbol'],
      'tips': row['pro_tips'],
      'computedAt': row['computed_at'],
      'stale': !cache.isFresh(row['computed_at'] as String?),
    });
  });
}

/// Kullanıcı auth'u DEĞİL — servis-to-servis/manuel tetikleme (cron, admin
/// panel vb.) için ayrı bir paylaşılan sır. `ADMIN_SYNC_SECRET` env var'ı
/// ayarlanmamışsa uç nokta tamamen kapalıdır (503) — açık bırakılmış bir
/// admin endpoint'i olmasın diye varsayılan "kapalı".
Future<Response> _adminSyncStockHandler(Request request, FundamentalsCache cache) async {
  final secret = _adminSyncSecret;
  if (secret == null || secret.isEmpty) {
    return _json({'error': 'Admin sync devre dışı (ADMIN_SYNC_SECRET ayarlanmamış)'},
        status: 503);
  }
  final provided = request.headers['x-admin-secret'];
  if (provided == null || provided != secret) {
    return _json({'error': 'Yetkisiz'}, status: 401);
  }
  final symbol = request.params['symbol'];
  if (symbol == null || symbol.trim().isEmpty) {
    return _json({'error': 'symbol gerekli'}, status: 400);
  }
  try {
    await cache.refresh(symbol);
    return _json({'symbol': symbol.trim().toUpperCase(), 'synced': true});
  } on YahooException catch (e) {
    return _json({'error': e.message}, status: 404);
  } on InsufficientDataException catch (e) {
    return _json({'error': e.message}, status: 422);
  } catch (e) {
    stderr.writeln('Admin sync hatası ($symbol): $e');
    return _json({'error': 'Senkronizasyon sırasında bir hata oluştu.'}, status: 502);
  }
}

// _technicalHandler'ın canlı puanla aynı büyüklükte bir lookback kullanması
// gibi, backtest de simülasyon başlangıcından önce en az bu kadar takvim
// günü geriye giderek ısınma verisi çeker (bkz. lib/backtest.dart
// _lookbackCandles doc yorumu — 260 iş günü ~370-400 takvim günü eder,
// hafta sonu/tatil boşluklarıyla güvenli pay bırakmak için 400 kullanılıyor).
const _backtestLookbackDays = 400;

/// "Bu puan eşiğine göre alım-satım yapsaydım geçmişte nasıl performans
/// verirdi" simülasyonu (bkz. lib/backtest.dart runBacktest). `/api/technical`
/// gibi public — sembole özgü, kullanıcı verisi içermiyor. Params: `symbol`,
/// `start`/`end` (ISO tarih, simülasyonun kendisi bu aralıkta çalışır — önceki
/// veri yalnızca ısınma için çekilir), `buyThreshold`/`sellThreshold`
/// (varsayılan 60/40 — Teknik sekmesindeki Al/Sat kademe sınırlarıyla aynı),
/// `initialCapital` (varsayılan 10000).
Future<Response> _backtestHandler(Request request) async {
  final params = request.url.queryParameters;
  final symbol = params['symbol'];
  if (symbol == null || symbol.trim().isEmpty) {
    return _json({'error': 'symbol parametresi gerekli'}, status: 400);
  }
  final start = DateTime.tryParse(params['start'] ?? '');
  final end = DateTime.tryParse(params['end'] ?? '');
  if (start == null || end == null || !end.isAfter(start)) {
    return _json({'error': 'geçerli start/end tarihleri gerekli'}, status: 400);
  }
  final buyThreshold = int.tryParse(params['buyThreshold'] ?? '') ?? 60;
  final sellThreshold = int.tryParse(params['sellThreshold'] ?? '') ?? 40;
  if (buyThreshold <= sellThreshold) {
    return _json({'error': 'buyThreshold, sellThreshold\'dan büyük olmalı'},
        status: 400);
  }
  final initialCapital = double.tryParse(params['initialCapital'] ?? '') ?? 10000;
  if (initialCapital <= 0) {
    return _json({'error': 'initialCapital 0\'dan büyük olmalı'}, status: 400);
  }

  final fetchStart = start.subtract(const Duration(days: _backtestLookbackDays));
  final period1 = fetchStart.millisecondsSinceEpoch ~/ 1000;
  final period2 =
      end.add(const Duration(days: 1)).millisecondsSinceEpoch ~/ 1000;

  try {
    final data = await fetchChart(_httpClient, symbol, period1, period2, '1d');
    final result = runBacktest(
      symbol: symbol.trim().toUpperCase(),
      currency: data.currency,
      candles: data.candles,
      simulationStart: start,
      buyThreshold: buyThreshold,
      sellThreshold: sellThreshold,
      initialCapital: initialCapital,
    );
    return _json(result.toJson());
  } on YahooException catch (e) {
    return _json({'error': e.message}, status: 404);
  } on InsufficientDataException catch (e) {
    return _json({'error': e.message}, status: 422);
  } catch (e) {
    stderr.writeln('Backtest hatası: $e');
    return _json({'error': 'Backtest hesaplanırken bir hata oluştu.'},
        status: 502);
  }
}

// BIST sembolleri ".IS", kripto sembolleri "-USD" ile bitiyor (bkz.
// preset_lists.dart / coingecko_client.dart) — NotificationStore.page'deki
// aynı kural, burada bellekteki bir liste üzerinde filtrelemek için.
String _categoryOf(String symbol) {
  if (symbol.endsWith('.IS')) return 'bist';
  if (symbol.endsWith('-USD')) return 'crypto';
  return 'us';
}

const _scorePageSize = 50;

/// Bildirimler sayfasındaki "Puan Sıralaması" sekmesi: kullanıcının izleme
/// listesindeki sembolleri (kategori filtresi + kullanıcının seçtiği yön)
/// [TechnicalScoreCache]'teki önbelleklenmiş puana göre sıralayıp 50'şerlik
/// sayfalar halinde döner. Puanı henüz hesaplanmamış semboller (ör. arka
/// plan taraması henüz oraya ulaşmadı) `pendingCount` ile ayrıca bildirilir,
/// listede görünmez.
Future<Response> _technicalScoresHandler(
  Request request,
  String userId,
  WatchlistStore watchlist,
  TechnicalScoreCache scoreCache,
) async {
  final params = request.url.queryParameters;
  final categoriesParam = params['categories'];
  final categories = (categoriesParam == null || categoriesParam.trim().isEmpty)
      ? {'bist', 'us', 'crypto'}
      : categoriesParam.split(',').map((s) => s.trim()).toSet();
  final ascending = params['sort'] == 'asc';
  final page = int.tryParse(params['page'] ?? '') ?? 1;
  final safePage = page < 1 ? 1 : page;

  final watchlistSymbols = await watchlist.symbolsFor(userId);
  final filtered =
      watchlistSymbols.where((s) => categories.contains(_categoryOf(s))).toList();

  final scored = scoreCache.scoresFor(filtered);
  scored.sort((a, b) =>
      ascending ? a.score.compareTo(b.score) : b.score.compareTo(a.score));

  final total = scored.length;
  final totalPages = total == 0 ? 1 : (total / _scorePageSize).ceil();
  final start = (safePage - 1) * _scorePageSize;
  final pageItems = start >= total
      ? const <ScoredSymbol>[]
      : scored.sublist(start, (start + _scorePageSize).clamp(0, total));

  return _json({
    'items': pageItems.map((s) => s.toJson()).toList(),
    'page': safePage,
    'totalPages': totalPages,
    'total': total,
    'pendingCount': filtered.length - total,
    'refreshing': scoreCache.isRefreshing,
  });
}

Future<Response> _technicalScoresRefreshHandler(
  Request request,
  String userId,
  TechnicalScoreCache scoreCache,
) async {
  if (scoreCache.isRefreshing) {
    return _json({'started': false, 'message': 'Zaten devam eden bir hesaplama var.'});
  }
  // Tüm kullanıcıları kapsayan global bir tarama (istekten bağımsız arka
  // planda çalışır); buton sadece bunu erkenden tetikler (bkz. _checkNowHandler).
  scoreCache.refreshAll().catchError((e) {
    stderr.writeln('Puan yenileme başarısız: $e');
  });
  return _json({'started': true, 'cachedCount': scoreCache.cachedCount});
}

class _AuthCacheEntry {
  final String userId;
  final DateTime expiresAt;
  _AuthCacheEntry(this.userId, this.expiresAt);
}

// Bir istemcinin kısa bir sürede birden fazla istek atması yaygın (ör. uygulama
// açılışında watchlist+favorites+notifications+tracked eşzamanlı çekiliyor);
// her biri için ayrı bir Supabase /auth/v1/user çağrısı yapmak yerine geçerli
// bir token'ı kısa süreliğine önbelleğe alıyoruz. 60sn, oturumu Supabase'de
// hemen iptal edilen bir kullanıcının en fazla bu kadar süre daha
// doğrulanmış sayılabileceği anlamına gelir — kişisel ölçekli bu uygulama
// için kabul edilebilir bir ödünleşim.
final _authCache = <String, _AuthCacheEntry>{};
const _authCacheTtl = Duration(seconds: 60);
const _authCacheMaxEntries = 200;

/// `Authorization: Bearer <supabase access token>` header'ını Supabase'in
/// `/auth/v1/user` ucuna sorup doğrular, geçerliyse kullanıcı id'sini döner.
/// Bu proje hiçbir yerde ağır bir SDK kullanmadığından (yahoo_client,
/// coingecko_client, supabase_client hepsi çıplak `http`) JWT'yi yerel
/// imza doğrulamak yerine bu tek HTTP çağrısını tercih ettik.
Future<String?> _authenticate(Request request, SupabaseConfig config) async {
  final authHeader = request.headers['authorization'];
  if (authHeader == null || !authHeader.startsWith('Bearer ')) return null;
  final token = authHeader.substring(7);

  final now = DateTime.now();
  final cached = _authCache[token];
  if (cached != null && cached.expiresAt.isAfter(now)) {
    return cached.userId;
  }

  try {
    final resp = await _httpClient.get(
      Uri.parse('${config.url}/auth/v1/user'),
      headers: {'Authorization': 'Bearer $token', 'apikey': config.serviceKey},
    );
    if (resp.statusCode != 200) return null;
    final user = jsonDecode(resp.body) as Map<String, dynamic>;
    final userId = user['id'] as String?;
    if (userId != null) {
      _authCache.removeWhere((_, e) => e.expiresAt.isBefore(now));
      if (_authCache.length > _authCacheMaxEntries) _authCache.clear();
      _authCache[token] = _AuthCacheEntry(userId, now.add(_authCacheTtl));
    }
    return userId;
  } catch (_) {
    return null;
  }
}

Response _unauthorized() => _json({'error': 'Giriş gerekli'}, status: 401);

/// Korumalı bir handler'ı auth kontrolüyle sarar: her handler kendi
/// `_authenticate` + null-kontrolü + `_unauthorized()` iskeletini
/// tekrarlamak yerine, router bu wrapper üzerinden kaydediliyor.
typedef _AuthedHandler = Future<Response> Function(Request request, String userId);

Handler _withAuth(SupabaseConfig config, _AuthedHandler handler) {
  return (Request request) async {
    final userId = await _authenticate(request, config);
    if (userId == null) return _unauthorized();
    return handler(request, userId);
  };
}

Future<Response> _watchlistGetHandler(
    Request request, String userId, WatchlistStore watchlist) async {
  return _json({'symbols': await watchlist.symbolsFor(userId)});
}

Future<Response> _watchlistAddHandler(
    Request request, String userId, WatchlistStore watchlist) async {
  final body = jsonDecode(await request.readAsString()) as Map<String, dynamic>;
  final symbol = body['symbol'] as String?;
  if (symbol == null || symbol.trim().isEmpty) {
    return _json({'error': 'symbol gerekli'}, status: 400);
  }
  final added = await watchlist.add(userId, symbol);
  return _json({'symbol': symbol.trim().toUpperCase(), 'added': added});
}

Future<Response> _watchlistRemoveHandler(
    Request request, String userId, WatchlistStore watchlist) async {
  final body = jsonDecode(await request.readAsString()) as Map<String, dynamic>;
  final symbol = body['symbol'] as String?;
  if (symbol == null || symbol.trim().isEmpty) {
    return _json({'error': 'symbol gerekli'}, status: 400);
  }
  final removed = await watchlist.remove(userId, symbol);
  return _json({'symbol': symbol.trim().toUpperCase(), 'removed': removed});
}

Future<Response> _watchlistBulkAddHandler(
    Request request, String userId, WatchlistStore watchlist) async {
  final body = jsonDecode(await request.readAsString()) as Map<String, dynamic>;
  final preset = body['preset'] as String?;

  List<String> symbols;
  switch (preset) {
    case 'bist200':
      symbols = bist200Symbols;
      break;
    case 'us200':
      symbols = usPopular200Symbols;
      break;
    case 'crypto300':
      try {
        symbols = await fetchTopCryptoSymbols(_httpClient, 300,
            apiKey: _coingeckoApiKey);
      } catch (e) {
        stderr.writeln('CoinGecko fetch failed, statik yedek listeye düşülüyor: $e');
        symbols = cryptoFallbackSymbols;
      }
      break;
    default:
      return _json(
        {'error': 'Geçersiz preset: bist200, us200 veya crypto300 olmalı'},
        status: 400,
      );
  }

  final added = await watchlist.addAll(userId, symbols);
  return _json({'symbols': await watchlist.symbolsFor(userId), 'added': added});
}

Future<Response> _favoritesGetHandler(
    Request request, String userId, FavoritesStore favorites) async {
  return _json({'symbols': await favorites.symbolsFor(userId)});
}

Future<Response> _favoritesAddHandler(
    Request request, String userId, FavoritesStore favorites) async {
  final body = jsonDecode(await request.readAsString()) as Map<String, dynamic>;
  final symbol = body['symbol'] as String?;
  if (symbol == null || symbol.trim().isEmpty) {
    return _json({'error': 'symbol gerekli'}, status: 400);
  }
  final added = await favorites.add(userId, symbol);
  return _json({'symbol': symbol.trim().toUpperCase(), 'added': added});
}

Future<Response> _favoritesRemoveHandler(
    Request request, String userId, FavoritesStore favorites) async {
  final body = jsonDecode(await request.readAsString()) as Map<String, dynamic>;
  final symbol = body['symbol'] as String?;
  if (symbol == null || symbol.trim().isEmpty) {
    return _json({'error': 'symbol gerekli'}, status: 400);
  }
  final removed = await favorites.remove(userId, symbol);
  return _json({'symbol': symbol.trim().toUpperCase(), 'removed': removed});
}

Future<Response> _technicalWatchlistGetHandler(
    Request request, String userId, TechnicalWatchlistStore technicalWatchlist) async {
  return _json({'symbols': await technicalWatchlist.symbolsFor(userId)});
}

Future<Response> _technicalWatchlistAddHandler(
    Request request, String userId, TechnicalWatchlistStore technicalWatchlist) async {
  final body = jsonDecode(await request.readAsString()) as Map<String, dynamic>;
  final symbol = body['symbol'] as String?;
  if (symbol == null || symbol.trim().isEmpty) {
    return _json({'error': 'symbol gerekli'}, status: 400);
  }
  final added = await technicalWatchlist.add(userId, symbol);
  return _json({'symbol': symbol.trim().toUpperCase(), 'added': added});
}

Future<Response> _technicalWatchlistRemoveHandler(
    Request request, String userId, TechnicalWatchlistStore technicalWatchlist) async {
  final body = jsonDecode(await request.readAsString()) as Map<String, dynamic>;
  final symbol = body['symbol'] as String?;
  if (symbol == null || symbol.trim().isEmpty) {
    return _json({'error': 'symbol gerekli'}, status: 400);
  }
  final removed = await technicalWatchlist.remove(userId, symbol);
  return _json({'symbol': symbol.trim().toUpperCase(), 'removed': removed});
}

Future<Response> _dividendWatchlistGetHandler(
    Request request, String userId, DividendWatchlistStore dividendWatchlist) async {
  return _json({'symbols': await dividendWatchlist.symbolsFor(userId)});
}

Future<Response> _dividendWatchlistAddHandler(
    Request request, String userId, DividendWatchlistStore dividendWatchlist) async {
  final body = jsonDecode(await request.readAsString()) as Map<String, dynamic>;
  final symbol = body['symbol'] as String?;
  if (symbol == null || symbol.trim().isEmpty) {
    return _json({'error': 'symbol gerekli'}, status: 400);
  }
  final added = await dividendWatchlist.add(userId, symbol);
  return _json({'symbol': symbol.trim().toUpperCase(), 'added': added});
}

Future<Response> _dividendWatchlistRemoveHandler(
    Request request, String userId, DividendWatchlistStore dividendWatchlist) async {
  final body = jsonDecode(await request.readAsString()) as Map<String, dynamic>;
  final symbol = body['symbol'] as String?;
  if (symbol == null || symbol.trim().isEmpty) {
    return _json({'error': 'symbol gerekli'}, status: 400);
  }
  final removed = await dividendWatchlist.remove(userId, symbol);
  return _json({'symbol': symbol.trim().toUpperCase(), 'removed': removed});
}

Future<Response> _fundamentalsWatchlistGetHandler(Request request, String userId,
    FundamentalsWatchlistStore fundamentalsWatchlist) async {
  return _json({'symbols': await fundamentalsWatchlist.symbolsFor(userId)});
}

Future<Response> _fundamentalsWatchlistAddHandler(Request request, String userId,
    FundamentalsWatchlistStore fundamentalsWatchlist) async {
  final body = jsonDecode(await request.readAsString()) as Map<String, dynamic>;
  final symbol = body['symbol'] as String?;
  if (symbol == null || symbol.trim().isEmpty) {
    return _json({'error': 'symbol gerekli'}, status: 400);
  }
  final added = await fundamentalsWatchlist.add(userId, symbol);
  return _json({'symbol': symbol.trim().toUpperCase(), 'added': added});
}

Future<Response> _fundamentalsWatchlistRemoveHandler(Request request, String userId,
    FundamentalsWatchlistStore fundamentalsWatchlist) async {
  final body = jsonDecode(await request.readAsString()) as Map<String, dynamic>;
  final symbol = body['symbol'] as String?;
  if (symbol == null || symbol.trim().isEmpty) {
    return _json({'error': 'symbol gerekli'}, status: 400);
  }
  final removed = await fundamentalsWatchlist.remove(userId, symbol);
  return _json({'symbol': symbol.trim().toUpperCase(), 'removed': removed});
}

Future<Response> _portfolioGetHandler(
    Request request, String userId, PortfolioStore portfolio) async {
  final holdings = await portfolio.holdingsFor(userId);
  final summary = await computePortfolioSummary(_httpClient, holdings);
  return _json(summary.toJson());
}

Future<Response> _portfolioAddHandler(
    Request request, String userId, PortfolioStore portfolio) async {
  final body = jsonDecode(await request.readAsString()) as Map<String, dynamic>;
  final symbol = body['symbol'] as String?;
  final quantity = (body['quantity'] as num?)?.toDouble();
  final costBasis = (body['costBasis'] as num?)?.toDouble();
  if (symbol == null || symbol.trim().isEmpty) {
    return _json({'error': 'symbol gerekli'}, status: 400);
  }
  if (quantity == null || quantity <= 0) {
    return _json({'error': 'quantity 0\'dan büyük olmalı'}, status: 400);
  }
  if (costBasis == null || costBasis < 0) {
    return _json({'error': 'costBasis gerekli'}, status: 400);
  }
  await portfolio.upsert(userId, symbol, quantity, costBasis);
  return _json({'symbol': symbol.trim().toUpperCase()});
}

Future<Response> _portfolioRemoveHandler(
    Request request, String userId, PortfolioStore portfolio) async {
  final body = jsonDecode(await request.readAsString()) as Map<String, dynamic>;
  final symbol = body['symbol'] as String?;
  if (symbol == null || symbol.trim().isEmpty) {
    return _json({'error': 'symbol gerekli'}, status: 400);
  }
  final removed = await portfolio.remove(userId, symbol);
  return _json({'symbol': symbol.trim().toUpperCase(), 'removed': removed});
}

Future<Response> _trackedGetHandler(
    Request request, String userId, TrackedSymbolStore tracked) async {
  return _json({'symbol': await tracked.getFor(userId)});
}

Future<Response> _trackedSetHandler(
    Request request, String userId, TrackedSymbolStore tracked) async {
  final body = jsonDecode(await request.readAsString()) as Map<String, dynamic>;
  final symbol = body['symbol'] as String?;
  if (symbol == null || symbol.trim().isEmpty) {
    return _json({'error': 'symbol gerekli'}, status: 400);
  }
  await tracked.setFor(userId, symbol);
  return _json({'symbol': symbol.trim().toUpperCase()});
}

Future<Response> _notificationsGetHandler(
    Request request, String userId, NotificationStore notifications) async {
  final page = int.tryParse(request.url.queryParameters['page'] ?? '') ?? 1;
  final category = request.url.queryParameters['category'];
  return _json(await notifications.page(userId, page, category: category));
}

bool _checkInProgress = false;

Future<Response> _checkNowHandler(Request request, String userId,
    MonthlyLowChecker checker, WatchlistStore watchlist) async {
  if (_checkInProgress) {
    return _json({'started': false, 'message': 'Zaten devam eden bir kontrol var.'});
  }
  _checkInProgress = true;
  // Tüm kullanıcıları kapsayan global bir tarama (istekten bağımsız arka
  // planda çalışır); buton sadece bunu erkenden tetikler.
  checker.checkAll().catchError((e) {
    stderr.writeln('Manuel kontrol başarısız: $e');
    return 0;
  }).whenComplete(() => _checkInProgress = false);
  final symbolCount = (await watchlist.symbolsFor(userId)).length;
  return _json({'started': true, 'symbolCount': symbolCount});
}

void main(List<String> args) async {
  final supabaseConfig = SupabaseConfig(
    url: requireEnv('SUPABASE_URL'),
    serviceKey: requireEnv('SUPABASE_SERVICE_KEY'),
  );
  final watchlist = WatchlistStore(supabaseConfig, _httpClient);
  final notifications = NotificationStore(supabaseConfig, _httpClient);
  final favorites = FavoritesStore(supabaseConfig, _httpClient);
  final technicalWatchlist = TechnicalWatchlistStore(supabaseConfig, _httpClient);
  final dividendWatchlist = DividendWatchlistStore(supabaseConfig, _httpClient);
  final fundamentalsWatchlist = FundamentalsWatchlistStore(supabaseConfig, _httpClient);
  final trackedSymbol = TrackedSymbolStore(supabaseConfig, _httpClient);
  final technicalScoreCache =
      TechnicalScoreCache(_httpClient, watchlist, notifications);
  final portfolio = PortfolioStore(supabaseConfig, _httpClient);
  final stockStore = StockStore(supabaseConfig, _httpClient);
  final financialStatementStore = FinancialStatementStore(supabaseConfig, _httpClient);
  final stockScoreStore = StockScoreStore(supabaseConfig, _httpClient);
  final fundamentalsCache =
      FundamentalsCache(_httpClient, stockStore, financialStatementStore, stockScoreStore);

  final checker = MonthlyLowChecker(_httpClient, watchlist, notifications);

  // Sunucu açılışında bir kez, sonrasında günde bir kez otomatik kontrol.
  // Not: Bu zamanlayıcının çalışması için proxy sunucusunun sürekli açık
  // kalması gerekir (bilgisayar kapanırsa/işlem durursa kontrol de durur).
  checker.checkAll().catchError((e) {
    stderr.writeln('İlk aylık dip kontrolü başarısız: $e');
    return 0;
  });
  Timer.periodic(const Duration(hours: 24), (_) {
    checker.checkAll().catchError((e) {
      stderr.writeln('Aylık dip kontrolü başarısız: $e');
      return 0;
    });
  });

  // Puan Sıralaması sekmesi için: açılışta bir kez, sonrasında 4 saatte bir
  // arka planda yenilenir (bkz. technical_score_cache.dart — Render'ın
  // ücretsiz planı hareketsizlikte durduğundan bu bellek soğuk başlangıçta
  // sıfırlanır, bu yüzden günlük değil daha sık taranıyor).
  technicalScoreCache.refreshAll().catchError((e) {
    stderr.writeln('İlk puan hesaplaması başarısız: $e');
  });
  Timer.periodic(const Duration(hours: 4), (_) {
    technicalScoreCache.refreshAll().catchError((e) {
      stderr.writeln('Puan hesaplaması başarısız: $e');
    });
  });

  // Temel Analiz için: açılışta bir kez, sonrasında 6 saatte bir arka planda
  // ön-senkronizasyon (bkz. fundamentals_cache.dart syncWatchlistedSymbols —
  // bilerek çok yavaş tempoda, MonthlyLowChecker/TechnicalScoreCache'in
  // aksine amaç paralellik değil Yahoo'nun crumb endpoint'ine yayılmış yük).
  // 24 saatlik DB cache TTL'sinden daha sık: cold start sonrası taze kalsın.
  fundamentalsCache.syncWatchlistedSymbols(fundamentalsWatchlist).catchError((e) {
    stderr.writeln('İlk temel analiz senkronizasyonu başarısız: $e');
  });
  Timer.periodic(const Duration(hours: 6), (_) {
    fundamentalsCache.syncWatchlistedSymbols(fundamentalsWatchlist).catchError((e) {
      stderr.writeln('Temel analiz senkronizasyonu başarısız: $e');
    });
  });

  final router = Router()
    ..get('/health', (r) => Response.ok('ok'))
    ..get('/api/search', _searchHandler)
    ..get('/api/candles', _candlesHandler)
    ..get(
      '/api/watchlist',
      _withAuth(supabaseConfig, (r, uid) => _watchlistGetHandler(r, uid, watchlist)),
    )
    ..post(
      '/api/watchlist/add',
      _withAuth(supabaseConfig, (r, uid) => _watchlistAddHandler(r, uid, watchlist)),
    )
    ..post(
      '/api/watchlist/remove',
      _withAuth(supabaseConfig, (r, uid) => _watchlistRemoveHandler(r, uid, watchlist)),
    )
    ..post(
      '/api/watchlist/bulk-add',
      _withAuth(supabaseConfig, (r, uid) => _watchlistBulkAddHandler(r, uid, watchlist)),
    )
    ..get(
      '/api/favorites',
      _withAuth(supabaseConfig, (r, uid) => _favoritesGetHandler(r, uid, favorites)),
    )
    ..post(
      '/api/favorites/add',
      _withAuth(supabaseConfig, (r, uid) => _favoritesAddHandler(r, uid, favorites)),
    )
    ..post(
      '/api/favorites/remove',
      _withAuth(supabaseConfig, (r, uid) => _favoritesRemoveHandler(r, uid, favorites)),
    )
    ..get('/api/technical', _technicalHandler)
    ..get(
      '/api/technical-watchlist',
      _withAuth(supabaseConfig,
          (r, uid) => _technicalWatchlistGetHandler(r, uid, technicalWatchlist)),
    )
    ..post(
      '/api/technical-watchlist/add',
      _withAuth(supabaseConfig,
          (r, uid) => _technicalWatchlistAddHandler(r, uid, technicalWatchlist)),
    )
    ..post(
      '/api/technical-watchlist/remove',
      _withAuth(supabaseConfig,
          (r, uid) => _technicalWatchlistRemoveHandler(r, uid, technicalWatchlist)),
    )
    ..get('/api/dividends', _dividendsHandler)
    ..get('/api/backtest', _backtestHandler)
    ..get(
      '/api/fundamentals/overview',
      (r) => _fundamentalsOverviewHandler(r, fundamentalsCache, stockStore),
    )
    ..get(
      '/api/fundamentals/fair-value',
      (r) => _fundamentalsFairValueHandler(r, fundamentalsCache, stockScoreStore),
    )
    ..get(
      '/api/fundamentals/health-score',
      (r) => _fundamentalsHealthScoreHandler(r, fundamentalsCache, stockScoreStore),
    )
    ..get(
      '/api/fundamentals/protips',
      (r) => _fundamentalsProTipsHandler(r, fundamentalsCache, stockScoreStore),
    )
    ..post(
      '/api/admin/sync-stock/<symbol>',
      (r) => _adminSyncStockHandler(r, fundamentalsCache),
    )
    ..get(
      '/api/dividend-watchlist',
      _withAuth(supabaseConfig,
          (r, uid) => _dividendWatchlistGetHandler(r, uid, dividendWatchlist)),
    )
    ..post(
      '/api/dividend-watchlist/add',
      _withAuth(supabaseConfig,
          (r, uid) => _dividendWatchlistAddHandler(r, uid, dividendWatchlist)),
    )
    ..post(
      '/api/dividend-watchlist/remove',
      _withAuth(supabaseConfig,
          (r, uid) => _dividendWatchlistRemoveHandler(r, uid, dividendWatchlist)),
    )
    ..get(
      '/api/fundamentals-watchlist',
      _withAuth(supabaseConfig,
          (r, uid) => _fundamentalsWatchlistGetHandler(r, uid, fundamentalsWatchlist)),
    )
    ..post(
      '/api/fundamentals-watchlist/add',
      _withAuth(supabaseConfig,
          (r, uid) => _fundamentalsWatchlistAddHandler(r, uid, fundamentalsWatchlist)),
    )
    ..post(
      '/api/fundamentals-watchlist/remove',
      _withAuth(supabaseConfig,
          (r, uid) => _fundamentalsWatchlistRemoveHandler(r, uid, fundamentalsWatchlist)),
    )
    ..get(
      '/api/technical-scores',
      _withAuth(supabaseConfig,
          (r, uid) => _technicalScoresHandler(r, uid, watchlist, technicalScoreCache)),
    )
    ..post(
      '/api/technical-scores/refresh',
      _withAuth(supabaseConfig,
          (r, uid) => _technicalScoresRefreshHandler(r, uid, technicalScoreCache)),
    )
    ..get(
      '/api/portfolio',
      _withAuth(supabaseConfig, (r, uid) => _portfolioGetHandler(r, uid, portfolio)),
    )
    ..post(
      '/api/portfolio/add',
      _withAuth(supabaseConfig, (r, uid) => _portfolioAddHandler(r, uid, portfolio)),
    )
    ..post(
      '/api/portfolio/remove',
      _withAuth(supabaseConfig, (r, uid) => _portfolioRemoveHandler(r, uid, portfolio)),
    )
    ..get(
      '/api/tracked',
      _withAuth(supabaseConfig, (r, uid) => _trackedGetHandler(r, uid, trackedSymbol)),
    )
    ..post(
      '/api/tracked',
      _withAuth(supabaseConfig, (r, uid) => _trackedSetHandler(r, uid, trackedSymbol)),
    )
    ..get(
      '/api/notifications',
      _withAuth(supabaseConfig, (r, uid) => _notificationsGetHandler(r, uid, notifications)),
    )
    ..post(
      '/api/notifications/check-now',
      _withAuth(supabaseConfig, (r, uid) => _checkNowHandler(r, uid, checker, watchlist)),
    );

  final handler = const Pipeline()
      .addMiddleware(_cors())
      .addMiddleware(_errorHandling())
      .addHandler(router.call);

  final port = int.tryParse(Platform.environment['PORT'] ?? '') ?? 8787;
  final server = await shelf_io.serve(handler, InternetAddress.anyIPv4, port);
  print('Proxy sunucusu çalışıyor: http://localhost:${server.port}');
}
