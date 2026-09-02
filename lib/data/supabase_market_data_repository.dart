import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'repositories.dart';

class SupabaseMarketDataRepository implements MarketDataRepository {
  SupabaseMarketDataRepository(this._client, this._preferences);

  static const _catalogKey = 'quick_ledger_twse_catalog_v2';
  static const _catalogAtKey = 'quick_ledger_twse_catalog_at_v2';
  final SupabaseClient _client;
  final SharedPreferences _preferences;
  List<MarketInstrument>? _catalog;

  @override
  Future<List<MarketInstrument>> loadCatalog({
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh && _catalog != null) return _catalog!;
    List<MarketInstrument>? cachedItems;
    if (!forceRefresh) {
      final cachedAt = DateTime.tryParse(
        _preferences.getString(_catalogAtKey) ?? '',
      );
      final encoded = _preferences.getString(_catalogKey);
      if (encoded != null) {
        try {
          cachedItems = (jsonDecode(encoded) as List)
              .map(
                (item) => MarketInstrument.fromJson(
                  Map<String, dynamic>.from(item as Map),
                ),
              )
              .toList();
          if (cachedItems.isNotEmpty &&
              cachedAt != null &&
              DateTime.now().difference(cachedAt) < const Duration(hours: 24)) {
            _catalog = cachedItems;
            return _catalog!;
          }
        } on Object {
          // Ignore a damaged cache and request a fresh catalogue.
        }
      }
    }
    List<MarketInstrument> items;
    try {
      final result = await _invoke({'action': 'catalog'});
      items = _decodeItems(result);
      if (items.isEmpty) throw StateError('投資商品目錄尚未同步');
    } on Object {
      if (cachedItems == null) rethrow;
      _catalog = cachedItems;
      return cachedItems;
    }
    _catalog = items;
    await _preferences.setString(
      _catalogKey,
      jsonEncode(items.map((item) => item.toJson()).toList()),
    );
    await _preferences.setString(
      _catalogAtKey,
      DateTime.now().toIso8601String(),
    );
    return items;
  }

  @override
  Future<List<MarketInstrument>> search(String query) async {
    final normalized = _normalize(query);
    if (normalized.length < 2) return const [];
    final catalog = _catalog;
    if (catalog != null) return _filter(catalog, normalized);
    final result = await _invoke({'action': 'search', 'query': normalized});
    return _decodeItems(result);
  }

  @override
  Future<List<MarketInstrument>> quotes(Iterable<String> symbols) async {
    final values = symbols.map(_normalize).where((item) => item.isNotEmpty);
    final result = await _invoke({
      'action': 'quotes',
      'symbols': values.toSet().toList(),
    });
    return _decodeItems(result);
  }

  Future<Map<String, dynamic>> _invoke(Map<String, dynamic> body) async {
    final response = await _client.functions.invoke(
      'investment-quotes',
      body: body,
    );
    if (response.status < 200 || response.status >= 300) {
      throw StateError('投資商品資料暫時無法取得');
    }
    return Map<String, dynamic>.from(response.data as Map);
  }

  static List<MarketInstrument> _decodeItems(Map<String, dynamic> response) =>
      (response['items'] as List? ?? const [])
          .map(
            (item) => MarketInstrument.fromJson(
              Map<String, dynamic>.from(item as Map),
            ),
          )
          .toList();

  static List<MarketInstrument> _filter(
    List<MarketInstrument> catalog,
    String query,
  ) {
    final result = catalog
        .where(
          (item) =>
              item.symbol.toUpperCase().contains(query) ||
              _normalize(item.name).contains(query),
        )
        .toList();
    result.sort((left, right) {
      final exact = (left.symbol == query ? 0 : 1).compareTo(
        right.symbol == query ? 0 : 1,
      );
      if (exact != 0) return exact;
      final prefix = (left.symbol.startsWith(query) ? 0 : 1).compareTo(
        right.symbol.startsWith(query) ? 0 : 1,
      );
      return prefix != 0 ? prefix : left.symbol.compareTo(right.symbol);
    });
    return result.take(8).toList();
  }

  static String _normalize(String value) =>
      value.trim().toUpperCase().replaceAll(RegExp(r'\s+'), '');
}
