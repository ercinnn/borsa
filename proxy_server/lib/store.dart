import 'dart:convert';
import 'dart:io';

class WatchlistStore {
  static const defaultSymbols = [
    'THYAO.IS',
    'ASELS.IS',
    'GARAN.IS',
    'AKBNK.IS',
    'BTC-USD',
    'ETH-USD',
    'AAPL',
    'TSLA',
  ];

  final File _file;
  List<String> _symbols = [];

  WatchlistStore(this._file);

  List<String> get symbols => List.unmodifiable(_symbols);

  Future<void> load() async {
    if (await _file.exists()) {
      final content = await _file.readAsString();
      _symbols = (jsonDecode(content) as List).cast<String>();
    } else {
      _symbols = List.of(defaultSymbols);
      await _save();
    }
  }

  Future<bool> add(String symbol) async {
    final normalized = symbol.trim().toUpperCase();
    if (normalized.isEmpty || _symbols.contains(normalized)) return false;
    _symbols.add(normalized);
    await _save();
    return true;
  }

  Future<int> addAll(List<String> symbols) async {
    var added = 0;
    for (final symbol in symbols) {
      final normalized = symbol.trim().toUpperCase();
      if (normalized.isEmpty || _symbols.contains(normalized)) continue;
      _symbols.add(normalized);
      added++;
    }
    if (added > 0) await _save();
    return added;
  }

  Future<bool> remove(String symbol) async {
    final removed = _symbols.remove(symbol.trim().toUpperCase());
    if (removed) await _save();
    return removed;
  }

  Future<void> _save() async {
    await _file.parent.create(recursive: true);
    await _file.writeAsString(jsonEncode(_symbols));
  }
}

class NotificationStore {
  final File _file;
  List<Map<String, dynamic>> _items = []; // en yeni başta

  NotificationStore(this._file);

  Future<void> load() async {
    if (await _file.exists()) {
      final content = await _file.readAsString();
      _items = (jsonDecode(content) as List).cast<Map<String, dynamic>>();
    } else {
      _items = [];
    }
  }

  bool existsFor(String symbol, String dateKey) {
    return _items.any((n) => n['symbol'] == symbol && n['date'] == dateKey);
  }

  Future<void> add(Map<String, dynamic> item) async {
    _items.insert(0, item);
    await _save();
  }

  Map<String, dynamic> page(int page, {int pageSize = 100}) {
    final safePage = page < 1 ? 1 : page;
    final total = _items.length;
    final totalPages = total == 0 ? 1 : (total / pageSize).ceil();
    final start = (safePage - 1) * pageSize;
    if (start >= total) {
      return {
        'notifications': [],
        'page': safePage,
        'totalPages': totalPages,
        'total': total,
      };
    }
    final end = (start + pageSize > total) ? total : start + pageSize;
    return {
      'notifications': _items.sublist(start, end),
      'page': safePage,
      'totalPages': totalPages,
      'total': total,
    };
  }

  Future<void> _save() async {
    await _file.parent.create(recursive: true);
    await _file.writeAsString(jsonEncode(_items));
  }
}
