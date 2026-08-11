import 'dart:convert';

import 'package:http/http.dart' as http;

import 'yahoo_client.dart' show YahooException, userAgent;

/// Bir sembolün "en güncel" (tek dönem) fundamental özeti — bilanço/gelir
/// tablosu geçmişi için bkz. [fetchFinancialHistory]. `quoteSummary`'nin
/// `assetProfile`/`price`/`summaryDetail`/`financialData`/
/// `defaultKeyStatistics` modüllerinden derlenir.
class StockOverview {
  final String symbol;
  final String companyName;
  final String currency;
  final String? sector;
  final String? country;
  final double lastPrice;
  final double? marketCap;
  final double? peRatio;
  final double? pbRatio;
  final double? dividendYield;
  final double? sharesOutstanding;
  final double? freeCashflow;
  final double? operatingCashflow;
  final double? returnOnAssets;
  final double? returnOnEquity;
  final double? currentRatio;
  final double? debtToEquity;

  StockOverview({
    required this.symbol,
    required this.companyName,
    required this.currency,
    this.sector,
    this.country,
    required this.lastPrice,
    this.marketCap,
    this.peRatio,
    this.pbRatio,
    this.dividendYield,
    this.sharesOutstanding,
    this.freeCashflow,
    this.operatingCashflow,
    this.returnOnAssets,
    this.returnOnEquity,
    this.currentRatio,
    this.debtToEquity,
  });
}

/// Bir mali yılın DCF/Piotroski/Altman hesaplamalarında kullanılan alanları.
/// Banka gibi finans sektörü şirketlerinde [grossProfit]/[currentAssets]/
/// [currentLiabilities]/[ebit] Yahoo'dan hiç gelmiyor (bkz. dosya başı
/// yorumu) — bu alanlar o durumda `null` kalır, hesaplayıcılar bunu
/// "bu sektörde hesaplanamaz" olarak yorumlamalı, hata fırlatmamalı.
class FinancialYear {
  final int fiscalYear;
  final double? totalRevenue;
  final double? netIncome;
  final double? freeCashFlow;
  final double? operatingCashFlow;
  final double? capitalExpenditure;
  final double? totalAssets;
  final double? totalLiabilities;
  final double? stockholdersEquity;
  final double? currentAssets;
  final double? currentLiabilities;
  final double? retainedEarnings;
  final double? grossProfit;
  final double? ebit;

  FinancialYear({
    required this.fiscalYear,
    this.totalRevenue,
    this.netIncome,
    this.freeCashFlow,
    this.operatingCashFlow,
    this.capitalExpenditure,
    this.totalAssets,
    this.totalLiabilities,
    this.stockholdersEquity,
    this.currentAssets,
    this.currentLiabilities,
    this.retainedEarnings,
    this.grossProfit,
    this.ebit,
  });

  Map<String, dynamic> toJson() => {
        'fiscalYear': fiscalYear,
        'totalRevenue': totalRevenue,
        'netIncome': netIncome,
        'freeCashFlow': freeCashFlow,
        'operatingCashFlow': operatingCashFlow,
        'capitalExpenditure': capitalExpenditure,
        'totalAssets': totalAssets,
        'totalLiabilities': totalLiabilities,
        'stockholdersEquity': stockholdersEquity,
        'currentAssets': currentAssets,
        'currentLiabilities': currentLiabilities,
        'retainedEarnings': retainedEarnings,
        'grossProfit': grossProfit,
        'ebit': ebit,
      };
}

// Yahoo'nun eski quoteSummary bilanço/nakit-akışı modülleri (balanceSheet
// History/cashflowStatementHistory) artık neredeyse boş dönüyor (yalnızca
// endDate/netIncome) — gerçek çok yıllı veri modern fundamentals-timeseries
// uç noktasından geliyor (bkz. CLAUDE.md Faz 0 bulguları). Bu uç nokta da
// dahil TÜM quoteSummary/fundamentals-timeseries istekleri artık bir
// cookie+crumb (CSRF token) çifti gerektiriyor — çıplak User-Agent yetmiyor
// (401 "Invalid Crumb"). Akış: fc.yahoo.com'dan bir cookie al, o cookie ile
// getcrumb'dan bir crumb al; ikisi de sonraki tüm isteklerde kullanılır.
class _CrumbSession {
  String? cookie;
  String? crumb;
  DateTime? fetchedAt;
}

final _crumbSession = _CrumbSession();
const _crumbTtl = Duration(hours: 1);

Future<void> _ensureCrumb(http.Client client, {bool forceRefresh = false}) async {
  final now = DateTime.now();
  if (!forceRefresh &&
      _crumbSession.crumb != null &&
      _crumbSession.fetchedAt != null &&
      now.difference(_crumbSession.fetchedAt!) < _crumbTtl) {
    return;
  }

  final cookieResp =
      await client.get(Uri.parse('https://fc.yahoo.com'), headers: {'User-Agent': userAgent});
  final setCookie = cookieResp.headers['set-cookie'];
  if (setCookie == null) {
    throw YahooException('Yahoo oturum çerezi alınamadı');
  }
  final cookie = setCookie.split(';').first;

  final crumbResp = await client.get(
    Uri.parse('https://query2.finance.yahoo.com/v1/test/getcrumb'),
    headers: {'User-Agent': userAgent, 'Cookie': cookie},
  );
  if (crumbResp.statusCode != 200 || crumbResp.body.trim().isEmpty) {
    throw YahooException('Yahoo crumb alınamadı (${crumbResp.statusCode})');
  }

  _crumbSession.cookie = cookie;
  _crumbSession.crumb = crumbResp.body.trim();
  _crumbSession.fetchedAt = now;
}

/// [uri]'ye cookie+crumb ile GET atar; 401 alırsa crumb'ı bir kez zorla
/// yeniler ve tekrar dener (crumb'ın sunucu tarafı ömrü bizim 1 saatlik
/// TTL'imizden daha kısa olabilir).
Future<http.Response> _getWithCrumb(
  http.Client client,
  Uri Function(String crumb) buildUri,
) async {
  await _ensureCrumb(client);
  var resp = await client.get(
    buildUri(_crumbSession.crumb!),
    headers: {'User-Agent': userAgent, 'Cookie': _crumbSession.cookie!},
  );
  if (resp.statusCode == 401) {
    await _ensureCrumb(client, forceRefresh: true);
    resp = await client.get(
      buildUri(_crumbSession.crumb!),
      headers: {'User-Agent': userAgent, 'Cookie': _crumbSession.cookie!},
    );
  }
  return resp;
}

class _OverviewCacheEntry {
  final StockOverview data;
  final DateTime expiresAt;
  _OverviewCacheEntry(this.data, this.expiresAt);
}

class _HistoryCacheEntry {
  final List<FinancialYear> data;
  final DateTime expiresAt;
  _HistoryCacheEntry(this.data, this.expiresAt);
}

// Fundamental veri fiyat mumlarına göre çok daha seyrek değiştiğinden
// (çeyreklik) fetchChart'ın 2 dakikalık cache'inden çok daha uzun ömürlü —
// fetchDividends'ın 6 saatlik TTL deseniyle aynı mantık, burada 24 saat.
final _overviewCache = <String, _OverviewCacheEntry>{};
final _historyCache = <String, _HistoryCacheEntry>{};
const _fundamentalsCacheTtl = Duration(hours: 24);

double? _asDouble(dynamic v) => v == null ? null : (v as num).toDouble();

/// `quoteSummary` (`assetProfile,price,summaryDetail,financialData,
/// defaultKeyStatistics` modülleri) üzerinden tek-dönemlik şirket özeti.
Future<StockOverview> fetchStockOverview(http.Client client, String symbol) async {
  final cached = _overviewCache[symbol];
  if (cached != null && cached.expiresAt.isAfter(DateTime.now())) {
    return cached.data;
  }

  final resp = await _getWithCrumb(
    client,
    (crumb) => Uri.https(
      'query2.finance.yahoo.com',
      '/v10/finance/quoteSummary/$symbol',
      {
        'modules': 'assetProfile,price,summaryDetail,financialData,defaultKeyStatistics',
        'crumb': crumb,
      },
    ),
  );
  if (resp.statusCode != 200) {
    throw YahooException('Yahoo quoteSummary isteği başarısız (${resp.statusCode})');
  }
  final body = jsonDecode(resp.body) as Map<String, dynamic>;
  final finance = body['quoteSummary'] as Map<String, dynamic>?;
  if (finance?['error'] != null) {
    throw YahooException('Sembol bulunamadı: $symbol');
  }
  final results = finance?['result'] as List?;
  if (results == null || results.isEmpty) {
    throw YahooException('Sembol bulunamadı: $symbol');
  }

  final result = results.first as Map<String, dynamic>;
  final price = result['price'] as Map<String, dynamic>? ?? {};
  final summaryDetail = result['summaryDetail'] as Map<String, dynamic>? ?? {};
  final financialData = result['financialData'] as Map<String, dynamic>? ?? {};
  final keyStats = result['defaultKeyStatistics'] as Map<String, dynamic>? ?? {};
  final assetProfile = result['assetProfile'] as Map<String, dynamic>? ?? {};

  dynamic raw(Map<String, dynamic> m, String key) {
    final v = m[key];
    if (v is Map<String, dynamic>) return v['raw'];
    return v;
  }

  final lastPrice = _asDouble(raw(price, 'regularMarketPrice'));
  if (lastPrice == null) {
    throw YahooException('Sembol bulunamadı: $symbol');
  }

  final overview = StockOverview(
    symbol: symbol.trim().toUpperCase(),
    companyName: (price['longName'] ?? price['shortName'] ?? symbol) as String,
    currency: price['currency'] as String? ?? '',
    sector: assetProfile['sector'] as String?,
    country: assetProfile['country'] as String?,
    lastPrice: lastPrice,
    marketCap: _asDouble(raw(price, 'marketCap') ?? raw(summaryDetail, 'marketCap')),
    peRatio: _asDouble(raw(summaryDetail, 'trailingPE')),
    pbRatio: _asDouble(raw(keyStats, 'priceToBook')),
    dividendYield: _asDouble(raw(summaryDetail, 'dividendYield')),
    sharesOutstanding: _asDouble(raw(keyStats, 'sharesOutstanding')),
    freeCashflow: _asDouble(raw(financialData, 'freeCashflow')),
    operatingCashflow: _asDouble(raw(financialData, 'operatingCashflow')),
    returnOnAssets: _asDouble(raw(financialData, 'returnOnAssets')),
    returnOnEquity: _asDouble(raw(financialData, 'returnOnEquity')),
    currentRatio: _asDouble(raw(financialData, 'currentRatio')),
    debtToEquity: _asDouble(raw(financialData, 'debtToEquity')),
  );

  _overviewCache[symbol] =
      _OverviewCacheEntry(overview, DateTime.now().add(_fundamentalsCacheTtl));
  return overview;
}

// annualX Yahoo tipi -> bu projede kullanılan kısa alan adı.
const _historyFieldMap = {
  'annualTotalRevenue': 'totalRevenue',
  'annualNetIncome': 'netIncome',
  'annualFreeCashFlow': 'freeCashFlow',
  'annualOperatingCashFlow': 'operatingCashFlow',
  'annualCapitalExpenditure': 'capitalExpenditure',
  'annualTotalAssets': 'totalAssets',
  'annualTotalLiabilitiesNetMinorityInterest': 'totalLiabilities',
  'annualStockholdersEquity': 'stockholdersEquity',
  'annualCurrentAssets': 'currentAssets',
  'annualCurrentLiabilities': 'currentLiabilities',
  'annualRetainedEarnings': 'retainedEarnings',
  'annualGrossProfit': 'grossProfit',
  'annualEBIT': 'ebit',
};

/// Son ~4 yıllık yıllık bilanço/gelir tablosu/nakit akışı verisi (bkz. dosya
/// başı `FinancialYear` doc yorumu — banka gibi finans sektörü şirketlerinde
/// bazı alanlar `null` kalır). `fundamentals-timeseries` uç noktasından
/// gelir, yeniden eskiye değil eskiden yeniye (mali yıl artan) sıralı döner.
Future<List<FinancialYear>> fetchFinancialHistory(http.Client client, String symbol) async {
  final cached = _historyCache[symbol];
  if (cached != null && cached.expiresAt.isAfter(DateTime.now())) {
    return cached.data;
  }

  final now = DateTime.now().toUtc();
  final period1 =
      now.subtract(const Duration(days: 365 * 5)).millisecondsSinceEpoch ~/ 1000;
  final period2 = now.millisecondsSinceEpoch ~/ 1000;

  final resp = await _getWithCrumb(
    client,
    (crumb) => Uri.https(
      'query2.finance.yahoo.com',
      '/ws/fundamentals-timeseries/v1/finance/timeseries/$symbol',
      {
        'symbol': symbol,
        'type': _historyFieldMap.keys.join(','),
        'period1': '$period1',
        'period2': '$period2',
        'crumb': crumb,
      },
    ),
  );
  if (resp.statusCode != 200) {
    throw YahooException('Yahoo fundamentals-timeseries isteği başarısız (${resp.statusCode})');
  }

  final body = jsonDecode(resp.body) as Map<String, dynamic>;
  final results = (body['timeseries']?['result'] as List?) ?? const [];
  if (results.isEmpty) {
    throw YahooException('Sembol bulunamadı veya finansal veri yok: $symbol');
  }

  final byYear = <int, Map<String, double?>>{};
  for (final r in results) {
    final rMap = r as Map<String, dynamic>;
    final types = (rMap['meta'] as Map<String, dynamic>?)?['type'] as List?;
    if (types == null || types.isEmpty) continue;
    final rawType = types.first as String;
    final field = _historyFieldMap[rawType];
    if (field == null) continue;
    final series = rMap[rawType] as List?;
    if (series == null) continue;

    for (final entry in series) {
      if (entry == null) continue;
      final e = entry as Map<String, dynamic>;
      final asOfDate = e['asOfDate'] as String?;
      final reportedValue = e['reportedValue'] as Map<String, dynamic>?;
      final value = _asDouble(reportedValue?['raw']);
      if (asOfDate == null || asOfDate.length < 4) continue;
      final year = int.tryParse(asOfDate.substring(0, 4));
      if (year == null) continue;
      (byYear[year] ??= {})[field] = value;
    }
  }

  final list = byYear.entries.map((e) {
    final v = e.value;
    return FinancialYear(
      fiscalYear: e.key,
      totalRevenue: v['totalRevenue'],
      netIncome: v['netIncome'],
      freeCashFlow: v['freeCashFlow'],
      operatingCashFlow: v['operatingCashFlow'],
      capitalExpenditure: v['capitalExpenditure'],
      totalAssets: v['totalAssets'],
      totalLiabilities: v['totalLiabilities'],
      stockholdersEquity: v['stockholdersEquity'],
      currentAssets: v['currentAssets'],
      currentLiabilities: v['currentLiabilities'],
      retainedEarnings: v['retainedEarnings'],
      grossProfit: v['grossProfit'],
      ebit: v['ebit'],
    );
  }).toList()
    ..sort((a, b) => a.fiscalYear.compareTo(b.fiscalYear));

  _historyCache[symbol] = _HistoryCacheEntry(list, DateTime.now().add(_fundamentalsCacheTtl));
  return list;
}
