import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:quick_ledger/application/app_store.dart';
import 'package:quick_ledger/data/local_repositories.dart';
import 'package:quick_ledger/data/repositories.dart';
import 'package:quick_ledger/domain/models.dart';

void main() {
  test(
    'category maintenance validates, orders, disables, and merges safely',
    () async {
      final store = AppStore(
        authRepository: _Auth(),
        financeRepository: LocalFinanceRepository(_MemoryPersistence()),
        csvExportService: _Csv(),
      );
      await store.initialize();

      await store.addCategory(
        kind: BookkeepingCategoryKind.expense,
        name: ' 寵物 ',
        iconKey: 'medical',
        colorKey: 'rose',
      );
      final pet = store.categoryByName('寵物', BookkeepingCategoryKind.expense)!;
      expect(pet.iconKey, 'medical');

      await store.addCategory(
        kind: BookkeepingCategoryKind.expense,
        name: '寵物',
        iconKey: 'other',
        colorKey: 'slate',
      );
      expect(store.lastSyncError, '同類型已有相同分類名稱');
      store.lastSyncError = null;

      await store.updateCategory(pet.copyWith(name: '毛孩'));
      final renamed = store.categoryById(pet.id)!;
      expect(renamed.name, '毛孩');

      await store.mergeCategory(renamed.id, 'expense-medical');
      expect(store.categoryById(renamed.id)!.isActive, isFalse);
      expect(
        store.categoryById(renamed.id)!.mergedIntoCategoryId,
        'expense-medical',
      );

      await store.setCategoryActive('expense-food', false);
      expect(store.lastSyncError, '請先更換預設消費分類');

      store.dispose();
    },
  );

  test('item names are remembered per category, most used first', () async {
    final store = AppStore(
      authRepository: _Auth(),
      financeRepository: LocalFinanceRepository(_MemoryPersistence()),
      csvExportService: _Csv(),
    );
    await store.initialize();

    Future<void> add(String item, String category, DateTime date) =>
        store.upsertExpense(
          Expense(
            id: store.newId(),
            userId: store.userId,
            date: date,
            amountMinor: 10000,
            paymentMethod: PaymentMethod.cash,
            item: item,
            category: category,
            merchant: '',
            note: '',
            isNecessary: false,
            accountId: store.activeAssetAccounts.first.id,
          ),
        );

    await add('早餐', '餐飲', DateTime(2026, 1, 1));
    await add('午餐 ', '餐飲', DateTime(2026, 1, 2));
    await add('午餐', '餐飲', DateTime(2026, 1, 3));
    await add('晚餐', '餐飲', DateTime(2026, 1, 4));
    await add('捷運', '交通', DateTime(2026, 1, 5));

    expect(store.itemNamesFor(BookkeepingCategoryKind.expense, '餐飲'), [
      '午餐',
      '晚餐',
      '早餐',
    ]);
    expect(store.itemNamesFor(BookkeepingCategoryKind.expense, '交通'), ['捷運']);
    expect(store.itemNamesFor(BookkeepingCategoryKind.expense, null), isEmpty);

    store.dispose();
  });
}

class _Auth implements AuthRepository {
  final _controller = StreamController<bool>.broadcast();

  @override
  Stream<bool> get authStateChanges => _controller.stream;

  @override
  String? get currentUserId => 'user';
  @override
  String? get currentUserDisplayName => '測試使用者';

  @override
  bool get isSignedIn => true;

  @override
  Future<void> signInWithLine({String? returnPath}) async {}

  @override
  Future<void> signOut() async {}
}

class _MemoryPersistence implements LocalPersistence {
  String? value;

  @override
  Future<void> clear() async => value = null;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String value) async => this.value = value;
}

class _Csv implements CsvExportService {
  @override
  Future<void> export(String fileName, List<List<Object?>> rows) async {}
}
