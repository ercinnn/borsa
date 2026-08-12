import '../models/candle.dart';
import '../models/interval.dart';
import '../services/market_api.dart';

/// [fetchCandlesWithMinimum]'ın sonucu: gösterilecek [result]'a ek olarak,
/// kullanıcının seçmediği ama grafiği doldurmak için otomatik eklenen
/// (en baştaki) mum sayısı ([paddingCount]) ve neler olduğuna dair
/// bayraklar. Ekranlar bunu hem `CandlestickChart`'a (görsel ayrım) hem bir
/// SnackBar'a (bkz. home_screen.dart/tracking_screen.dart `_fetch()`) besler.
class PaddedCandleResult {
  final CandleResult result;
  final int paddingCount;
  final bool wasPadded;
  final bool historyLimited;
  final DateTime effectiveStart;

  const PaddedCandleResult({
    required this.result,
    required this.paddingCount,
    required this.wasPadded,
    required this.historyLimited,
    required this.effectiveStart,
  });
}

// Interval başına kaba bir "mum başına takvim günü" tahmini — kesin olması
// gerekmiyor, sadece başlangıç tarihini ne kadar geriye çekmemiz gerektiğine
// dair bir ilk tahmin. Günlük için 7/5 (hafta sonu), diğerleri kendi doğal
// periyodu (`_technicalHandler`'ın ~500 takvim günü/~250 işlem günü
// oranıyla aynı ruhta bir yaklaşıklık — bkz. bin/server.dart).
const _calendarDaysPerCandle = {
  ChartInterval.hourly: 0.3,
  ChartInterval.fourHour: 0.5,
  ChartInterval.daily: 1.4,
  ChartInterval.weekly: 7.0,
  ChartInterval.monthly: 30.0,
  ChartInterval.quarterly: 91.0,
  ChartInterval.yearly: 365.0,
};

// Tam isabet yerine biraz fazla istemek (eksik kalıp yine "yetersiz" görünen
// bir grafikten daha iyi) — hafta sonu/tatil boşluklarının basit tahminde
// hesaba katılmayan payını da kısmen kapatıyor.
const _overshootFactor = 1.4;

final _pickerFirstDate = DateTime(2000);

// Yahoo'nun gün-içi (60m/4h) geçmişi kabaca son ~730 günle sınırlı (bkz.
// CLAUDE.md "Known rough edges") — uzatılmış başlangıcı bu sınırın epey
// gerisinde tutup, aşağıdaki try/catch'i gereksiz yere tetiklememeye
// çalışıyoruz.
const _intradayLookbackCapDays = 700;

/// [range]/[interval] ile çekilen mum sayısı [minCandles]'ın altında
/// kalırsa, başlangıç tarihini geriye çekip bir kez daha dener. İkinci
/// deneme de yetmezse ya da Yahoo'nun kendi geçmiş sınırına takılırsa
/// (`ApiException`), orijinal sonuçla devam edilir — sonsuz tekrar yok,
/// en fazla iki istek.
Future<PaddedCandleResult> fetchCandlesWithMinimum({
  required MarketApi api,
  required String symbol,
  required DateTime start,
  required DateTime end,
  required ChartInterval interval,
  required int minCandles,
  bool includeIndicators = false,
}) async {
  final original = await api.candles(
    symbol: symbol,
    start: start,
    end: end,
    interval: interval,
    includeIndicators: includeIndicators,
  );

  if (original.candles.length >= minCandles) {
    return PaddedCandleResult(
      result: original,
      paddingCount: 0,
      wasPadded: false,
      historyLimited: false,
      effectiveStart: start,
    );
  }

  final missing = minCandles - original.candles.length;
  final daysPerCandle = _calendarDaysPerCandle[interval] ?? 30.0;
  final extraDays = (missing * daysPerCandle * _overshootFactor).ceil();

  var extendedStart = start.subtract(Duration(days: extraDays));
  if (extendedStart.isBefore(_pickerFirstDate)) {
    extendedStart = _pickerFirstDate;
  }
  final isIntraday = interval == ChartInterval.hourly || interval == ChartInterval.fourHour;
  if (isIntraday) {
    final cap = end.subtract(const Duration(days: _intradayLookbackCapDays));
    if (extendedStart.isBefore(cap)) extendedStart = cap;
  }

  if (!extendedStart.isBefore(start)) {
    // Zaten en erken tarihe (2000 ya da intraday tavanı) dayanmış, geriye
    // gidecek yer yok — ikinci bir istek atmaya gerek yok.
    return PaddedCandleResult(
      result: original,
      paddingCount: 0,
      wasPadded: false,
      historyLimited: true,
      effectiveStart: start,
    );
  }

  CandleResult extended;
  try {
    extended = await api.candles(
      symbol: symbol,
      start: extendedStart,
      end: end,
      interval: interval,
      includeIndicators: includeIndicators,
    );
  } on ApiException {
    // Uzatılmış aralık Yahoo'nun kendi sınırını aştı (ör. intraday ~730
    // gün) — kullanıcının önceden çalışan grafiğini bir hataya çevirmek
    // yerine sessizce orijinal sonuçla devam ediyoruz.
    return PaddedCandleResult(
      result: original,
      paddingCount: 0,
      wasPadded: false,
      historyLimited: true,
      effectiveStart: start,
    );
  }

  final gained = extended.candles.length - original.candles.length;
  if (gained <= 0) {
    // Sembolün gerçek geçmişi zaten bu kadarmış (ör. yeni halka arz).
    return PaddedCandleResult(
      result: original,
      paddingCount: 0,
      wasPadded: false,
      historyLimited: true,
      effectiveStart: start,
    );
  }

  return PaddedCandleResult(
    result: extended,
    paddingCount: gained,
    wasPadded: true,
    historyLimited: false,
    effectiveStart: extendedStart,
  );
}
