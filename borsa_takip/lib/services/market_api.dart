import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/backtest.dart';
import '../models/candle.dart';
import '../models/dividend.dart';
import '../models/fundamentals.dart';
import '../models/interval.dart';
import '../models/notification_item.dart';
import '../models/portfolio.dart';
import '../models/scored_symbol.dart';
import '../models/symbol.dart';
import '../models/technical_analysis.dart';

class ApiException implements Exception {
  final String message;
  ApiException(this.message);

  @override
  String toString() => message;
}

class MarketApi {
  // Yerelde `flutter run` varsayılan olarak localhost:8787'yi kullanır.
  // Dağıtım build'inde `--dart-define=API_BASE_URL=https://...` ile
  // barındırılan proxy_server adresi verilir (bkz. .github/workflows).
  static const _baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://localhost:8787',
  );

  Future<List<MarketSymbol>> search(String query) async {
    final uri = Uri.parse('$_baseUrl/api/search')
        .replace(queryParameters: {'q': query});
    final resp = await _get(uri);
    final results = (resp['results'] as List).cast<Map<String, dynamic>>();
    return results.map(MarketSymbol.fromJson).toList();
  }

  /// [includeIndicators] `true` ise her mumda RSI(14)/MACD(12,26,9) zaman
  /// serisi de gelir (bkz. models/candle.dart, mum grafiğinin altındaki
  /// RSI/MACD paneli için) — gereksiz hesaplama/veri olmasın diye
  /// varsayılan `false`.
  Future<CandleResult> candles({
    required String symbol,
    required DateTime start,
    required DateTime end,
    required ChartInterval interval,
    bool includeIndicators = false,
  }) async {
    final uri = Uri.parse('$_baseUrl/api/candles').replace(
      queryParameters: {
        'symbol': symbol,
        'start': _formatDate(start),
        'end': _formatDate(end),
        'interval': interval.apiValue,
        if (includeIndicators) 'indicators': 'rsi,macd',
      },
    );
    final resp = await _get(uri);
    return CandleResult.fromJson(resp);
  }

  Future<List<String>> getWatchlist() async {
    final resp = await _get(Uri.parse('$_baseUrl/api/watchlist'));
    return (resp['symbols'] as List).cast<String>();
  }

  /// Eklenen sembolün normalize edilmiş (trim+uppercase) hali ve gerçekten
  /// eklenip eklenmediği döner; artık backend'in tam listeyi tekrar Supabase'e
  /// sorup döndürmesine gerek kalmasın diye çağıran taraf yerel listesine bu
  /// ikisiyle kendisi ekliyor (bkz. notifications_screen.dart _addSymbol).
  Future<({String symbol, bool added})> addToWatchlist(String symbol) async {
    final resp = await _post(
      Uri.parse('$_baseUrl/api/watchlist/add'),
      {'symbol': symbol},
    );
    return (
      symbol: resp['symbol'] as String,
      added: resp['added'] as bool? ?? false,
    );
  }

  Future<({String symbol, bool removed})> removeFromWatchlist(String symbol) async {
    final resp = await _post(
      Uri.parse('$_baseUrl/api/watchlist/remove'),
      {'symbol': symbol},
    );
    return (
      symbol: resp['symbol'] as String,
      removed: resp['removed'] as bool? ?? false,
    );
  }

  /// preset: 'bist200', 'us200' veya 'crypto300'. Backend zaten bulk-add
  /// sonrası güncel tam listeyi döndürüyor (bkz. bin/server.dart
  /// _watchlistBulkAddHandler); çağıran taraf bunu doğrudan kullanmalı,
  /// ayrıca bir getWatchlist() ile tekrar sorgulamamalı.
  Future<({int added, List<String> symbols})> bulkAddToWatchlist(String preset) async {
    final resp = await _post(
      Uri.parse('$_baseUrl/api/watchlist/bulk-add'),
      {'preset': preset},
    );
    return (
      added: resp['added'] as int,
      symbols: (resp['symbols'] as List).cast<String>(),
    );
  }

  Future<List<String>> getFavorites() async {
    final resp = await _get(Uri.parse('$_baseUrl/api/favorites'));
    return (resp['symbols'] as List).cast<String>();
  }

  Future<({String symbol, bool added})> addToFavorites(String symbol) async {
    final resp = await _post(
      Uri.parse('$_baseUrl/api/favorites/add'),
      {'symbol': symbol},
    );
    return (
      symbol: resp['symbol'] as String,
      added: resp['added'] as bool? ?? false,
    );
  }

  Future<({String symbol, bool removed})> removeFromFavorites(String symbol) async {
    final resp = await _post(
      Uri.parse('$_baseUrl/api/favorites/remove'),
      {'symbol': symbol},
    );
    return (
      symbol: resp['symbol'] as String,
      removed: resp['removed'] as bool? ?? false,
    );
  }

  Future<List<String>> getTechnicalWatchlist() async {
    final resp = await _get(Uri.parse('$_baseUrl/api/technical-watchlist'));
    return (resp['symbols'] as List).cast<String>();
  }

  Future<({String symbol, bool added})> addToTechnicalWatchlist(String symbol) async {
    final resp = await _post(
      Uri.parse('$_baseUrl/api/technical-watchlist/add'),
      {'symbol': symbol},
    );
    return (
      symbol: resp['symbol'] as String,
      added: resp['added'] as bool? ?? false,
    );
  }

  Future<({String symbol, bool removed})> removeFromTechnicalWatchlist(
      String symbol) async {
    final resp = await _post(
      Uri.parse('$_baseUrl/api/technical-watchlist/remove'),
      {'symbol': symbol},
    );
    return (
      symbol: resp['symbol'] as String,
      removed: resp['removed'] as bool? ?? false,
    );
  }

  /// Pivot Noktaları, Hareketli Ortalamalar ve Teknik İndikatörler + özet
  /// (bkz. models/technical_analysis.dart). `/api/candles` gibi auth
  /// gerektirmez — sembole özgü, kullanıcı verisi içermez.
  Future<TechnicalAnalysisResult> technicalAnalysis(String symbol) async {
    final uri = Uri.parse('$_baseUrl/api/technical')
        .replace(queryParameters: {'symbol': symbol});
    final resp = await _get(uri);
    return TechnicalAnalysisResult.fromJson(resp);
  }

  /// Bildirimler sayfasındaki Puan Sıralaması sekmesi: izleme listesindeki
  /// sembolleri [categories] ('bist'/'us'/'crypto' altkümesi) ile filtreleyip
  /// puana göre sıralar (varsayılan yüksekten düşüğe), 50'şerlik sayfalar
  /// halinde döner. Puanlar arka planda önceden hesaplanmış bir önbellekten
  /// gelir (bkz. proxy_server/lib/technical_score_cache.dart) — bu yüzden
  /// anlık değil, `refreshTechnicalScores()` ile tetiklenen son taramayı
  /// yansıtır.
  Future<ScoredSymbolPage> getTechnicalScores({
    required Set<String> categories,
    bool descending = true,
    int page = 1,
  }) async {
    final uri = Uri.parse('$_baseUrl/api/technical-scores').replace(
      queryParameters: {
        'categories': categories.join(','),
        'sort': descending ? 'desc' : 'asc',
        'page': '$page',
      },
    );
    final resp = await _get(uri);
    return ScoredSymbolPage.fromJson(resp);
  }

  /// Puan önbelleğinin arka planda yenilenmesini tetikler; sonucu beklemeden
  /// döner (izleme listesi büyükse dakikalar sürebilir, bkz. `checkNow`).
  Future<bool> refreshTechnicalScores() async {
    final resp = await _post(Uri.parse('$_baseUrl/api/technical-scores/refresh'), {});
    return resp['started'] as bool? ?? false;
  }

  /// Bir sembolün son 15 yıllık temettü geçmişi (bkz. models/dividend.dart,
  /// proxy_server/lib/yahoo_client.dart fetchDividends). `/api/technical`
  /// gibi auth gerektirmez.
  Future<DividendHistory> getDividends(String symbol) async {
    final uri = Uri.parse('$_baseUrl/api/dividends')
        .replace(queryParameters: {'symbol': symbol});
    final resp = await _get(uri);
    return DividendHistory.fromJson(resp);
  }

  Future<List<String>> getDividendWatchlist() async {
    final resp = await _get(Uri.parse('$_baseUrl/api/dividend-watchlist'));
    return (resp['symbols'] as List).cast<String>();
  }

  Future<({String symbol, bool added})> addToDividendWatchlist(String symbol) async {
    final resp = await _post(
      Uri.parse('$_baseUrl/api/dividend-watchlist/add'),
      {'symbol': symbol},
    );
    return (
      symbol: resp['symbol'] as String,
      added: resp['added'] as bool? ?? false,
    );
  }

  Future<({String symbol, bool removed})> removeFromDividendWatchlist(String symbol) async {
    final resp = await _post(
      Uri.parse('$_baseUrl/api/dividend-watchlist/remove'),
      {'symbol': symbol},
    );
    return (
      symbol: resp['symbol'] as String,
      removed: resp['removed'] as bool? ?? false,
    );
  }

  /// "Bu puan eşiğine göre alım-satım yapsaydım geçmişte nasıl performans
  /// verirdi" simülasyonu (bkz. models/backtest.dart,
  /// proxy_server/lib/backtest.dart runBacktest). `/api/technical` gibi
  /// auth gerektirmez.
  Future<BacktestResult> runBacktest({
    required String symbol,
    required DateTime start,
    required DateTime end,
    required int buyThreshold,
    required int sellThreshold,
    required double initialCapital,
  }) async {
    final uri = Uri.parse('$_baseUrl/api/backtest').replace(queryParameters: {
      'symbol': symbol,
      'start': _formatDate(start),
      'end': _formatDate(end),
      'buyThreshold': '$buyThreshold',
      'sellThreshold': '$sellThreshold',
      'initialCapital': '$initialCapital',
    });
    final resp = await _get(uri);
    return BacktestResult.fromJson(resp);
  }

  /// Temel Analiz sekmesi (bkz. models/fundamentals.dart). Kendi bağımsız
  /// izleme listesi vardır (`FundamentalsWatchlistStore` — bkz.
  /// getFundamentalsWatchlist/addToFundamentalsWatchlist/
  /// removeFromFundamentalsWatchlist aşağıda); önceden Teknik sekmesiyle
  /// aynı listeyi paylaşıyordu, artık ayrı. Bu dördü `/api/technical` gibi
  /// auth gerektirmez; backend'de Supabase'de 24 saat önbelleklenir (bkz.
  /// proxy_server/lib/fundamentals_cache.dart), bu yüzden ilk istek dışında
  /// hızlıdır.
  Future<StockOverview> getFundamentalOverview(String symbol) async {
    final uri = Uri.parse('$_baseUrl/api/fundamentals/overview')
        .replace(queryParameters: {'symbol': symbol});
    final resp = await _get(uri);
    return StockOverview.fromJson(resp);
  }

  Future<FairValueResult> getFairValue(String symbol) async {
    final uri = Uri.parse('$_baseUrl/api/fundamentals/fair-value')
        .replace(queryParameters: {'symbol': symbol});
    final resp = await _get(uri);
    return FairValueResult.fromJson(resp);
  }

  Future<HealthScoreResult> getHealthScore(String symbol) async {
    final uri = Uri.parse('$_baseUrl/api/fundamentals/health-score')
        .replace(queryParameters: {'symbol': symbol});
    final resp = await _get(uri);
    return HealthScoreResult.fromJson(resp);
  }

  Future<ProTipsResult> getFundamentalProTips(String symbol) async {
    final uri = Uri.parse('$_baseUrl/api/fundamentals/protips')
        .replace(queryParameters: {'symbol': symbol});
    final resp = await _get(uri);
    return ProTipsResult.fromJson(resp);
  }

  Future<List<String>> getFundamentalsWatchlist() async {
    final resp = await _get(Uri.parse('$_baseUrl/api/fundamentals-watchlist'));
    return (resp['symbols'] as List).cast<String>();
  }

  Future<({String symbol, bool added})> addToFundamentalsWatchlist(String symbol) async {
    final resp = await _post(
      Uri.parse('$_baseUrl/api/fundamentals-watchlist/add'),
      {'symbol': symbol},
    );
    return (
      symbol: resp['symbol'] as String,
      added: resp['added'] as bool? ?? false,
    );
  }

  Future<({String symbol, bool removed})> removeFromFundamentalsWatchlist(
      String symbol) async {
    final resp = await _post(
      Uri.parse('$_baseUrl/api/fundamentals-watchlist/remove'),
      {'symbol': symbol},
    );
    return (
      symbol: resp['symbol'] as String,
      removed: resp['removed'] as bool? ?? false,
    );
  }

  /// Portföy sekmesi: pozisyonlar + canlı fiyat/TL karşılığıyla hesaplanmış
  /// özet (bkz. models/portfolio.dart, proxy_server/lib/portfolio_summary.dart).
  Future<PortfolioSummary> getPortfolio() async {
    final resp = await _get(Uri.parse('$_baseUrl/api/portfolio'));
    return PortfolioSummary.fromJson(resp);
  }

  /// Aynı sembol zaten portföydeyse mevcut adet/maliyeti YENİ değerlerle
  /// tamamen değiştirir (bkz. proxy_server/lib/store.dart PortfolioStore).
  Future<void> addPortfolioHolding({
    required String symbol,
    required double quantity,
    required double costBasis,
  }) async {
    await _post(Uri.parse('$_baseUrl/api/portfolio/add'), {
      'symbol': symbol,
      'quantity': quantity,
      'costBasis': costBasis,
    });
  }

  Future<void> removePortfolioHolding(String symbol) async {
    await _post(Uri.parse('$_baseUrl/api/portfolio/remove'), {'symbol': symbol});
  }

  /// Takip sekmesinde gösterilen, kullanıcı başına kalıcı olarak saklanan
  /// aktif sembol. Hiç ayarlanmadıysa null döner.
  Future<String?> getTrackedSymbol() async {
    final resp = await _get(Uri.parse('$_baseUrl/api/tracked'));
    return resp['symbol'] as String?;
  }

  Future<void> setTrackedSymbol(String symbol) async {
    await _post(Uri.parse('$_baseUrl/api/tracked'), {'symbol': symbol});
  }

  /// Ayarlar sekmesinde kullanıcının kapattığı alt gezinme sekmelerinin
  /// anahtar listesi (ör. `['chart', 'backtest']`). Hiç ayarlanmadıysa boş
  /// liste döner (tüm sekmeler açık).
  Future<List<String>> getHiddenTabs() async {
    final resp = await _get(Uri.parse('$_baseUrl/api/tab-preferences'));
    final raw = resp['hiddenTabs'] as List?;
    return raw?.cast<String>() ?? [];
  }

  Future<void> setHiddenTabs(List<String> hiddenTabs) async {
    await _post(
      Uri.parse('$_baseUrl/api/tab-preferences'),
      {'hiddenTabs': hiddenTabs},
    );
  }

  /// [category]: 'bist', 'us' veya 'crypto'; verilmezse tüm bildirimler.
  Future<NotificationPage> getNotifications({int page = 1, String? category}) async {
    final uri = Uri.parse('$_baseUrl/api/notifications').replace(
      queryParameters: {
        'page': '$page',
        'category': ?category,
      },
    );
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

  /// Watchlist/notifications uçları proxy_server'da bu token'ı doğrulayıp
  /// isteği o kullanıcıya kısıtlar (bkz. bin/server.dart _authenticate).
  Map<String, String> get _authHeaders {
    final token = Supabase.instance.client.auth.currentSession?.accessToken;
    return token == null ? {} : {'Authorization': 'Bearer $token'};
  }

  Future<Map<String, dynamic>> _get(Uri uri) =>
      _sendWithAuthRetry(() => http.get(uri, headers: _authHeaders));

  Future<Map<String, dynamic>> _post(Uri uri, Map<String, dynamic> body) => _sendWithAuthRetry(
        () => http.post(
          uri,
          headers: {'Content-Type': 'application/json', ..._authHeaders},
          body: jsonEncode(body),
        ),
      );

  /// Supabase access token'ı süresi dolmuş olabilir (bkz. _authHeaders); bu
  /// durumda proxy 401 döner. Kullanıcıya doğrudan bir hata göstermeden önce
  /// oturumu bir kez yenileyip isteği tekrar deniyoruz — [send] her
  /// çağrıldığında _authHeaders'ı yeniden okuduğundan (kapanış içinde), retry
  /// otomatik olarak yenilenmiş token'ı kullanır.
  Future<Map<String, dynamic>> _sendWithAuthRetry(
    Future<http.Response> Function() send,
  ) async {
    http.Response resp;
    try {
      resp = await send();
    } catch (e) {
      throw ApiException(
        'Proxy sunucusuna bağlanılamadı. "dart run bin/server.dart" '
        'komutunun proxy_server klasöründe çalıştığından emin olun.',
      );
    }
    if (resp.statusCode == 401) {
      try {
        await Supabase.instance.client.auth.refreshSession();
        resp = await send();
      } catch (_) {
        // Yenileme başarısız oldu; orijinal 401 yanıtıyla devam edip
        // _handle'ın normal hata mesajını göstermesine izin ver.
      }
    }
    return _handle(resp);
  }

  Map<String, dynamic> _handle(http.Response resp) {
    final Map<String, dynamic> body;
    try {
      body = jsonDecode(resp.body) as Map<String, dynamic>;
    } catch (_) {
      // Proxy JSON olmayan bir yanıt döndürdüyse (ör. shelf_router'ın düz
      // metin "Route not found" 404'ü — sunucu henüz güncel kodu deploy
      // etmemiş olabilir, ya da Render soğuk başlangıçta HTML hata sayfası
      // dönebilir) jsonDecode'un ham "Unexpected token" hatasını olduğu
      // gibi kullanıcıya göstermek yerine anlaşılır bir mesaj veriyoruz.
      throw ApiException(
        'Sunucudan beklenmeyen bir yanıt geldi (HTTP ${resp.statusCode}). '
        'Proxy sunucusu güncel olmayabilir veya geçici olarak erişilemiyor '
        'olabilir.',
      );
    }
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
