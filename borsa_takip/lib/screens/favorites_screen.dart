import 'package:flutter/material.dart';

import '../models/symbol.dart';
import '../services/market_api.dart';
import '../widgets/symbol_search_field.dart';

class FavoritesScreen extends StatefulWidget {
  final List<String> favorites;
  final ValueChanged<String> onToggleFavorite;
  final ValueChanged<MarketSymbol> onTrack;

  const FavoritesScreen({
    super.key,
    required this.favorites,
    required this.onToggleFavorite,
    required this.onTrack,
  });

  @override
  State<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends State<FavoritesScreen> {
  final _api = MarketApi();

  void _addFromSearch(MarketSymbol s) {
    final normalized = s.symbol.trim().toUpperCase();
    if (widget.favorites.contains(normalized)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bu sembol zaten favorilerde.')),
      );
      return;
    }
    widget.onToggleFavorite(s.symbol);
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Favoriler', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            'Aşağıdan arayıp herhangi bir sembolü favorilere ekleyebilirsin. '
            'Bir favorinin yanındaki takip ikonuna basınca Takip sekmesinde '
            'o sembolü canlı izlemeye başlarsın.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          SymbolSearchField(api: _api, onSelect: _addFromSearch),
          const SizedBox(height: 16),
          Text('${widget.favorites.length} favori sembol',
              style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 8),
          if (widget.favorites.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Text(
                  'Henüz favori sembol yok. Yukarıdan arayıp ekleyebilirsin.'),
            )
          else
            for (final s in widget.favorites)
              Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: IconButton(
                    icon: const Icon(Icons.star, color: Colors.amber),
                    onPressed: () => widget.onToggleFavorite(s),
                    tooltip: 'Favorilerden çıkar',
                  ),
                  title: Text(s),
                  trailing: IconButton(
                    icon: const Icon(Icons.query_stats),
                    onPressed: () =>
                        widget.onTrack(MarketSymbol(symbol: s, name: s)),
                    tooltip: 'Takip sekmesinde izle',
                  ),
                ),
              ),
        ],
      ),
    );
  }
}
