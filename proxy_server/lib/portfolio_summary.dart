import 'package:http/http.dart' as http;

import 'store.dart';
import 'yahoo_client.dart';

class PortfolioHoldingResult {
  final String symbol;
  final double quantity;
  final double costBasis;
  final String currency;
  final double? currentPrice;
  final double? currentValue; // quantity * currentPrice, sembolün kendi para birimi
  final double? costValue; // quantity * costBasis, aynı para birimi
  final double? pnl;
  final double? pnlPct;
  /// TRY karşılığı — yalnızca para birimi TRY veya USD ise dolu (bkz.
  /// [computePortfolioSummary] doc yorumu); diğer para birimleri toplama
  /// dahil edilmez.
  final double? valueInTry;
  /// Son 15 yılda ödenen hisse başı temettülerin toplamı (bkz.
  /// yahoo_client.dart fetchDividends) — temettü verisi alınamazsa veya hiç
  /// temettü ödenmemişse null.
  final double? totalDividendPerShare;
  /// quantity × totalDividendPerShare, holding'in kendi para biriminde.
  /// BASİTLEŞTİRİLMİŞ BİR TAHMİNDİR: pozisyonu ne zaman satın aldığın hesaba
  /// katılmaz, sanki mevcut adedi son 15 yıl boyunca elinde tutmuşsun gibi
  /// hesaplanır (bkz. [computePortfolioSummary] doc yorumu).
  final double? estimatedDividendIncome;
  /// estimatedDividendIncome'ın TRY karşılığı — valueInTry ile aynı kural
  /// (yalnızca TRY/USD).
  final double? estimatedDividendIncomeTry;
  final String? error;

  PortfolioHoldingResult({
    required this.symbol,
    required this.quantity,
    required this.costBasis,
    required this.currency,
    this.currentPrice,
    this.currentValue,
    this.costValue,
    this.pnl,
    this.pnlPct,
    this.valueInTry,
    this.totalDividendPerShare,
    this.estimatedDividendIncome,
    this.estimatedDividendIncomeTry,
    this.error,
  });

  Map<String, dynamic> toJson() => {
        'symbol': symbol,
        'quantity': quantity,
        'costBasis': costBasis,
        'currency': currency,
        'currentPrice': currentPrice,
        'currentValue': currentValue,
        'costValue': costValue,
        'pnl': pnl,
        'pnlPct': pnlPct,
        'valueInTry': valueInTry,
        'totalDividendPerShare': totalDividendPerShare,
        'estimatedDividendIncome': estimatedDividendIncome,
        'estimatedDividendIncomeTry': estimatedDividendIncomeTry,
        'error': error,
      };
}

class PortfolioSummary {
  final List<PortfolioHoldingResult> holdings;
  final double totalValueTry;
  final double totalCostTry;
  final double totalPnlTry;
  final double? totalPnlPct;
  final double? usdTryRate;
  final int unconvertedCount;
  /// Tüm holding'lerin estimatedDividendIncomeTry toplamı (bkz.
  /// [PortfolioHoldingResult.estimatedDividendIncome] doc yorumu — aynı
  /// basitleştirme burada da geçerli).
  final double totalDividendIncomeTry;

  PortfolioSummary({
    required this.holdings,
    required this.totalValueTry,
    required this.totalCostTry,
    required this.totalPnlTry,
    required this.totalPnlPct,
    required this.usdTryRate,
    required this.unconvertedCount,
    required this.totalDividendIncomeTry,
  });

  Map<String, dynamic> toJson() => {
        'holdings': holdings.map((h) => h.toJson()).toList(),
        'totalValueTry': totalValueTry,
        'totalCostTry': totalCostTry,
        'totalPnlTry': totalPnlTry,
        'totalPnlPct': totalPnlPct,
        'usdTryRate': usdTryRate,
        'unconvertedCount': unconvertedCount,
        'totalDividendIncomeTry': totalDividendIncomeTry,
      };
}

/// Her pozisyon için Yahoo'dan güncel fiyatı çeker (kendi para biriminde
/// kâr/zarar hesaplanır — ör. bir BIST hissesi için TRY, bir ABD hissesi
/// için USD), ayrıca "TRY=X" (USD/TRY kuru) sembolünü de aynı `fetchChart`
/// ile çekip TRY ve USD cinsinden pozisyonları TEK bir toplam portföy
/// değerine çevirir. Bu uygulamada BIST sembolleri TRY, ABD hisseleri ve
/// kripto (`-USD` çiftleri) USD döndürür — pratikte karşılaşılan tek iki
/// para birimi budur; başka bir para birimi (ör. EUR) dönerse o pozisyon
/// listede ayrı ayrı gösterilir ama TRY toplamına dahil edilmez
/// (`valueInTry: null`, `unconvertedCount` ile sayılır).
Future<PortfolioSummary> computePortfolioSummary(
  http.Client client,
  List<PortfolioHoldingRow> holdings,
) async {
  if (holdings.isEmpty) {
    return PortfolioSummary(
      holdings: [],
      totalValueTry: 0,
      totalCostTry: 0,
      totalPnlTry: 0,
      totalPnlPct: null,
      usdTryRate: null,
      unconvertedCount: 0,
      totalDividendIncomeTry: 0,
    );
  }

  final now = DateTime.now().toUtc();
  final period2 = now.millisecondsSinceEpoch ~/ 1000 + 86400;
  final period1 = now.subtract(const Duration(days: 7)).millisecondsSinceEpoch ~/ 1000;

  double? usdTryRate;
  try {
    final rateData = await fetchChart(client, 'TRY=X', period1, period2, '1d');
    if (rateData.candles.isNotEmpty) {
      usdTryRate = rateData.candles.last.close.toDouble();
    }
  } catch (_) {
    // Kur alınamazsa USD pozisyonlar TRY toplamına giremez (aşağıda
    // valueInTry: null olarak işaretlenir) ama kendi para birimlerinde
    // gösterilmeye devam eder.
  }

  final results = await Future.wait(holdings.map((h) async {
    try {
      final data = await fetchChart(client, h.symbol, period1, period2, '1d');
      if (data.candles.isEmpty) {
        return PortfolioHoldingResult(
          symbol: h.symbol,
          quantity: h.quantity,
          costBasis: h.costBasis,
          currency: data.currency,
          error: 'Güncel fiyat alınamadı',
        );
      }
      final price = data.candles.last.close.toDouble();
      final currentValue = h.quantity * price;
      final costValue = h.quantity * h.costBasis;
      final pnl = currentValue - costValue;
      final pnlPct = costValue == 0 ? null : (pnl / costValue) * 100;
      final valueInTry = _convertToTry(currentValue, data.currency, usdTryRate);

      // Temettü verisi ayrı bir Yahoo isteği gerektirir (bkz. fetchDividends
      // doc yorumu); alınamazsa pozisyon yine de fiyat/kâr-zarar bilgisiyle
      // gösterilir, sadece temettü alanları null kalır.
      double? totalDividendPerShare;
      try {
        final dividendData = await fetchDividends(client, h.symbol);
        if (dividendData.dividends.isNotEmpty) {
          totalDividendPerShare = dividendData.dividends
              .fold<double>(0, (sum, d) => sum + d.amount.toDouble());
        }
      } catch (_) {
        // Yukarıdaki yorumda açıklandığı gibi sessizce null bırakılır.
      }
      // BASİTLEŞTİRİLMİŞ BİR TAHMİN: pozisyonu ne zaman satın aldığın hesaba
      // katılmaz, mevcut adedi son 15 yıl boyunca elinde tutmuşsun gibi
      // hesaplanır (bkz. PortfolioHoldingResult.estimatedDividendIncome doc
      // yorumu).
      final estimatedDividendIncome =
          totalDividendPerShare == null ? null : h.quantity * totalDividendPerShare;
      final estimatedDividendIncomeTry = estimatedDividendIncome == null
          ? null
          : _convertToTry(estimatedDividendIncome, data.currency, usdTryRate);

      return PortfolioHoldingResult(
        symbol: h.symbol,
        quantity: h.quantity,
        costBasis: h.costBasis,
        currency: data.currency,
        currentPrice: price,
        currentValue: currentValue,
        costValue: costValue,
        pnl: pnl,
        pnlPct: pnlPct,
        valueInTry: valueInTry,
        totalDividendPerShare: totalDividendPerShare,
        estimatedDividendIncome: estimatedDividendIncome,
        estimatedDividendIncomeTry: estimatedDividendIncomeTry,
      );
    } on YahooException catch (e) {
      return PortfolioHoldingResult(
        symbol: h.symbol,
        quantity: h.quantity,
        costBasis: h.costBasis,
        currency: '',
        error: e.message,
      );
    } catch (e) {
      return PortfolioHoldingResult(
        symbol: h.symbol,
        quantity: h.quantity,
        costBasis: h.costBasis,
        currency: '',
        error: 'Fiyat alınırken bir hata oluştu',
      );
    }
  }));

  var totalValueTry = 0.0;
  var totalCostTry = 0.0;
  var unconvertedCount = 0;
  var totalDividendIncomeTry = 0.0;
  for (final r in results) {
    final costValueTry = r.costValue == null
        ? null
        : _convertToTry(r.costValue!, r.currency, usdTryRate);
    if (r.valueInTry != null && costValueTry != null) {
      totalValueTry += r.valueInTry!;
      totalCostTry += costValueTry;
    } else if (r.error == null) {
      unconvertedCount++;
    }
    if (r.estimatedDividendIncomeTry != null) {
      totalDividendIncomeTry += r.estimatedDividendIncomeTry!;
    }
  }
  final totalPnlTry = totalValueTry - totalCostTry;
  final totalPnlPct = totalCostTry == 0 ? null : (totalPnlTry / totalCostTry) * 100;

  return PortfolioSummary(
    holdings: results,
    totalValueTry: totalValueTry,
    totalCostTry: totalCostTry,
    totalPnlTry: totalPnlTry,
    totalPnlPct: totalPnlPct,
    usdTryRate: usdTryRate,
    unconvertedCount: unconvertedCount,
    totalDividendIncomeTry: totalDividendIncomeTry,
  );
}

double? _convertToTry(double value, String currency, double? usdTryRate) {
  if (currency == 'TRY') return value;
  if (currency == 'USD' && usdTryRate != null) return value * usdTryRate;
  return null;
}
