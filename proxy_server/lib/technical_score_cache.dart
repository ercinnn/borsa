import 'package:http/http.dart' as http;

import 'store.dart';
import 'technical_analysis.dart';
import 'yahoo_client.dart';

class ScoredSymbol {
  final String symbol;
  final int score;
  final String currency;
  final double lastClose;
  final DateTime asOf;

  ScoredSymbol({
    required this.symbol,
    required this.score,
    required this.currency,
    required this.lastClose,
    required this.asOf,
  });

  Map<String, dynamic> toJson() => {
        'symbol': symbol,
        'score': score,
        'currency': currency,
        'lastClose': lastClose,
        'asOf': asOf.toIso8601String(),
      };
}

/// Watchlist'teki (İzleme Listesi) her sembol için Teknik sekmesindeki
/// "alım puanı"nı (0-100, bkz. technical_analysis.dart) arka planda önceden
/// hesaplayıp bellekte tutar. Bildirimler sayfasındaki "Puan Sıralaması"
/// sekmesi buradan okur — yüzlerce sembolü her istekte canlı hesaplamak hem
/// yavaş olurdu hem de Yahoo'yu rate-limit'e sokardı. MonthlyLowChecker ile
/// birebir aynı desen: aynı sembolü izleyen birden fazla kullanıcı için
/// Yahoo'dan yalnızca bir kez çekilir, gruplar arası 300ms duraklamayla 4'lü
/// eşzamanlı batch'ler halinde taranır. Render'ın ücretsiz planı ~15dk
/// hareketsizlikte durduğundan bu bellek her soğuk başlangıçta boşalır —
/// bilinçli bir ödünleşim: kalıcı depolamaya (Supabase) yazmaya değecek
/// kadar önemli veri değil, bir sonraki periyodik/manuel yenilemede yeniden
/// dolar.
class TechnicalScoreCache {
  final http.Client client;
  final WatchlistStore watchlist;

  TechnicalScoreCache(this.client, this.watchlist);

  final Map<String, ScoredSymbol> _scores = {};
  bool _refreshing = false;

  static const _batchSize = 4;

  bool get isRefreshing => _refreshing;
  int get cachedCount => _scores.length;

  List<ScoredSymbol> scoresFor(Iterable<String> symbols) {
    final result = <ScoredSymbol>[];
    for (final s in symbols) {
      final entry = _scores[s];
      if (entry != null) result.add(entry);
    }
    return result;
  }

  Future<void> refreshAll() async {
    if (_refreshing) return;
    _refreshing = true;
    try {
      final rows = await watchlist.allRows();
      final symbols = rows.map((r) => r['symbol'] as String).toSet().toList();
      for (var i = 0; i < symbols.length; i += _batchSize) {
        final batch = symbols.sublist(
          i,
          (i + _batchSize) > symbols.length ? symbols.length : i + _batchSize,
        );
        await Future.wait(batch.map((symbol) async {
          try {
            await _refreshOne(symbol);
          } catch (_) {
            // Tek bir sembolün hatası (ör. veri yetersiz, Yahoo 404) tüm
            // taramayı durdurmasın.
          }
        }));
        if (i + _batchSize < symbols.length) {
          await Future.delayed(const Duration(milliseconds: 300));
        }
      }
    } finally {
      _refreshing = false;
    }
  }

  Future<void> _refreshOne(String symbol) async {
    final now = DateTime.now().toUtc();
    final period2 = now.millisecondsSinceEpoch ~/ 1000 + 86400;
    final period1 =
        now.subtract(const Duration(days: 500)).millisecondsSinceEpoch ~/ 1000;
    final data = await fetchChart(client, symbol, period1, period2, '1d');
    final result = computeTechnicalAnalysis(symbol, data.currency, data.candles);
    _scores[symbol] = ScoredSymbol(
      symbol: symbol,
      score: result.summary.score,
      currency: result.currency,
      lastClose: result.lastClose,
      asOf: result.asOf,
    );
  }
}
