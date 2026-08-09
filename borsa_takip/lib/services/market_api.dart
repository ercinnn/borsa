import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/candle.dart';
import '../models/interval.dart';
import '../models/notification_item.dart';
import '../models/symbol.dart';

class ApiException implements Exception {
  final String message;
  ApiException(this.message);

  @override
  String toString() => message;
}

class MarketApi {
  static const _baseUrl = 'http://localhost:8787';

  Future<List<MarketSymbol>> search(String query) async {
    final uri = Uri.parse('$_baseUrl/api/search')
        .replace(queryParameters: {'q': query});
    final resp = await _get(uri);
    final results = (resp['results'] as List).cast<Map<String, dynamic>>();
    return results.map(MarketSymbol.fromJson).toList();
  }

  Future<CandleResult> candles({
    required String symbol,
    required DateTime start,
    required DateTime end,
    required ChartInterval interval,
  }) async {
    final uri = Uri.parse('$_baseUrl/api/candles').replace(
      queryParameters: {
        'symbol': symbol,
        'start': _formatDate(start),
        'end': _formatDate(end),
        'interval': interval.apiValue,
      },
    );
    final resp = await _get(uri);
    return CandleResult.fromJson(resp);
  }

  Future<List<String>> getWatchlist() async {
    final resp = await _get(Uri.parse('$_baseUrl/api/watchlist'));
    return (resp['symbols'] as List).cast<String>();
  }

  Future<List<String>> addToWatchlist(String symbol) async {
    final resp = await _post(
      Uri.parse('$_baseUrl/api/watchlist/add'),
      {'symbol': symbol},
    );
    return (resp['symbols'] as List).cast<String>();
  }

  Future<List<String>> removeFromWatchlist(String symbol) async {
    final resp = await _post(
      Uri.parse('$_baseUrl/api/watchlist/remove'),
      {'symbol': symbol},
    );
    return (resp['symbols'] as List).cast<String>();
  }

  /// preset: 'bist100', 'us100' veya 'crypto200'. Eklenen sembol sayısını
  /// döndürür.
  Future<int> bulkAddToWatchlist(String preset) async {
    final resp = await _post(
      Uri.parse('$_baseUrl/api/watchlist/bulk-add'),
      {'preset': preset},
    );
    return resp['added'] as int;
  }

  Future<NotificationPage> getNotifications({int page = 1}) async {
    final uri = Uri.parse('$_baseUrl/api/notifications')
        .replace(queryParameters: {'page': '$page'});
    final resp = await _get(uri);
    return NotificationPage.fromJson(resp);
  }

  /// Kontrolü arka planda başlatır; sonucu beklemeden döner (izleme listesi
  /// büyük olabileceğinden istek uzun sürebilir).
  Future<bool> checkNow() async {
    final resp =
        await _post(Uri.parse('$_baseUrl/api/notifications/check-now'), {});
    return resp['started'] as bool? ?? false;
  }

  Future<Map<String, dynamic>> _get(Uri uri) async {
    late final http.Response resp;
    try {
      resp = await http.get(uri);
    } catch (e) {
      throw ApiException(
        'Proxy sunucusuna bağlanılamadı. "dart run bin/server.dart" '
        'komutunun proxy_server klasöründe çalıştığından emin olun.',
      );
    }
    return _handle(resp);
  }

  Future<Map<String, dynamic>> _post(Uri uri, Map<String, dynamic> body) async {
    late final http.Response resp;
    try {
      resp = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      );
    } catch (e) {
      throw ApiException(
        'Proxy sunucusuna bağlanılamadı. "dart run bin/server.dart" '
        'komutunun proxy_server klasöründe çalıştığından emin olun.',
      );
    }
    return _handle(resp);
  }

  Map<String, dynamic> _handle(http.Response resp) {
    final body = jsonDecode(resp.body) as Map<String, dynamic>;
    if (resp.statusCode != 200) {
      throw ApiException(body['error'] as String? ?? 'Bilinmeyen hata');
    }
    return body;
  }

  String _formatDate(DateTime d) {
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '${d.year}-$m-$day';
  }
}
