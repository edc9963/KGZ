import '../../domain/models.dart';
import '../app_store.dart';

/// Bookkeeping-category CRUD: add/rename/reorder, activate/deactivate,
/// merge one category into another, and delete an unused one. Renaming or
/// merging a category also renames it on every expense/income/recurring
/// expense/transaction that still refers to it by name.
class CategoriesManager {
  CategoriesManager(this._store);

  final AppStore _store;

  AppData get _data => _store.data;

  Future<void> addCategory({
    required BookkeepingCategoryKind kind,
    required String name,
    required String iconKey,
    required String colorKey,
  }) async {
    final normalized = name.trim();
    if (!_validateCategoryName(normalized, kind)) return;
    await _store.commit(
      _data.copyWith(
        categories: [
          ..._data.categories,
          BookkeepingCategory(
            id: _store.newId(),
            userId: _store.userId,
            name: normalized,
            kind: kind,
            iconKey: iconKey,
            colorKey: colorKey,
            sortOrder: _store.ledger.categoriesFor(kind).length,
          ),
        ],
      ),
    );
  }

  Future<void> updateCategory(BookkeepingCategory category) async {
    final normalized = category.name.trim();
    if (!_validateCategoryName(
      normalized,
      category.kind,
      exceptId: category.id,
    )) {
      return;
    }
    final previous = _store.ledger.categoryById(category.id);
    if (previous == null) return;
    final renamed = previous.name != normalized;
    await _store.commit(
      _data.copyWith(
        categories: [
          for (final item in _data.categories)
            if (item.id == category.id)
              category.copyWith(name: normalized)
            else
              item,
        ],
        expenses: renamed && category.kind == BookkeepingCategoryKind.expense
            ? [
                for (final item in _data.expenses)
                  if (item.category == previous.name)
                    item.copyWith(category: normalized)
                  else
                    item,
              ]
            : _data.expenses,
        recurringExpenses:
            renamed && category.kind == BookkeepingCategoryKind.expense
            ? [
                for (final item in _data.recurringExpenses)
                  if (item.category == previous.name)
                    item.copyWith(category: normalized)
                  else
                    item,
              ]
            : _data.recurringExpenses,
        incomes: renamed && category.kind == BookkeepingCategoryKind.income
            ? [
                for (final item in _data.incomes)
                  if (item.category == previous.name)
                    item.copyWith(category: normalized)
                  else
                    item,
              ]
            : _data.incomes,
        settings: _data.settings.defaultExpenseCategoryId == category.id
            ? _data.settings.copyWith(defaultCategory: normalized)
            : _data.settings,
      ),
    );
  }

  Future<void> setCategoryActive(String id, bool active) async {
    final category = _store.ledger.categoryById(id);
    if (category == null || category.isActive == active) return;
    if (!active && _data.settings.defaultExpenseCategoryId == id) {
      _store.lastSyncError = '請先更換預設消費分類';
      _store.notify();
      return;
    }
    if (!active &&
        _store.ledger.categoriesFor(category.kind, activeOnly: true).length <=
            1) {
      _store.lastSyncError = '每種記帳類型至少需要一個啟用分類';
      _store.notify();
      return;
    }
    await _store.commit(
      _data.copyWith(
        categories: [
          for (final item in _data.categories)
            if (item.id == id)
              item.copyWith(isActive: active, clearMergedInto: active)
            else
              item,
        ],
      ),
    );
  }

  Future<void> reorderCategories(
    BookkeepingCategoryKind kind,
    List<String> orderedIds,
  ) => _store.commit(
    _data.copyWith(
      categories: [
        for (final item in _data.categories)
          if (item.kind == kind)
            item.copyWith(sortOrder: orderedIds.indexOf(item.id))
          else
            item,
      ],
    ),
  );

  Future<void> mergeCategory(String sourceId, String targetId) async {
    final source = _store.ledger.categoryById(sourceId);
    final target = _store.ledger.categoryById(targetId);
    if (source == null ||
        target == null ||
        source.id == target.id ||
        source.kind != target.kind ||
        !target.isActive) {
      _store.lastSyncError = '只能合併到同類型的啟用分類';
      _store.notify();
      return;
    }
    final defaultIsSource = _data.settings.defaultExpenseCategoryId == source.id;
    await _store.commit(
      _data.copyWith(
        categories: [
          for (final item in _data.categories)
            if (item.id == source.id)
              item.copyWith(isActive: false, mergedIntoCategoryId: target.id)
            else
              item,
        ],
        transactions: [
          for (final item in _data.transactions)
            if (item.categoryId == source.id)
              item.copyWith(categoryId: target.id)
            else
              item,
        ],
        expenses: source.kind == BookkeepingCategoryKind.expense
            ? [
                for (final item in _data.expenses)
                  if (item.category == source.name)
                    item.copyWith(category: target.name)
                  else
                    item,
              ]
            : _data.expenses,
        recurringExpenses: source.kind == BookkeepingCategoryKind.expense
            ? [
                for (final item in _data.recurringExpenses)
                  if (item.category == source.name)
                    item.copyWith(category: target.name)
                  else
                    item,
              ]
            : _data.recurringExpenses,
        incomes: source.kind == BookkeepingCategoryKind.income
            ? [
                for (final item in _data.incomes)
                  if (item.category == source.name)
                    item.copyWith(category: target.name)
                  else
                    item,
              ]
            : _data.incomes,
        settings: defaultIsSource
            ? _data.settings.copyWith(
                defaultCategory: target.name,
                defaultExpenseCategoryId: target.id,
              )
            : _data.settings,
      ),
    );
  }

  Future<void> deleteCategory(String id) async {
    final category = _store.ledger.categoryById(id);
    if (category == null) return;
    if (category.isBuiltIn || _store.ledger.isCategoryUsed(category)) {
      _store.lastSyncError = '已使用或內建分類只能停用或合併';
      _store.notify();
      return;
    }
    await _store.commit(
      _data.copyWith(
        categories: _data.categories.where((item) => item.id != id).toList(),
      ),
    );
  }

  bool _validateCategoryName(
    String name,
    BookkeepingCategoryKind kind, {
    String? exceptId,
  }) {
    if (name.isEmpty || name.runes.length > 20) {
      _store.lastSyncError = '分類名稱需為 1–20 字';
      _store.notify();
      return false;
    }
    if (_data.categories.any(
      (item) =>
          item.id != exceptId &&
          item.kind == kind &&
          item.name.trim().toLowerCase() == name.toLowerCase(),
    )) {
      _store.lastSyncError = '同類型已有相同分類名稱';
      _store.notify();
      return false;
    }
    return true;
  }
}
