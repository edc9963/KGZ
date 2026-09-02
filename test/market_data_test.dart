import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:quick_ledger/application/app_store.dart';
import 'package:quick_ledger/data/repositories.dart';
import 'package:quick_ledger/domain/models.dart';

void main() {
  const catalog = [
    MarketInstrument(
      market: 'TWSE',
      symbol: '0050',
      name: '元大台灣50',
      type: 'ETF',
      currency: 'TWD',
      closePriceMinor: 10310,
      quoteDate: null,
    ),
    MarketInstrument(
      market: 'TWSE',
      symbol: '0051',
      name: '元大中型100',
      type: 'ETF',
      currency: 'TWD',
      closePriceMinor: 14100,
      quoteDate: null,
    ),
  ];

  test('market catalogue searches by symbol and Chinese name', () async {
    final store = _store(market: const _MarketRepository(catalog));
    await store.initialize();
    await store.ensureMarketCatalog();

    expect(store.searchMarketCatalog('005').first.symbol, '0050');
    expect(store.searchMarketCatalog('台灣50').single.symbol, '0050');
    expect(store.searchMarketCatalog('0'), isEmpty);
  });

  test('linking an existing product preserves inventory inputs', () async {
    final product = InvestmentProduct(
      id: 'p1',
      userId: 'user',
      symbol: '0050',
      name: '原名稱',
      type: 'ETF',
      currency: 'TWD',
      currentPriceMinor: 9000,
      priceUpdatedAt: DateTime(2026, 8, 1),
      note: '保留',
    );
    final finance = _FinanceRepository(
      AppData(
        products: [product],
        investmentAdjustments: [
          InvestmentAdjustment(
            id: 'a1',
            userId: 'user',
            productId: 'p1',
            date: DateTime(2026, 8, 1),
            quantityMicros: 1000000000,
            averageCostMinor: 8000,
            reason: '期初',
          ),
        ],
      ),
    );
    final store = _store(finance: finance);
    await store.initialize();
    final before = store.holdings['p1']!;
    await store.linkMarketProducts({'p1': catalog.first});
    final after = store.holdings['p1']!;

    expect(after.quantityMicros, before.quantityMicros);
    expect(after.averageCostMinor, before.averageCostMinor);
    expect(store.productById('p1')!.usesAutomaticQuote, isTrue);
    expect(store.productById('p1')!.currentPriceMinor, 10310);
  });

  test('automatic quote metadata round-trips through product JSON', () {
    final linkedAt = DateTime.utc(2026, 8, 20);
    final product = InvestmentProduct(
      id: 'p1',
      userId: 'user',
      symbol: '0050',
      name: '元大台灣50',
      type: 'ETF',
      currency: 'TWD',
      currentPriceMinor: 10310,
      priceUpdatedAt: DateTime.utc(2026, 8, 19),
      note: '',
      priceSource: 'twse',
      market: 'TWSE',
      marketSymbol: '0050',
      quoteLinkedAt: linkedAt,
    );

    final restored = InvestmentProduct.fromJson(product.toJson());
    expect(restored.usesAutomaticQuote, isTrue);
    expect(restored.marketSymbol, '0050');
    expect(restored.quoteLinkedAt, linkedAt);
  });
}

AppStore _store({_FinanceRepository? finance, MarketDataRepository? market}) =>
    AppStore(
      authRepository: _AuthRepository(),
      financeRepository: finance ?? _FinanceRepository(const AppData()),
      csvExportService: const _CsvExportService(),
      marketDataRepository: market,
    );

class _AuthRepository implements AuthRepository {
  @override
  String? get currentUserId => 'user';
  @override
  String? get currentUserDisplayName => 'User';
  @override
  bool get isSignedIn => true;
  @override
  Stream<bool> get authStateChanges => const Stream.empty();
  @override
  Future<void> signInWithLine({String? returnPath}) async {}
  @override
  Future<void> signOut() async {}
}

class _FinanceRepository implements FinanceRepository {
  _FinanceRepository(this.data);
  AppData data;
  int revision = 0;

  @override
  Future<FinanceSnapshot> load() async =>
      FinanceSnapshot(data: data, revision: revision, cloudExists: true);
  @override
  Future<SaveResult> save(AppData value) async {
    data = value;
    revision += 1;
    return SaveResult(revision: revision, updatedAt: DateTime.now());
  }

  @override
  Future<SaveResult> clear() => save(const AppData());
  @override
  Future<FinanceSnapshot> resolveInitialMigration(
    InitialMigrationAction action,
  ) => load();
}

class _CsvExportService implements CsvExportService {
  const _CsvExportService();
  @override
  Future<void> export(String fileName, List<List<Object?>> rows) async {}
}

class _MarketRepository implements MarketDataRepository {
  const _MarketRepository(this.items);
  final List<MarketInstrument> items;

  @override
  Future<List<MarketInstrument>> loadCatalog({
    bool forceRefresh = false,
  }) async => items;
  @override
  Future<List<MarketInstrument>> quotes(Iterable<String> symbols) async =>
      items.where((item) => symbols.contains(item.symbol)).toList();
  @override
  Future<List<MarketInstrument>> search(String query) async => items;
}
