import 'models.dart';

enum ReportIssueSeverity { info, warning }

class ReportPeriod {
  const ReportPeriod({required this.start, required this.end});

  final DateTime start;
  final DateTime end;

  bool contains(DateTime value) {
    final day = DateTime(value.year, value.month, value.day);
    return !day.isBefore(_day(start)) && !day.isAfter(_day(end));
  }

  static DateTime _day(DateTime value) =>
      DateTime(value.year, value.month, value.day);
}

class StatementLine {
  const StatementLine({
    required this.label,
    required this.amountMinor,
    this.children = const [],
    this.estimated = false,
  });

  final String label;
  final int amountMinor;
  final List<StatementLine> children;
  final bool estimated;
}

class ReportDataQualityIssue {
  const ReportDataQualityIssue({
    required this.message,
    this.severity = ReportIssueSeverity.warning,
  });

  final String message;
  final ReportIssueSeverity severity;
}

class ChartSlice {
  const ChartSlice(this.label, this.amountMinor);
  final String label;
  final int amountMinor;
}

/// One line of the per-category expense breakdown shown under the expense pie
/// chart (date / item / amount). [amountMinor] is already converted to the
/// default currency, so the lines of a category add up to its pie slice.
class ExpenseDetail {
  const ExpenseDetail({
    required this.date,
    required this.item,
    required this.amountMinor,
  });

  final DateTime date;
  final String item;
  final int amountMinor;
}

class MonthlyReportPoint {
  const MonthlyReportPoint({
    required this.month,
    required this.incomeMinor,
    required this.expenseMinor,
  });

  final DateTime month;
  final int incomeMinor;
  final int expenseMinor;
}

class NetWorthTrendPoint {
  const NetWorthTrendPoint({required this.month, required this.amountMinor});

  final DateTime month;
  final int amountMinor;
}

class FinancialReportSnapshot {
  const FinancialReportSnapshot({
    required this.period,
    required this.assets,
    required this.liabilities,
    required this.income,
    required this.expenses,
    required this.operatingCashFlow,
    required this.investingCashFlow,
    required this.financingCashFlow,
    required this.otherCashFlow,
    required this.fxEffect,
    required this.cashChange,
    required this.assetAllocation,
    required this.expenseAllocation,
    this.expenseDetails = const {},
    required this.monthlyTrend,
    required this.issues,
  });

  final ReportPeriod period;
  final List<StatementLine> assets;
  final List<StatementLine> liabilities;
  final List<StatementLine> income;
  final List<StatementLine> expenses;
  final List<StatementLine> operatingCashFlow;
  final List<StatementLine> investingCashFlow;
  final List<StatementLine> financingCashFlow;
  final List<StatementLine> otherCashFlow;
  final int fxEffect;
  final int cashChange;
  final List<ChartSlice> assetAllocation;
  final List<ChartSlice> expenseAllocation;

  /// Transactions behind each [expenseAllocation] slice, keyed by the slice's
  /// label (including the merged 其他 slice), newest first.
  final Map<String, List<ExpenseDetail>> expenseDetails;
  final List<MonthlyReportPoint> monthlyTrend;
  final List<ReportDataQualityIssue> issues;

  int get totalAssets => assets.fold(0, (sum, line) => sum + line.amountMinor);
  int get totalLiabilities =>
      liabilities.fold(0, (sum, line) => sum + line.amountMinor);
  int get netWorth => totalAssets - totalLiabilities;
  int get totalIncome => income.fold(0, (sum, line) => sum + line.amountMinor);
  int get totalExpenses =>
      expenses.fold(0, (sum, line) => sum + line.amountMinor);
  int get netIncome => totalIncome - totalExpenses;
  int get classifiedCashFlow => [
    ...operatingCashFlow,
    ...investingCashFlow,
    ...financingCashFlow,
    ...otherCashFlow,
  ].fold(fxEffect, (sum, line) => sum + line.amountMinor);
  bool get cashFlowBalances => classifiedCashFlow == cashChange;
  bool get balanceSheetBalances => totalAssets - totalLiabilities == netWorth;
}

class FinancialReportService {
  FinancialReportService(this.data);

  final AppData data;
  final List<ReportDataQualityIssue> _issues = [];

  /// The category name a 代訂 order's own (`isSelf`) consumption is grouped
  /// under in the expense breakdown/pie chart — the order's chosen
  /// [GroupOrder.selfExpenseCategoryId] (picked in the 代訂 editor) if it
  /// still resolves to a real category, otherwise the built-in 餐飲 category.
  /// Every order created before this was configurable has a null
  /// [GroupOrder.selfExpenseCategoryId], so this is also what makes old
  /// 代訂 data default to 餐飲.
  String _orderSelfExpenseCategoryName(GroupOrder order) {
    final id = order.selfExpenseCategoryId ?? 'expense-food';
    final byId = data.categories
        .where(
          (item) => item.id == id && item.kind == BookkeepingCategoryKind.expense,
        )
        .firstOrNull;
    if (byId != null) return byId.name;
    final byName = data.categories
        .where(
          (item) =>
              item.kind == BookkeepingCategoryKind.expense && item.name == '餐飲',
        )
        .firstOrNull;
    return byName?.name ?? '餐飲';
  }

  List<NetWorthTrendPoint> netWorthTrend(DateTime end, {int months = 6}) {
    assert(months > 0);
    return List.generate(months, (index) {
      final offset = months - index - 1;
      final month = DateTime(end.year, end.month - offset, 1);
      final monthEnd = DateTime(
        month.year,
        month.month + 1,
        1,
      ).subtract(const Duration(days: 1));
      final asOf = monthEnd.isAfter(end) ? end : monthEnd;
      final snapshot = FinancialReportService(
        data,
      ).build(ReportPeriod(start: month, end: asOf));
      return NetWorthTrendPoint(month: month, amountMinor: snapshot.netWorth);
    });
  }

  FinancialReportSnapshot build(ReportPeriod period) {
    _issues.clear();
    final assets = <StatementLine>[];
    final liabilities = <StatementLine>[];
    final cashChildren = <StatementLine>[];
    var positiveCash = 0;
    var overdrafts = 0;
    for (final account in data.accounts) {
      final native = _accountBalanceAt(account, period.end);
      if (native == 0) continue;
      final converted = _convert(native.abs(), account.currency, period.end);
      final line = StatementLine(
        label: account.name,
        amountMinor: converted,
        estimated: _isEstimatedRate(account.currency, period.end),
      );
      if (native > 0) {
        positiveCash += converted;
        cashChildren.add(line);
      } else {
        overdrafts += converted;
      }
    }
    if (positiveCash > 0) {
      assets.add(
        StatementLine(
          label: '現金及存款',
          amountMinor: positiveCash,
          children: cashChildren,
        ),
      );
    }

    final investmentLines = <StatementLine>[];
    var investmentTotal = 0;
    for (final product in data.products) {
      final holding = _holdingAt(product.id, period.end);
      if (holding.quantityMicros <= 0) continue;
      final price = _priceAt(product, period.end);
      final native = (holding.quantityMicros * price.priceMinor / 1000000)
          .round();
      final converted = _convert(native, product.currency, period.end);
      investmentTotal += converted;
      investmentLines.add(
        StatementLine(
          label: product.name,
          amountMinor: converted,
          estimated:
              price.estimated || _isEstimatedRate(product.currency, period.end),
        ),
      );
    }
    if (investmentTotal > 0) {
      assets.add(
        StatementLine(
          label: '投資市值',
          amountMinor: investmentTotal,
          children: investmentLines,
          estimated: investmentLines.any((line) => line.estimated),
        ),
      );
    }

    final receivables = _receivablesAt(period.end);
    if (receivables > 0) {
      assets.add(
        StatementLine(
          label: '代收應收款',
          amountMinor: _convert(receivables, 'TWD', period.end),
        ),
      );
    }
    final cards = _cardLiabilityAt(period.end);
    if (cards > 0) {
      liabilities.add(
        StatementLine(
          label: '信用卡未付款',
          amountMinor: _convert(cards, 'TWD', period.end),
        ),
      );
    }
    final telecom = _telecomLiabilityAt(period.end);
    if (telecom > 0) {
      liabilities.add(
        StatementLine(
          label: '電信帳單未付款',
          amountMinor: _convert(telecom, 'TWD', period.end),
        ),
      );
    }
    if (overdrafts > 0) {
      liabilities.add(StatementLine(label: '帳戶透支', amountMinor: overdrafts));
    }

    final pnl = _profitAndLoss(period);
    final cash = _cashFlow(period);
    final startDay = period.start.subtract(const Duration(days: 1));
    final openingCash = _totalCashAt(startDay);
    final endingCash = _totalCashAt(period.end);
    final cashChange = endingCash - openingCash;
    final classified = [
      ...cash.operating,
      ...cash.investing,
      ...cash.financing,
      ...cash.other,
    ].fold(0, (sum, line) => sum + line.amountMinor);
    final fxEffect = cashChange - classified;

    final assetAllocation = [
      for (final line in assets)
        if (line.amountMinor > 0) ChartSlice(line.label, line.amountMinor),
    ];
    final grouped = _groupExpenses(period);
    final expenseAllocation = grouped.slices;
    final monthlyTrend = _monthlyTrend(period.end);

    return FinancialReportSnapshot(
      period: period,
      assets: assets,
      liabilities: liabilities,
      income: pnl.income,
      expenses: pnl.expenses,
      operatingCashFlow: cash.operating,
      investingCashFlow: cash.investing,
      financingCashFlow: cash.financing,
      otherCashFlow: cash.other,
      fxEffect: fxEffect,
      cashChange: cashChange,
      assetAllocation: assetAllocation,
      expenseAllocation: expenseAllocation,
      expenseDetails: grouped.details,
      monthlyTrend: monthlyTrend,
      issues: List.unmodifiable(_issues),
    );
  }

  int _accountBalanceAt(Account account, DateTime asOf) {
    if (account.effectiveOpeningBalanceDate.isAfter(asOf)) return 0;
    var total = account.openingBalanceMinor;
    total += data.balanceAdjustments
        .where(
          (item) => item.accountId == account.id && !item.date.isAfter(asOf),
        )
        .fold(0, (sum, item) => sum + item.amountMinor);
    total += data.incomes
        .where(
          (item) => item.accountId == account.id && !item.date.isAfter(asOf),
        )
        .fold(0, (sum, item) => sum + item.amountMinor);
    total -= data.expenses
        .where(
          (item) =>
              !item.isCreditCard &&
              item.paymentMethod != PaymentMethod.telecomBill &&
              item.accountId == account.id &&
              !item.date.isAfter(asOf),
        )
        .fold(0, (sum, item) => sum + item.amountMinor);
    for (final tx in data.investmentTransactions.where(
      (item) => !item.date.isAfter(asOf),
    )) {
      final gross = tx.grossMinor;
      if ((tx.type == InvestmentTransactionType.buy ||
              tx.type == InvestmentTransactionType.subscribe) &&
          tx.debitAccountId == account.id) {
        total -= gross + tx.feeMinor + tx.taxMinor;
      } else if ((tx.type == InvestmentTransactionType.sell ||
              tx.type == InvestmentTransactionType.redeem ||
              tx.type == InvestmentTransactionType.dividend) &&
          tx.creditAccountId == account.id) {
        total += gross - tx.feeMinor - tx.taxMinor;
      }
    }
    final paymentBillIds = <String>{};
    for (final payment in data.transactions.where(
      (item) =>
          item.type == FinancialTransactionType.cardPayment &&
          item.relatedEntityType == 'cardBill' &&
          !item.date.isAfter(asOf),
    )) {
      if (payment.relatedEntityId != null) {
        paymentBillIds.add(payment.relatedEntityId!);
      }
      total += payment.impacts
          .where((impact) => impact.accountId == account.id)
          .fold(0, (sum, impact) => sum + impact.amountMinor);
    }
    for (final bill in data.bills.where(
      (item) => item.paidMinor > 0 && !paymentBillIds.contains(item.id),
    )) {
      final card = data.cards
          .where((item) => item.id == bill.cardId)
          .firstOrNull;
      final paidAt = bill.paidAt ?? bill.autoDebitDate;
      if (card?.debitAccountId == account.id && !paidAt.isAfter(asOf)) {
        total -= bill.paidMinor;
      }
    }
    for (final payment in data.telecomBillPayments.where(
      (item) => !item.paidAt.isAfter(asOf),
    )) {
      if (payment.debitAccountId == account.id) total -= payment.amountMinor;
    }
    for (final order in data.orders) {
      for (final participant in order.participants) {
        if (!participant.isSelf &&
            participant.collectionAccountId == account.id &&
            participant.collectedAt != null &&
            !participant.collectedAt!.isAfter(asOf)) {
          total += participant.dueMinor;
        }
      }
    }
    return total;
  }

  int _totalCashAt(DateTime asOf) => data.accounts.fold(0, (sum, account) {
    final native = _accountBalanceAt(account, asOf);
    return sum + _convert(native, account.currency, asOf);
  });

  int _receivablesAt(DateTime asOf) => data.orders
      .where((order) => !order.date.isAfter(asOf))
      .fold(
        0,
        (sum, order) =>
            sum +
            order.participants
                .where((participant) {
                  if (participant.isSelf) return false;
                  if (participant.cancelledAt != null &&
                      !participant.cancelledAt!.isAfter(asOf)) {
                    return false;
                  }
                  return participant.collectedAt == null ||
                      participant.collectedAt!.isAfter(asOf);
                })
                .fold(
                  0,
                  (subtotal, participant) => subtotal + participant.dueMinor,
                ),
      );

  int _cardLiabilityAt(DateTime asOf) {
    final charges =
        data.expenses
            .where((item) => item.isCreditCard && !item.date.isAfter(asOf))
            .fold(0, (sum, item) => sum + item.amountMinor) +
        data.orders
            .where((item) => !item.date.isAfter(asOf))
            .fold(0, (sum, item) => sum + item.totalMinor);
    final paymentTransactions = data.transactions.where(
      (item) =>
          item.type == FinancialTransactionType.cardPayment &&
          item.relatedEntityType == 'cardBill' &&
          !item.date.isAfter(asOf),
    );
    final transactionBillIds = paymentTransactions
        .map((item) => item.relatedEntityId)
        .whereType<String>()
        .toSet();
    final payments =
        paymentTransactions.fold(0, (sum, item) => sum + item.amountMinor) +
        data.bills
            .where((item) {
              final paidAt = item.paidAt ?? item.autoDebitDate;
              return item.paidMinor > 0 &&
                  !transactionBillIds.contains(item.id) &&
                  !paidAt.isAfter(asOf);
            })
            .fold(0, (sum, item) => sum + item.paidMinor);
    final reconciliation = data.transactions
        .where(
          (item) =>
              item.relatedEntityType == 'cardBillReconciliation' &&
              !item.date.isAfter(asOf),
        )
        .expand((item) => item.impacts)
        .where(
          (impact) => data.accounts.any(
            (account) =>
                account.id == impact.accountId &&
                account.kind == FinancialAccountKind.liability,
          ),
        )
        .fold(0, (sum, impact) => sum + impact.amountMinor);
    return (charges + reconciliation - payments).clamp(0, 1 << 62).toInt();
  }

  int _telecomLiabilityAt(DateTime asOf) {
    final paidIds = <String>{
      for (final payment in data.telecomBillPayments)
        if (!payment.paidAt.isAfter(asOf)) ...payment.expenseIds,
    };
    return data.expenses
        .where(
          (item) =>
              item.paymentMethod == PaymentMethod.telecomBill &&
              !item.date.isAfter(asOf) &&
              !paidIds.contains(item.id),
        )
        .fold(0, (sum, item) => sum + item.amountMinor);
  }

  Holding _holdingAt(String productId, DateTime asOf) {
    final events =
        <
            ({
              DateTime date,
              InvestmentTransaction? tx,
              InvestmentAdjustment? adjustment,
            })
          >[
            ...data.investmentTransactions
                .where(
                  (item) =>
                      item.productId == productId && !item.date.isAfter(asOf),
                )
                .map((item) => (date: item.date, tx: item, adjustment: null)),
            ...data.investmentAdjustments
                .where(
                  (item) =>
                      item.productId == productId && !item.date.isAfter(asOf),
                )
                .map((item) => (date: item.date, tx: null, adjustment: item)),
          ]
          ..sort((a, b) => a.date.compareTo(b.date));
    var quantity = 0;
    var averageCost = 0;
    for (final event in events) {
      if (event.adjustment case final adjustment?) {
        quantity = adjustment.quantityMicros;
        averageCost = adjustment.averageCostMinor;
        continue;
      }
      final tx = event.tx!;
      switch (tx.type) {
        case InvestmentTransactionType.buy:
        case InvestmentTransactionType.subscribe:
        case InvestmentTransactionType.transferIn:
          final cost = tx.type == InvestmentTransactionType.transferIn
              ? tx.grossMinor
              : tx.grossMinor + tx.feeMinor + tx.taxMinor;
          final totalCost = (quantity * averageCost / 1000000).round() + cost;
          quantity += tx.quantityMicros;
          averageCost = quantity == 0
              ? 0
              : (totalCost * 1000000 / quantity).round();
        case InvestmentTransactionType.sell:
        case InvestmentTransactionType.redeem:
        case InvestmentTransactionType.transferOut:
          quantity = (quantity - tx.quantityMicros).clamp(0, 1 << 62);
          if (quantity == 0) averageCost = 0;
        case InvestmentTransactionType.dividend:
          break;
      }
    }
    return Holding(
      productId: productId,
      quantityMicros: quantity,
      averageCostMinor: averageCost,
    );
  }

  ({int priceMinor, bool estimated}) _priceAt(
    InvestmentProduct product,
    DateTime asOf,
  ) {
    final points =
        data.investmentPriceHistory
            .where((item) => item.productId == product.id)
            .toList()
          ..sort((a, b) => a.date.compareTo(b.date));
    final prior = points.where((item) => !item.date.isAfter(asOf)).lastOrNull;
    if (prior != null) {
      return (priceMinor: prior.priceMinor, estimated: prior.estimated);
    }
    final fallback = points.firstOrNull;
    if (fallback != null) {
      _addIssue('「${product.name}」截止日前無價格，已使用 ${_date(fallback.date)} 價格推估。');
      return (priceMinor: fallback.priceMinor, estimated: true);
    }
    _addIssue('「${product.name}」無歷史價格，已使用目前價格推估。');
    return (priceMinor: product.currentPriceMinor, estimated: true);
  }

  /// Groups the period's income/expenses by category. When [details] is
  /// given, every expense contribution is also recorded there (per category)
  /// so the pie chart can list the transactions behind each slice.
  ({List<StatementLine> income, List<StatementLine> expenses}) _profitAndLoss(
    ReportPeriod period, {
    Map<String, List<ExpenseDetail>>? details,
  }) {
    final income = <String, int>{};
    final expenses = <String, int>{};
    void addExpense(String category, int amount, DateTime date, String item) {
      expenses.update(
        category,
        (value) => value + amount,
        ifAbsent: () => amount,
      );
      details?.putIfAbsent(category, () => []).add(
        ExpenseDetail(date: date, item: item, amountMinor: amount),
      );
    }
    for (final item in data.incomes.where(
      (item) => period.contains(item.date),
    )) {
      final account = data.accounts
          .where((account) => account.id == item.accountId)
          .firstOrNull;
      final currency = account?.currency ?? data.settings.defaultCurrency;
      income.update(
        item.category,
        (value) => value + _convert(item.amountMinor, currency, item.date),
        ifAbsent: () => _convert(item.amountMinor, currency, item.date),
      );
    }
    for (final item in data.expenses.where(
      (item) => period.contains(item.date),
    )) {
      addExpense(
        item.category,
        _convert(item.amountMinor, 'TWD', item.date),
        item.date,
        item.item.trim().isNotEmpty
            ? item.item.trim()
            : (item.merchant.trim().isNotEmpty ? item.merchant.trim() : '未命名'),
      );
    }
    for (final order in data.orders.where(
      (item) => period.contains(item.date),
    )) {
      if (order.selfExpenseMinor > 0) {
        addExpense(
          _orderSelfExpenseCategoryName(order),
          order.selfExpenseMinor,
          order.date,
          order.name.trim().isNotEmpty ? '代訂：${order.name.trim()}' : '代訂',
        );
      }
      for (final participant in order.participants.where(
        (item) =>
            !item.isSelf &&
            item.collectedAt != null &&
            period.contains(item.collectedAt!),
      )) {
        final result = participant.collectionResultMinor;
        if (result >= 0) {
          income.update(
            '代收差額',
            (value) => value + result.abs(),
            ifAbsent: () => result.abs(),
          );
        } else {
          addExpense(
            '代收差額',
            result.abs(),
            participant.collectedAt!,
            '代收差額：${participant.name}${order.name.trim().isNotEmpty ? '（${order.name.trim()}）' : ''}',
          );
        }
      }
    }
    for (final product in data.products) {
      var holding = const Holding(
        productId: '',
        quantityMicros: 0,
        averageCostMinor: 0,
      );
      final txs =
          data.investmentTransactions
              .where(
                (item) =>
                    item.productId == product.id &&
                    !item.date.isAfter(period.end),
              )
              .toList()
            ..sort((a, b) => a.date.compareTo(b.date));
      for (final tx in txs) {
        if (tx.type == InvestmentTransactionType.dividend &&
            period.contains(tx.date)) {
          final net = tx.grossMinor - tx.feeMinor - tx.taxMinor;
          income.update(
            '股息收入',
            (value) => value + _convert(net, product.currency, tx.date),
            ifAbsent: () => _convert(net, product.currency, tx.date),
          );
        }
        if (tx.type == InvestmentTransactionType.buy ||
            tx.type == InvestmentTransactionType.subscribe ||
            tx.type == InvestmentTransactionType.transferIn) {
          final cost = tx.type == InvestmentTransactionType.transferIn
              ? tx.grossMinor
              : tx.grossMinor + tx.feeMinor + tx.taxMinor;
          final totalCost =
              (holding.quantityMicros * holding.averageCostMinor / 1000000)
                  .round() +
              cost;
          final quantity = holding.quantityMicros + tx.quantityMicros;
          holding = Holding(
            productId: product.id,
            quantityMicros: quantity,
            averageCostMinor: quantity == 0
                ? 0
                : (totalCost * 1000000 / quantity).round(),
          );
        } else if (tx.type == InvestmentTransactionType.sell ||
            tx.type == InvestmentTransactionType.redeem) {
          final basis = (tx.quantityMicros * holding.averageCostMinor / 1000000)
              .round();
          final result = tx.grossMinor - tx.feeMinor - tx.taxMinor - basis;
          if (period.contains(tx.date)) {
            final amount = _convert(result.abs(), product.currency, tx.date);
            if (result >= 0) {
              income.update(
                '已實現投資利得',
                (value) => value + amount,
                ifAbsent: () => amount,
              );
            } else {
              addExpense('已實現投資損失', amount, tx.date, '${product.name} 賣出損失');
            }
          }
          final quantity = (holding.quantityMicros - tx.quantityMicros).clamp(
            0,
            1 << 62,
          );
          holding = Holding(
            productId: product.id,
            quantityMicros: quantity,
            averageCostMinor: quantity == 0 ? 0 : holding.averageCostMinor,
          );
        }
      }
    }
    return (income: _lines(income), expenses: _lines(expenses));
  }

  ({
    List<StatementLine> operating,
    List<StatementLine> investing,
    List<StatementLine> financing,
    List<StatementLine> other,
  })
  _cashFlow(ReportPeriod period) {
    final operating = <String, int>{};
    final investing = <String, int>{};
    final other = <String, int>{};
    void add(Map<String, int> target, String key, int amount) =>
        target.update(key, (value) => value + amount, ifAbsent: () => amount);
    for (final account in data.accounts) {
      if (period.contains(account.effectiveOpeningBalanceDate) &&
          account.openingBalanceMinor != 0) {
        add(
          other,
          '期初餘額建立',
          _convert(
            account.openingBalanceMinor,
            account.currency,
            account.effectiveOpeningBalanceDate,
          ),
        );
      }
    }
    for (final item in data.incomes.where(
      (item) => period.contains(item.date),
    )) {
      final account = data.accounts
          .where((a) => a.id == item.accountId)
          .firstOrNull;
      add(
        operating,
        '一般收入',
        _convert(
          item.amountMinor,
          account?.currency ?? data.settings.defaultCurrency,
          item.date,
        ),
      );
    }
    for (final item in data.expenses.where(
      (item) =>
          !item.isCreditCard &&
          item.paymentMethod != PaymentMethod.telecomBill &&
          period.contains(item.date),
    )) {
      add(operating, '現金支出', -_convert(item.amountMinor, 'TWD', item.date));
    }
    for (final item in data.balanceAdjustments.where(
      (item) => period.contains(item.date),
    )) {
      final account = data.accounts
          .where((a) => a.id == item.accountId)
          .firstOrNull;
      add(
        other,
        '餘額調整',
        _convert(
          item.amountMinor,
          account?.currency ?? data.settings.defaultCurrency,
          item.date,
        ),
      );
    }
    final paymentBillIds = <String>{};
    for (final payment in data.transactions.where(
      (item) =>
          item.type == FinancialTransactionType.cardPayment &&
          item.relatedEntityType == 'cardBill',
    )) {
      if (payment.relatedEntityId != null) {
        paymentBillIds.add(payment.relatedEntityId!);
      }
      if (period.contains(payment.date)) {
        add(
          operating,
          '信用卡繳款',
          -_convert(payment.amountMinor, payment.currency, payment.date),
        );
      }
    }
    for (final bill in data.bills.where(
      (item) => item.paidMinor > 0 && !paymentBillIds.contains(item.id),
    )) {
      final paidAt = bill.paidAt ?? bill.autoDebitDate;
      if (period.contains(paidAt)) {
        add(operating, '信用卡繳款', -_convert(bill.paidMinor, 'TWD', paidAt));
      }
    }
    for (final payment in data.telecomBillPayments.where(
      (item) => period.contains(item.paidAt),
    )) {
      add(
        operating,
        '電信帳單繳款',
        -_convert(payment.amountMinor, 'TWD', payment.paidAt),
      );
    }
    for (final order in data.orders) {
      for (final participant in order.participants.where(
        (item) =>
            !item.isSelf &&
            item.collectedAt != null &&
            period.contains(item.collectedAt!),
      )) {
        add(
          operating,
          '代收款入帳',
          _convert(participant.dueMinor, 'TWD', participant.collectedAt!),
        );
      }
    }
    for (final tx in data.investmentTransactions.where(
      (item) => period.contains(item.date),
    )) {
      final product = data.products
          .where((item) => item.id == tx.productId)
          .firstOrNull;
      final currency = product?.currency ?? data.settings.defaultCurrency;
      switch (tx.type) {
        case InvestmentTransactionType.buy:
        case InvestmentTransactionType.subscribe:
          add(
            investing,
            '買入投資',
            -_convert(
              tx.grossMinor + tx.feeMinor + tx.taxMinor,
              currency,
              tx.date,
            ),
          );
        case InvestmentTransactionType.sell:
        case InvestmentTransactionType.redeem:
          add(
            investing,
            '出售投資',
            _convert(
              tx.grossMinor - tx.feeMinor - tx.taxMinor,
              currency,
              tx.date,
            ),
          );
        case InvestmentTransactionType.dividend:
          add(
            operating,
            '股息收款',
            _convert(
              tx.grossMinor - tx.feeMinor - tx.taxMinor,
              currency,
              tx.date,
            ),
          );
        case InvestmentTransactionType.transferIn:
        case InvestmentTransactionType.transferOut:
          break;
      }
    }
    return (
      operating: _signedLines(operating),
      investing: _signedLines(investing),
      financing: const [],
      other: _signedLines(other),
    );
  }

  ({List<ChartSlice> slices, Map<String, List<ExpenseDetail>> details})
  _groupExpenses(ReportPeriod period) {
    final rawDetails = <String, List<ExpenseDetail>>{};
    final pnl = _profitAndLoss(period, details: rawDetails);
    final values = [
      for (final line in pnl.expenses) ChartSlice(line.label, line.amountMinor),
    ]..sort((a, b) => b.amountMinor.compareTo(a.amountMinor));
    int newestFirst(ExpenseDetail a, ExpenseDetail b) {
      final byDate = b.date.compareTo(a.date);
      return byDate != 0 ? byDate : b.amountMinor.compareTo(a.amountMinor);
    }

    if (values.length <= 6) {
      return (
        slices: values,
        details: {
          for (final slice in values)
            slice.label: [...?rawDetails[slice.label]]..sort(newestFirst),
        },
      );
    }
    final kept = values.take(5).toList();
    final rest = values.skip(5).toList();
    kept.add(
      ChartSlice('其他', rest.fold(0, (sum, item) => sum + item.amountMinor)),
    );
    final details = <String, List<ExpenseDetail>>{
      for (final slice in kept.take(5))
        slice.label: [...?rawDetails[slice.label]],
    };
    // The merged 其他 slice lists every transaction of the folded-in
    // categories, with the original category shown in the item text.
    details.putIfAbsent('其他', () => []).addAll([
      for (final slice in rest)
        for (final detail
            in rawDetails[slice.label] ?? const <ExpenseDetail>[])
          ExpenseDetail(
            date: detail.date,
            item: '${detail.item}（${slice.label}）',
            amountMinor: detail.amountMinor,
          ),
    ]);
    for (final list in details.values) {
      list.sort(newestFirst);
    }
    return (slices: kept, details: details);
  }

  List<MonthlyReportPoint> _monthlyTrend(DateTime end) {
    final result = <MonthlyReportPoint>[];
    final lastMonth = DateTime(end.year, end.month);
    for (var offset = 11; offset >= 0; offset--) {
      final month = DateTime(lastMonth.year, lastMonth.month - offset);
      final next = DateTime(month.year, month.month + 1);
      final pnl = _profitAndLoss(
        ReportPeriod(start: month, end: next.subtract(const Duration(days: 1))),
      );
      result.add(
        MonthlyReportPoint(
          month: month,
          incomeMinor: pnl.income.fold(
            0,
            (sum, line) => sum + line.amountMinor,
          ),
          expenseMinor: pnl.expenses.fold(
            0,
            (sum, line) => sum + line.amountMinor,
          ),
        ),
      );
    }
    return result;
  }

  int _convert(int amount, String currency, DateTime at) {
    if (currency == data.settings.defaultCurrency) return amount;
    final rates =
        data.settings.fxRates
            .where(
              (rate) =>
                  rate.from == currency &&
                  rate.to == data.settings.defaultCurrency,
            )
            .toList()
          ..sort((a, b) => a.updatedAt.compareTo(b.updatedAt));
    final rate = rates.where((item) => !item.updatedAt.isAfter(at)).lastOrNull;
    final selected = rate ?? rates.firstOrNull;
    if (selected == null) {
      _addIssue('缺少 $currency 對 ${data.settings.defaultCurrency} 匯率，該金額未換算。');
      return 0;
    }
    if (rate == null) {
      _addIssue('$currency 截止日前無匯率，已使用 ${_date(selected.updatedAt)} 匯率推估。');
    }
    return (amount * selected.rateMicros / 1000000).round();
  }

  bool _isEstimatedRate(String currency, DateTime at) {
    if (currency == data.settings.defaultCurrency) return false;
    return !data.settings.fxRates.any(
      (rate) =>
          rate.from == currency &&
          rate.to == data.settings.defaultCurrency &&
          !rate.updatedAt.isAfter(at),
    );
  }

  List<StatementLine> _lines(Map<String, int> values) =>
      values.entries
          .where((entry) => entry.value != 0)
          .map(
            (entry) =>
                StatementLine(label: entry.key, amountMinor: entry.value.abs()),
          )
          .toList()
        ..sort((a, b) => b.amountMinor.compareTo(a.amountMinor));

  List<StatementLine> _signedLines(Map<String, int> values) =>
      values.entries
          .where((entry) => entry.value != 0)
          .map(
            (entry) =>
                StatementLine(label: entry.key, amountMinor: entry.value),
          )
          .toList()
        ..sort((a, b) => b.amountMinor.abs().compareTo(a.amountMinor.abs()));

  void _addIssue(String message) {
    if (_issues.any((issue) => issue.message == message)) return;
    _issues.add(ReportDataQualityIssue(message: message));
  }

  String _date(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
}
