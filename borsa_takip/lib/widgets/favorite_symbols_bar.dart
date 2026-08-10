import 'package:flutter/material.dart';

import '../models/symbol.dart';

class FavoriteSymbolsBar extends StatelessWidget {
  final List<MarketSymbol> symbols;
  final MarketSymbol? selected;
  final ValueChanged<MarketSymbol> onSelect;

  const FavoriteSymbolsBar({
    super.key,
    required this.symbols,
    required this.selected,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    if (symbols.isEmpty) {
      return Text(
        'Favori sembol yok. Favoriler sekmesinden ekleyebilirsin.',
        style: Theme.of(context).textTheme.bodySmall,
      );
    }
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final s in symbols)
          ChoiceChip(
            label: Text(s.symbol),
            selected: selected?.symbol == s.symbol,
            onSelected: (_) => onSelect(s),
          ),
      ],
    );
  }
}
