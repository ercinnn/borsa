import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';

import '../lib/coingecko_client.dart';
import '../lib/monthly_low_checker.dart';
import '../lib/preset_lists.dart';
import '../lib/store.dart';
import '../lib/yahoo_client.dart';

final _httpClient = http.Client();

Middleware _cors() {
  const headers = {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Methods': 'GET, POST, DELETE, OPTIONS',
    'Access-Control-Allow-Headers': 'Content-Type',
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
// parametreleri. '12mo' Yahoo'da yok; 1 aylık mumlar çekilip 12'şerli
// gruplar halinde sunucu tarafında birleştiriliyor.
const _yahooIntervalFor = {
  '1d': '1d',
  '1wk': '1wk',
  '1mo': '1mo',
  '3mo': '3mo',
  '12mo': '1mo',
};

String _twoDigits(int n) => n.toString().padLeft(2, '0');

String _formatPeriod(String interval, DateTime start, DateTime end) {
  switch (interval) {
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

Future<Response> _watchlistGetHandler(
    Request request, WatchlistStore watchlist) async {
  return _json({'symbols': watchlist.symbols});
}

Future<Response> _watchlistAddHandler(
    Request request, WatchlistStore watchlist) async {
  final body = jsonDecode(await request.readAsString()) as Map<String, dynamic>;
  final symbol = body['symbol'] as String?;
  if (symbol == null || symbol.trim().isEmpty) {
    return _json({'error': 'symbol gerekli'}, status: 400);
  }
  final added = await watchlist.add(symbol);
  return _json({'symbols': watchlist.symbols, 'added': added});
}

Future<Response> _watchlistRemoveHandler(
    Request request, WatchlistStore watchlist) async {
  final body = jsonDecode(await request.readAsString()) as Map<String, dynamic>;
  final symbol = body['symbol'] as String?;
  if (symbol == null || symbol.trim().isEmpty) {
    return _json({'error': 'symbol gerekli'}, status: 400);
  }
  final removed = await watchlist.remove(symbol);
  return _json({'symbols': watchlist.symbols, 'removed': removed});
}

Future<Response> _watchlistBulkAddHandler(
    Request request, WatchlistStore watchlist) async {
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
        symbols = await fetchTopCryptoSymbols(_httpClient, 200);
      } catch (e) {
        return _json({'error': 'Kripto listesi alınamadı: $e'}, status: 502);
      }
      break;
    default:
      return _json(
        {'error': 'Geçersiz preset: bist100, us100 veya crypto200 olmalı'},
        status: 400,
      );
  }

  final added = await watchlist.addAll(symbols);
  return _json({'symbols': watchlist.symbols, 'added': added});
}

Future<Response> _notificationsGetHandler(
    Request request, NotificationStore notifications) async {
  final page = int.tryParse(request.url.queryParameters['page'] ?? '') ?? 1;
  return _json(notifications.page(page));
}

bool _checkInProgress = false;

Future<Response> _checkNowHandler(
    Request request, MonthlyLowChecker checker, WatchlistStore watchlist) async {
  if (_checkInProgress) {
    return _json({'started': false, 'message': 'Zaten devam eden bir kontrol var.'});
  }
  _checkInProgress = true;
  // Sembol sayısı fazla olabileceğinden (BIST100 + ABD100 + kripto200 gibi
  // toplu eklemeler sonrası) kontrol istekten bağımsız arka planda çalışır.
  checker.checkAll().catchError((e) {
    stderr.writeln('Manuel kontrol başarısız: $e');
    return 0;
  }).whenComplete(() => _checkInProgress = false);
  return _json({'started': true, 'symbolCount': watchlist.symbols.length});
}

void main(List<String> args) async {
  final dataDir = Directory('data');
  final watchlist = WatchlistStore(File('${dataDir.path}/watchlist.json'));
  final notifications =
      NotificationStore(File('${dataDir.path}/notifications.json'));
  await watchlist.load();
  await notifications.load();

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
    ..get('/api/search', _searchHandler)
    ..get('/api/candles', _candlesHandler)
    ..get('/api/watchlist', (r) => _watchlistGetHandler(r, watchlist))
    ..post('/api/watchlist/add', (r) => _watchlistAddHandler(r, watchlist))
    ..post('/api/watchlist/remove', (r) => _watchlistRemoveHandler(r, watchlist))
    ..post('/api/watchlist/bulk-add', (r) => _watchlistBulkAddHandler(r, watchlist))
    ..get('/api/notifications', (r) => _notificationsGetHandler(r, notifications))
    ..post('/api/notifications/check-now', (r) => _checkNowHandler(r, checker, watchlist));

  final handler =
      const Pipeline().addMiddleware(_cors()).addHandler(router.call);

  final port = int.tryParse(Platform.environment['PORT'] ?? '') ?? 8787;
  final server = await shelf_io.serve(handler, InternetAddress.anyIPv4, port);
  print('Proxy sunucusu çalışıyor: http://localhost:${server.port}');
}
