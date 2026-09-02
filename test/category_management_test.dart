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
