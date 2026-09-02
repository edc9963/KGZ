import '../application/app_store.dart';
import '../domain/models.dart';

class TransactionDisplayRecord {
  const TransactionDisplayRecord({
    required this.date,
    required this.amountMinor,
    required this.item,
    required this.category,
    required this.isIncome,
    required this.currency,
    required this.detail,
    this.accountId,
    this.paymentMethod,
    this.expense,
    this.income,
    this.order,
  });

  final DateTime date;
  final int amountMinor;
  final String item;
  final String category;
  final bool isIncome;
  final String currency;
  final String detail;
  final String? accountId;
  final PaymentMethod? paymentMethod;
  final Expense? expense;
  final IncomeEntry? income;
  final GroupOrder? order;
}

List<TransactionDisplayRecord> transactionDisplayRecords(AppStore store) {
  final records = <TransactionDisplayRecord>[
    for (final expense in store.data.expenses)
      TransactionDisplayRecord(
        date: expense.date,
        amountMinor: expense.amountMinor,
        item: expense.item,
        category: expense.category,
        isIncome: false,
        currency: 'TWD',
        detail:
            '${expense.paymentMethod.label}'
            '${expense.merchant.isEmpty ? '' : '・${expense.merchant}'}',
        accountId: expense.accountId,
        paymentMethod: expense.paymentMethod,
        expense: expense,
      ),
    for (final income in store.data.incomes)
      TransactionDisplayRecord(
        date: income.date,
        amountMinor: income.amountMinor,
        item: income.item,
        category: income.category,
        isIncome: true,
        currency:
            store.accountById(income.accountId)?.currency ??
            store.data.settings.defaultCurrency,
        detail: store.accountById(income.accountId)?.name ?? '未指定',
        accountId: income.accountId,
        income: income,
      ),
    for (final order in store.data.orders)
      if (order.selfExpenseMinor > 0)
        TransactionDisplayRecord(
          date: order.date,
          amountMinor: order.selfExpenseMinor,
          item: '${_selfOrderItems(order)}（代訂本人）',
          category: '餐飲',
          isIncome: false,
          currency: 'TWD',
          detail: '${order.platform}・代訂本人消費',
          paymentMethod: PaymentMethod.creditCard,
          order: order,
        ),
  ]..sort((a, b) => b.date.compareTo(a.date));
  return records;
}

String _selfOrderItems(GroupOrder order) {
  final items = order.participants
      .where((participant) => participant.isSelf)
      .map((participant) => participant.itemName.trim())
      .where((item) => item.isNotEmpty)
      .join('、');
  return items.isEmpty ? order.name : items;
}
