import 'package:flutter/foundation.dart';

import '../../data/repositories.dart';
import '../../domain/models.dart';
import '../app_store.dart';
import 'first_or_null.dart';

/// Owns the cached market (TWSE/ETF) catalogue and quote refresh, and the
/// linking of an [InvestmentProduct] to a catalogue [MarketInstrument].
///
/// [AppStore] forwards its `marketCatalog` / `isLoadingMarketCatalog` /
/// `marketDataError` getters and its market-data methods here; this class
/// still reaches back into [AppStore] for `data`, `commit` and
/// `loadFinance` because linking/unlinking a product mutates the shared
/// [AppData], and a quote refresh needs a fresh finance snapshot afterwards.
class MarketDataManager {
  MarketDataManager(this._store, this._repository);

  final AppStore _store;
  final MarketDataRepository? _repository;

  List<MarketInstrument> marketCatalog = const [];
  bool isLoadingMarketCatalog = false;
  String? marketDataError;

  Future<void> ensureMarketCatalog({bool forceRefresh = false}) async {
    final repository = _repository;
    if (repository == null || isLoadingMarketCatalog) return;
    if (!forceRefresh && marketCatalog.isNotEmpty) return;
    isLoadingMarketCatalog = true;
    marketDataError = null;
    _store.notify();
    try {
      marketCatalog = await repository.loadCatalog(forceRefresh: forceRefresh);
    } on Object catch (error) {
      debugPrint('Market catalogue load failed: $error');
      marketDataError = '上市商品資料暫時無法取得';
    } finally {
      isLoadingMarketCatalog = false;
      _store.notify();
    }
  }

  List<MarketInstrument> searchMarketCatalog(String query) {
    final normalized = query.trim().toUpperCase().replaceAll(
      RegExp(r'\s+'),
      '',
    );
    if (normalized.length < 2) return const [];
    final result = marketCatalog
        .where(
          (item) =>
              item.symbol.toUpperCase().contains(normalized) ||
              item.name.replaceAll(RegExp(r'\s+'), '').contains(normalized),
        )
        .toList();
    result.sort((left, right) {
      final exact = (left.symbol == normalized ? 0 : 1).compareTo(
        right.symbol == normalized ? 0 : 1,
      );
      if (exact != 0) return exact;
      final prefix = (left.symbol.startsWith(normalized) ? 0 : 1).compareTo(
        right.symbol.startsWith(normalized) ? 0 : 1,
      );
      return prefix != 0 ? prefix : left.symbol.compareTo(right.symbol);
    });
    return result.take(8).toList();
  }

  Future<void> refreshMarketData() async {
    final repository = _repository;
    if (repository == null || !_store.isSignedIn || _store.isOffline) return;
    await ensureMarketCatalog();
    final symbols = _store.data.products
        .where((item) => item.usesAutomaticQuote)
        .map((item) => item.marketSymbol!)
        .toSet();
    if (symbols.isEmpty) return;
    try {
      await repository.quotes(symbols);
      await _store.loadFinance();
    } on Object catch (error) {
      debugPrint('Market quote refresh failed: $error');
      marketDataError = '收盤價更新失敗，暫時沿用最後有效價格';
      _store.notify();
    }
  }

  Map<String, MarketInstrument> get existingMarketLinkCandidates {
    final result = <String, MarketInstrument>{};
    for (final product in _store.data.products.where(
      (item) => !item.usesAutomaticQuote && item.symbol.trim().isNotEmpty,
    )) {
      final symbol = product.symbol.trim().toUpperCase();
      final match = marketCatalog
          .where((item) => item.symbol == symbol)
          .firstOrNull;
      if (match != null) result[product.id] = match;
    }
    return result;
  }

  Future<void> linkMarketProducts(Map<String, MarketInstrument> links) async {
    if (links.isEmpty) return;
    final now = DateTime.now();
    final products = [
      for (final product in _store.data.products)
        if (links[product.id] case final instrument?)
          product.copyWith(
            symbol: instrument.symbol,
            name: instrument.name,
            type: instrument.type,
            currency: instrument.currency,
            currentPriceMinor: instrument.closePriceMinor,
            priceUpdatedAt: instrument.quoteDate ?? now,
            priceSource: 'twse',
            market: instrument.market,
            marketSymbol: instrument.symbol,
            quoteLinkedAt: now,
          )
        else
          product,
    ];
    await _store.commit(_store.data.copyWith(products: products));
  }

  Future<void> unlinkMarketProduct(String productId) async {
    await _store.commit(
      _store.data.copyWith(
        products: [
          for (final product in _store.data.products)
            if (product.id == productId)
              product.copyWith(
                priceSource: 'manual',
                clearMarketLink: true,
                priceUpdatedAt: DateTime.now(),
              )
            else
              product,
        ],
      ),
    );
  }
}
