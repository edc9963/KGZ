import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quick_ledger/application/app_store.dart';
import 'package:quick_ledger/application/providers.dart';
import 'package:quick_ledger/data/repositories.dart';
import 'package:quick_ledger/domain/models.dart';
import 'package:quick_ledger/presentation/pages/collection_page.dart';

void main() {
  testWidgets('public collection loads without a signed-in finance snapshot', (
    tester,
  ) async {
    final collection = _CollectionRepository();
    final store = AppStore(
      authRepository: _SignedOutAuth(),
      financeRepository: _UnusedFinance(),
      csvExportService: _Csv(),
      publicCollectionRepository: collection,
    );
    await store.initialize();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appStoreProvider.overrideWith((ref) => store)],
        child: const MaterialApp(home: CollectionPage(token: 'public-token')),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('跨裝置午餐'), findsOneWidget);
    expect(find.text('應付 NT\$180'), findsOneWidget);
    expect(find.text('我已付款'), findsOneWidget);

    await tester.tap(find.text('我已付款'));
    await tester.pumpAndSettle();

    expect(collection.markPendingCalls, 1);
    expect(find.text('已通知收款人，等待確認'), findsOneWidget);
  });
}

class _CollectionRepository implements PublicCollectionRepository {
  var status = CollectionStatus.unpaid;
  var markPendingCalls = 0;

  @override
  Future<PublicCollectionDetails?> load(String token) async =>
      PublicCollectionDetails(
        orderName: '跨裝置午餐',
        orderDate: DateTime(2026, 8, 12),
        orderNote: '',
        participantName: '朋友',
        itemName: '便當',
        itemAmountMinor: 17000,
        sharedFeeMinor: 2000,
        discountMinor: 1000,
        dueMinor: 18000,
        status: status,
        collectionMethod: collectionMethodCash,
        bankQrData: '',
        bankAccountInfo: '',
      );

  @override
  Future<void> markPending(String token) async {
    markPendingCalls += 1;
    status = CollectionStatus.pending;
  }
}

class _SignedOutAuth implements AuthRepository {
  @override
  Stream<bool> get authStateChanges => const Stream.empty();
  @override
  String? get currentUserId => null;
  @override
  String? get currentUserDisplayName => null;
  @override
  bool get isSignedIn => false;
  @override
  Future<void> signInWithLine({String? returnPath}) async {}
  @override
  Future<void> signOut() async {}
}

class _UnusedFinance implements FinanceRepository {
  @override
  Future<FinanceSnapshot> load() async =>
      const FinanceSnapshot(data: AppData());
  @override
  Future<SaveResult> save(AppData data) => throw UnimplementedError();
  @override
  Future<SaveResult> clear() => throw UnimplementedError();
  @override
  Future<FinanceSnapshot> resolveInitialMigration(
    InitialMigrationAction action,
  ) => throw UnimplementedError();
}

class _Csv implements CsvExportService {
  @override
  Future<void> export(String fileName, List<List<Object?>> rows) async {}
}
