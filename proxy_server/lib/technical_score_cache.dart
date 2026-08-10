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
///
/// Her yenilemede bir sembolün önceki puanıyla yenisini de karşılaştırır:
/// puan bir "kademe" (Güçlü Al/Al/Nötr/Sat/Güçlü Sat) sınırını aşarsa, o
/// sembolü izleyen her kullanıcıya `NotificationStore` üzerinden bir
/// bildirim yazılır (bkz. `_refreshOne`) — MonthlyLowChecker'ın aylık-dip
/// bildirimleriyle aynı tabloyu, aynı Bildirimler akışını paylaşır, ayrı
/// bir mekanizma değil. Karşılaştırma bu bellekteki "önceki" değere
/// dayandığından, sunucu soğuk başlangıç yaptığında (yukarıdaki gibi) bir
/// önceki döngüdeki kademe unutulur — nadir bir kademe geçişi bu yüzden
/// kaçırılabilir, ama asla tekrar bildirim üretmez (bilinçli bir ödünleşim,
/// diğer önbellek kayıplarıyla aynı gerekçe).
class TechnicalScoreCache {
  final http.Client client;
  final WatchlistStore watchlist;
  final NotificationStore notifications;

  TechnicalScoreCache(this.client, this.watchlist, this.notifications);

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
      final usersBySymbol = <String, List<String>>{};
      for (final row in rows) {
        final userId = row['user_id'] as String?;
        if (userId == null) continue; // henüz kimse tarafından sahiplenilmemiş
        final symbol = row['symbol'] as String;
        usersBySymbol.putIfAbsent(symbol, () => []).add(userId);
      }

      final entries = usersBySymbol.entries.toList();
      for (var i = 0; i < entries.length; i += _batchSize) {
        final batch = entries.sublist(
          i,
          (i + _batchSize) > entries.length ? entries.length : i + _batchSize,
        );
        await Future.wait(batch.map((entry) async {
          try {
            await _refreshOne(entry.key, entry.value);
          } catch (_) {
            // Tek bir sembolün hatası (ör. veri yetersiz, Yahoo 404) tüm
            // taramayı durdurmasın.
          }
        }));
        if (i + _batchSize < entries.length) {
          await Future.delayed(const Duration(milliseconds: 300));
        }
      }
    } finally {
      _refreshing = false;
    }
  }

  Future<void> _refreshOne(String symbol, List<String> userIds) async {
    final now = DateTime.now().toUtc();
    final period2 = now.millisecondsSinceEpoch ~/ 1000 + 86400;
    final period1 =
        now.subtract(const Duration(days: 500)).millisecondsSinceEpoch ~/ 1000;
    final data = await fetchChart(client, symbol, period1, period2, '1d');
    final result = computeTechnicalAnalysis(symbol, data.currency, data.candles);
    final newScore = result.summary.score;
    final previous = _scores[symbol];

    _scores[symbol] = ScoredSymbol(
      symbol: symbol,
      score: newScore,
      currency: result.currency,
      lastClose: result.lastClose,
      asOf: result.asOf,
    );

    if (previous == null) return; // ilk hesaplama, karşılaştıracak bir şey yok
    final oldTier = summarySignalForScore(previous.score);
    final newTier = summarySignalForScore(newScore);
    if (oldTier == newTier) return; // kademe değişmedi, bildirime gerek yok

    final direction = newScore > previous.score ? '↑' : '↓';
    final message = '$symbol teknik puan kademesi değişti: '
        '${oldTier.turkishLabel} → ${newTier.turkishLabel} '
        '($newScore/100 $direction).';
    final dateKey = _dateKey(now);
    final createdAt = DateTime.now().toIso8601String();
    final items = [
      for (final userId in userIds)
        {
          'id': '$userId-$symbol-score-$dateKey-${DateTime.now().millisecondsSinceEpoch}',
          'user_id': userId,
          'symbol': symbol,
          'price': result.lastClose,
          'currency': result.currency,
          'date': dateKey,
          'createdAt': createdAt,
          'message': message,
        },
    ];
    await notifications.addAll(items);
  }

  String _dateKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}
