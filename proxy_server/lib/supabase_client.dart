import 'dart:convert';

import 'package:http/http.dart' as http;

class SupabaseConfig {
  final String url;
  final String serviceKey;
  const SupabaseConfig({required this.url, required this.serviceKey});
}

/// Genel amaçlı bir SDK değil; bu projenin ihtiyaç duyduğu select/insert/
/// delete işlemlerini PostgREST üzerinden yapan minimal bir yardımcı.
/// service_role anahtarı kullanıldığından RLS baypas edilir (bkz. tabloları
/// oluşturan SQL script'i: RLS açık ama politika yok, yalnızca bu anahtar
/// erişebiliyor).
class SupabaseTable {
  final http.Client client;
  final SupabaseConfig config;
  final String table;

  SupabaseTable(this.client, this.config, this.table);

  Uri _uri(Map<String, String> query) =>
      Uri.parse('${config.url}/rest/v1/$table').replace(queryParameters: query);

  Map<String, String> get _headers => {
        'apikey': config.serviceKey,
        'Authorization': 'Bearer ${config.serviceKey}',
        'Content-Type': 'application/json',
      };

  Future<List<Map<String, dynamic>>> select({
    String columns = '*',
    Map<String, String> filters = const {},
  }) async {
    final resp =
        await client.get(_uri({'select': columns, ...filters}), headers: _headers);
    if (resp.statusCode != 200) {
      throw Exception('Supabase select hatası ($table, ${resp.statusCode}): ${resp.body}');
    }
    return (jsonDecode(resp.body) as List).cast<Map<String, dynamic>>();
  }

  /// [rowOrRows] tek bir Map veya Map listesi olabilir (toplu ekleme).
  /// Varsayılan `return=representation` ile eklenen satırları döner —
  /// çağıran taraf, "gerçekten eklendi mi" bilgisini (ör. ignore-duplicates
  /// ile atlanan satırlar boş döner) ekstra bir sorgu yapmadan öğrenir.
  Future<List<Map<String, dynamic>>> insert(
    Object rowOrRows, {
    String? onConflict,
    String prefer = 'return=representation',
  }) async {
    final query = onConflict != null ? {'on_conflict': onConflict} : <String, String>{};
    final resp = await client.post(
      _uri(query),
      headers: {..._headers, 'Prefer': prefer},
      body: jsonEncode(rowOrRows),
    );
    if (resp.statusCode >= 300) {
      throw Exception('Supabase insert hatası ($table, ${resp.statusCode}): ${resp.body}');
    }
    return _parseRepresentation(prefer, resp.body);
  }

  Future<List<Map<String, dynamic>>> update(
    Map<String, dynamic> patch, {
    required Map<String, String> filters,
    String prefer = 'return=representation',
  }) async {
    final resp = await client.patch(
      _uri(filters),
      headers: {..._headers, 'Prefer': prefer},
      body: jsonEncode(patch),
    );
    if (resp.statusCode >= 300) {
      throw Exception('Supabase update hatası ($table, ${resp.statusCode}): ${resp.body}');
    }
    return _parseRepresentation(prefer, resp.body);
  }

  Future<List<Map<String, dynamic>>> delete(
    Map<String, String> filters, {
    String prefer = 'return=representation',
  }) async {
    final resp =
        await client.delete(_uri(filters), headers: {..._headers, 'Prefer': prefer});
    if (resp.statusCode >= 300) {
      throw Exception('Supabase delete hatası ($table, ${resp.statusCode}): ${resp.body}');
    }
    return _parseRepresentation(prefer, resp.body);
  }

  List<Map<String, dynamic>> _parseRepresentation(String prefer, String body) {
    if (!prefer.contains('return=representation')) return const [];
    final trimmed = body.trim();
    if (trimmed.isEmpty) return const [];
    return (jsonDecode(trimmed) as List).cast<Map<String, dynamic>>();
  }
}
