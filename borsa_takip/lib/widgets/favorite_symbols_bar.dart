import 'package:flutter/material.dart';

import '../models/symbol.dart';

const favoriteSymbols = <MarketSymbol>[
  MarketSymbol(symbol: 'THYAO.IS', name: 'Türk Hava Yolları', exchange: 'BIST'),
  MarketSymbol(symbol: 'ASELS.IS', name: 'Aselsan', exchange: 'BIST'),
  MarketSymbol(symbol: 'GARAN.IS', name: 'Garanti BBVA', exchange: 'BIST'),
  MarketSymbol(symbol: 'AKBNK.IS', name: 'Akbank', exchange: 'BIST'),
  MarketSymbol(symbol: 'BTC-USD', name: 'Bitcoin', exchange: 'Kripto'),
  MarketSymbol(symbol: 'ETH-USD', name: 'Ethereum', exchange: 'Kripto'),
  MarketSymbol(symbol: 'AAPL', name: 'Apple', exchange: 'NASDAQ'),
  MarketSymbol(symbol: 'TSLA', name: 'Tesla', exchange: 'NASDAQ'),
];

class FavoriteSymbolsBar extends StatelessWidget {
  final MarketSymbol? selected;
  final ValueChanged<MarketSymbol> onSelect;

  const FavoriteSymbolsBar({
    super.key,
    required this.selected,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final s in favoriteSymbols)
          ChoiceChip(
            label: Text('${s.symbol} · ${s.name}'),
            selected: selected?.symbol == s.symbol,
            onSelected: (_) => onSelect(s),
          ),
      ],
    );
  }
}
