import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../models/symbol.dart';
import '../models/technical_analysis.dart';
import '../services/market_api.dart';
import '../theme/app_colors.dart';
import '../utils/price_format.dart';
import '../utils/score_color.dart';
import '../widgets/favorite_symbols_bar.dart';
import '../widgets/glass_card.dart';
import '../widgets/symbol_search_field.dart';

/// Investing.com'un "Teknik Özet" sayfasına benzer bir analiz: kullanıcının
/// bu sekmeye eklediği her sembol için Pivot Noktaları, Hareketli Ortalamalar
/// (MA5..MA200) ve Teknik İndikatörler (RSI, STOCH, STOCHRSI, MACD, ATR, ADX,
/// CCI, Highs/Lows, UO, ROC, Williams %R, Bull/Bear Power) + üç özet kutusu
/// gösterilir. Hesaplama tamamen proxy_server'da yapılır (bkz.
/// lib/technical_analysis.dart); bu ekran sadece sonucu tablolar halinde
/// gösterir. Watchlist/Favoriler'den bağımsız kendi listesini tutar (bkz.
/// TechnicalWatchlistStore) — favorites deseniyle aynı: bildirim üretmez,
/// sadece bu sekmede hangi sembollerin analiz edileceğini belirler.
class TechnicalScreen extends StatefulWidget {
  // Favoriler sekmesindeki listeyle aynı (bkz. main.dart RootShell): bir
  // favoriye tıklamak onu doğrudan bu sekmenin izleme listesine ekler,
  // arayıp bulmaya gerek kalmadan.
  final List<String> favorites;

  const TechnicalScreen({super.key, this.favorites = const []});

  @override
  State<TechnicalScreen> createState() => _TechnicalScreenState();
}

class _TechnicalScreenState extends State<TechnicalScreen> {
  final _api = MarketApi();
  final _dateFormat = DateFormat('dd.MM.yyyy HH:mm');

  List<String> _watchlist = [];
  bool _loadingWatchlist = true;
  String? _watchlistError;

  String? _selectedSymbol;
  bool _loadingAnalysis = false;
  String? _analysisError;
  TechnicalAnalysisResult? _result;

  @override
  void initState() {
    super.initState();
    _loadWatchlist();
  }

  Future<void> _loadWatchlist() async {
    setState(() => _loadingWatchlist = true);
    try {
      final list = await _api.getTechnicalWatchlist();
      if (!mounted) return;
      setState(() {
        _watchlist = list;
        _loadingWatchlist = false;
      });
      if (_selectedSymbol == null && list.isNotEmpty) {
        _selectSymbol(list.first);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _watchlistError = e.toString();
        _loadingWatchlist = false;
      });
    }
  }

  Future<void> _addSymbol(MarketSymbol symbol) async {
    try {
      final result = await _api.addToTechnicalWatchlist(symbol.symbol);
      if (!mounted) return;
      if (result.added && !_watchlist.contains(result.symbol)) {
        setState(() => _watchlist = [..._watchlist, result.symbol]..sort());
      }
      _selectSymbol(result.symbol);
    } catch (e) {
      if (!mounted) return;
      setState(() => _watchlistError = e.toString());
    }
  }

  Future<void> _removeSymbol(String symbol) async {
    try {
      final result = await _api.removeFromTechnicalWatchlist(symbol);
      if (!mounted) return;
      if (result.removed) {
        setState(() {
          _watchlist = _watchlist.where((s) => s != result.symbol).toList();
          if (_selectedSymbol == result.symbol) {
            _selectedSymbol = null;
            _result = null;
          }
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _watchlistError = e.toString());
    }
  }

  Future<void> _selectSymbol(String symbol) async {
    setState(() {
      _selectedSymbol = symbol;
      _loadingAnalysis = true;
      _analysisError = null;
      _result = null;
    });
    try {
      final result = await _api.technicalAnalysis(symbol);
      if (!mounted) return;
      setState(() {
        _result = result;
        _loadingAnalysis = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _analysisError = e.toString();
        _loadingAnalysis = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Teknik', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            'Eklediğin her sembol için Pivot Noktaları, Hareketli Ortalamalar '
            've Teknik İndikatörlere göre otomatik Al/Sat özeti (Investing.com '
            'tarzı, standart formüllerle bu uygulama içinde hesaplanır).',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          SymbolSearchField(api: _api, onSelect: _addSymbol),
          if (widget.favorites.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text('Favoriler', style: Theme.of(context).textTheme.labelSmall),
            const SizedBox(height: 8),
            FavoriteSymbolsBar(
              symbols: [
                for (final s in widget.favorites) MarketSymbol(symbol: s, name: s),
              ],
              selected: _selectedSymbol == null
                  ? null
                  : MarketSymbol(symbol: _selectedSymbol!, name: _selectedSymbol!),
              onSelect: _addSymbol,
            ),
          ],
          if (_watchlistError != null) ...[
            const SizedBox(height: 8),
            Text(_watchlistError!, style: const TextStyle(color: AppColors.rose500)),
          ],
          const SizedBox(height: 12),
          if (_loadingWatchlist)
            const Center(child: CircularProgressIndicator())
          else if (_watchlist.isEmpty)
            Text(
              'Henüz sembol eklenmedi. Yukarıdan arayıp ekleyebilirsin.',
              style: Theme.of(context).textTheme.bodySmall,
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final s in _watchlist)
                  _SymbolChip(
                    symbol: s,
                    selected: s == _selectedSymbol,
                    onSelect: () => _selectSymbol(s),
                    onRemove: () => _removeSymbol(s),
                  ),
              ],
            ),
          const SizedBox(height: 20),
          if (_loadingAnalysis) const Center(child: CircularProgressIndicator()),
          if (_analysisError != null)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.rose500.withValues(alpha: 0.15),
                border: Border.all(color: AppColors.rose500.withValues(alpha: 0.4)),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(_analysisError!, style: const TextStyle(color: AppColors.slate100)),
            ),
          if (_result != null) _TechnicalResultView(result: _result!, dateFormat: _dateFormat),
        ],
      ),
    );
  }
}

/// Pivot satırları ve gösterge satırları için ⓘ diyaloğu içeriği (backend'deki
/// `IndicatorRow.name`/pivot etiketleriyle birebir eşleşen anahtarlar).
/// Investing.com'un kendi açıklama metinleri değil, bu ekrandaki formüllerin
/// (bkz. proxy_server/lib/technical_analysis.dart) genel dille özetidir.
const Map<String, String> _indicatorInfo = {
  'R3': 'Direnç 3 (R3): Fiyatın yükselirken zorlanabileceği en uzak/güçlü '
      'teorik direnç seviyesi. Bir önceki günün en yüksek (H), en düşük (L) '
      've kapanış (C) fiyatlarından türetilir: Pivot = (H+L+C)/3, '
      'R3 = H + 2×(Pivot − L).',
  'R2': 'Direnç 2 (R2): R1\'den sonraki, daha güçlü teorik direnç seviyesi. '
      'R2 = Pivot + (H − L), burada Pivot bir önceki günün H/L/C '
      'ortalamasıdır.',
  'R1': 'Direnç 1 (R1): Fiyatın yükselirken karşılaşabileceği en yakın '
      'teorik direnç seviyesi. R1 = 2×Pivot − L (bir önceki günün en '
      'düşüğü).',
  'Pivot': 'Pivot Noktası: Bir önceki günün en yüksek (H), en düşük (L) ve '
      'kapanış (C) fiyatlarının ortalaması — (H+L+C)/3. Günün "denge" '
      'seviyesi kabul edilir: fiyat bunun üzerindeyse gün genelde alıcılı '
      '(yükseliş eğilimli), altındaysa satıcılı (düşüş eğilimli) yorumlanır. '
      'Diğer tüm destek/direnç seviyeleri bu değerden hesaplanır.',
  'S1': 'Destek 1 (S1): Fiyatın düşerken karşılaşabileceği en yakın teorik '
      'destek seviyesi. S1 = 2×Pivot − H (bir önceki günün en yükseği).',
  'S2': 'Destek 2 (S2): S1\'den sonraki, daha güçlü teorik destek seviyesi. '
      'S2 = Pivot − (H − L).',
  'S3': 'Destek 3 (S3): Fiyatın düşerken zorlanabileceği en uzak/güçlü '
      'teorik destek seviyesi. S3 = L − 2×(H − Pivot).',
  'RSI(14)': 'RSI — Göreceli Güç Endeksi (14): Son 14 günün ortalama '
      'kazanç ve kayıplarının oranından 0-100 arasında hesaplanan bir '
      'momentum göstergesi. 70 üzeri "aşırı alım" (fiyat çok hızlı '
      'yükselmiş, düzeltme gelebilir → Sat sinyali), 30 altı "aşırı satım" '
      '(fiyat çok hızlı düşmüş, tepki yükselişi gelebilir → Al sinyali) '
      'olarak yorumlanır.',
  'STOCH(9,6) %K': 'Stokastik Osilatör (9,6) — %K: Son 9 günün en '
      'yüksek/en düşük aralığında güncel kapanışın nerede durduğunu 0-100 '
      'arasında ölçer. 80 üzeri aşırı alım (Sat), 20 altı aşırı satım (Al) '
      'kabul edilir.',
  'STOCH(9,6) %D': 'Stokastik Osilatör (9,6) — %D: %K çizgisinin son 6 '
      'günlük ortalaması; %K\'dan daha yumuşak hareket eder. Aynı şekilde '
      '80 üzeri aşırı alım (Sat), 20 altı aşırı satım (Al) kabul edilir.',
  'STOCHRSI(14)': 'Stokastik RSI (14): RSI değerinin kendisine, son 14 '
      'günlük en düşük-en yüksek RSI aralığındaki konumunu ölçen stokastik '
      'formülü uygulanmış hali — düz RSI\'den daha hassas/hızlı hareket '
      'eder. 80 üzeri aşırı alım (Sat), 20 altı aşırı satım (Al) kabul '
      'edilir.',
  'MACD(12,26)': 'MACD — Hareketli Ortalama Yakınsama/Iraksama: 12 günlük '
      'üstel ortalama (EMA) ile 26 günlük EMA arasındaki fark olan "MACD '
      'çizgisi", bu çizginin 9 günlük EMA\'sı olan "sinyal çizgisi" ile '
      'karşılaştırılır. MACD, sinyalin üzerine çıkarsa momentum yükselişe '
      'dönüyor demektir (Al); altına inerse düşüşe dönüyor demektir (Sat).',
  'ATR(14)': 'ATR — Ortalama Gerçek Aralık (14): Son 14 günün gün-içi '
      'fiyat hareket genişliğinin (oynaklık/volatilite) ortalaması. Yön '
      'belirtmez, sadece piyasanın ne kadar sert hareket ettiğini gösterir '
      '— bu yüzden Al/Sat sayımına dahil edilmez.',
  'ADX(14)': 'ADX — Ortalama Yönsel Endeks (14): Bir trendin ne kadar '
      '"güçlü" olduğunu 0-100 arasında ölçer (yön değil, şiddet). 25 üzeri '
      'güçlü trend kabul edilir; bu durumda yükseliş yönü (+DI) düşüş '
      'yönünden (−DI) baskınsa Al, tersi Sat sinyali verir. 25 altında '
      'trend zayıf/yatay kabul edilir (Nötr).',
  'CCI(14)': 'CCI — Emtia Kanal Endeksi (14): Fiyatın kendi son 14 günlük '
      'ortalamasından (tipik fiyat üzerinden) ne kadar saptığını ölçer. '
      '+100 üzeri fiyatın belirgin biçimde ortalamanın üzerinde olduğunu ve '
      'yükseliş momentumunun güçlü olduğunu gösterir (Al); −100 altı tam '
      'tersini gösterir (Sat).',
  'Highs/Lows(14)': 'Highs/Lows (14): Son 14 günde günlük en yüksek ve en '
      'düşük fiyatların bir önceki güne göre nasıl değiştiğinin ortalaması. '
      'Pozitifse tepe ve dip noktaları yükseliyor demektir (yükseliş '
      'trendi, Al); negatifse düşüyor demektir (düşüş trendi, Sat).',
  'UO': 'UO — Ultimate (Nihai) Osilatör: Kısa (7 gün), orta (14 gün) ve '
      'uzun (28 gün) vadeli alım baskısı oranlarını ağırlıklı biçimde '
      'birleştiren bir momentum göstergesi (0-100). 70 üzeri aşırı alım '
      '(Sat), 30 altı aşırı satım (Al) olarak yorumlanır.',
  'ROC(12)': 'ROC — Değişim Oranı (12): Fiyatın 12 gün önceki değerine '
      'göre yüzde kaç değiştiğini gösterir. Pozitifse fiyat 12 gün öncesine '
      'göre yükselmiş demektir (Al); negatifse düşmüş demektir (Sat).',
  'Williams %R(14)': 'Williams %R (14): Son 14 günün en yüksek fiyatına '
      'göre güncel kapanışın ne kadar geride olduğunu −100 ile 0 arasında '
      'ölçer (Stokastik\'in tersten hesaplanmış hali gibidir). −80 altı '
      'aşırı satım (Al), −20 üzeri aşırı alım (Sat) kabul edilir.',
  'Bull/Bear Power(13)': 'Bull/Bear Power (13, Elder): Günün en yüksek ve '
      'en düşük fiyatlarının, 13 günlük üstel ortalamaya (EMA) olan '
      'uzaklığını ölçer — alıcıların (Bull) ve satıcıların (Bear) fiyatı '
      'ortalamadan ne kadar uzağa itebildiğini gösterir. Net değer '
      '(Bull+Bear) pozitifse alıcılar baskın demektir (Al); negatifse '
      'satıcılar baskın demektir (Sat).',
};

String _maInfo(int period) =>
    'Hareketli Ortalama (MA$period): Son $period günün kapanış '
    'fiyatlarının ortalaması — günlük fiyat gürültüsünü yumuşatıp genel '
    'trendi gösterir. Basit (SMA) her güne eşit ağırlık verir; Üstel (EMA) '
    'son günlere daha fazla ağırlık vererek fiyat değişimlerine daha hızlı '
    'tepki verir. Genel kural: kapanış fiyatı ortalamanın üzerindeyse Al '
    '(yükseliş trendi), altındaysa Sat (düşüş trendi) sinyali kabul edilir.';

void _showInfoDialog(BuildContext context, String title, String body) {
  showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: AppColors.slate900,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: AppColors.slate800.withValues(alpha: 0.8)),
      ),
      title: Text(title,
          style: const TextStyle(color: AppColors.slate100, fontWeight: FontWeight.w700)),
      content: Text(body,
          style: const TextStyle(color: AppColors.slate100, height: 1.4)),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Kapat'),
        ),
      ],
    ),
  );
}

/// Bir gösterge/pivot/hareketli-ortalama etiketinin yanında gösterilen ⓘ
/// simgesi; tıklanınca formülü ve genel anlamını açıklayan bir diyalog açar.
class _InfoIcon extends StatelessWidget {
  final String title;
  final String body;
  const _InfoIcon({required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.info_outline, size: 15, color: AppColors.slate400),
      onPressed: () => _showInfoDialog(context, title, body),
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 22, minHeight: 22),
      visualDensity: VisualDensity.compact,
      splashRadius: 14,
      tooltip: 'Ne anlama geliyor?',
    );
  }
}

class _SymbolChip extends StatelessWidget {
  final String symbol;
  final bool selected;
  final VoidCallback onSelect;
  final VoidCallback onRemove;

  const _SymbolChip({
    required this.symbol,
    required this.selected,
    required this.onSelect,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onSelect,
      child: Container(
        padding: const EdgeInsets.only(left: 12, right: 4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: selected
              ? AppColors.cyan500.withValues(alpha: 0.2)
              : AppColors.slate900.withValues(alpha: 0.6),
          border: Border.all(
            color: selected
                ? AppColors.cyan500.withValues(alpha: 0.6)
                : AppColors.slate800.withValues(alpha: 0.8),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(symbol, style: const TextStyle(color: AppColors.slate100)),
            IconButton(
              icon: const Icon(Icons.close, size: 16, color: AppColors.slate400),
              onPressed: onRemove,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              visualDensity: VisualDensity.compact,
              tooltip: 'Listeden çıkar',
            ),
          ],
        ),
      ),
    );
  }
}

Color _signalColor(Signal? signal) => switch (signal) {
      Signal.buy => AppColors.emerald400,
      Signal.sell => AppColors.rose500,
      Signal.neutral || null => AppColors.slate400,
    };

Color _summaryColor(SummarySignal signal) => switch (signal) {
      SummarySignal.strongBuy || SummarySignal.buy => AppColors.emerald400,
      SummarySignal.strongSell || SummarySignal.sell => AppColors.rose500,
      SummarySignal.neutral => AppColors.slate400,
    };

IndicatorRow? _findIndicator(List<IndicatorRow> list, String name) {
  for (final row in list) {
    if (row.name == name) return row;
  }
  return null;
}

/// Tüm pivot/MA/gösterge hesaplarını tek bir doğal dil paragrafında
/// sentezleyen kural-tabanlı "insansı" yorum — bir yapay zekaya bağlanmıyor,
/// bu ekranda zaten hesaplanmış olan sinyallerden üretiliyor. Yatırım
/// tavsiyesi değildir; her zaman bu uyarıyla biter.
String _generateCommentary(TechnicalAnalysisResult r) {
  final score = r.summary.score;
  final sb = StringBuffer();

  if (score >= 90) {
    sb.write('${r.symbol} için teknik tablo oldukça güçlü görünüyor: '
        'hesapladığımız hareketli ortalamaların ve göstergelerin büyük '
        'çoğunluğu alım yönünde sinyal veriyor. ');
  } else if (score >= 70) {
    sb.write('${r.symbol} teknik olarak pozitif bir görünüm sergiliyor; '
        'göstergelerin çoğu yükseliş yönünde hizalanmış durumda. ');
  } else if (score >= 58) {
    sb.write('${r.symbol} için tablo hafif pozitife eğimli: alım sinyali '
        'veren göstergeler satım verenlere göre biraz daha ağır basıyor. ');
  } else if (score > 42) {
    sb.write('${r.symbol} şu an net bir yön vermiyor; alım ve satım '
        'sinyalleri büyük ölçüde birbirini dengeliyor, kararsız/yatay bir '
        'görünüm hakim. ');
  } else if (score >= 30) {
    sb.write('${r.symbol} için tablo hafif negatife eğimli: satım sinyali '
        'veren göstergeler alım verenlere göre biraz daha ağır basıyor. ');
  } else if (score >= 18) {
    sb.write('${r.symbol} teknik olarak zayıf bir görünüm sergiliyor; '
        'göstergelerin çoğu düşüş yönünde hizalanmış durumda. ');
  } else {
    sb.write('${r.symbol} için teknik tablo oldukça zayıf: hesapladığımız '
        'hareketli ortalamaların ve göstergelerin büyük çoğunluğu satış '
        'yönünde. ');
  }

  final shortTerm =
      r.movingAverages.where((m) => m.period <= 20 && m.smaSignal != null).toList();
  final longTerm =
      r.movingAverages.where((m) => m.period >= 50 && m.smaSignal != null).toList();
  if (shortTerm.isNotEmpty && longTerm.isNotEmpty) {
    final shortBullish =
        shortTerm.where((m) => m.smaSignal == Signal.buy).length > shortTerm.length / 2;
    final longBullish =
        longTerm.where((m) => m.smaSignal == Signal.buy).length > longTerm.length / 2;
    if (shortBullish && !longBullish) {
      sb.write('Kısa vadeli ortalamalar (MA5-MA20) toparlanma işareti '
          'verirken uzun vadeli ortalamalar hâlâ zayıf — bu, olası bir '
          'dip/tepki hareketine işaret edebilir. ');
    } else if (!shortBullish && longBullish) {
      sb.write('Kısa vadeli ortalamalar (MA5-MA20) zayıflık gösterirken '
          'uzun vadeli ortalamalar (MA50 ve üzeri) hâlâ ana trendi yukarı '
          'yönlü destekliyor — bu görünüm, ana yükseliş trendi içinde kısa '
          'vadeli bir soluklanma/düzeltme olabileceğini düşündürüyor. ');
    } else if (shortBullish && longBullish) {
      sb.write('Kısa ve uzun vadeli hareketli ortalamaların neredeyse '
          'tamamı aynı yönde (yukarı) hizalanmış, bu da trendin tutarlı '
          'olduğuna işaret ediyor. ');
    } else {
      sb.write('Kısa ve uzun vadeli hareketli ortalamaların neredeyse '
          'tamamı aynı yönde (aşağı) hizalanmış, bu da düşüş trendinin '
          'tutarlı olduğuna işaret ediyor. ');
    }
  }

  final rsi = _findIndicator(r.indicators, 'RSI(14)');
  if (rsi != null) {
    if (rsi.signal == Signal.buy) {
      sb.write('RSI ${rsi.value.toStringAsFixed(0)} ile aşırı satım '
          'bölgesine yakın seyrediyor; bu tür seviyeler tarihsel olarak '
          'tepki alımlarının geldiği bölgeler olabiliyor. ');
    } else if (rsi.signal == Signal.sell) {
      sb.write('RSI ${rsi.value.toStringAsFixed(0)} ile aşırı alım '
          'bölgesine yaklaşmış durumda; kısa vadede bir kâr satışı/düzeltme '
          'riski artabilir. ');
    } else {
      sb.write('RSI ${rsi.value.toStringAsFixed(0)} ile nötr bölgede, ne '
          'aşırı alım ne aşırı satım sinyali vermiyor. ');
    }
  }

  final macd = _findIndicator(r.indicators, 'MACD(12,26)');
  if (macd != null) {
    sb.write(macd.signal == Signal.buy
        ? 'MACD, sinyal çizgisinin üzerinde seyrederek momentumun yukarı '
            'yönlü olduğunu destekliyor. '
        : 'MACD, sinyal çizgisinin altında seyrederek momentumun '
            'zayıflamaya başladığına işaret ediyor. ');
  }

  final adx = _findIndicator(r.indicators, 'ADX(14)');
  if (adx != null) {
    sb.write(adx.value > 25
        ? 'ADX ${adx.value.toStringAsFixed(0)} ile 25 eşiğinin üzerinde '
            'olduğundan mevcut trend güçlü/belirgin kabul edilebilir. '
        : 'ADX ${adx.value.toStringAsFixed(0)} ile 25 eşiğinin altında '
            'olduğundan piyasa şu an net bir trendden çok yatay/kararsız '
            'bir seyir izliyor olabilir. ');
  }

  sb.write('\n\nGenel puanımız 100 üzerinden $score. ');
  if (score >= 70) {
    sb.write('Bu seviye, mevcut göstergelerin çoğunluğunun yukarı yönü '
        'desteklediği anlamına geliyor.');
  } else if (score <= 30) {
    sb.write('Bu seviye, mevcut göstergelerin çoğunluğunun aşağı yönü '
        'desteklediği anlamına geliyor.');
  } else {
    sb.write('Bu seviye, göstergeler arasında net bir üstünlük olmadığını, '
        'fiyatın yön arayışında olabileceğini gösteriyor.');
  }

  sb.write('\n\nBu yorum, yukarıdaki teknik göstergelerin otomatik bir '
      'sentezidir; bir yatırım tavsiyesi değildir.');

  return sb.toString();
}

void _showCommentaryDialog(BuildContext context, TechnicalAnalysisResult result) {
  final score = result.summary.score;
  showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: AppColors.slate900,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: AppColors.slate800.withValues(alpha: 0.8)),
      ),
      title: Row(
        children: [
          Expanded(
            child: Text('${result.symbol} · Yorum',
                style: const TextStyle(
                    color: AppColors.slate100, fontWeight: FontWeight.w700)),
          ),
          Text('$score/100',
              style: GoogleFonts.robotoMono(
                  color: scoreColor(score), fontWeight: FontWeight.w800)),
        ],
      ),
      content: SingleChildScrollView(
        child: Text(_generateCommentary(result),
            style: const TextStyle(color: AppColors.slate100, height: 1.5)),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Kapat'),
        ),
      ],
    ),
  );
}

/// "Yorum (X/100)" butonu — Genel Özet kartında Nötr/Al/Sat rozetinin hemen
/// solunda gösterilir. X, [scoreColor]'a göre renklenir; uç noktalarda
/// (çok düşük/çok yüksek puan) hafif bir "glow" gölgesiyle vurgulanır.
class _CommentButton extends StatelessWidget {
  final TechnicalAnalysisResult result;
  const _CommentButton({required this.result});

  @override
  Widget build(BuildContext context) {
    final score = result.summary.score;
    final color = scoreColor(score);
    final glow = scoreGlows(score);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => _showCommentaryDialog(context, result),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: AppColors.slate900.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: color.withValues(alpha: 0.6)),
            boxShadow:
                glow ? [BoxShadow(color: color.withValues(alpha: 0.6), blurRadius: 14)] : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.chat_bubble_outline, size: 13, color: AppColors.slate400),
              const SizedBox(width: 5),
              const Text('Yorum ',
                  style: TextStyle(
                      color: AppColors.slate100, fontSize: 12, fontWeight: FontWeight.w600)),
              Text('($score/100)',
                  style: GoogleFonts.robotoMono(
                      color: color, fontSize: 12, fontWeight: FontWeight.w800)),
            ],
          ),
        ),
      ),
    );
  }
}

class _SignalBadge extends StatelessWidget {
  final String label;
  final Color color;
  const _SignalBadge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _TechnicalResultView extends StatelessWidget {
  final TechnicalAnalysisResult result;
  final DateFormat dateFormat;

  const _TechnicalResultView({required this.result, required this.dateFormat});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GlassCard(
          glow: true,
          glowBullish: result.summary.overall == SummarySignal.strongBuy ||
              result.summary.overall == SummarySignal.buy,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${result.symbol} · Genel Özet',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  _CommentButton(result: result),
                  const SizedBox(width: 8),
                  _SignalBadge(
                    label: result.summary.overall.label,
                    color: _summaryColor(result.summary.overall),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Son kapanış: ${formatPrice(result.lastClose)} ${result.currency} '
                '· ${dateFormat.format(result.asOf.toLocal())}',
                style: GoogleFonts.robotoMono(
                    fontSize: 12, color: AppColors.slate400),
              ),
              const SizedBox(height: 4),
              Text(
                'Bu özet, standart teknik analiz formülleriyle bu uygulama '
                'içinde hesaplanır; yatırım tavsiyesi değildir.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
        if (result.pivotPoints != null) ...[
          const SizedBox(height: 16),
          GlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Pivot Noktaları', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 12),
                _PivotRow(label: 'R3', value: result.pivotPoints!.r3),
                _PivotRow(label: 'R2', value: result.pivotPoints!.r2),
                _PivotRow(label: 'R1', value: result.pivotPoints!.r1),
                _PivotRow(label: 'Pivot', value: result.pivotPoints!.pivot, emphasize: true),
                _PivotRow(label: 'S1', value: result.pivotPoints!.s1),
                _PivotRow(label: 'S2', value: result.pivotPoints!.s2),
                _PivotRow(label: 'S3', value: result.pivotPoints!.s3),
              ],
            ),
          ),
        ],
        const SizedBox(height: 16),
        GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text('Hareketli Ortalamalar',
                        style: Theme.of(context).textTheme.titleMedium),
                  ),
                  _SignalBadge(
                    label: result.summary.movingAverages.label,
                    color: _summaryColor(result.summary.movingAverages),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columns: [
                    DataColumn(label: Text('PERİYOT', style: Theme.of(context).textTheme.labelSmall)),
                    DataColumn(label: Text('BASİT (SMA)', style: Theme.of(context).textTheme.labelSmall)),
                    DataColumn(label: Text('ÜSTEL (EMA)', style: Theme.of(context).textTheme.labelSmall)),
                  ],
                  rows: [
                    for (final row in result.movingAverages)
                      DataRow(cells: [
                        DataCell(Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('MA${row.period}',
                                style: const TextStyle(color: AppColors.slate100)),
                            _InfoIcon(
                                title: 'MA${row.period}', body: _maInfo(row.period)),
                          ],
                        )),
                        DataCell(_MaCell(value: row.sma, signal: row.smaSignal)),
                        DataCell(_MaCell(value: row.ema, signal: row.emaSignal)),
                      ]),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text('Teknik İndikatörler',
                        style: Theme.of(context).textTheme.titleMedium),
                  ),
                  _SignalBadge(
                    label: result.summary.indicators.label,
                    color: _summaryColor(result.summary.indicators),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              for (final row in result.indicators)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(
                              child: Text(row.name,
                                  style: const TextStyle(color: AppColors.slate100)),
                            ),
                            _InfoIcon(
                                title: row.name, body: _indicatorInfo[row.name] ?? ''),
                          ],
                        ),
                      ),
                      Expanded(
                        flex: 2,
                        child: Text(
                          row.value.toStringAsFixed(row.value.abs() < 10 ? 4 : 2),
                          style: GoogleFonts.robotoMono(
                              fontSize: 13, color: AppColors.slate100),
                        ),
                      ),
                      _SignalBadge(label: row.signal.label, color: _signalColor(row.signal)),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PivotRow extends StatelessWidget {
  final String label;
  final double value;
  final bool emphasize;

  const _PivotRow({required this.label, required this.value, this.emphasize = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: 56,
            child: Text(
              label,
              style: TextStyle(
                color: emphasize ? AppColors.cyan500 : AppColors.slate400,
                fontWeight: emphasize ? FontWeight.w700 : FontWeight.w500,
                fontSize: 12,
              ),
            ),
          ),
          _InfoIcon(title: label, body: _indicatorInfo[label] ?? ''),
          const SizedBox(width: 4),
          Text(
            formatPrice(value),
            style: GoogleFonts.robotoMono(
              color: emphasize ? AppColors.slate100 : AppColors.slate100.withValues(alpha: 0.85),
              fontWeight: emphasize ? FontWeight.w700 : FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _MaCell extends StatelessWidget {
  final double? value;
  final Signal? signal;

  const _MaCell({required this.value, required this.signal});

  @override
  Widget build(BuildContext context) {
    if (value == null) {
      return const Text('—', style: TextStyle(color: AppColors.slate400));
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(formatPrice(value!),
            style: GoogleFonts.robotoMono(fontSize: 13, color: AppColors.slate100)),
        const SizedBox(width: 8),
        _SignalBadge(label: signal!.label, color: _signalColor(signal)),
      ],
    );
  }
}
