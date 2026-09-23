import '../../domain/models.dart';
import '../app_store.dart';
import 'first_or_null.dart';
import 'transaction_utils.dart';

/// Expense, recurring-expense and income CRUD, including mirroring each
/// one into the unified [FinancialTransaction] ledger.
class ExpensesManager {
  ExpensesManager(this._store);

  final AppStore _store;

  AppData get _data => _store.data;

  Future<void> upsertExpense(Expense expense) async {
    if (expense.paymentMethod == PaymentMethod.debitCard) {
      final card = _store.ledger.cardById(expense.cardId);
      if (card == null || !card.isDebit || !card.isActive) {
        _store.lastSyncError = '請選擇已啟用的金融卡';
        _store.notify();
        return;
      }
      expense = expense.copyWith(accountId: card.debitAccountId);
    }
    final items = [..._data.expenses];
    final index = items.indexWhere((item) => item.id == expense.id);
    index < 0 ? items.add(expense) : items[index] = expense;
    await _store.commit(
      _data.copyWith(
        expenses: items,
        transactions: replaceTransaction(
          _data.transactions,
          'expense:${expense.id}',
          _expenseTransaction(expense),
        ),
      ),
    );
  }

  Future<void> deleteExpense(String id) async {
    if (_data.recurringExpenseOccurrences.any(
          (item) => item.expenseId == id,
        ) ||
        _data.telecomBillPayments.any(
          (item) => item.expenseIds.contains(id),
        )) {
      _store.lastSyncError = '已入帳的固定支出或電信帳單不可刪除';
      _store.notify();
      return;
    }
    await _store.commit(
      _data.copyWith(
        expenses: _data.expenses.where((item) => item.id != id).toList(),
        transactions: _data.transactions
            .where((item) => item.id != 'expense:$id')
            .toList(),
      ),
    );
  }

  Future<void> upsertRecurringExpense(RecurringExpense expense) async {
    if (expense.isTelecom &&
        expense.isActive &&
        _data.recurringExpenses.any(
          (item) => item.id != expense.id && item.isActive && item.isTelecom,
        )) {
      _store.lastSyncError = '只能啟用一組電信帳單固定支出';
      _store.notify();
      return;
    }
    final items = [..._data.recurringExpenses];
    final index = items.indexWhere((item) => item.id == expense.id);
    index < 0 ? items.add(expense) : items[index] = expense;
    await _store.commit(_data.copyWith(recurringExpenses: items));
  }

  Future<void> setRecurringExpenseActive(String id, bool active) async {
    final existing = _data.recurringExpenses
        .where((item) => item.id == id)
        .firstOrNull;
    if (existing == null) return;
    await upsertRecurringExpense(existing.copyWith(isActive: active));
  }

  Future<void> upsertIncome(IncomeEntry income) async {
    final items = [..._data.incomes];
    final index = items.indexWhere((item) => item.id == income.id);
    index < 0 ? items.add(income) : items[index] = income;
    await _store.commit(
      _data.copyWith(
        incomes: items,
        transactions: replaceTransaction(
          _data.transactions,
          'income:${income.id}',
          _incomeTransaction(income),
        ),
      ),
    );
  }

  Future<void> deleteIncome(String id) => _store.commit(
    _data.copyWith(
      incomes: _data.incomes.where((item) => item.id != id).toList(),
      transactions: _data.transactions
          .where((item) => item.id != 'income:$id')
          .toList(),
    ),
  );

  FinancialTransaction _expenseTransaction(Expense expense) {
    final impacts = <AccountImpact>[];
    if (expense.isCreditCard) {
      final liabilityId = _store.ledger
          .cardById(expense.cardId)
          ?.liabilityAccountId;
      if (liabilityId != null) {
        impacts.add(
          AccountImpact(
            accountId: liabilityId,
            amountMinor: expense.amountMinor,
            currency: 'TWD',
          ),
        );
      }
    } else if (expense.accountId != null &&
        expense.paymentMethod != PaymentMethod.telecomBill) {
      impacts.add(
        AccountImpact(
          accountId: expense.accountId!,
          amountMinor: -expense.amountMinor,
          currency:
              _store.ledger.accountById(expense.accountId)?.currency ??
              'TWD',
        ),
      );
    }
    return FinancialTransaction(
      id: 'expense:${expense.id}',
      userId: expense.userId,
      date: expense.date,
      type: FinancialTransactionType.expense,
      label: expense.item,
      amountMinor: expense.amountMinor,
      currency: 'TWD',
      categoryId:
          _store.ledger
              .categoryByName(expense.category, BookkeepingCategoryKind.expense)
              ?.id ??
          _data.settings.defaultExpenseCategoryId,
      note: expense.note,
      relatedEntityType: 'expense',
      relatedEntityId: expense.id,
      impacts: impacts,
      origin: expense.origin,
    );
  }

  FinancialTransaction _incomeTransaction(IncomeEntry income) =>
      FinancialTransaction(
        id: 'income:${income.id}',
        userId: income.userId,
        date: income.date,
        type: FinancialTransactionType.income,
        label: income.item,
        amountMinor: income.amountMinor,
        currency: _store.ledger.accountById(income.accountId)?.currency ?? 'TWD',
        categoryId: _store.ledger.categoryByName(
          income.category,
          BookkeepingCategoryKind.income,
        )?.id,
        note: income.note,
        relatedEntityType: 'income',
        relatedEntityId: income.id,
        impacts: [
          AccountImpact(
            accountId: income.accountId,
            amountMinor: income.amountMinor,
            currency:
                _store.ledger.accountById(income.accountId)?.currency ??
                'TWD',
          ),
        ],
        origin: income.origin,
      );
}
