import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';

import '../lib/coingecko_client.dart';
import '../lib/env.dart';
import '../lib/monthly_low_checker.dart';
import '../lib/preset_lists.dart';
import '../lib/store.dart';
import '../lib/supabase_client.dart';
import '../lib/yahoo_client.dart';

final _httpClient = http.Client();
final _coingeckoApiKey = env('COINGECKO_API_KEY');

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
    return _json({'results': results});
  } catch (e) {
    return _json({'error': 'Arama sırasında hata: $e'}, status: 502);
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

    return _json({
      'symbol': symbol,
      'currency': data.currency,
      'candles': candles,
    });
  } on YahooException catch (e) {
    return _json({'error': e.message}, status: 404);
  } catch (e) {
    return _json({'error': 'Veri alınırken hata: $e'}, status: 502);
  }
}

/// `Authorization: Bearer <supabase access token>` header'ını Supabase'in
/// `/auth/v1/user` ucuna sorup doğrular, geçerliyse kullanıcı id'sini döner.
/// Bu proje hiçbir yerde ağır bir SDK kullanmadığından (yahoo_client,
/// coingecko_client, supabase_client hepsi çıplak `http`) JWT'yi yerel
/// imza doğrulamak yerine bu tek HTTP çağrısını tercih ettik.
Future<String?> _authenticate(Request request, SupabaseConfig config) async {
  final authHeader = request.headers['authorization'];
  if (authHeader == null || !authHeader.startsWith('Bearer ')) return null;
  final token = authHeader.substring(7);
  try {
    final resp = await _httpClient.get(
      Uri.parse('${config.url}/auth/v1/user'),
      headers: {'Authorization': 'Bearer $token', 'apikey': config.serviceKey},
    );
    if (resp.statusCode != 200) return null;
    final user = jsonDecode(resp.body) as Map<String, dynamic>;
    return user['id'] as String?;
  } catch (_) {
    return null;
  }
}

Response _unauthorized() => _json({'error': 'Giriş gerekli'}, status: 401);

Future<Response> _watchlistGetHandler(
    Request request, WatchlistStore watchlist, SupabaseConfig config) async {
  final userId = await _authenticate(request, config);
  if (userId == null) return _unauthorized();
  return _json({'symbols': await watchlist.symbolsFor(userId)});
}

Future<Response> _watchlistAddHandler(
    Request request, WatchlistStore watchlist, SupabaseConfig config) async {
  final userId = await _authenticate(request, config);
  if (userId == null) return _unauthorized();
  final body = jsonDecode(await request.readAsString()) as Map<String, dynamic>;
  final symbol = body['symbol'] as String?;
  if (symbol == null || symbol.trim().isEmpty) {
    return _json({'error': 'symbol gerekli'}, status: 400);
  }
  final added = await watchlist.add(userId, symbol);
  return _json({'symbols': await watchlist.symbolsFor(userId), 'added': added});
}

Future<Response> _watchlistRemoveHandler(
    Request request, WatchlistStore watchlist, SupabaseConfig config) async {
  final userId = await _authenticate(request, config);
  if (userId == null) return _unauthorized();
  final body = jsonDecode(await request.readAsString()) as Map<String, dynamic>;
  final symbol = body['symbol'] as String?;
  if (symbol == null || symbol.trim().isEmpty) {
    return _json({'error': 'symbol gerekli'}, status: 400);
  }
  final removed = await watchlist.remove(userId, symbol);
  return _json({'symbols': await watchlist.symbolsFor(userId), 'removed': removed});
}

Future<Response> _watchlistBulkAddHandler(
    Request request, WatchlistStore watchlist, SupabaseConfig config) async {
  final userId = await _authenticate(request, config);
  if (userId == null) return _unauthorized();
  final body = jsonDecode(await request.readAsString()) as Map<String, dynamic>;
  final preset = body['preset'] as String?;

  List<String> symbols;
  switch (preset) {
    case 'bist100':
      symbols = bist100Symbols;
      break;
    case 'us100':
      symbols = usPopular100Symbols;
      break;
    case 'crypto200':
      try {
        symbols = await fetchTopCryptoSymbols(_httpClient, 200,
            apiKey: _coingeckoApiKey);
      } catch (e) {
        stderr.writeln('CoinGecko fetch failed, statik yedek listeye düşülüyor: $e');
        symbols = cryptoFallbackSymbols;
      }
      break;
    default:
      return _json(
        {'error': 'Geçersiz preset: bist100, us100 veya crypto200 olmalı'},
        status: 400,
      );
  }

  final added = await watchlist.addAll(userId, symbols);
  return _json({'symbols': await watchlist.symbolsFor(userId), 'added': added});
}

Future<Response> _favoritesGetHandler(
    Request request, FavoritesStore favorites, SupabaseConfig config) async {
  final userId = await _authenticate(request, config);
  if (userId == null) return _unauthorized();
  return _json({'symbols': await favorites.symbolsFor(userId)});
}

Future<Response> _favoritesAddHandler(
    Request request, FavoritesStore favorites, SupabaseConfig config) async {
  final userId = await _authenticate(request, config);
  if (userId == null) return _unauthorized();
  final body = jsonDecode(await request.readAsString()) as Map<String, dynamic>;
  final symbol = body['symbol'] as String?;
  if (symbol == null || symbol.trim().isEmpty) {
    return _json({'error': 'symbol gerekli'}, status: 400);
  }
  final added = await favorites.add(userId, symbol);
  return _json({'symbols': await favorites.symbolsFor(userId), 'added': added});
}

Future<Response> _favoritesRemoveHandler(
    Request request, FavoritesStore favorites, SupabaseConfig config) async {
  final userId = await _authenticate(request, config);
  if (userId == null) return _unauthorized();
  final body = jsonDecode(await request.readAsString()) as Map<String, dynamic>;
  final symbol = body['symbol'] as String?;
  if (symbol == null || symbol.trim().isEmpty) {
    return _json({'error': 'symbol gerekli'}, status: 400);
  }
  final removed = await favorites.remove(userId, symbol);
  return _json({'symbols': await favorites.symbolsFor(userId), 'removed': removed});
}

Future<Response> _trackedGetHandler(
    Request request, TrackedSymbolStore tracked, SupabaseConfig config) async {
  final userId = await _authenticate(request, config);
  if (userId == null) return _unauthorized();
  return _json({'symbol': await tracked.getFor(userId)});
}

Future<Response> _trackedSetHandler(
    Request request, TrackedSymbolStore tracked, SupabaseConfig config) async {
  final userId = await _authenticate(request, config);
  if (userId == null) return _unauthorized();
  final body = jsonDecode(await request.readAsString()) as Map<String, dynamic>;
  final symbol = body['symbol'] as String?;
  if (symbol == null || symbol.trim().isEmpty) {
    return _json({'error': 'symbol gerekli'}, status: 400);
  }
  await tracked.setFor(userId, symbol);
  return _json({'symbol': symbol.trim().toUpperCase()});
}

Future<Response> _notificationsGetHandler(
    Request request, NotificationStore notifications, SupabaseConfig config) async {
  final userId = await _authenticate(request, config);
  if (userId == null) return _unauthorized();
  final page = int.tryParse(request.url.queryParameters['page'] ?? '') ?? 1;
  final category = request.url.queryParameters['category'];
  return _json(await notifications.page(userId, page, category: category));
}

bool _checkInProgress = false;

Future<Response> _checkNowHandler(Request request, MonthlyLowChecker checker,
    WatchlistStore watchlist, SupabaseConfig config) async {
  final userId = await _authenticate(request, config);
  if (userId == null) return _unauthorized();
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
  final trackedSymbol = TrackedSymbolStore(supabaseConfig, _httpClient);

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

  final router = Router()
    ..get('/health', (r) => Response.ok('ok'))
    ..get('/api/search', _searchHandler)
    ..get('/api/candles', _candlesHandler)
    ..get('/api/watchlist', (r) => _watchlistGetHandler(r, watchlist, supabaseConfig))
    ..post('/api/watchlist/add', (r) => _watchlistAddHandler(r, watchlist, supabaseConfig))
    ..post('/api/watchlist/remove',
        (r) => _watchlistRemoveHandler(r, watchlist, supabaseConfig))
    ..post('/api/watchlist/bulk-add',
        (r) => _watchlistBulkAddHandler(r, watchlist, supabaseConfig))
    ..get('/api/favorites', (r) => _favoritesGetHandler(r, favorites, supabaseConfig))
    ..post('/api/favorites/add',
        (r) => _favoritesAddHandler(r, favorites, supabaseConfig))
    ..post('/api/favorites/remove',
        (r) => _favoritesRemoveHandler(r, favorites, supabaseConfig))
    ..get('/api/tracked', (r) => _trackedGetHandler(r, trackedSymbol, supabaseConfig))
    ..post('/api/tracked', (r) => _trackedSetHandler(r, trackedSymbol, supabaseConfig))
    ..get('/api/notifications',
        (r) => _notificationsGetHandler(r, notifications, supabaseConfig))
    ..post('/api/notifications/check-now',
        (r) => _checkNowHandler(r, checker, watchlist, supabaseConfig));

  final handler =
      const Pipeline().addMiddleware(_cors()).addHandler(router.call);

  final port = int.tryParse(Platform.environment['PORT'] ?? '') ?? 8787;
  final server = await shelf_io.serve(handler, InternetAddress.anyIPv4, port);
  print('Proxy sunucusu çalışıyor: http://localhost:${server.port}');
}
