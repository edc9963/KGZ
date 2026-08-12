import 'package:flutter_test/flutter_test.dart';
import 'package:quick_ledger/domain/financial_reports.dart';
import 'package:quick_ledger/domain/models.dart';

void main() {
  group('financial reports', () {
    test(
      'income and cash expense reconcile profit, cash, and balance sheet',
      () {
        final january = ReportPeriod(
          start: DateTime(2026, 1, 1),
          end: DateTime(2026, 1, 31),
        );
        final data = AppData(
          accounts: [_account(opening: 100000)],
          incomes: [
            IncomeEntry(
              id: 'salary',
              userId: 'u',
              date: DateTime(2026, 1, 10),
              amountMinor: 50000,
              item: '薪資',
              category: '薪資',
              accountId: 'bank',
              note: '',
            ),
          ],
          expenses: [
            Expense(
              id: 'food',
              userId: 'u',
              date: DateTime(2026, 1, 12),
              amountMinor: 10000,
              paymentMethod: PaymentMethod.transfer,
              item: '餐飲',
              category: '餐飲',
              accountId: 'bank',
              merchant: '',
              note: '',
              isNecessary: true,
            ),
          ],
        );

        final report = FinancialReportService(data).build(january);

        expect(report.totalIncome, 50000);
        expect(report.totalExpenses, 10000);
        expect(report.netIncome, 40000);
        expect(report.totalAssets, 140000);
        expect(report.totalLiabilities, 0);
        expect(report.cashChange, 140000);
        expect(report.cashFlowBalances, isTrue);
        expect(report.balanceSheetBalances, isTrue);
      },
    );

    test('credit card liability uses transaction and actual payment dates', () {
      final data = AppData(
        accounts: [_account(opening: 100000)],
        cards: const [
          CreditCard(
            id: 'card',
            userId: 'u',
            name: '卡',
            bank: '銀行',
            lastFour: '1234',
            closingDay: 20,
            dueDay: 5,
            autoDebitDay: 5,
            debitAccountId: 'bank',
            isActive: true,
            note: '',
          ),
        ],
        expenses: [
          Expense(
            id: 'card-expense',
            userId: 'u',
            date: DateTime(2026, 1, 15),
            amountMinor: 20000,
            paymentMethod: PaymentMethod.creditCard,
            item: '採買',
            category: '購物',
            cardId: 'card',
            merchant: '',
            note: '',
            isNecessary: false,
          ),
        ],
        bills: [
          CardBill(
            id: 'bill',
            userId: 'u',
            cardId: 'card',
            month: '2026-01',
            chargeIds: const ['expense:card-expense'],
            manualAdjustmentMinor: 0,
            paidMinor: 20000,
            dueDate: DateTime(2026, 2, 5),
            autoDebitDate: DateTime(2026, 2, 5),
            paidAt: DateTime(2026, 2, 8),
            note: '',
          ),
        ],
      );

      final january = FinancialReportService(data).build(
        ReportPeriod(start: DateTime(2026, 1, 1), end: DateTime(2026, 1, 31)),
      );
      final february = FinancialReportService(data).build(
        ReportPeriod(start: DateTime(2026, 2, 1), end: DateTime(2026, 2, 28)),
      );

      expect(january.totalLiabilities, 20000);
      expect(january.totalExpenses, 20000);
      expect(february.totalLiabilities, 0);
      expect(february.cashChange, -20000);
      expect(february.cashFlowBalances, isTrue);
    });

    test('telecom charges are expensed once and paid as later cash flow', () {
      final data = AppData(
        accounts: [_account(opening: 100000)],
        expenses: [
          Expense(
            id: 'monthly-fee',
            userId: 'u',
            date: DateTime(2026, 1, 31),
            amountMinor: 59900,
            paymentMethod: PaymentMethod.telecomBill,
            item: '手機月租',
            category: '訂閱',
            merchant: '',
            note: '',
            isNecessary: true,
          ),
          Expense(
            id: 'carrier-purchase',
            userId: 'u',
            date: DateTime(2026, 1, 20),
            amountMinor: 10000,
            paymentMethod: PaymentMethod.telecomBill,
            item: 'App 代收',
            category: '娛樂',
            merchant: '',
            note: '',
            isNecessary: false,
          ),
        ],
        telecomBillPayments: [
          TelecomBillPayment(
            id: 'phone-payment',
            userId: 'u',
            recurringExpenseId: 'phone',
            month: '2026-02',
            expenseIds: const ['monthly-fee', 'carrier-purchase'],
            amountMinor: 69900,
            paidAt: DateTime(2026, 2, 5),
            debitAccountId: 'bank',
            balanceInsufficient: false,
          ),
        ],
      );

      final january = FinancialReportService(data).build(
        ReportPeriod(start: DateTime(2026, 1, 1), end: DateTime(2026, 1, 31)),
      );
      final february = FinancialReportService(data).build(
        ReportPeriod(start: DateTime(2026, 2, 1), end: DateTime(2026, 2, 28)),
      );

      expect(january.totalExpenses, 69900);
      expect(january.totalLiabilities, 69900);
      expect(february.totalExpenses, 0);
      expect(february.totalLiabilities, 0);
      expect(february.cashChange, -69900);
      expect(february.cashFlowBalances, isTrue);
    });

    test(
      'moving average sale creates realized gain and keeps market value',
      () {
        final data = AppData(
          accounts: [_account(opening: 100000)],
          products: [
            InvestmentProduct(
              id: 'fund',
              userId: 'u',
              symbol: 'F',
              name: '基金',
              type: '基金',
              currency: 'TWD',
              currentPriceMinor: 12000,
              priceUpdatedAt: DateTime(2026, 1, 31),
              note: '',
            ),
          ],
          investmentPriceHistory: [
            InvestmentPricePoint(
              productId: 'fund',
              priceMinor: 12000,
              date: DateTime(2026, 1, 31),
            ),
          ],
          investmentTransactions: [
            InvestmentTransaction(
              id: 'buy',
              userId: 'u',
              date: DateTime(2026, 1, 5),
              type: InvestmentTransactionType.buy,
              productId: 'fund',
              quantityMicros: 1000000,
              priceMinor: 10000,
              feeMinor: 0,
              taxMinor: 0,
              debitAccountId: 'bank',
              note: '',
            ),
            InvestmentTransaction(
              id: 'sell',
              userId: 'u',
              date: DateTime(2026, 1, 20),
              type: InvestmentTransactionType.sell,
              productId: 'fund',
              quantityMicros: 500000,
              priceMinor: 15000,
              feeMinor: 0,
              taxMinor: 0,
              creditAccountId: 'bank',
              note: '',
            ),
          ],
        );

        final report = FinancialReportService(data).build(
          ReportPeriod(start: DateTime(2026, 1, 1), end: DateTime(2026, 1, 31)),
        );

        expect(
          report.income
              .singleWhere((line) => line.label == '已實現投資利得')
              .amountMinor,
          2500,
        );
        expect(report.totalAssets, 103500);
        expect(report.cashFlowBalances, isTrue);
      },
    );

    test(
      'receivable remains at an earlier cutoff and clears on collection',
      () {
        final order = GroupOrder(
          id: 'order',
          userId: 'u',
          name: '代訂',
          date: DateTime(2026, 1, 20),
          platform: '店家',
          cardId: 'card',
          totalMinor: 3000,
          deliveryFeeMinor: 0,
          serviceFeeMinor: 0,
          discountMinor: 0,
          splitMethod: SplitMethod.equal,
          note: '',
          participants: [
            OrderParticipant(
              id: 'friend',
              name: '朋友',
              isSelf: false,
              itemName: '餐點',
              itemAmountMinor: 3000,
              sharedFeeMinor: 0,
              discountMinor: 0,
              status: CollectionStatus.paid,
              collectionMethod: collectionMethodBankTransfer,
              collectionAccountId: 'bank',
              token: 'token',
              collectedAt: DateTime(2026, 2, 10),
              note: '',
            ),
          ],
        );
        final data = AppData(accounts: [_account(opening: 0)], orders: [order]);

        final january = FinancialReportService(data).build(
          ReportPeriod(start: DateTime(2026, 1, 1), end: DateTime(2026, 1, 31)),
        );
        final february = FinancialReportService(data).build(
          ReportPeriod(start: DateTime(2026, 2, 1), end: DateTime(2026, 2, 28)),
        );

        expect(january.assets.any((line) => line.label == '代收應收款'), isTrue);
        expect(february.assets.any((line) => line.label == '代收應收款'), isFalse);
        expect(february.cashChange, 3000);
        expect(february.cashFlowBalances, isTrue);
      },
    );

    test('net worth trend returns stable month-end snapshots', () {
      final data = AppData(
        accounts: [_account(opening: 100000)],
        incomes: [
          IncomeEntry(
            id: 'salary',
            userId: 'u',
            date: DateTime(2026, 2, 10),
            amountMinor: 50000,
            item: '薪資',
            category: '薪資',
            accountId: 'bank',
            note: '',
          ),
        ],
      );

      final trend = FinancialReportService(
        data,
      ).netWorthTrend(DateTime(2026, 3, 15), months: 3);

      expect(trend.map((point) => point.month.month), [1, 2, 3]);
      expect(trend.map((point) => point.amountMinor), [100000, 150000, 150000]);
    });
  });
}

Account _account({required int opening}) => Account(
  id: 'bank',
  userId: 'u',
  name: '銀行',
  institution: '',
  type: '銀行帳戶',
  currency: 'TWD',
  openingBalanceMinor: opening,
  isActive: true,
  note: '',
  createdAt: DateTime(2026, 1, 1),
  updatedAt: DateTime(2026, 1, 1),
  openingBalanceDate: DateTime(2026, 1, 1),
);
