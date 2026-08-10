import 'dart:io';

// Render'da gerçek ortam değişkenleri kullanılıyor; yerel geliştirmede
// tekrar tekrar `$env:...` yazmamak için proxy_server/.env (gitignore'lu)
// dosyası varsa okunuyor. Basit KEY=VALUE satırları dışında bir şey
// desteklemiyor, yeni bir paket gerektirmiyor.
Map<String, String>? _dotEnv;

void _loadDotEnv() {
  if (_dotEnv != null) return;
  _dotEnv = {};
  final file = File('.env');
  if (!file.existsSync()) return;
  for (final line in file.readAsLinesSync()) {
    final trimmed = line.trim();
    if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
    final idx = trimmed.indexOf('=');
    if (idx == -1) continue;
    _dotEnv![trimmed.substring(0, idx).trim()] = trimmed.substring(idx + 1).trim();
  }
}

String? env(String key) {
  _loadDotEnv();
  return Platform.environment[key] ?? _dotEnv![key];
}

String requireEnv(String key) {
  final value = env(key);
  if (value == null || value.isEmpty) {
    stderr.writeln(
      'Ortam değişkeni eksik: $key. Yerelde proxy_server/.env dosyasına '
      '(bkz. .env.example) veya Render\'da Environment sekmesine ekleyin.',
    );
    exit(1);
  }
  return value;
}
