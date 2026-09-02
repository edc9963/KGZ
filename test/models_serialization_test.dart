import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:quick_ledger/data/local_repositories.dart';
import 'package:quick_ledger/data/repositories.dart';
import 'package:quick_ledger/domain/models.dart';

void main() {
  test(
    'payment card type round-trips and legacy cards remain credit cards',
    () {
      const debit = CreditCard(
        id: 'debit',
        userId: 'user',
        name: '金融卡',
        bank: '銀行',
        lastFour: '1234',
        closingDay: 1,
        dueDay: 1,
        autoDebitDay: 1,
        debitAccountId: 'bank',
        isActive: true,
        note: '',
        cardType: PaymentCardType.debit,
      );

      expect(
        CreditCard.fromJson(debit.toJson()).cardType,
        PaymentCardType.debit,
      );
      final legacyJson = Map<String, dynamic>.from(debit.toJson())
        ..remove('cardType');
      expect(CreditCard.fromJson(legacyJson).cardType, PaymentCardType.credit);
    },
  );

  test('AppData round-trips versioned JSON', () {
    final now = DateTime(2026, 7, 28);
    final original = AppData(
      settings: UserSettings(
        defaultCurrency: 'TWD',
        fxRates: [
          FxRate(from: 'USD', to: 'TWD', rateMicros: 32680000, updatedAt: now),
        ],
      ),
      accounts: [
        Account(
          id: 'a',
          userId: 'u',
          name: '帳戶',
          institution: '銀行',
          type: '銀行帳戶',
          currency: 'TWD',
          openingBalanceMinor: 12345,
          isActive: true,
          note: '測試',
          createdAt: now,
          updatedAt: now,
        ),
      ],
      incomes: [
        IncomeEntry(
          id: 'income',
          userId: 'u',
          date: now,
          amountMinor: 50000,
          item: '薪資',
          category: '薪資',
          accountId: 'a',
          note: '',
        ),
      ],
      recurringExpenses: [
        const RecurringExpense(
          id: 'phone',
          userId: 'u',
          item: '手機月租',
          category: '訂閱',
          amountMinor: 59900,
          paymentMethod: PaymentMethod.telecomBill,
          dayOfMonth: 31,
          startMonth: '2026-07',
          telecomDebitAccountId: 'a',
          isActive: true,
          isNecessary: true,
          note: '',
        ),
      ],
      recurringExpenseOccurrences: [
        RecurringExpenseOccurrence(
          id: 'occurrence',
          userId: 'u',
          recurringExpenseId: 'phone',
          month: '2026-07',
          expenseId: 'monthly-fee',
          scheduledDate: now,
        ),
      ],
      telecomBillPayments: [
        TelecomBillPayment(
          id: 'payment',
          userId: 'u',
          recurringExpenseId: 'phone',
          month: '2026-07',
          expenseIds: const ['monthly-fee'],
          amountMinor: 59900,
          paidAt: now,
          debitAccountId: 'a',
          balanceInsufficient: false,
        ),
      ],
    );
    final restored = AppData.fromJson(
      jsonDecode(jsonEncode(original.toJson())) as Json,
    );
    expect(restored.schemaVersion, 9);
    expect(restored.accounts.single.name, '帳戶');
    expect(restored.accounts.single.openingBalanceMinor, 12345);
    expect(restored.settings.fxRates.single.rateMicros, 32680000);
    expect(restored.incomes.single.item, '薪資');
    expect(restored.recurringExpenses.single.dayOfMonth, 31);
    expect(restored.telecomBillPayments.single.expenseIds, ['monthly-fee']);
  });

  test('corrupt optional lists fall back to empty lists', () {
    final restored = AppData.fromJson({
      'schemaVersion': 1,
      'settings': <String, dynamic>{},
    });
    expect(restored.accounts, isEmpty);
    expect(restored.orders, isEmpty);
  });

  test('v8 bills migrate actual totals and reconciliation metadata', () {
    final migrated = migrateLocalFinanceJson({
      'schemaVersion': 8,
      'settings': <String, dynamic>{},
      'transactions': <dynamic>[],
      'accounts': <dynamic>[],
      'cards': <dynamic>[],
      'expenses': [
        {'id': 'expense', 'amountMinor': 10000},
      ],
      'orders': <dynamic>[],
      'bills': [
        {
          'id': 'bill',
          'userId': 'user',
          'cardId': 'card',
          'month': '2026-08',
          'chargeIds': ['expense:expense'],
          'manualAdjustmentMinor': -500,
          'paidMinor': 0,
          'dueDate': '2026-09-15T00:00:00.000',
          'autoDebitDate': '2026-09-15T00:00:00.000',
          'note': '舊回饋',
        },
      ],
    });
    final bill = (migrated['bills'] as List).single as Map;
    expect(migrated['schemaVersion'], 9);
    expect(bill['statementAmountMinor'], 9500);
    expect(bill['reconciliationReason'], 'legacyAdjustment');
    expect(bill['reconciliationNote'], '舊回饋');
  });

  test(
    'legacy participant discount is preserved as a fixed eligible share',
    () {
      final participant = OrderParticipant.fromJson({
        'id': 'p1',
        'name': '舊參與者',
        'isSelf': false,
        'itemName': '餐點',
        'itemAmountMinor': 10000,
        'sharedFeeMinor': 0,
        'discountMinor': 500,
        'status': 'unpaid',
        'token': 'token',
      });

      expect(participant.discountEligible, isTrue);
      expect(participant.discountIsFixed, isTrue);
      expect(participant.discountMinor, 500);
    },
  );

  test('legacy group orders keep exact remainder rounding policy', () {
    final order = GroupOrder.fromJson({
      'id': 'legacy-order',
      'userId': 'u',
      'name': '舊代訂',
      'date': DateTime(2026, 7, 29).toIso8601String(),
      'platform': '店家',
      'cardId': 'card',
      'totalMinor': 10000,
      'deliveryFeeMinor': 0,
      'serviceFeeMinor': 0,
      'discountMinor': 0,
      'splitMethod': 'equal',
      'participants': <dynamic>[],
    });

    expect(order.feeRoundingPolicy, FeeRoundingPolicy.exactRemainder);
  });

  test('v4 migration backfills report history metadata', () {
    final migrated = migrateLocalFinanceJson({
      'schemaVersion': 4,
      'settings': <String, dynamic>{},
      'accounts': [
        {
          'id': 'bank',
          'userId': 'u',
          'name': '銀行',
          'institution': '',
          'type': '銀行帳戶',
          'currency': 'TWD',
          'openingBalanceMinor': 100,
          'isActive': true,
          'note': '',
          'createdAt': '2026-01-01T00:00:00.000Z',
          'updatedAt': '2026-01-02T00:00:00.000Z',
        },
      ],
      'bills': [
        {
          'id': 'bill',
          'userId': 'u',
          'cardId': 'card',
          'month': '2026-01',
          'chargeIds': <dynamic>[],
          'manualAdjustmentMinor': 0,
          'paidMinor': 100,
          'dueDate': '2026-02-01T00:00:00.000Z',
          'autoDebitDate': '2026-02-02T00:00:00.000Z',
          'note': '',
        },
      ],
      'products': [
        {
          'id': 'fund',
          'userId': 'u',
          'symbol': 'F',
          'name': '基金',
          'type': '基金',
          'currency': 'TWD',
          'currentPriceMinor': 123,
          'priceUpdatedAt': '2026-01-31T00:00:00.000Z',
          'note': '',
        },
      ],
    });
    final data = AppData.fromJson(migrated);

    expect(data.schemaVersion, 9);
    expect(
      data.accounts.singleWhere((item) => item.id == 'bank').openingBalanceDate,
      DateTime.utc(2026, 1, 1),
    );
    expect(data.bills.single.paidAt, DateTime.utc(2026, 2, 2));
    expect(data.investmentPriceHistory.single.priceMinor, 123);
    expect(data.investmentPriceHistory.single.estimated, isTrue);
  });

  test(
    'local repository migrates v0 snapshots and recovers corrupt JSON',
    () async {
      final persistence = _StringPersistence(
        jsonEncode({'accounts': <dynamic>[]}),
      );
      final repository = LocalFinanceRepository(persistence);
      expect((await repository.load()).data.schemaVersion, 9);

      persistence.value = '{broken json';
      expect((await repository.load()).data.accounts, isEmpty);
    },
  );

  test(
    'v6 migration creates stable categories and unified account impacts',
    () {
      final source = <String, dynamic>{
        'schemaVersion': 6,
        'settings': {'defaultCategory': '寵物'},
        'accounts': [
          {
            'id': 'bank',
            'userId': 'u',
            'name': '銀行',
            'institution': '',
            'type': '銀行帳戶',
            'currency': 'TWD',
            'openingBalanceMinor': 100000,
            'isActive': true,
            'note': '',
            'createdAt': '2026-08-01T00:00:00.000Z',
            'updatedAt': '2026-08-01T00:00:00.000Z',
          },
        ],
        'cards': [
          {
            'id': 'card',
            'userId': 'u',
            'name': '測試卡',
            'bank': '銀行',
            'lastFour': '1234',
            'closingDay': 1,
            'dueDay': 15,
            'autoDebitDay': 15,
            'debitAccountId': 'bank',
            'isActive': true,
            'note': '',
          },
        ],
        'expenses': [
          {
            'id': 'vet',
            'userId': 'u',
            'date': '2026-08-02T00:00:00.000Z',
            'amountMinor': 50000,
            'paymentMethod': 'creditCard',
            'item': '獸醫',
            'category': '寵物',
            'cardId': 'card',
            'merchant': '',
            'note': '',
            'isNecessary': true,
          },
        ],
        'incomes': [
          {
            'id': 'salary',
            'userId': 'u',
            'date': '2026-08-03T00:00:00.000Z',
            'amountMinor': 200000,
            'item': '薪資',
            'category': '薪資',
            'accountId': 'bank',
            'note': '',
          },
        ],
      };

      final first = migrateLocalFinanceJson(source);
      final second = migrateLocalFinanceJson(first);
      final data = AppData.fromJson(first);

      expect(jsonEncode(second), jsonEncode(first));
      expect(data.schemaVersion, 9);
      expect(data.categories.any((item) => item.name == '寵物'), isTrue);
      expect(
        data.settings.defaultExpenseCategoryId,
        startsWith('custom-expense'),
      );
      final expense = data.transactions.singleWhere(
        (item) => item.id == 'expense:vet',
      );
      expect(expense.type, FinancialTransactionType.expense);
      expect(expense.impacts.single.accountId, 'card-liability-card');
      expect(expense.impacts.single.amountMinor, 50000);
      final income = data.transactions.singleWhere(
        (item) => item.id == 'income:salary',
      );
      expect(income.impacts.single.amountMinor, 200000);
    },
  );
}

class _StringPersistence implements LocalPersistence {
  _StringPersistence(this.value);
  String? value;

  @override
  Future<void> clear() async {
    value = null;
  }

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String value) async {
    this.value = value;
  }
}
