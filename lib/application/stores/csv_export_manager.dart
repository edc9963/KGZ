import '../../data/repositories.dart';
import '../../domain/models.dart';
import '../app_store.dart';

/// Builds and hands off the CSV exports offered from Settings. Each method
/// reads across whichever collections that export needs — through
/// [AppStore.data] directly for raw rows and through [AppStore.ledger] for
/// derived figures like a bill's calculated amount — since a CSV export is
/// inherently a cross-domain report, not a single domain's data.
class CsvExportManager {
  CsvExportManager(this._store, this._csv);

  final AppStore _store;
  final CsvExportService _csv;

  AppData get _data => _store.data;

  Future<void> exportAccounts() => _csv.export('快記帳_帳戶.csv', [
    ['帳戶名稱', '機構', '類型', '幣別', '目前餘額', '啟用', '備註'],
    for (final item in _data.accounts)
      [
        item.name,
        item.institution,
        item.type,
        item.currency,
        _store.ledger.accountBalance(item.id) / 100,
        item.isActive ? '是' : '否',
        item.note,
      ],
  ]);

  Future<void> exportExpenses() => _csv.export('快記帳_消費.csv', [
    ['日期', '項目', '分類', '金額', '付款方式', '店家', '必要支出', '備註'],
    for (final item in _data.expenses)
      [
        item.date.toIso8601String(),
        item.item,
        item.category,
        item.amountMinor / 100,
        item.paymentMethod.label,
        item.merchant,
        item.isNecessary ? '是' : '否',
        item.note,
      ],
  ]);

  Future<void> exportIncomes() => _csv.export('快記帳_收入.csv', [
    ['日期', '項目', '分類', '金額', '收款帳戶', '備註'],
    for (final item in _data.incomes)
      [
        item.date.toIso8601String(),
        item.item,
        item.category,
        item.amountMinor / 100,
        _store.ledger.accountById(item.accountId)?.name ?? '',
        item.note,
      ],
  ]);

  Future<void> exportInvestments() => _csv.export('快記帳_投資.csv', [
    ['日期', '商品', '類型', '數量', '價格', '手續費', '稅費', '備註'],
    for (final item in _data.investmentTransactions)
      [
        item.date.toIso8601String(),
        _store.ledger.productById(item.productId)?.name ?? '',
        item.type.label,
        item.quantity,
        item.priceMinor / 100,
        item.feeMinor / 100,
        item.taxMinor / 100,
        item.note,
      ],
  ]);

  Future<void> exportBills() => _csv.export('快記帳_信用卡帳單.csv', [
    [
      '月份',
      '信用卡',
      '銀行實際總額',
      '系統明細合計',
      '核對差額',
      '差異原因',
      '已繳金額',
      '剩餘待繳',
      '狀態',
      '截止日',
      '自動扣款日',
    ],
    for (final item in _data.bills)
      [
        item.month,
        _store.ledger.cardById(item.cardId)?.name ?? '',
        _store.ledger.billAmount(item) / 100,
        _store.ledger.calculatedBillAmount(item) / 100,
        _store.ledger.reconciliationDifference(item) / 100,
        item.reconciliationReason.label,
        _store.ledger.paidBillMinor(item) / 100,
        _store.ledger.outstandingBillMinor(item) / 100,
        _store.ledger.billStatus(item).label,
        item.dueDate.toIso8601String(),
        item.autoDebitDate.toIso8601String(),
      ],
  ]);

  Future<void> exportOrders() => _csv.export('快記帳_代訂收款.csv', [
    [
      '訂購日',
      '代訂名稱',
      '姓名',
      '品項',
      '實際成本',
      '最終收款',
      '代收損益',
      '狀態',
      '收款方式',
      '入帳帳戶',
      '收款日',
    ],
    for (final order in _data.orders)
      for (final item in order.participants.where((person) => !person.isSelf))
        [
          order.date.toIso8601String(),
          order.name,
          item.name,
          item.itemName,
          item.calculatedDueMinor / 100,
          item.dueMinor / 100,
          item.collectionResultMinor / 100,
          item.status.label,
          item.collectionMethod,
          _store.ledger.accountById(item.collectionAccountId)?.name ?? '',
          item.collectedAt?.toIso8601String() ?? '',
        ],
  ]);
}
