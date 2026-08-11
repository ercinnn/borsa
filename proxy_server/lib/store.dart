import 'package:http/http.dart' as http;

import 'supabase_client.dart';

/// Çok kullanıcılı: her metod bir [userId] alır, Supabase'e o kullanıcıya
/// filtrelenmiş bir sorgu atar (in-memory cache yok — tek kullanıcılı
/// dönemden kalan yaklaşım, farklı kullanıcıların verisinin karışma riski
/// olmasın diye terk edildi).
class WatchlistStore {
  static const defaultSymbols = [
    'THYAO.IS',
    'ASELS.IS',
    'GARAN.IS',
    'AKBNK.IS',
    'BTC-USD',
    'ETH-USD',
    'AAPL',
    'TSLA',
  ];

  final SupabaseTable _table;

  WatchlistStore(SupabaseConfig config, http.Client client)
      : _table = SupabaseTable(client, config, 'watchlist');

  Future<List<String>> symbolsFor(String userId) async {
    final rows = await _table.select(
      columns: 'symbol',
      filters: {'user_id': 'eq.$userId', 'order': 'symbol.asc'},
    );
    if (rows.isEmpty) {
      await addAll(userId, defaultSymbols);
      return List.of(defaultSymbols)..sort();
    }
    return rows.map((r) => r['symbol'] as String).toList();
  }

  Future<bool> add(String userId, String symbol) async {
    final normalized = symbol.trim().toUpperCase();
    if (normalized.isEmpty) return false;
    final inserted = await _table.insert(
      {'user_id': userId, 'symbol': normalized},
      onConflict: 'user_id,symbol',
      prefer: 'resolution=ignore-duplicates,return=representation',
    );
    return inserted.isNotEmpty;
  }

  Future<int> addAll(String userId, List<String> symbols) async {
    final unique = <String>{};
    for (final symbol in symbols) {
      final normalized = symbol.trim().toUpperCase();
      if (normalized.isNotEmpty) unique.add(normalized);
    }
    if (unique.isEmpty) return 0;
    final inserted = await _table.insert(
      [for (final s in unique) {'user_id': userId, 'symbol': s}],
      onConflict: 'user_id,symbol',
      prefer: 'resolution=ignore-duplicates,return=representation',
    );
    return inserted.length;
  }

  Future<bool> remove(String userId, String symbol) async {
    final normalized = symbol.trim().toUpperCase();
    final deleted = await _table.delete({
      'user_id': 'eq.$userId',
      'symbol': 'eq.$normalized',
    });
    return deleted.isNotEmpty;
  }

  /// Arka plan aylık-dip kontrolü için: tüm kullanıcıların tüm sembolleri.
  Future<List<Map<String, dynamic>>> allRows() {
    return _table.select(columns: 'user_id,symbol');
  }
}

/// Watchlist'ten bağımsız, ayrı bir liste: bildirim/aylık-dip kontrolü
/// almaz, sadece kullanıcının hızlı erişim için işaretlediği semboller
/// (Grafik ve Bildirimler sekmelerindeki yıldız butonu, Favoriler sekmesi).
class FavoritesStore {
  final SupabaseTable _table;

  FavoritesStore(SupabaseConfig config, http.Client client)
      : _table = SupabaseTable(client, config, 'favorites');

  Future<List<String>> symbolsFor(String userId) async {
    final rows = await _table.select(
      columns: 'symbol',
      filters: {'user_id': 'eq.$userId', 'order': 'symbol.asc'},
    );
    return rows.map((r) => r['symbol'] as String).toList();
  }

  Future<bool> add(String userId, String symbol) async {
    final normalized = symbol.trim().toUpperCase();
    if (normalized.isEmpty) return false;
    final inserted = await _table.insert(
      {'user_id': userId, 'symbol': normalized},
      onConflict: 'user_id,symbol',
      prefer: 'resolution=ignore-duplicates,return=representation',
    );
    return inserted.isNotEmpty;
  }

  Future<bool> remove(String userId, String symbol) async {
    final normalized = symbol.trim().toUpperCase();
    final deleted = await _table.delete({
      'user_id': 'eq.$userId',
      'symbol': 'eq.$normalized',
    });
    return deleted.isNotEmpty;
  }
}

/// Teknik sekmesinde kullanıcının analiz için eklediği semboller.
/// FavoritesStore ile aynı desen: watchlist/favorites'ten bağımsız, bildirim
/// üretmez — yalnızca hangi sembollerin Teknik sekmesinde gösterileceğini
/// belirler.
class TechnicalWatchlistStore {
  final SupabaseTable _table;

  TechnicalWatchlistStore(SupabaseConfig config, http.Client client)
      : _table = SupabaseTable(client, config, 'technical_watchlist');

  Future<List<String>> symbolsFor(String userId) async {
    final rows = await _table.select(
      columns: 'symbol',
      filters: {'user_id': 'eq.$userId', 'order': 'symbol.asc'},
    );
    return rows.map((r) => r['symbol'] as String).toList();
  }

  Future<bool> add(String userId, String symbol) async {
    final normalized = symbol.trim().toUpperCase();
    if (normalized.isEmpty) return false;
    final inserted = await _table.insert(
      {'user_id': userId, 'symbol': normalized},
      onConflict: 'user_id,symbol',
      prefer: 'resolution=ignore-duplicates,return=representation',
    );
    return inserted.isNotEmpty;
  }

  Future<bool> remove(String userId, String symbol) async {
    final normalized = symbol.trim().toUpperCase();
    final deleted = await _table.delete({
      'user_id': 'eq.$userId',
      'symbol': 'eq.$normalized',
    });
    return deleted.isNotEmpty;
  }

  /// Temel Analiz'in arka plan ön-senkronizasyonu için: tüm kullanıcıların
  /// tüm sembolleri (bkz. fundamentals_cache.dart syncWatchlistedSymbols) —
  /// `WatchlistStore.allRows()` ile aynı desen.
  Future<List<Map<String, dynamic>>> allRows() {
    return _table.select(columns: 'user_id,symbol');
  }
}

/// Temettü sekmesinde kullanıcının takip için eklediği semboller.
/// TechnicalWatchlistStore ile aynı desen: watchlist/favorites/teknik
/// listeden bağımsız, bildirim üretmez — yalnızca hangi sembollerin Temettü
/// sekmesinde gösterileceğini belirler.
class DividendWatchlistStore {
  final SupabaseTable _table;

  DividendWatchlistStore(SupabaseConfig config, http.Client client)
      : _table = SupabaseTable(client, config, 'dividend_watchlist');

  Future<List<String>> symbolsFor(String userId) async {
    final rows = await _table.select(
      columns: 'symbol',
      filters: {'user_id': 'eq.$userId', 'order': 'symbol.asc'},
    );
    return rows.map((r) => r['symbol'] as String).toList();
  }

  Future<bool> add(String userId, String symbol) async {
    final normalized = symbol.trim().toUpperCase();
    if (normalized.isEmpty) return false;
    final inserted = await _table.insert(
      {'user_id': userId, 'symbol': normalized},
      onConflict: 'user_id,symbol',
      prefer: 'resolution=ignore-duplicates,return=representation',
    );
    return inserted.isNotEmpty;
  }

  Future<bool> remove(String userId, String symbol) async {
    final normalized = symbol.trim().toUpperCase();
    final deleted = await _table.delete({
      'user_id': 'eq.$userId',
      'symbol': 'eq.$normalized',
    });
    return deleted.isNotEmpty;
  }
}

/// Temel Analiz için sembol bazlı, HERKESE AÇIK piyasa verisi — diğer tüm
/// Store sınıflarının aksine `userId` almaz (bkz.
/// supabase_schema_fundamentals.sql'in RLS deseni notu: bu üç tablo
/// anon/authenticated'e SELECT açık, yazma yalnızca bu proxy'nin
/// service_role anahtarıyla).
class StockStore {
  final SupabaseTable _table;

  StockStore(SupabaseConfig config, http.Client client)
      : _table = SupabaseTable(client, config, 'stocks');

  Future<Map<String, dynamic>?> getBySymbol(String symbol) async {
    final rows = await _table.select(
      filters: {'symbol': 'eq.${symbol.trim().toUpperCase()}', 'limit': '1'},
    );
    return rows.isEmpty ? null : rows.first;
  }

  Future<void> upsert({
    required String symbol,
    required String companyName,
    String? sector,
    String? country,
    required String currency,
    required double lastPrice,
    double? marketCap,
    double? peRatio,
    double? pbRatio,
    double? dividendYield,
  }) async {
    await _table.insert(
      {
        'symbol': symbol.trim().toUpperCase(),
        'company_name': companyName,
        'sector': sector,
        'country': country,
        'currency': currency,
        'last_price': lastPrice,
        'market_cap': marketCap,
        'pe_ratio': peRatio,
        'pb_ratio': pbRatio,
        'dividend_yield': dividendYield,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      },
      onConflict: 'symbol',
      prefer: 'resolution=merge-duplicates,return=minimal',
    );
  }
}

/// Sembol başına son ~4 yıllık finansal metrik geçmişi — bkz.
/// yahoo_fundamentals.dart FinancialYear.toJson() (tek düz JSONB, ayrı
/// bilanço/gelir tablosu/nakit akışı objeleri değil, doc yorumundaki
/// gerekçe için bkz. supabase_schema_fundamentals.sql).
class FinancialStatementStore {
  final SupabaseTable _table;

  FinancialStatementStore(SupabaseConfig config, http.Client client)
      : _table = SupabaseTable(client, config, 'financial_statements');

  Future<List<Map<String, dynamic>>> getBySymbol(String symbol) {
    return _table.select(
      filters: {
        'symbol': 'eq.${symbol.trim().toUpperCase()}',
        'order': 'fiscal_year.asc',
      },
    );
  }

  Future<void> upsertAll(String symbol, List<Map<String, dynamic>> years) async {
    final normalized = symbol.trim().toUpperCase();
    if (years.isEmpty) return;
    final now = DateTime.now().toUtc().toIso8601String();
    await _table.insert(
      [
        for (final y in years)
          {'symbol': normalized, 'fiscal_year': y['fiscalYear'], 'data': y, 'updated_at': now},
      ],
      onConflict: 'symbol,fiscal_year',
      prefer: 'resolution=merge-duplicates,return=minimal',
    );
  }
}

/// Sembol başına en son hesaplanmış DCF/Piotroski/Altman/ProTips sonucu —
/// GET endpoint'leri (bkz. bin/server.dart) her istekte yeniden hesaplamak
/// yerine bunu okur; yalnızca veri 24 saatten eskiyse (bkz.
/// fundamentals_cache.dart) yeniden hesaplanıp buraya yazılır.
class StockScoreStore {
  final SupabaseTable _table;

  StockScoreStore(SupabaseConfig config, http.Client client)
      : _table = SupabaseTable(client, config, 'stock_scores');

  Future<Map<String, dynamic>?> getBySymbol(String symbol) async {
    final rows = await _table.select(
      filters: {'symbol': 'eq.${symbol.trim().toUpperCase()}', 'limit': '1'},
    );
    return rows.isEmpty ? null : rows.first;
  }

  Future<void> upsert(String symbol, Map<String, dynamic> scoreData) async {
    await _table.insert(
      {
        'symbol': symbol.trim().toUpperCase(),
        ...scoreData,
        'computed_at': DateTime.now().toUtc().toIso8601String(),
      },
      onConflict: 'symbol',
      prefer: 'resolution=merge-duplicates,return=minimal',
    );
  }
}

class PortfolioHoldingRow {
  final String symbol;
  final double quantity;
  final double costBasis;
  PortfolioHoldingRow(this.symbol, this.quantity, this.costBasis);
}

/// Portföy sekmesindeki pozisyonlar: kullanıcı başına sembol başına tek
/// satır. Aynı sembolü tekrar eklemek mevcut adet/maliyeti YENİ değerlerle
/// tamamen değiştirir (ağırlıklı ortalama birleştirme yapılmaz — "basit"
/// portföy takibi kapsamında bilinçli bir sadeleştirme; kullanıcı toplam
/// adedi/ortalama maliyeti kendisi hesaplayıp tekrar girer).
class PortfolioStore {
  final SupabaseTable _table;

  PortfolioStore(SupabaseConfig config, http.Client client)
      : _table = SupabaseTable(client, config, 'portfolio_holdings');

  Future<List<PortfolioHoldingRow>> holdingsFor(String userId) async {
    final rows = await _table.select(
      columns: 'symbol,quantity,cost_basis',
      filters: {'user_id': 'eq.$userId', 'order': 'symbol.asc'},
    );
    return rows
        .map((r) => PortfolioHoldingRow(
              r['symbol'] as String,
              (r['quantity'] as num).toDouble(),
              (r['cost_basis'] as num).toDouble(),
            ))
        .toList();
  }

  Future<void> upsert(String userId, String symbol, double quantity, double costBasis) async {
    final normalized = symbol.trim().toUpperCase();
    if (normalized.isEmpty || quantity <= 0) return;
    await _table.insert(
      {
        'user_id': userId,
        'symbol': normalized,
        'quantity': quantity,
        'cost_basis': costBasis,
        'updated_at': DateTime.now().toIso8601String(),
      },
      onConflict: 'user_id,symbol',
      prefer: 'resolution=merge-duplicates,return=minimal',
    );
  }

  Future<bool> remove(String userId, String symbol) async {
    final normalized = symbol.trim().toUpperCase();
    final deleted = await _table.delete({
      'user_id': 'eq.$userId',
      'symbol': 'eq.$normalized',
    });
    return deleted.isNotEmpty;
  }
}

/// Takip sekmesinde gösterilen, kullanıcı başına tek aktif sembol.
class TrackedSymbolStore {
  final SupabaseTable _table;

  TrackedSymbolStore(SupabaseConfig config, http.Client client)
      : _table = SupabaseTable(client, config, 'tracked_symbol');

  Future<String?> getFor(String userId) async {
    final rows = await _table.select(
      columns: 'symbol',
      filters: {'user_id': 'eq.$userId', 'limit': '1'},
    );
    if (rows.isEmpty) return null;
    return rows.first['symbol'] as String?;
  }

  Future<void> setFor(String userId, String symbol) async {
    final normalized = symbol.trim().toUpperCase();
    if (normalized.isEmpty) return;
    await _table.insert(
      {'user_id': userId, 'symbol': normalized},
      onConflict: 'user_id',
      prefer: 'resolution=merge-duplicates,return=minimal',
    );
  }
}

class NotificationStore {
  final SupabaseTable _table;

  NotificationStore(SupabaseConfig config, http.Client client)
      : _table = SupabaseTable(client, config, 'notifications');

  /// Aynı sembol+tarih için her kullanıcıyı tek tek sorgulamak yerine tek
  /// bir sorguda hangi kullanıcıların zaten bildirimi olduğunu döner (bkz.
  /// MonthlyLowChecker._checkSymbol).
  Future<Set<String>> existingUserIdsFor(
    String symbol,
    String dateKey,
    List<String> userIds,
  ) async {
    if (userIds.isEmpty) return {};
    final rows = await _table.select(
      columns: 'user_id',
      filters: {
        'symbol': 'eq.$symbol',
        'date': 'eq.$dateKey',
        'user_id': 'in.(${userIds.join(',')})',
      },
    );
    return rows.map((r) => r['user_id'] as String).toSet();
  }

  /// Birden fazla kullanıcı için tek bir bildirimi tek seferde ekler (bkz.
  /// MonthlyLowChecker._checkSymbol) — her kullanıcı için ayrı bir insert
  /// çağrısı yapmak yerine.
  Future<void> addAll(List<Map<String, dynamic>> items) async {
    if (items.isEmpty) return;
    await _table.insert(items, prefer: 'return=minimal');
  }

  /// [category] verilirse ('bist', 'us' veya 'crypto') yalnızca o kategoriye
  /// giren sembollerin bildirimleri sayfalanır (frontend'deki İzleme Listesi
  /// alt sekmeleriyle aynı .IS/-USD sonek kuralı, PostgREST like/not.like
  /// filtreleriyle DB tarafında uygulanır — tüm tabloyu çekip bellekte
  /// filtrelemek yerine).
  Future<Map<String, dynamic>> page(
    String userId,
    int page, {
    int pageSize = 100,
    String? category,
  }) async {
    final safePage = page < 1 ? 1 : page;
    final start = (safePage - 1) * pageSize;

    final filters = <String, String>{
      'user_id': 'eq.$userId',
      'order': 'createdAt.desc',
      'limit': '$pageSize',
      'offset': '$start',
    };
    switch (category) {
      case 'bist':
        filters['symbol'] = 'like.*.IS';
        break;
      case 'crypto':
        filters['symbol'] = 'like.*-USD';
        break;
      case 'us':
        filters['and'] = '(symbol.not.like.*.IS,symbol.not.like.*-USD)';
        break;
    }

    final result = await _table.selectWithCount(filters: filters);
    final totalPages = result.total == 0 ? 1 : (result.total / pageSize).ceil();
    return {
      'notifications': result.rows,
      'page': safePage,
      'totalPages': totalPages,
      'total': result.total,
    };
  }
}
