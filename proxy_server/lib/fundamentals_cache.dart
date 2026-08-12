import 'package:http/http.dart' as http;

import 'fundamental_analysis.dart';
import 'store.dart';
import 'yahoo_fundamentals.dart';

/// `stocks`/`financial_statements`/`stock_scores` tablolarını "24 saatten
/// eskiyse yeniden hesapla" kuralıyla besleyen orkestrasyon katmanı —
/// `technical_score_cache.dart`'ın rolüne benzer ama sonucu bir Dart
/// belleğinde değil doğrudan Supabase'de tutar (Render'ın ücretsiz planı
/// soğuk başlangıçta bellek cache'ini sıfırlıyor; DB-backed olduğundan bu
/// veri süreç yeniden başlasa da hayatta kalır — bu, orijinal istekteki
/// "24 saatlik DB-backed cache" ihtiyacının karşılığı).
///
/// GET endpoint'leri (bkz. bin/server.dart) her istekte Yahoo'ya gitmek
/// yerine [ensureFresh] çağırıp ardından doğrudan Store'lardan okur; yalnızca
/// veri eksik/eskiyse burada canlı Yahoo çağrısı + hesaplama + DB yazımı
/// olur. `POST /api/admin/sync-stock/{symbol}` ise tazelik kontrolünü atlayıp
/// doğrudan [refresh] çağırır.
class FundamentalsCache {
  final http.Client client;
  final StockStore stocks;
  final FinancialStatementStore statements;
  final StockScoreStore scores;

  FundamentalsCache(this.client, this.stocks, this.statements, this.scores);

  static const _dbCacheTtl = Duration(hours: 24);

  // Temel Analiz sayfası bir sembolü açarken 4 endpoint'e (overview/
  // fair-value/health-score/protips) paralel istek atıyor (bkz.
  // fundamentals_screen.dart); hiç senkronlanmamış bir sembolde bu dördü
  // backend'e aynı anda ulaşıp hepsi [ensureFresh] → [refresh] çağırır.
  // Kilit olmadan her biri kendi Yahoo fetch+hesaplama+DB yazımı turunu
  // başlatırsa tek bir sayfa açılışı Yahoo'ya 4 kat (overview+history ayrı
  // sayılırsa 8 kat) yük bindirir — canlıda 429 riskini büyüten asıl
  // sebeplerden biri buydu. Devam eden bir refresh varsa yeni çağrılar onu
  // paylaşır.
  final Map<String, Future<void>> _inFlightRefreshes = {};

  /// `stock_scores.computed_at` 24 saatten eskiyse/satır yoksa [refresh]
  /// çağırır. Tazelik `stocks.updated_at` değil `stock_scores.computed_at`
  /// üzerinden kontrol edilir çünkü [refresh] üç tabloyu da yazar ve
  /// `scores` EN SON yazılan tablodur (bkz. [_doRefresh]) — bu yüzden onun
  /// zaman damgası "pipeline gerçekten tamamlandı mı" sorusuna `stocks`'tan
  /// daha doğru cevap verir (stocks yazılıp scores'a gelmeden bir hata
  /// olursa, stocks'a bakan bir kontrol yanlışlıkla "taze" der ve bir daha
  /// hiç yeniden denemez).
  Future<void> ensureFresh(String symbol) async {
    final normalized = symbol.trim().toUpperCase();
    final row = await scores.getBySymbol(normalized);
    if (row != null && isFresh(row['computed_at'] as String?)) return;
    await refresh(normalized);
  }

  /// `bin/server.dart`'taki GET handler'ları, okudukları satırın `stale`
  /// olup olmadığını (bkz. [_doRefresh]'in stale-fallback davranışı) yanıta
  /// eklemek için bu aynı eşiği kullanır — ayrı bir 24 saat sabiti
  /// tekrarlamak yerine.
  bool isFresh(String? timestamp) {
    final parsed = timestamp == null ? null : DateTime.tryParse(timestamp);
    if (parsed == null) return false;
    return DateTime.now().toUtc().difference(parsed.toUtc()) < _dbCacheTtl;
  }

  /// Yahoo'dan canlı veri çeker, DCF/Piotroski/Altman/ProTips'i hesaplar,
  /// üç tabloya da yazar. Tazelik kontrolü yapmaz — çağıran taraf karar
  /// verir. Aynı sembol için eşzamanlı çağrılar tek bir Future'ı paylaşır
  /// (bkz. [_inFlightRefreshes] doc yorumu).
  Future<void> refresh(String symbol) {
    final normalized = symbol.trim().toUpperCase();
    return _inFlightRefreshes[normalized] ??=
        _doRefresh(normalized).whenComplete(() => _inFlightRefreshes.remove(normalized));
  }

  // yahoo_fundamentals.dart'ın crumb+veri isteği retry'leri birden fazla
  // katmanda (cookie, crumb, veri isteği, 401'de tekrarı) ayrı ayrı
  // uygulanıyor — bunlar en kötü senaryoda üst üste binebilir (canlıda
  // gözlemlendi: eski, daha uzun retry bütçesiyle bazı istekler 90 saniyeyi
  // aştı). Her Yahoo çağrısına bu üst sınırı koyup ne kadar iç içe retry
  // dense de tek bir sembolün yenilenmesinin toplamda dakikalarca sürmesini
  // engelliyoruz — süre dolarsa [_doRefresh] altındaki catch bunu diğer
  // hatalarla aynı şekilde ele alır (stale varsa ona düşer, yoksa fırlatır).
  static const _yahooFetchTimeout = Duration(seconds: 20);

  Future<void> _doRefresh(String symbol) async {
    try {
      final overview =
          await fetchStockOverview(client, symbol).timeout(_yahooFetchTimeout);
      final history =
          await fetchFinancialHistory(client, symbol).timeout(_yahooFetchTimeout);

      final fairValue = computeFairValueDCF(symbol, overview, history);
      final piotroski = computePiotroskiFScore(history);
      final altman = computeAltmanZScore(overview, history);
      final tips = generateProTips(overview, history, fairValue, piotroski, altman);

      await stocks.upsert(
        symbol: symbol,
        companyName: overview.companyName,
        sector: overview.sector,
        country: overview.country,
        currency: overview.currency,
        lastPrice: overview.lastPrice,
        marketCap: overview.marketCap,
        peRatio: overview.peRatio,
        pbRatio: overview.pbRatio,
        dividendYield: overview.dividendYield,
      );
      await statements.upsertAll(symbol, [for (final y in history) y.toJson()]);
      await scores.upsert(symbol, {
        'fair_value_per_share': fairValue.fairValuePerShare,
        'fair_value_upside_pct': fairValue.upsidePct,
        'fair_value_error': fairValue.error,
        'dcf_assumptions': fairValue.assumptions.toJson(),
        'altman_z_score': altman.zScore,
        'altman_zone': altman.zone,
        'altman_error': altman.error,
        'piotroski_score': piotroski.score,
        'piotroski_max_score': piotroski.maxScore,
        'piotroski_criteria': [for (final c in piotroski.criteria) c.toJson()],
        'pro_tips': tips,
      });
    } catch (e) {
      // Yahoo canlı erişimi başarısız oldu (ör. Render'ın paylaşımlı IP'si
      // crumb endpoint'inde 429'a takıldı — bkz. yahoo_fundamentals.dart
      // doc yorumu). Bu sembol için önceden senkronlanmış bir satır varsa
      // (24 saatten eski olsa bile) sessizce ona düşüyoruz —
      // coingecko_client.dart'ın "istek başarısız olursa son bilinen
      // sonuca düş" deseninin aynısı; kullanıcı kırık bir sayfa yerine eski
      // ama çalışan veriyi görür (bkz. bin/server.dart'ın `stale` alanı).
      // Hiç senkronlanmamış bir sembolde (ilk görüntüleme) düşülecek veri
      // yoktur, hata olduğu gibi fırlatılır.
      final existing = await scores.getBySymbol(symbol);
      if (existing == null) rethrow;
    }
  }

  bool _syncing = false;

  // MonthlyLowChecker/TechnicalScoreCache'in 4'lü batch + 300ms deseninden
  // KASITLI olarak çok daha yavaş — buradaki amaç paralellik değil, Yahoo'nun
  // hassas crumb endpoint'ine yayılmış, düşük hızlı istek göndermek (bkz.
  // yahoo_fundamentals.dart'ın "thundering herd" doc yorumu). Sadece
  // GERÇEKTEN Yahoo'ya gidilen sembollerden sonra bekleniyor (aşağıda) —
  // zaten taze olan semboller anında geçilir, bu yüzden bir sembol seti
  // tamamen senkronken bu taramanın tamamı saniyeler sürer.
  static const _syncDelay = Duration(seconds: 4);

  /// Temel Analiz'in KENDİ izleme listesindeki (bkz.
  /// [FundamentalsWatchlistStore] — Teknik sekmesinden bağımsız) tüm
  /// kullanıcıların distinct sembollerini gezip [ensureFresh]'i tetikler —
  /// amaç, bir kullanıcı Temel Analiz'i açtığında sembolün büyük ihtimalle
  /// ZATEN senkronlanmış olması, yani o anki kullanıcı isteğinin hiç canlı
  /// Yahoo çağrısı tetiklememesi (429 riski kullanıcı isteğinden tamamen
  /// ayrılır). `main()`'de açılışta bir kez + periyodik çağrılır (bkz.
  /// bin/server.dart).
  Future<void> syncWatchlistedSymbols(FundamentalsWatchlistStore watchlist) async {
    if (_syncing) return;
    _syncing = true;
    try {
      final rows = await watchlist.allRows();
      final symbols = {for (final r in rows) r['symbol'] as String};
      for (final symbol in symbols) {
        final row = await scores.getBySymbol(symbol);
        if (row != null && isFresh(row['computed_at'] as String?)) {
          continue; // zaten taze, Yahoo'ya gidilmedi — beklemeye gerek yok
        }
        try {
          await refresh(symbol);
        } catch (_) {
          // Tek bir sembolün hatası (ör. veri yetersiz, Yahoo 404) tüm
          // taramayı durdurmasın — MonthlyLowChecker ile aynı desen.
        }
        await Future.delayed(_syncDelay);
      }
    } finally {
      _syncing = false;
    }
  }
}
