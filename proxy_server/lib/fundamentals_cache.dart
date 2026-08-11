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

  /// `stocks` satırı yoksa veya 24 saatten eskiyse [refresh] çağırır; tazeyse
  /// hiçbir şey yapmaz (çağıran taraf zaten DB'den okuyabilir).
  Future<void> ensureFresh(String symbol) async {
    final row = await stocks.getBySymbol(symbol);
    if (row != null && _isFresh(row['updated_at'] as String?)) return;
    await refresh(symbol);
  }

  bool _isFresh(String? updatedAt) {
    final parsed = updatedAt == null ? null : DateTime.tryParse(updatedAt);
    if (parsed == null) return false;
    return DateTime.now().toUtc().difference(parsed.toUtc()) < _dbCacheTtl;
  }

  /// Yahoo'dan canlı veri çeker, DCF/Piotroski/Altman/ProTips'i hesaplar,
  /// üç tabloya da yazar. Tazelik kontrolü yapmaz — çağıran taraf karar verir.
  Future<void> refresh(String symbol) async {
    final normalized = symbol.trim().toUpperCase();
    final overview = await fetchStockOverview(client, normalized);
    final history = await fetchFinancialHistory(client, normalized);

    final fairValue = computeFairValueDCF(normalized, overview, history);
    final piotroski = computePiotroskiFScore(history);
    final altman = computeAltmanZScore(overview, history);
    final tips = generateProTips(overview, history, fairValue, piotroski, altman);

    await stocks.upsert(
      symbol: normalized,
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
    await statements.upsertAll(normalized, [for (final y in history) y.toJson()]);
    await scores.upsert(normalized, {
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
  }
}
