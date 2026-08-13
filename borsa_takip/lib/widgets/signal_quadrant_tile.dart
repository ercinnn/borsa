import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/technical_analysis.dart';
import '../services/market_api.dart';
import '../theme/app_colors.dart';
import 'glass_card.dart';

/// Bento düzeninin yan sütunundaki sinyal özeti karosu — seçili sembol için
/// `/api/technical`'ı (bkz. proxy_server/lib/technical_analysis.dart) çağırıp
/// genel Güçlü Al..Güçlü Sat özetini + RSI/MACD/Stochastic'in tek tek
/// durumunu gösterir. Teknik sekmesindeki tam tabloyla aynı veriye dayanır
/// ama sadece 3 gösterge seçilerek kompakt tutulmuş; tam liste için kullanıcı
/// zaten Teknik sekmesine gidebilir. Kendi fetch'ini kendi yönetir (BentoKpiRow
/// gibi ek bir ekran-durumu gerektirmez) — sadece [symbol] değiştiğinde yeniden
/// çeker.
class SignalQuadrantTile extends StatefulWidget {
  final MarketApi api;
  final String? symbol;

  const SignalQuadrantTile({super.key, required this.api, required this.symbol});

  @override
  State<SignalQuadrantTile> createState() => _SignalQuadrantTileState();
}

class _SignalQuadrantTileState extends State<SignalQuadrantTile> {
  bool _loading = false;
  String? _error;
  TechnicalAnalysisResult? _result;
  String? _fetchedFor;

  @override
  void initState() {
    super.initState();
    _maybeFetch();
  }

  @override
  void didUpdateWidget(covariant SignalQuadrantTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    _maybeFetch();
  }

  void _maybeFetch() {
    final symbol = widget.symbol;
    if (symbol == null || symbol == _fetchedFor) return;
    _fetchedFor = symbol;
    setState(() {
      _loading = true;
      _error = null;
    });
    widget.api.technicalAnalysis(symbol).then((result) {
      if (!mounted || widget.symbol != symbol) return;
      setState(() {
        _result = result;
        _loading = false;
      });
    }).catchError((e) {
      if (!mounted || widget.symbol != symbol) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    });
  }

  IndicatorRow? _find(String name) {
    for (final row in _result?.indicators ?? const <IndicatorRow>[]) {
      if (row.name == name) return row;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.speed, color: AppColors.cyan500, size: 18),
              const SizedBox(width: 8),
              Text('Sinyal Özeti', style: Theme.of(context).textTheme.titleSmall),
              const Spacer(),
              if (_loading)
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (widget.symbol == null)
            Text('Grafikte bir sembol seçince burada teknik sinyal özeti görünür.',
                style: Theme.of(context).textTheme.bodySmall)
          else if (_error != null)
            Text(_error!, style: const TextStyle(color: AppColors.rose500, fontSize: 12))
          else if (_result != null) ...[
            _OverallBadge(summary: _result!.summary),
            const SizedBox(height: 12),
            const Divider(height: 1, color: AppColors.slate800),
            const SizedBox(height: 12),
            _IndicatorLine(label: 'RSI', row: _find('RSI(14)')),
            const SizedBox(height: 8),
            _IndicatorLine(label: 'MACD', row: _find('MACD(12,26)')),
            const SizedBox(height: 8),
            _IndicatorLine(label: 'Stochastic', row: _find('STOCH(9,6) %K')),
          ],
        ],
      ),
    );
  }
}

Color _summaryColor(SummarySignal signal) => switch (signal) {
      SummarySignal.strongBuy || SummarySignal.buy => AppColors.emerald400,
      SummarySignal.sell || SummarySignal.strongSell => AppColors.rose500,
      SummarySignal.neutral => AppColors.amber500,
    };

Color _signalColor(Signal signal) => switch (signal) {
      Signal.buy => AppColors.emerald400,
      Signal.sell => AppColors.rose500,
      Signal.neutral => AppColors.amber500,
    };

class _OverallBadge extends StatelessWidget {
  final TechnicalSummary summary;
  const _OverallBadge({required this.summary});

  @override
  Widget build(BuildContext context) {
    final color = _summaryColor(summary.overall);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              summary.overall.label,
              style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 15),
            ),
          ),
          Text(
            '${summary.score}/100',
            style: GoogleFonts.robotoMono(color: AppColors.slate100, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _IndicatorLine extends StatelessWidget {
  final String label;
  final IndicatorRow? row;
  const _IndicatorLine({required this.label, required this.row});

  @override
  Widget build(BuildContext context) {
    final row = this.row;
    return Row(
      children: [
        Expanded(
          child: Text(label, style: const TextStyle(color: AppColors.slate400, fontSize: 12)),
        ),
        if (row == null)
          const Text('—', style: TextStyle(color: AppColors.slate400))
        else ...[
          Text(
            row.value.toStringAsFixed(1),
            style: GoogleFonts.robotoMono(fontSize: 12, color: AppColors.slate100),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: _signalColor(row.signal).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              row.signal.label,
              style: TextStyle(color: _signalColor(row.signal), fontSize: 11, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ],
    );
  }
}
