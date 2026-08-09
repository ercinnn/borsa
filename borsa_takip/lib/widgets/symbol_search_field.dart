import 'dart:async';

import 'package:flutter/material.dart';

import '../models/symbol.dart';
import '../services/market_api.dart';

class SymbolSearchField extends StatefulWidget {
  final MarketApi api;
  final ValueChanged<MarketSymbol> onSelect;

  const SymbolSearchField({
    super.key,
    required this.api,
    required this.onSelect,
  });

  @override
  State<SymbolSearchField> createState() => _SymbolSearchFieldState();
}

class _SymbolSearchFieldState extends State<SymbolSearchField> {
  final _controller = TextEditingController();
  Timer? _debounce;
  List<MarketSymbol> _results = [];
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    if (value.trim().length < 2) {
      setState(() {
        _results = [];
        _error = null;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 400), () => _search(value));
  }

  Future<void> _search(String query) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await widget.api.search(query);
      if (!mounted) return;
      setState(() {
        _results = results;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _controller,
          decoration: InputDecoration(
            labelText: 'Sembol ara (ör. AAPL, BTC, THYAO)',
            border: const OutlineInputBorder(),
            suffixIcon: _loading
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : const Icon(Icons.search),
          ),
          onChanged: _onChanged,
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(_error!, style: TextStyle(color: Colors.red[700])),
          ),
        if (_results.isNotEmpty)
          Card(
            margin: const EdgeInsets.only(top: 4),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 240),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: _results.length,
                itemBuilder: (context, i) {
                  final s = _results[i];
                  return ListTile(
                    dense: true,
                    title: Text(s.symbol),
                    subtitle: Text('${s.name} · ${s.exchange}'),
                    onTap: () {
                      widget.onSelect(s);
                      setState(() {
                        _results = [];
                        _controller.clear();
                      });
                    },
                  );
                },
              ),
            ),
          ),
      ],
    );
  }
}
