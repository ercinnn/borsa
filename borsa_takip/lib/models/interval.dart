enum ChartInterval {
  daily('1d', 'Günlük'),
  weekly('1wk', 'Haftalık'),
  monthly('1mo', 'Aylık'),
  quarterly('3mo', '3 Aylık'),
  yearly('12mo', '12 Aylık');

  final String apiValue;
  final String label;

  const ChartInterval(this.apiValue, this.label);
}
