class MarketSymbol {
  final String symbol;
  final String name;
  final String exchange;

  const MarketSymbol({
    required this.symbol,
    required this.name,
    this.exchange = '',
  });

  factory MarketSymbol.fromJson(Map<String, dynamic> json) {
    return MarketSymbol(
      symbol: json['symbol'] as String,
      name: json['name'] as String? ?? json['symbol'] as String,
      exchange: json['exchange'] as String? ?? '',
    );
  }

  @override
  bool operator ==(Object other) =>
      other is MarketSymbol && other.symbol == symbol;

  @override
  int get hashCode => symbol.hashCode;
}
