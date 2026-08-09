import 'package:flutter/material.dart';

import '../models/notification_item.dart';
import '../models/symbol.dart';
import '../services/market_api.dart';
import '../widgets/symbol_search_field.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final _api = MarketApi();

  List<String> _watchlist = [];
  NotificationPage? _notificationPage;
  int _page = 1;

  bool _loadingWatchlist = true;
  bool _loadingNotifications = true;
  bool _checking = false;
  String? _bulkAddingPreset;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadWatchlist();
    _loadNotifications();
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
      final result = await _api.getNotifications(page: page ?? _page);
      if (!mounted) return;
      setState(() {
        _notificationPage = result;
        _page = result.page;
        _loadingNotifications = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loadingNotifications = false;
      });
    }
  }

  Future<void> _addSymbol(MarketSymbol symbol) async {
    try {
      final list = await _api.addToWatchlist(symbol.symbol);
      if (!mounted) return;
      setState(() => _watchlist = list);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    }
  }

  Future<void> _removeSymbol(String symbol) async {
    try {
      final list = await _api.removeFromWatchlist(symbol);
      if (!mounted) return;
      setState(() => _watchlist = list);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    }
  }

  Future<void> _bulkAdd(String preset, String label) async {
    setState(() => _bulkAddingPreset = preset);
    try {
      final added = await _api.bulkAddToWatchlist(preset);
      await _loadWatchlist();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$label: $added yeni sembol eklendi.')),
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
                color: Theme.of(context).colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(_error!),
            ),
          Text('İzleme Listesi', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
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
                label: 'BIST 100 Ekle',
                loading: _bulkAddingPreset == 'bist100',
                onPressed: () => _bulkAdd('bist100', 'BIST 100'),
              ),
              _PresetButton(
                label: 'ABD Popüler 100 Ekle',
                loading: _bulkAddingPreset == 'us100',
                onPressed: () => _bulkAdd('us100', 'ABD Popüler 100'),
              ),
              _PresetButton(
                label: 'Kripto İlk 200 Ekle',
                loading: _bulkAddingPreset == 'crypto200',
                onPressed: () => _bulkAdd('crypto200', 'Kripto İlk 200'),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'BIST 100 ve ABD Popüler 100 listeleri düzenli aralıklarla '
            'güncellenen sabit/küratörlü listelerdir (Yahoo\'nun canlı "en '
            'çok işlem gören" verisi kimlik doğrulaması gerektirdiğinden '
            'kullanılamıyor); Kripto İlk 200 ise CoinGecko\'dan piyasa '
            'değerine göre canlı çekilir.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          if (_loadingWatchlist)
            const Center(child: CircularProgressIndicator())
          else ...[
            Text('${_watchlist.length} sembol izleniyor',
                style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final s in _watchlist)
                  Chip(
                    label: Text(s),
                    onDeleted: () => _removeSymbol(s),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 24),
          Row(
            children: [
              Text('Bildirimler', style: Theme.of(context).textTheme.titleMedium),
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
            for (final n in _notificationPage!.notifications) _NotificationTile(item: n),
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

class _NotificationTile extends StatelessWidget {
  final NotificationItem item;

  const _NotificationTile({required this.item});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: const Icon(Icons.trending_down),
        title: Text(item.message),
        subtitle: Text('${item.date} · ${item.createdAt}'),
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
