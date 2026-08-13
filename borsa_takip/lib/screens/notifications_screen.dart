import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../models/notification_item.dart';
import '../models/symbol.dart';
import '../services/market_api.dart';
import '../theme/app_colors.dart';
import '../utils/score_color.dart';
import '../widgets/glass_card.dart';
import '../widgets/score_ranking_section.dart';
import '../widgets/symbol_search_field.dart';

class NotificationsScreen extends StatefulWidget {
  final ValueChanged<MarketSymbol>? onOpenChart;
  final List<String> favorites;
  final ValueChanged<String>? onToggleFavorite;

  const NotificationsScreen({
    super.key,
    this.onOpenChart,
    this.favorites = const [],
    this.onToggleFavorite,
  });

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen>
    with TickerProviderStateMixin {
  final _api = MarketApi();

  List<String> _watchlist = [];
  NotificationPage? _notificationPage;
  int _page = 1;

  // Bildirim kartlarında gösterilen Teknik puan (X/100) rozeti için —
  // sadece o an sayfada görünen bildirimlerin sembollerine göre doldurulur,
  // bkz. _loadScoresForCurrentPage.
  Map<String, int> _scores = {};

  bool _loadingWatchlist = true;
  bool _loadingNotifications = true;
  bool _checking = false;
  String? _bulkAddingPreset;
  String? _error;

  // Uzun izleme listelerinde (ör. 300+ kripto) kategori sekmesi + sembol
  // rozetleri sayfayı kalabalıklaştırıyor; kullanıcı bu bölümü katlayıp
  // sadece toplam sayıyı görebilsin diye açık/kapalı durumu — sembol
  // sayısı bilgisi (`X sembol izleniyor`) her zaman görünür kalır, sadece
  // kategori sekmesi + rozet listesi gizlenir/gösterilir.
  bool _watchlistSymbolsVisible = true;

  late final TabController _categoryTabController;
  int _lastCategoryIndex = 0;

  // İzleme Listesi (mevcut yönetim UI'ı) ile Puan Sıralaması (bkz.
  // ScoreRankingSection) arasında geçiş; Bildirimler akışı bundan bağımsız,
  // her zaman görünür kalır.
  late final TabController _sectionTabController;
  int _lastSectionIndex = 0;

  // BIST sembolleri ".IS", kripto sembolleri "-USD" ile bitiyor (bkz.
  // preset_lists.dart / coingecko_client.dart); geri kalan her şey ABD/diğer
  // sekmesinde toplanıyor. Sıra proxy_server'daki NotificationStore
  // kategori anahtarlarıyla (bist/us/crypto) eşleşiyor.
  static const _categoryKeys = ['bist', 'us', 'crypto'];

  List<String> get _bistSymbols =>
      _watchlist.where((s) => s.endsWith('.IS')).toList();
  List<String> get _cryptoSymbols =>
      _watchlist.where((s) => s.endsWith('-USD')).toList();
  List<String> get _usSymbols => _watchlist
      .where((s) => !s.endsWith('.IS') && !s.endsWith('-USD'))
      .toList();

  List<String> get _currentCategorySymbols {
    switch (_categoryTabController.index) {
      case 0:
        return _bistSymbols;
      case 1:
        return _usSymbols;
      default:
        return _cryptoSymbols;
    }
  }

  String get _currentCategoryKey => _categoryKeys[_categoryTabController.index];

  @override
  void initState() {
    super.initState();
    _categoryTabController = TabController(length: 3, vsync: this)
      ..addListener(_onCategoryTabChanged);
    _sectionTabController = TabController(length: 2, vsync: this)
      ..addListener(_onSectionTabChanged);
    _loadWatchlist();
    _loadNotifications();
  }

  void _onCategoryTabChanged() {
    if (_categoryTabController.indexIsChanging) return;
    if (_categoryTabController.index == _lastCategoryIndex) return;
    _lastCategoryIndex = _categoryTabController.index;
    setState(() {});
    _loadNotifications(page: 1);
  }

  void _onSectionTabChanged() {
    if (_sectionTabController.indexIsChanging) return;
    if (_sectionTabController.index == _lastSectionIndex) return;
    _lastSectionIndex = _sectionTabController.index;
    setState(() {});
  }

  @override
  void dispose() {
    _categoryTabController.dispose();
    _sectionTabController.dispose();
    super.dispose();
  }

  Future<void> _loadWatchlist() async {
    setState(() => _loadingWatchlist = true);
    try {
      final list = await _api.getWatchlist();
      if (!mounted) return;
      setState(() {
        _watchlist = list;
        _loadingWatchlist = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loadingWatchlist = false;
      });
    }
  }

  Future<void> _loadNotifications({int? page}) async {
    setState(() => _loadingNotifications = true);
    try {
      final result = await _api.getNotifications(
        page: page ?? _page,
        category: _currentCategoryKey,
      );
      if (!mounted) return;
      setState(() {
        _notificationPage = result;
        _page = result.page;
        _loadingNotifications = false;
      });
      _loadScoresForCurrentPage();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loadingNotifications = false;
      });
    }
  }

  // En iyi çaba (best-effort): puan önbelleği henüz doldurulmamışsa ya da
  // istek başarısız olursa rozetler sessizce gösterilmez — bu, bildirim
  // akışının kendisini kırmamalı, bu yüzden _error'a yazmıyor.
  Future<void> _loadScoresForCurrentPage() async {
    final symbols =
        (_notificationPage?.notifications ?? const <NotificationItem>[])
            .map((n) => n.symbol)
            .toSet();
    if (symbols.isEmpty) return;
    try {
      final result = await _api.getTechnicalScoresFor(symbols);
      if (!mounted) return;
      setState(() {
        _scores = {for (final s in result.items) s.symbol: s.score};
      });
    } catch (_) {
      // Rozet olmadan devam et.
    }
  }

  Future<void> _addSymbol(MarketSymbol symbol) async {
    try {
      final result = await _api.addToWatchlist(symbol.symbol);
      if (!mounted) return;
      if (result.added && !_watchlist.contains(result.symbol)) {
        setState(() => _watchlist = [..._watchlist, result.symbol]..sort());
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    }
  }

  Future<void> _removeSymbol(String symbol) async {
    try {
      final result = await _api.removeFromWatchlist(symbol);
      if (!mounted) return;
      if (result.removed) {
        setState(() =>
            _watchlist = _watchlist.where((s) => s != result.symbol).toList());
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    }
  }

  Future<void> _bulkAdd(String preset, String label) async {
    setState(() => _bulkAddingPreset = preset);
    try {
      // Backend bulk-add yanıtında güncel tam listeyi de döndürüyor; ayrı bir
      // _loadWatchlist() çağrısıyla aynı veriyi ikinci kez sormaya gerek yok.
      final result = await _api.bulkAddToWatchlist(preset);
      if (!mounted) return;
      setState(() => _watchlist = result.symbols);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$label: ${result.added} yeni sembol eklendi.')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _bulkAddingPreset = null);
    }
  }

  Future<void> _checkNow() async {
    setState(() => _checking = true);
    try {
      await _api.checkNow();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Kontrol arka planda başlatıldı. İzleme listesi büyükse birkaç '
            'dakika sürebilir, bildirimleri daha sonra yenileyin.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_error != null)
            Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.rose500.withValues(alpha: 0.15),
                border: Border.all(color: AppColors.rose500.withValues(alpha: 0.4)),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(_error!, style: const TextStyle(color: AppColors.slate100)),
            ),
          DecoratedBox(
            decoration: BoxDecoration(
              border: Border.all(color: AppColors.slate800.withValues(alpha: 0.8)),
              borderRadius: BorderRadius.circular(8),
            ),
            child: TabBar(
              controller: _sectionTabController,
              tabs: const [
                Tab(text: 'İzleme Listesi'),
                Tab(text: 'Puan Sıralaması'),
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (_sectionTabController.index == 1)
            const ScoreRankingSection()
          else ...[
            Text(
              'Aylık en düşük değerine ulaştığında bildirim almak istediğiniz '
              'sembolleri buraya ekleyin (herhangi bir hisse, kripto veya '
              'Amerikan borsası sembolü olabilir).',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            SymbolSearchField(api: _api, onSelect: _addSymbol),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _PresetButton(
                  label: 'BIST 200 Ekle',
                  loading: _bulkAddingPreset == 'bist200',
                  onPressed: () => _bulkAdd('bist200', 'BIST 200'),
                ),
                _PresetButton(
                  label: 'ABD Popüler 200 Ekle',
                  loading: _bulkAddingPreset == 'us200',
                  onPressed: () => _bulkAdd('us200', 'ABD Popüler 200'),
                ),
                _PresetButton(
                  label: 'Kripto İlk 300 Ekle',
                  loading: _bulkAddingPreset == 'crypto300',
                  onPressed: () => _bulkAdd('crypto300', 'Kripto İlk 300'),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'BIST 200 ve ABD Popüler 200 listeleri düzenli aralıklarla '
              'güncellenen sabit/küratörlü listelerdir (Yahoo\'nun canlı "en '
              'çok işlem gören" verisi kimlik doğrulaması gerektirdiğinden '
              'kullanılamıyor); Kripto İlk 300 ise CoinGecko\'dan piyasa '
              'değerine göre canlı çekilir.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            if (_loadingWatchlist)
              const Center(child: CircularProgressIndicator())
            else ...[
              Row(
                children: [
                  Text('${_watchlist.length} sembol izleniyor',
                      style: Theme.of(context).textTheme.bodySmall),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: () => setState(
                        () => _watchlistSymbolsVisible = !_watchlistSymbolsVisible),
                    icon: Icon(
                      _watchlistSymbolsVisible
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                      size: 18,
                    ),
                    label: Text(_watchlistSymbolsVisible ? 'Gizle' : 'Göster'),
                  ),
                ],
              ),
              if (_watchlistSymbolsVisible) ...[
                const SizedBox(height: 8),
                DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border.all(color: AppColors.slate800.withValues(alpha: 0.8)),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: TabBar(
                    controller: _categoryTabController,
                    tabs: [
                      Tab(text: 'BIST (${_bistSymbols.length})'),
                      Tab(text: 'ABD (${_usSymbols.length})'),
                      Tab(text: 'Kripto (${_cryptoSymbols.length})'),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final s in _currentCategorySymbols)
                      _WatchlistSymbolChip(
                        symbol: s,
                        isFavorite: widget.favorites.contains(s),
                        onToggleFavorite: widget.onToggleFavorite == null
                            ? null
                            : () => widget.onToggleFavorite!(s),
                        onRemove: () => _removeSymbol(s),
                      ),
                  ],
                ),
              ],
            ],
          ],
          const SizedBox(height: 24),
          Row(
            children: [
              Text(
                'Bildirimler · ${const ['BIST', 'ABD', 'Kripto'][_categoryTabController.index]}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const Spacer(),
              OutlinedButton.icon(
                onPressed: _checking ? null : _checkNow,
                icon: _checking
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh),
                label: const Text('Şimdi Kontrol Et'),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Sistem izleme listesindeki sembolleri günde bir kez otomatik '
            'kontrol eder (proxy sunucusu açık kaldığı sürece). Hemen '
            'kontrol etmek için yukarıdaki butonu kullanabilirsiniz.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          IconButton(
            onPressed: () => _loadNotifications(page: 1),
            icon: const Icon(Icons.sync),
            tooltip: 'Bildirim listesini yenile',
          ),
          if (_loadingNotifications)
            const Center(child: CircularProgressIndicator())
          else if (_notificationPage == null || _notificationPage!.notifications.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Henüz bildirim yok.'),
            )
          else ...[
            for (final n in _notificationPage!.notifications)
              _NotificationTile(
                item: n,
                score: _scores[n.symbol],
                onTap: widget.onOpenChart == null
                    ? null
                    : () => widget.onOpenChart!(
                          MarketSymbol(symbol: n.symbol, name: n.symbol),
                        ),
                isFavorite: widget.favorites.contains(n.symbol.toUpperCase()),
                onToggleFavorite: widget.onToggleFavorite == null
                    ? null
                    : () => widget.onToggleFavorite!(n.symbol),
              ),
            const SizedBox(height: 12),
            _Pagination(
              page: _notificationPage!.page,
              totalPages: _notificationPage!.totalPages,
              total: _notificationPage!.total,
              onPageChanged: (p) => _loadNotifications(page: p),
            ),
          ],
        ],
      ),
    );
  }
}

class _PresetButton extends StatelessWidget {
  final String label;
  final bool loading;
  final VoidCallback onPressed;

  const _PresetButton({
    required this.label,
    required this.loading,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: loading ? null : onPressed,
      icon: loading
          ? const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.playlist_add, size: 18),
      label: Text(label),
    );
  }
}

class _WatchlistSymbolChip extends StatelessWidget {
  final String symbol;
  final bool isFavorite;
  final VoidCallback? onToggleFavorite;
  final VoidCallback onRemove;

  const _WatchlistSymbolChip({
    required this.symbol,
    required this.isFavorite,
    required this.onToggleFavorite,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.only(left: 12, right: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: AppColors.slate900.withValues(alpha: 0.6),
        border: Border.all(color: AppColors.slate800.withValues(alpha: 0.8)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(symbol, style: const TextStyle(color: AppColors.slate100)),
          IconButton(
            icon: Icon(
              isFavorite ? Icons.star : Icons.star_border,
              size: 18,
              color: isFavorite ? Colors.amber : Colors.grey,
            ),
            onPressed: onToggleFavorite,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            visualDensity: VisualDensity.compact,
            tooltip: isFavorite ? 'Favorilerden çıkar' : 'Favorilere ekle',
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 16),
            onPressed: onRemove,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            visualDensity: VisualDensity.compact,
            tooltip: 'İzleme listesinden çıkar',
          ),
        ],
      ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  final NotificationItem item;
  final int? score;
  final VoidCallback? onTap;
  final bool isFavorite;
  final VoidCallback? onToggleFavorite;

  const _NotificationTile({
    required this.item,
    this.score,
    this.onTap,
    this.isFavorite = false,
    this.onToggleFavorite,
  });

  // Bildirim türünü ayırt eden bir sütun eklemek yerine (ayrı bir Supabase
  // şema değişikliği gerektirirdi) mesaj metnindeki sabit önek üzerinden
  // ayırt ediliyor — bkz. proxy_server/lib/technical_score_cache.dart'taki
  // mesaj şablonu.
  bool get _isScoreChange => item.message.contains('teknik puan kademesi değişti');

  static final _dateFormat = DateFormat('dd.MM.yyyy');
  static final _dateTimeFormat = DateFormat('dd.MM.yyyy HH:mm');

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GlassCard(
        padding: EdgeInsets.zero,
        child: ListTile(
          leading: Icon(
            _isScoreChange ? Icons.query_stats : Icons.trending_down,
            color: _isScoreChange ? AppColors.cyan500 : AppColors.rose500,
          ),
          title: Text(item.message, style: const TextStyle(color: AppColors.slate100)),
          subtitle: Text(
            '${_dateFormat.format(item.date.toLocal())} · '
            '${_dateTimeFormat.format(item.createdAt.toLocal())}',
            style: const TextStyle(color: AppColors.slate400),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (score != null && !_isScoreChange) _ScoreBadge(score: score!),
              IconButton(
                icon: Icon(
                  isFavorite ? Icons.star : Icons.star_border,
                  color: isFavorite ? Colors.amber : AppColors.slate400,
                ),
                onPressed: onToggleFavorite,
                tooltip: isFavorite ? 'Favorilerden çıkar' : 'Favorilere ekle',
              ),
              if (onTap != null)
                const Icon(Icons.chevron_right, color: AppColors.slate400),
            ],
          ),
          onTap: onTap,
        ),
      ),
    );
  }
}

/// Bildirim kartında sembolün Teknik sekmesindeki alım puanı (0-100),
/// `score_ranking_section.dart`'taki `_ScoredSymbolTile` rozetiyle aynı
/// renk dili (`scoreColor()`) ama trailing satırına sığacak kompakt boyutta
/// — kademe adı burada tekrar yazılmıyor, renk zaten kademeyi taşıyor.
class _ScoreBadge extends StatelessWidget {
  final int score;
  const _ScoreBadge({required this.score});

  @override
  Widget build(BuildContext context) {
    final color = scoreColor(score);
    final glow = scoreGlows(score);
    return Container(
      margin: const EdgeInsets.only(right: 4),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.slate900.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.6)),
        boxShadow: glow
            ? [BoxShadow(color: color.withValues(alpha: 0.6), blurRadius: 10)]
            : null,
      ),
      child: Text(
        '$score/100',
        style: GoogleFonts.robotoMono(
            color: color, fontWeight: FontWeight.w800, fontSize: 12),
      ),
    );
  }
}

class _Pagination extends StatelessWidget {
  final int page;
  final int totalPages;
  final int total;
  final ValueChanged<int> onPageChanged;

  const _Pagination({
    required this.page,
    required this.totalPages,
    required this.total,
    required this.onPageChanged,
  });

  @override
  Widget build(BuildContext context) {
    if (totalPages <= 1) return const SizedBox.shrink();
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          onPressed: page > 1 ? () => onPageChanged(page - 1) : null,
          icon: const Icon(Icons.chevron_left),
        ),
        Text('Sayfa $page / $totalPages · Toplam $total bildirim'),
        IconButton(
          onPressed: page < totalPages ? () => onPageChanged(page + 1) : null,
          icon: const Icon(Icons.chevron_right),
        ),
      ],
    );
  }
}
