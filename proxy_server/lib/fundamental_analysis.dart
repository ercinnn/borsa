import 'dart:math';

import 'technical_analysis.dart' show InsufficientDataException;
import 'yahoo_fundamentals.dart';

/// DCF hesaplamasında kullanılan varsayımlar — hepsi BASİTLEŞTİRİLMİŞTİR
/// (bkz. [computeFairValueDCF] doc yorumu). Yanıtta döndürülür ki kullanıcı
/// hangi varsayımlarla üretildiğini görebilsin.
class DcfAssumptions {
  final double growthRate;
  final double discountRate;
  final double terminalGrowthRate;
  final int projectionYears;
  DcfAssumptions({
    required this.growthRate,
    required this.discountRate,
    required this.terminalGrowthRate,
    required this.projectionYears,
  });

  Map<String, dynamic> toJson() => {
        'growthRate': growthRate,
        'discountRate': discountRate,
        'terminalGrowthRate': terminalGrowthRate,
        'projectionYears': projectionYears,
      };
}

class FairValueResult {
  final String symbol;
  final double? fairValuePerShare;
  final double? currentPrice;
  final String currency;
  /// (fairValue - currentPrice) / currentPrice * 100 — pozitifse mevcut
  /// fiyat DCF'e göre iskontolu (ucuz), negatifse primli (pahalı).
  final double? upsidePct;
  final DcfAssumptions assumptions;
  final String? error;

  FairValueResult({
    required this.symbol,
    required this.fairValuePerShare,
    required this.currentPrice,
    required this.currency,
    required this.upsidePct,
    required this.assumptions,
    this.error,
  });

  Map<String, dynamic> toJson() => {
        'symbol': symbol,
        'fairValuePerShare': fairValuePerShare,
        'currentPrice': currentPrice,
        'currency': currency,
        'upsidePct': upsidePct,
        'assumptions': assumptions.toJson(),
        'error': error,
      };
}

/// DCF (İndirgenmiş Nakit Akışı) ile hisse başına Adil Değer tahmini.
/// BASİTLEŞTİRİLMİŞ VARSAYIMLAR (gerçek bir DCF, şirkete özgü beta/sermaye
/// yapısı/risksiz faiz oranı gerektirir — bunlar burada elde edilebilir
/// veriler değil):
/// - Büyüme oranı: geçmiş FCF'in yıllık ortalama değişim oranı, aşırı
///   ekstrapolasyonu önlemek için [-%15, +%20] aralığına clamp'lenir.
/// - İskonto oranı (WACC yerine): sabit bir varsayım — TRY için %30, diğer
///   para birimleri için %10 (Türkiye'nin yapısal olarak yüksek enflasyon/
///   nominal faiz ortamı gerçek bir WACC hesabını bu kapsamın dışına
///   taşır; sabit oran kaba ama şeffaf bir yaklaşım).
/// - Terminal büyüme: TRY için %15, diğerleri için %2.5.
/// - Projeksiyon ufku: 5 yıl.
/// Bu bir yatırım tavsiyesi değildir; yalnızca yukarıdaki varsayımlar
/// altında ne çıktığını gösterir (`assumptions` alanı şeffaflık için
/// döndürülür).
FairValueResult computeFairValueDCF(
  String symbol,
  StockOverview overview,
  List<FinancialYear> history,
) {
  final isTry = overview.currency == 'TRY';
  final discountRate = isTry ? 0.30 : 0.10;
  final terminalGrowthRate = isTry ? 0.15 : 0.025;
  const projectionYears = 5;

  FairValueResult withError(String message, {double growthRate = 0}) => FairValueResult(
        symbol: symbol,
        fairValuePerShare: null,
        currentPrice: overview.lastPrice,
        currency: overview.currency,
        upsidePct: null,
        assumptions: DcfAssumptions(
          growthRate: growthRate,
          discountRate: discountRate,
          terminalGrowthRate: terminalGrowthRate,
          projectionYears: projectionYears,
        ),
        error: message,
      );

  final fcfYears = history.where((y) => y.freeCashFlow != null).toList()
    ..sort((a, b) => a.fiscalYear.compareTo(b.fiscalYear));
  if (fcfYears.length < 2) {
    return withError('DCF hesaplamak için yeterli serbest nakit akışı geçmişi yok.');
  }
  if (overview.sharesOutstanding == null || overview.sharesOutstanding == 0) {
    return withError('Hisse adedi bilgisi alınamadığından DCF hesaplanamadı.');
  }

  final growthRates = <double>[];
  for (var i = 1; i < fcfYears.length; i++) {
    final prev = fcfYears[i - 1].freeCashFlow!;
    final curr = fcfYears[i].freeCashFlow!;
    if (prev > 0) growthRates.add((curr - prev) / prev);
  }
  final avgGrowth =
      growthRates.isEmpty ? 0.05 : growthRates.reduce((a, b) => a + b) / growthRates.length;
  final growthRate = avgGrowth.clamp(-0.15, 0.20);

  final lastFcf = fcfYears.last.freeCashFlow!;
  if (lastFcf <= 0) {
    return withError(
      'Son yıl serbest nakit akışı negatif/sıfır olduğundan DCF anlamlı bir sonuç üretmiyor.',
      growthRate: growthRate,
    );
  }

  var pvSum = 0.0;
  var fcf = lastFcf;
  for (var t = 1; t <= projectionYears; t++) {
    fcf *= (1 + growthRate);
    pvSum += fcf / pow(1 + discountRate, t);
  }
  final terminalValue = fcf * (1 + terminalGrowthRate) / (discountRate - terminalGrowthRate);
  final pvTerminal = terminalValue / pow(1 + discountRate, projectionYears);
  final enterpriseValue = pvSum + pvTerminal;
  final fairValuePerShare = enterpriseValue / overview.sharesOutstanding!;
  final upsidePct = overview.lastPrice == 0
      ? null
      : (fairValuePerShare - overview.lastPrice) / overview.lastPrice * 100;

  return FairValueResult(
    symbol: symbol,
    fairValuePerShare: fairValuePerShare,
    currentPrice: overview.lastPrice,
    currency: overview.currency,
    upsidePct: upsidePct,
    assumptions: DcfAssumptions(
      growthRate: growthRate,
      discountRate: discountRate,
      terminalGrowthRate: terminalGrowthRate,
      projectionYears: projectionYears,
    ),
  );
}

class PiotroskiCriterion {
  final String name;
  /// null: bu sembol için veri yetersizliği nedeniyle hesaplanamadı (bkz.
  /// [computePiotroskiFScore] doc yorumu — banka gibi finans sektörü
  /// şirketlerinde bazı kriterler hiç hesaplanamaz).
  final bool? passed;
  PiotroskiCriterion(this.name, this.passed);

  Map<String, dynamic> toJson() => {'name': name, 'passed': passed};
}

class PiotroskiResult {
  final int score;
  /// Bu sembol için gerçekten hesaplanabilen kriter sayısı (9 değil — bkz.
  /// [computePiotroskiFScore] doc yorumu).
  final int maxScore;
  final List<PiotroskiCriterion> criteria;

  PiotroskiResult({required this.score, required this.maxScore, required this.criteria});

  Map<String, dynamic> toJson() => {
        'score': score,
        'maxScore': maxScore,
        'criteria': criteria.map((c) => c.toJson()).toList(),
      };
}

/// Piotroski F-Score: karlılık/kaldıraç-likidite/operasyonel verimlilik
/// kriterlerine göre ikili (geçti/kalmadı) bir puan sistemi — klasik
/// literatürde 9 kriter, 0-9 arası puan. Bu implementasyon **8 kriter**
/// içerir: "dönem içinde yeni hisse ihraç edilmedi" kriteri, Yahoo'dan
/// geçmiş hisse adedi serisi çekilmediğinden (bkz. yahoo_fundamentals.dart
/// — yalnızca güncel `sharesOutstanding` var, tarihsel seri yok) bu sürümde
/// yer almıyor. Ayrıca banka gibi finans sektörü şirketlerinde brüt marj/
/// cari oran kriterleri de veri eksikliğinden hesaplanamaz (bkz.
/// yahoo_fundamentals.dart `FinancialYear` doc yorumu) — bu durumda
/// `passed: null` döner ve puan yalnızca hesaplanabilen kriterler üzerinden
/// (`maxScore`) normalize edilir, 9 üzerinden gösterilmez.
PiotroskiResult computePiotroskiFScore(List<FinancialYear> history) {
  final sorted = List<FinancialYear>.from(history)
    ..sort((a, b) => a.fiscalYear.compareTo(b.fiscalYear));
  if (sorted.length < 2) {
    throw InsufficientDataException(
      'Piotroski F-Score hesaplamak için en az 2 yıllık finansal veri gerekli.',
    );
  }
  final curr = sorted.last;
  final prev = sorted[sorted.length - 2];

  double? roa(FinancialYear y) =>
      (y.netIncome == null || y.totalAssets == null || y.totalAssets == 0)
          ? null
          : y.netIncome! / y.totalAssets!;
  double? leverage(FinancialYear y) =>
      (y.totalLiabilities == null || y.totalAssets == null || y.totalAssets == 0)
          ? null
          : y.totalLiabilities! / y.totalAssets!;
  double? currentRatio(FinancialYear y) =>
      (y.currentAssets == null || y.currentLiabilities == null || y.currentLiabilities == 0)
          ? null
          : y.currentAssets! / y.currentLiabilities!;
  double? grossMargin(FinancialYear y) =>
      (y.grossProfit == null || y.totalRevenue == null || y.totalRevenue == 0)
          ? null
          : y.grossProfit! / y.totalRevenue!;
  double? assetTurnover(FinancialYear y) =>
      (y.totalRevenue == null || y.totalAssets == null || y.totalAssets == 0)
          ? null
          : y.totalRevenue! / y.totalAssets!;

  bool? gt(double? a, double? b) => (a == null || b == null) ? null : a > b;
  bool? isPositive(double? v) => v == null ? null : v > 0;

  final currRoa = roa(curr);
  final prevRoa = roa(prev);
  final currLeverage = leverage(curr);
  final prevLeverage = leverage(prev);
  final currCurrentRatio = currentRatio(curr);
  final prevCurrentRatio = currentRatio(prev);
  final currGrossMargin = grossMargin(curr);
  final prevGrossMargin = grossMargin(prev);
  final currAssetTurnover = assetTurnover(curr);
  final prevAssetTurnover = assetTurnover(prev);
  final cfoOverNetIncome = (curr.operatingCashFlow == null || curr.netIncome == null)
      ? null
      : curr.operatingCashFlow! > curr.netIncome!;

  final criteria = [
    PiotroskiCriterion('ROA pozitif', isPositive(currRoa)),
    PiotroskiCriterion('Faaliyet nakit akışı pozitif', isPositive(curr.operatingCashFlow)),
    PiotroskiCriterion('ROA geçen yıla göre arttı', gt(currRoa, prevRoa)),
    PiotroskiCriterion('Faaliyet nakit akışı net kârdan yüksek', cfoOverNetIncome),
    PiotroskiCriterion('Kaldıraç (borç/aktif) azaldı', gt(prevLeverage, currLeverage)),
    PiotroskiCriterion('Cari oran arttı', gt(currCurrentRatio, prevCurrentRatio)),
    PiotroskiCriterion('Brüt kâr marjı arttı', gt(currGrossMargin, prevGrossMargin)),
    PiotroskiCriterion('Aktif devir hızı arttı', gt(currAssetTurnover, prevAssetTurnover)),
  ];

  final applicable = criteria.where((c) => c.passed != null).toList();
  final score = applicable.where((c) => c.passed == true).length;

  return PiotroskiResult(score: score, maxScore: applicable.length, criteria: criteria);
}

class AltmanZResult {
  final double? zScore;
  final String? zone; // 'safe' | 'grey' | 'distress'
  final String? error;

  AltmanZResult({this.zScore, this.zone, this.error});

  Map<String, dynamic> toJson() => {'zScore': zScore, 'zone': zone, 'error': error};
}

/// Altman Z-Score: iflas riskini 5 oranlı ağırlıklı bir formülle özetler —
/// klasik formül (kamuya açık, imalat/sanayi tipi şirketler için):
/// Z = 1.2·A + 1.4·B + 3.3·C + 0.6·D + 1.0·E, burada A=işletme sermayesi/
/// aktif, B=dağıtılmamış kâr/aktif, C=FVÖK/aktif, D=piyasa değeri/toplam
/// yükümlülük, E=satışlar/aktif. **Banka/finans sektörü şirketlerinde
/// hesaplanamaz**: bu formül işletme sermayesi (cari varlık-cari yükümlülük)
/// ve FVÖK gerektirir, bankaların bilanço yapısında bu kalemler yok (bkz.
/// yahoo_fundamentals.dart doc yorumu) — bu durumda `zScore: null` +
/// açıklayıcı `error` döner.
AltmanZResult computeAltmanZScore(StockOverview overview, List<FinancialYear> history) {
  if (history.isEmpty) {
    return AltmanZResult(error: 'Altman Z-Score hesaplamak için finansal veri yok.');
  }
  final latest = (List<FinancialYear>.from(history)
        ..sort((a, b) => a.fiscalYear.compareTo(b.fiscalYear)))
      .last;

  final totalAssets = latest.totalAssets;
  final currentAssets = latest.currentAssets;
  final currentLiabilities = latest.currentLiabilities;
  final retainedEarnings = latest.retainedEarnings;
  final ebit = latest.ebit;
  final totalLiabilities = latest.totalLiabilities;
  final totalRevenue = latest.totalRevenue;
  final marketCap = overview.marketCap;

  if (totalAssets == null ||
      totalAssets == 0 ||
      currentAssets == null ||
      currentLiabilities == null ||
      retainedEarnings == null ||
      ebit == null ||
      totalLiabilities == null ||
      totalLiabilities == 0 ||
      totalRevenue == null ||
      marketCap == null) {
    return AltmanZResult(
      error: 'Bu skor banka/finans sektörü şirketleri için hesaplanamıyor '
          '(bilanço yapısı farklı — işletme sermayesi/FVÖK kalemleri yok).',
    );
  }

  final a = (currentAssets - currentLiabilities) / totalAssets;
  final b = retainedEarnings / totalAssets;
  final c = ebit / totalAssets;
  final d = marketCap / totalLiabilities;
  final e = totalRevenue / totalAssets;

  final z = 1.2 * a + 1.4 * b + 3.3 * c + 0.6 * d + 1.0 * e;
  final zone = z > 2.99 ? 'safe' : (z >= 1.81 ? 'grey' : 'distress');

  return AltmanZResult(zScore: z, zone: zone);
}

/// Tüm hesaplamaları tek bir kural-tabanlı Türkçe özet metin dizisine
/// sentezler — `technical_screen.dart`'taki `_generateCommentary()` ile aynı
/// ruh (LLM yok, şablon cümleler), ama fundamental veriden. Yatırım
/// tavsiyesi değildir.
List<String> generateProTips(
  StockOverview overview,
  List<FinancialYear> history,
  FairValueResult fairValue,
  PiotroskiResult piotroski,
  AltmanZResult altman,
) {
  final tips = <String>[];
  final sorted = List<FinancialYear>.from(history)
    ..sort((a, b) => a.fiscalYear.compareTo(b.fiscalYear));

  final fcfYears = sorted.where((y) => y.freeCashFlow != null).toList();
  if (fcfYears.length >= 2) {
    final first = fcfYears.first.freeCashFlow!;
    final last = fcfYears.last.freeCashFlow!;
    if (first > 0) {
      final totalGrowthPct = (last - first) / first * 100;
      if (totalGrowthPct > 20) {
        tips.add('Şirket, ${fcfYears.first.fiscalYear}-${fcfYears.last.fiscalYear} arasında '
            'serbest nakit akışını %${totalGrowthPct.toStringAsFixed(0)} büyüttü.');
      } else if (totalGrowthPct < -20) {
        tips.add('Şirketin serbest nakit akışı ${fcfYears.first.fiscalYear}-'
            '${fcfYears.last.fiscalYear} arasında %${totalGrowthPct.abs().toStringAsFixed(0)} '
            'geriledi.');
      }
    }
  }

  if (overview.debtToEquity != null) {
    if (overview.debtToEquity! > 150) {
      tips.add('Borç/özkaynak oranı ${overview.debtToEquity!.toStringAsFixed(0)} ile yüksek — '
          'kaldıraç riski taşıyor.');
    } else if (overview.debtToEquity! < 30) {
      tips.add('Borç/özkaynak oranı ${overview.debtToEquity!.toStringAsFixed(0)} ile düşük — '
          'görece sağlam bir bilanço yapısı.');
    }
  }

  if (piotroski.maxScore > 0) {
    final ratio = piotroski.score / piotroski.maxScore;
    if (ratio >= 0.75) {
      tips.add('Piotroski F-Score ${piotroski.score}/${piotroski.maxScore} ile güçlü — '
          'karlılık, kaldıraç ve verimlilik kriterlerinin çoğunu karşılıyor.');
    } else if (ratio <= 0.25) {
      tips.add('Piotroski F-Score ${piotroski.score}/${piotroski.maxScore} ile zayıf — '
          'temel finansal sağlık kriterlerinin çoğunu karşılamıyor.');
    }
  }

  if (altman.zone != null) {
    switch (altman.zone) {
      case 'safe':
        tips.add('Altman Z-Score güvenli bölgede (${altman.zScore!.toStringAsFixed(2)}) — '
            'iflas riski düşük olarak görünüyor.');
        break;
      case 'distress':
        tips.add('Altman Z-Score riskli bölgede (${altman.zScore!.toStringAsFixed(2)}) — '
            'finansal sıkıntı riski modele göre yüksek.');
        break;
    }
  }

  if (fairValue.upsidePct != null) {
    if (fairValue.upsidePct! > 20) {
      tips.add('Güncel fiyat, bu sayfadaki basitleştirilmiş DCF varsayımlarına göre '
          'hesaplanan adil değerin %${fairValue.upsidePct!.toStringAsFixed(0)} altında.');
    } else if (fairValue.upsidePct! < -20) {
      tips.add('Güncel fiyat, bu sayfadaki basitleştirilmiş DCF varsayımlarına göre '
          'hesaplanan adil değerin %${fairValue.upsidePct!.abs().toStringAsFixed(0)} üzerinde.');
    }
  }

  if (overview.dividendYield != null && overview.dividendYield! > 0.05) {
    tips.add('Temettü verimi %${(overview.dividendYield! * 100).toStringAsFixed(1)} ile '
        'dikkat çekici seviyede.');
  }

  if (tips.isEmpty) {
    tips.add('Bu sembol için öne çıkan bir bulgu tespit edilmedi — göstergeler nötr aralıkta.');
  }

  return tips;
}
