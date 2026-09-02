import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:quick_ledger/application/app_store.dart';
import 'package:quick_ledger/data/download_service_stub.dart';
import 'package:quick_ledger/data/repositories.dart';
import 'package:quick_ledger/domain/models.dart';

void main() {
  group('Money', () {
    test('uses integer minor units and converts with micros', () {
      const usd = Money(12345, 'USD');
      final converted = usd.convert(
        FxRate(
          from: 'USD',
          to: 'TWD',
          rateMicros: 32680000,
          updatedAt: DateTime(2026),
        ),
      );
      expect(converted.minorUnits, 403435);
    });
  });

  group('accounting engine', () {
    test(
      'credit-card expense does not debit bank until bill is paid',
      () async {
        final now = DateTime.now();
        const bankId = 'bank';
        const cardId = 'card';
        const expenseId = 'expense';
        final seed = AppData(
          accounts: [
            Account(
              id: bankId,
              userId: 'user',
              name: '銀行',
              institution: '測試銀行',
              type: '銀行帳戶',
              currency: 'TWD',
              openingBalanceMinor: 100000,
              isActive: true,
              note: '',
              createdAt: now,
              updatedAt: now,
            ),
          ],
          cards: const [
            CreditCard(
              id: cardId,
              userId: 'user',
              name: '測試卡',
              bank: '測試銀行',
              lastFour: '1234',
              closingDay: 15,
              dueDay: 28,
              autoDebitDay: 28,
              debitAccountId: bankId,
              isActive: true,
              note: '',
            ),
          ],
          expenses: [
            Expense(
              id: expenseId,
              userId: 'user',
              date: now,
              amountMinor: 12500,
              paymentMethod: PaymentMethod.creditCard,
              item: '午餐',
              category: '餐飲',
              cardId: cardId,
              merchant: '',
              note: '',
              isNecessary: true,
            ),
          ],
          bills: [
            CardBill(
              id: 'bill',
              userId: 'user',
              cardId: cardId,
              month: '2026-07',
              chargeIds: const ['expense:$expenseId'],
              manualAdjustmentMinor: 0,
              paidMinor: 0,
              dueDate: now,
              autoDebitDate: now,
              note: '',
            ),
          ],
        );
        final store = await _store(seed);
        expect(store.accountBalance(bankId), 100000);
        expect(store.pendingCardMinor, 12500);

        await store.payBill('bill');
        expect(store.accountBalance(bankId), 87500);
        expect(store.pendingCardMinor, 0);
      },
    );

    test(
      'debit-card expense immediately debits the card linked account',
      () async {
        final now = DateTime(2026, 8, 19);
        final store = await _store(
          AppData(
            accounts: [
              Account(
                id: 'linked-bank',
                userId: 'user',
                name: '金融卡扣款帳戶',
                institution: '測試銀行',
                type: '銀行帳戶',
                currency: 'TWD',
                openingBalanceMinor: 100000,
                isActive: true,
                note: '',
                createdAt: now,
                updatedAt: now,
              ),
              Account(
                id: 'wrong-bank',
                userId: 'user',
                name: '不應扣款帳戶',
                institution: '其他銀行',
                type: '銀行帳戶',
                currency: 'TWD',
                openingBalanceMinor: 50000,
                isActive: true,
                note: '',
                createdAt: now,
                updatedAt: now,
              ),
            ],
          ),
        );

        await store.upsertCard(
          const CreditCard(
            id: 'debit-card',
            userId: 'user',
            name: '測試金融卡',
            bank: '測試銀行',
            lastFour: '5678',
            closingDay: 1,
            dueDay: 1,
            autoDebitDay: 1,
            debitAccountId: 'linked-bank',
            isActive: true,
            note: '',
            cardType: PaymentCardType.debit,
          ),
        );
        expect(store.cardById('debit-card')?.liabilityAccountId, isNull);
        expect(
          store.data.accounts.where(
            (account) => account.id == 'card-liability-debit-card',
          ),
          isEmpty,
        );

        await store.upsertExpense(
          Expense(
            id: 'debit-expense',
            userId: 'user',
            date: now,
            amountMinor: 12500,
            paymentMethod: PaymentMethod.debitCard,
            item: '午餐',
            category: '餐飲',
            accountId: 'wrong-bank',
            cardId: 'debit-card',
            merchant: '',
            note: '',
            isNecessary: true,
          ),
        );

        expect(store.data.expenses.single.accountId, 'linked-bank');
        expect(store.accountBalance('linked-bank'), 87500);
        expect(store.accountBalance('wrong-bank'), 50000);
        expect(store.pendingCardMinor, 0);
        expect(
          store.data.transactions
              .singleWhere((item) => item.id == 'expense:debit-expense')
              .impacts
              .single
              .amountMinor,
          -12500,
        );
      },
    );

    test(
      'account selectors expose assets but not internal ledger accounts',
      () async {
        final now = DateTime(2026, 8, 20);
        final store = await _store(
          AppData(
            accounts: [
              Account(
                id: 'bank',
                userId: 'user',
                name: '銀行',
                institution: '測試銀行',
                type: '銀行帳戶',
                currency: 'TWD',
                openingBalanceMinor: 0,
                isActive: true,
                note: '',
                createdAt: now,
                updatedAt: now,
              ),
              Account(
                id: 'liability',
                userId: 'user',
                name: '測試卡未繳',
                institution: '測試銀行',
                type: '信用卡負債',
                currency: 'TWD',
                openingBalanceMinor: 0,
                isActive: true,
                note: '',
                createdAt: now,
                updatedAt: now,
                kind: FinancialAccountKind.liability,
                subtype: 'creditCard',
              ),
              Account(
                id: 'deleted-bank',
                userId: 'user',
                name: '已刪除舊帳戶',
                institution: '舊銀行',
                type: '銀行帳戶',
                currency: 'TWD',
                openingBalanceMinor: 0,
                isActive: false,
                note: '',
                createdAt: now,
                updatedAt: now,
              ),
            ],
          ),
        );

        expect(store.activeAssetAccounts.map((item) => item.id), [
          systemCashAccountId,
          'bank',
        ]);
      },
    );

    test(
      'deleting a card also deletes its internal liability account',
      () async {
        final now = DateTime(2026, 8, 20);
        final store = await _store(
          AppData(
            accounts: [
              Account(
                id: 'bank',
                userId: 'user',
                name: '銀行',
                institution: '測試銀行',
                type: '銀行帳戶',
                currency: 'TWD',
                openingBalanceMinor: 0,
                isActive: true,
                note: '',
                createdAt: now,
                updatedAt: now,
              ),
            ],
            cards: const [
              CreditCard(
                id: 'card-to-delete',
                userId: 'user',
                name: '測試卡',
                bank: '測試銀行',
                lastFour: '1234',
                closingDay: 15,
                dueDay: 28,
                autoDebitDay: 28,
                debitAccountId: 'bank',
                isActive: true,
                note: '',
              ),
            ],
          ),
        );
        final liabilityId = store
            .cardById('card-to-delete')!
            .liabilityAccountId!;
        expect(store.accountById(liabilityId), isNotNull);

        await store.deleteCard('card-to-delete');

        expect(store.cardById('card-to-delete'), isNull);
        expect(store.accountById(liabilityId), isNull);
      },
    );

    test(
      'telecom purchases debit only when the carrier bill is paid',
      () async {
        final now = DateTime(2026, 8, 10);
        final seed = AppData(
          accounts: [
            Account(
              id: 'bank',
              userId: 'user',
              name: '銀行',
              institution: '測試銀行',
              type: '銀行帳戶',
              currency: 'TWD',
              openingBalanceMinor: 100000,
              isActive: true,
              note: '',
              createdAt: DateTime(2026, 1, 1),
              updatedAt: now,
            ),
          ],
          expenses: [
            Expense(
              id: 'monthly-fee',
              userId: 'user',
              date: now,
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
              userId: 'user',
              date: DateTime(2026, 8, 5),
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
              id: 'payment',
              userId: 'user',
              recurringExpenseId: 'phone',
              month: '2026-08',
              expenseIds: const ['monthly-fee', 'carrier-purchase'],
              amountMinor: 69900,
              paidAt: now,
              debitAccountId: 'bank',
              balanceInsufficient: false,
            ),
          ],
        );
        final store = await _store(seed);

        expect(store.accountBalance('bank'), 30100);
        expect(store.pendingTelecomMinor, 0);
        expect(
          store
              .accountLedgerEntries('bank')
              .where((item) => item.sourceType == 'telecomBillPayment')
              .single
              .sourceType,
          'telecomBillPayment',
        );
      },
    );

    test('monthly due dates clamp to the last day of short months', () {
      expect(monthlyDueDate(2026, 2, 31), DateTime(2026, 2, 28));
      expect(monthlyDueDate(2028, 2, 31), DateTime(2028, 2, 29));
      expect(monthlyDueDate(2026, 4, 30), DateTime(2026, 4, 30));
    });

    test(
      'group order counts only self share and collection clears receivable',
      () async {
        final now = DateTime.now();
        final seed = AppData(
          accounts: [
            Account(
              id: 'wallet',
              userId: 'user',
              name: '電子支付',
              institution: '',
              type: '電子支付',
              currency: 'TWD',
              openingBalanceMinor: 0,
              isActive: true,
              note: '',
              createdAt: now,
              updatedAt: now,
            ),
          ],
          orders: [
            GroupOrder(
              id: 'order',
              userId: 'user',
              name: '午餐',
              date: now,
              platform: '店家',
              cardId: 'card',
              totalMinor: 40000,
              deliveryFeeMinor: 0,
              serviceFeeMinor: 0,
              discountMinor: 0,
              splitMethod: SplitMethod.equal,
              note: '',
              participants: const [
                OrderParticipant(
                  id: 'self',
                  name: '我',
                  isSelf: true,
                  itemName: 'A',
                  itemAmountMinor: 18000,
                  sharedFeeMinor: 0,
                  discountMinor: 0,
                  status: CollectionStatus.paid,
                  collectionMethod: '',
                  collectionAccountId: null,
                  token: 'self',
                  note: '',
                ),
                OrderParticipant(
                  id: 'friend',
                  name: '朋友',
                  isSelf: false,
                  itemName: 'B',
                  itemAmountMinor: 22000,
                  sharedFeeMinor: 0,
                  discountMinor: 0,
                  status: CollectionStatus.unpaid,
                  collectionMethod: 'LINE Pay',
                  collectionAccountId: 'wallet',
                  token: 'secure-token',
                  note: '',
                ),
              ],
            ),
          ],
        );
        final store = await _store(seed);
        expect(store.currentMonthExpenseMinor, 18000);
        expect(store.receivablesMinor, 22000);
        await store.updateParticipantStatus(
          'order',
          'friend',
          CollectionStatus.paid,
        );
        expect(store.receivablesMinor, 0);
        expect(store.accountBalance('wallet'), 22000);
      },
    );

    test(
      'ceil collection records profit only after coworker payment',
      () async {
        final now = DateTime.now();
        final order = GroupOrder(
          id: 'rounded-order',
          userId: 'user',
          name: '午餐代訂',
          date: now,
          platform: 'Uber Eats',
          cardId: 'card',
          totalMinor: 80100,
          deliveryFeeMinor: 0,
          serviceFeeMinor: 1100,
          discountMinor: 0,
          feeRoundingPolicy: FeeRoundingPolicy.ceilEachFee,
          splitMethod: SplitMethod.equal,
          note: '',
          participants: const [
            OrderParticipant(
              id: 'self',
              name: '我',
              isSelf: true,
              itemName: '餐盒',
              itemAmountMinor: 15000,
              sharedFeeMinor: 0,
              discountMinor: 0,
              suggestedDueMinor: 15000,
              status: CollectionStatus.paid,
              collectionMethod: '',
              collectionAccountId: null,
              token: 'self',
              note: '',
            ),
            OrderParticipant(
              id: 'one',
              name: '一',
              isSelf: false,
              itemName: '餐盒',
              itemAmountMinor: 16000,
              sharedFeeMinor: 300,
              discountMinor: 0,
              suggestedDueMinor: 16300,
              finalDueMinor: 16300,
              status: CollectionStatus.unpaid,
              collectionMethod: '轉帳',
              collectionAccountId: 'wallet',
              token: 'one',
              note: '',
            ),
            OrderParticipant(
              id: 'two',
              name: '二',
              isSelf: false,
              itemName: '餐盒',
              itemAmountMinor: 16000,
              sharedFeeMinor: 300,
              discountMinor: 0,
              suggestedDueMinor: 16300,
              finalDueMinor: 16300,
              status: CollectionStatus.unpaid,
              collectionMethod: '轉帳',
              collectionAccountId: 'wallet',
              token: 'two',
              note: '',
            ),
            OrderParticipant(
              id: 'three',
              name: '三',
              isSelf: false,
              itemName: '餐盒',
              itemAmountMinor: 16000,
              sharedFeeMinor: 300,
              discountMinor: 0,
              suggestedDueMinor: 16300,
              finalDueMinor: 16300,
              status: CollectionStatus.unpaid,
              collectionMethod: '轉帳',
              collectionAccountId: 'wallet',
              token: 'three',
              note: '',
            ),
            OrderParticipant(
              id: 'four',
              name: '四',
              isSelf: false,
              itemName: '餐盒',
              itemAmountMinor: 16000,
              sharedFeeMinor: 200,
              discountMinor: 0,
              suggestedDueMinor: 16300,
              finalDueMinor: 16300,
              status: CollectionStatus.unpaid,
              collectionMethod: '轉帳',
              collectionAccountId: 'wallet',
              token: 'four',
              note: '',
            ),
          ],
        );
        final store = await _store(
          AppData(
            accounts: [
              Account(
                id: 'wallet',
                userId: 'user',
                name: '收款帳戶',
                institution: '',
                type: '銀行帳戶',
                currency: 'TWD',
                openingBalanceMinor: 0,
                isActive: true,
                note: '',
                createdAt: now,
                updatedAt: now,
              ),
            ],
            orders: [order],
          ),
        );

        expect(order.selfExpenseMinor, 15000);
        expect(order.advanceCardMinor, 65100);
        expect(order.expectedCollectionMinor, 65200);
        expect(order.expectedCollectionResultMinor, 100);
        expect(store.pendingCardMinor, 80100);
        expect(store.currentMonthCollectionResultMinor, 0);

        await store.updateParticipantStatus(
          order.id,
          'four',
          CollectionStatus.paid,
        );
        expect(store.accountBalance('wallet'), 16300);
        expect(store.currentMonthCollectionResultMinor, 100);

        await store.updateParticipantStatus(
          order.id,
          'four',
          CollectionStatus.unpaid,
        );
        expect(store.accountBalance('wallet'), 0);
        expect(store.currentMonthCollectionResultMinor, 0);
      },
    );

    test('group order without self is entirely an advance', () async {
      final now = DateTime.now();
      final order = GroupOrder(
        id: 'no-self-order',
        userId: 'user',
        name: '純代訂',
        date: now,
        platform: 'Uber Eats',
        cardId: 'card',
        totalMinor: 30000,
        deliveryFeeMinor: 0,
        serviceFeeMinor: 0,
        discountMinor: 0,
        splitMethod: SplitMethod.equal,
        note: '',
        participants: const [
          OrderParticipant(
            id: 'one',
            name: '一',
            isSelf: false,
            itemName: '餐點一',
            itemAmountMinor: 12000,
            sharedFeeMinor: 0,
            discountMinor: 0,
            suggestedDueMinor: 12000,
            finalDueMinor: 12000,
            status: CollectionStatus.unpaid,
            collectionMethod: '轉帳',
            collectionAccountId: null,
            token: 'one',
            note: '',
          ),
          OrderParticipant(
            id: 'two',
            name: '二',
            isSelf: false,
            itemName: '餐點二',
            itemAmountMinor: 18000,
            sharedFeeMinor: 0,
            discountMinor: 0,
            suggestedDueMinor: 18000,
            finalDueMinor: 18000,
            status: CollectionStatus.unpaid,
            collectionMethod: '轉帳',
            collectionAccountId: null,
            token: 'two',
            note: '',
          ),
        ],
      );
      final store = await _store(AppData(orders: [order]));

      expect(order.selfExpenseMinor, 0);
      expect(order.advanceCardMinor, 30000);
      expect(order.expectedCollectionMinor, 30000);
      expect(store.currentMonthExpenseMinor, 0);
      expect(store.pendingCardMinor, 30000);
    });

    test('new group order appears immediately and survives reload', () async {
      final now = DateTime.now();
      final repository = _MemoryFinance(const AppData());
      final store = AppStore(
        authRepository: _FakeAuth(),
        financeRepository: repository,
        csvExportService: _FakeCsv(),
      );
      await store.initialize();
      final order = GroupOrder(
        id: 'persisted-order',
        userId: 'user',
        name: '回歸測試午餐',
        date: now,
        platform: '店家',
        cardId: 'card',
        totalMinor: 30000,
        deliveryFeeMinor: 0,
        serviceFeeMinor: 0,
        discountMinor: 0,
        splitMethod: SplitMethod.equal,
        note: '',
        participants: const [
          OrderParticipant(
            id: 'self',
            name: '我',
            isSelf: true,
            itemName: '雞腿飯',
            itemAmountMinor: 15000,
            sharedFeeMinor: 0,
            discountMinor: 0,
            status: CollectionStatus.paid,
            collectionMethod: '',
            collectionAccountId: null,
            token: 'self-token',
            note: '',
          ),
          OrderParticipant(
            id: 'friend',
            name: '同事',
            isSelf: false,
            itemName: '排骨飯',
            itemAmountMinor: 15000,
            sharedFeeMinor: 0,
            discountMinor: 0,
            status: CollectionStatus.unpaid,
            collectionMethod: '現金',
            collectionAccountId: null,
            token: 'friend-token',
            note: '',
          ),
        ],
      );

      await store.upsertOrder(order);
      expect(store.data.orders.single.name, '回歸測試午餐');

      final reloaded = AppStore(
        authRepository: _FakeAuth(),
        financeRepository: repository,
        csvExportService: _FakeCsv(),
      );
      await reloaded.initialize();
      expect(reloaded.data.orders.single.id, 'persisted-order');
    });

    test('cash collection uses the protected system cash account', () async {
      final store = await _store(
        AppData(orders: [_collectionOrder(method: collectionMethodCash)]),
      );

      final cash = store.accountById(systemCashAccountId);
      expect(cash?.name, '現金');
      expect(cash?.isActive, isTrue);
      expect(
        await store.confirmParticipantCollection('collection', 'friend'),
        isTrue,
      );
      expect(store.accountBalance(systemCashAccountId), 15000);

      await store.deleteAccount(systemCashAccountId);
      expect(store.accountById(systemCashAccountId), isNotNull);
      await store.updateParticipantStatus(
        'collection',
        'friend',
        CollectionStatus.unpaid,
      );
      expect(store.accountBalance(systemCashAccountId), 0);
      expect(store.data.orders.single.participants.last.collectedAt, isNull);
    });

    test('bank collection requires an active TWD bank account', () async {
      final now = DateTime.now();
      final store = await _store(
        AppData(
          accounts: [
            Account(
              id: 'bank',
              userId: 'user',
              name: '銀行',
              institution: '',
              type: '銀行帳戶',
              currency: 'TWD',
              openingBalanceMinor: 0,
              isActive: true,
              note: '',
              createdAt: now,
              updatedAt: now,
            ),
          ],
          orders: [
            _collectionOrder(
              method: collectionMethodBankTransfer,
              accountId: 'bank',
            ),
          ],
        ),
      );

      expect(
        await store.confirmParticipantCollection('collection', 'friend'),
        isTrue,
      );
      expect(store.accountBalance('bank'), 15000);

      final legacy = await _store(
        AppData(orders: [_collectionOrder(method: 'LINE Pay')]),
      );
      expect(
        await legacy.confirmParticipantCollection('collection', 'friend'),
        isFalse,
      );
      expect(
        legacy.data.orders.single.participants.last.status,
        CollectionStatus.unpaid,
      );
    });

    test(
      'account ledger combines, sorts, edits, and removes effects',
      () async {
        final d1 = DateTime.utc(2026, 1, 1);
        final d2 = DateTime.utc(2026, 1, 2);
        final d3 = DateTime.utc(2026, 1, 3);
        final d4 = DateTime.utc(2026, 1, 4);
        final d5 = DateTime.utc(2026, 1, 5);
        final d6 = DateTime.utc(2026, 1, 6);
        final store = await _store(
          AppData(
            accounts: [
              Account(
                id: 'bank',
                userId: 'user',
                name: '銀行',
                institution: '',
                type: '銀行帳戶',
                currency: 'TWD',
                openingBalanceMinor: 100000,
                isActive: true,
                note: '',
                createdAt: d1,
                updatedAt: d1,
              ),
            ],
            balanceAdjustments: [
              BalanceAdjustment(
                id: 'adjustment',
                userId: 'user',
                accountId: 'bank',
                amountMinor: 2000,
                date: d4,
                reason: '盤點',
              ),
            ],
            expenses: [
              Expense(
                id: 'expense',
                userId: 'user',
                date: d2,
                amountMinor: 12000,
                paymentMethod: PaymentMethod.cash,
                item: '午餐',
                category: '餐飲',
                accountId: 'bank',
                merchant: '',
                note: '',
                isNecessary: true,
              ),
            ],
            cards: const [
              CreditCard(
                id: 'card',
                userId: 'user',
                name: '測試卡',
                bank: '',
                lastFour: '1234',
                closingDay: 1,
                dueDay: 10,
                autoDebitDay: 10,
                debitAccountId: 'bank',
                isActive: true,
                note: '',
              ),
            ],
            bills: [
              CardBill(
                id: 'bill',
                userId: 'user',
                cardId: 'card',
                month: '2026-01',
                chargeIds: const [],
                manualAdjustmentMinor: 5000,
                paidMinor: 5000,
                dueDate: d5,
                autoDebitDate: d5,
                note: '',
              ),
            ],
            investmentTransactions: [
              InvestmentTransaction(
                id: 'investment',
                userId: 'user',
                date: d3,
                type: InvestmentTransactionType.buy,
                productId: 'fund',
                quantityMicros: 1000000,
                priceMinor: 10000,
                feeMinor: 100,
                taxMinor: 50,
                debitAccountId: 'bank',
                note: '',
              ),
            ],
            orders: [
              GroupOrder(
                id: 'order',
                userId: 'user',
                name: '下午茶',
                date: d2,
                platform: '店家',
                cardId: 'card',
                totalMinor: 15000,
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
                    itemName: '點心',
                    itemAmountMinor: 15000,
                    sharedFeeMinor: 0,
                    discountMinor: 0,
                    status: CollectionStatus.paid,
                    collectionMethod: collectionMethodBankTransfer,
                    collectionAccountId: 'bank',
                    token: 'token',
                    collectedAt: d6,
                    note: '',
                  ),
                ],
              ),
            ],
          ),
        );

        final entries = store.accountLedgerEntries('bank');
        expect(entries.map((item) => item.sourceType), [
          'collection',
          'cardPayment',
          'balanceAdjustment',
          'investment',
          'expense',
          'openingBalance',
        ]);
        expect(entries.first.parentSourceId, 'order');
        expect(entries.map((item) => item.amountMinor), [
          15000,
          -5000,
          2000,
          -10150,
          -12000,
          100000,
        ]);
        expect(
          entries.fold<int>(0, (sum, item) => sum + item.amountMinor),
          store.accountBalance('bank'),
        );

        await store.upsertBalanceAdjustment(
          BalanceAdjustment(
            id: 'adjustment',
            userId: 'user',
            accountId: 'bank',
            amountMinor: 3000,
            date: d4,
            reason: '更新盤點',
          ),
        );
        expect(store.data.balanceAdjustments.single.amountMinor, 3000);
        await store.deleteBalanceAdjustment('adjustment');
        expect(store.data.balanceAdjustments, isEmpty);

        await store.cancelParticipantCollection('order', 'friend');
        final participant = store.data.orders.single.participants.single;
        expect(participant.status, CollectionStatus.unpaid);
        expect(participant.collectedAt, isNull);
        expect(
          store.accountLedgerEntries('bank').map((item) => item.sourceType),
          isNot(contains('collection')),
        );
      },
    );

    test('editing an opening balance creates a dated adjustment', () async {
      final now = DateTime.utc(2026, 1, 1);
      final original = Account(
        id: 'bank',
        userId: 'user',
        name: '銀行',
        institution: '',
        type: '銀行帳戶',
        currency: 'TWD',
        openingBalanceMinor: 100000,
        isActive: true,
        note: '',
        createdAt: now,
        updatedAt: now,
      );
      final store = await _store(AppData(accounts: [original]));

      await store.upsertAccount(original.copyWith(openingBalanceMinor: 125000));

      expect(
        store.data.accounts
            .firstWhere((account) => account.id == 'bank')
            .openingBalanceMinor,
        100000,
      );
      expect(store.data.balanceAdjustments.single.amountMinor, 25000);
      expect(store.accountBalance('bank'), 125000);
    });

    test('merging accounts preserves balance and moves references', () async {
      final now = DateTime.utc(2026, 1, 1);
      Account account(String id, String name, int openingBalance) => Account(
        id: id,
        userId: 'user',
        name: name,
        institution: '彰化銀行',
        type: '銀行帳戶',
        currency: 'TWD',
        openingBalanceMinor: openingBalance,
        isActive: true,
        note: '',
        createdAt: now,
        updatedAt: now,
      );
      final store = await _store(
        AppData(
          settings: const UserSettings(defaultCollectionAccountId: 'duplicate'),
          accounts: [
            account('kept', '彰銀主帳戶', 100000),
            account('duplicate', '彰銀舊帳戶', 20000),
          ],
          transactions: [
            FinancialTransaction(
              id: 'transfer-between-duplicates',
              userId: 'user',
              date: now,
              type: FinancialTransactionType.transfer,
              label: '內部轉帳',
              amountMinor: 5000,
              currency: 'TWD',
              impacts: const [
                AccountImpact(
                  accountId: 'duplicate',
                  amountMinor: -5000,
                  currency: 'TWD',
                ),
                AccountImpact(
                  accountId: 'kept',
                  amountMinor: 5000,
                  currency: 'TWD',
                ),
              ],
            ),
          ],
          balanceAdjustments: [
            BalanceAdjustment(
              id: 'adjustment',
              userId: 'user',
              accountId: 'duplicate',
              amountMinor: 3000,
              date: now,
              reason: '盤點',
            ),
          ],
          incomes: [
            IncomeEntry(
              id: 'income',
              userId: 'user',
              date: now,
              amountMinor: 4000,
              item: '收入',
              category: '其他收入',
              accountId: 'duplicate',
              note: '',
            ),
          ],
          expenses: [
            Expense(
              id: 'expense',
              userId: 'user',
              date: now,
              amountMinor: 1000,
              paymentMethod: PaymentMethod.transfer,
              item: '支出',
              category: '其他',
              accountId: 'duplicate',
              merchant: '',
              note: '',
              isNecessary: false,
            ),
          ],
        ),
      );

      expect(store.accountBalance('kept'), 105000);
      expect(store.accountBalance('duplicate'), 21000);

      await store.mergeAccounts(
        sourceAccountId: 'duplicate',
        targetAccountId: 'kept',
      );

      expect(store.accountById('duplicate'), isNull);
      expect(store.accountBalance('kept'), 126000);
      expect(store.data.transactions.single.impacts, isEmpty);
      expect(store.data.balanceAdjustments.single.accountId, 'kept');
      expect(store.data.incomes.single.accountId, 'kept');
      expect(store.data.expenses.single.accountId, 'kept');
      expect(store.data.settings.defaultCollectionAccountId, 'kept');
    });

    test('accounts with different currencies cannot be merged', () async {
      final now = DateTime.utc(2026, 1, 1);
      Account account(String id, String currency) => Account(
        id: id,
        userId: 'user',
        name: id,
        institution: '',
        type: '銀行帳戶',
        currency: currency,
        openingBalanceMinor: 0,
        isActive: true,
        note: '',
        createdAt: now,
        updatedAt: now,
      );
      final store = await _store(
        AppData(accounts: [account('twd', 'TWD'), account('usd', 'USD')]),
      );

      await store.mergeAccounts(sourceAccountId: 'usd', targetAccountId: 'twd');

      expect(store.accountById('twd'), isNotNull);
      expect(store.accountById('usd'), isNotNull);
      expect(store.lastSyncError, '不同幣別的帳戶無法合併');
    });

    test('account transfer moves money atomically and can be edited', () async {
      final now = DateTime.utc(2026, 1, 8);
      Account account(String id, String name, int balance) => Account(
        id: id,
        userId: 'user',
        name: name,
        institution: '',
        type: '銀行帳戶',
        currency: 'TWD',
        openingBalanceMinor: balance,
        isActive: true,
        note: '',
        createdAt: now,
        updatedAt: now,
      );
      final store = await _store(
        AppData(
          accounts: [
            account('checking', '活存', 100000),
            account('savings', '儲蓄', 20000),
          ],
        ),
      );

      await store.upsertAccountTransfer(
        id: 'move',
        fromAccountId: 'checking',
        toAccountId: 'savings',
        amountMinor: 30000,
        date: now,
        note: '每月儲蓄',
      );

      expect(store.accountBalance('checking'), 70000);
      expect(store.accountBalance('savings'), 50000);
      expect(
        store.data.transactions.single.type,
        FinancialTransactionType.transfer,
      );
      expect(
        store.accountLedgerEntries('checking').first.sourceType,
        'transfer',
      );
      expect(
        store.accountLedgerEntries('savings').first.sourceType,
        'transfer',
      );

      await store.upsertAccountTransfer(
        id: store.data.transactions.single.id,
        fromAccountId: 'checking',
        toAccountId: 'savings',
        amountMinor: 10000,
        date: now,
      );
      expect(store.data.transactions, hasLength(1));
      expect(store.accountBalance('checking'), 90000);
      expect(store.accountBalance('savings'), 30000);

      await store.deleteAccountTransfer(store.data.transactions.single.id);
      expect(store.accountBalance('checking'), 100000);
      expect(store.accountBalance('savings'), 20000);
    });
  });

  group('direct investment holding creation', () {
    InvestmentProduct product(DateTime now) => InvestmentProduct(
      id: '0050',
      userId: 'user',
      symbol: '0050',
      name: '元大台灣50',
      type: 'ETF',
      currency: 'TWD',
      currentPriceMinor: 0,
      priceUpdatedAt: now,
      note: '',
    );

    test(
      'snapshot creates product and holding without touching cash',
      () async {
        final now = DateTime.utc(2026, 8, 11);
        final account = Account(
          id: 'bank',
          userId: 'user',
          name: '銀行',
          institution: '',
          type: '銀行帳戶',
          currency: 'TWD',
          openingBalanceMinor: 1000000,
          isActive: true,
          note: '',
          createdAt: now,
          updatedAt: now,
        );
        final store = await _store(AppData(accounts: [account]));

        await store.createInvestmentHolding(
          product: product(now),
          adjustment: InvestmentAdjustment(
            id: 'snapshot',
            userId: 'user',
            productId: '0050',
            date: now,
            quantityMicros: 10000000,
            averageCostMinor: 1500000,
            reason: '建立既有持倉',
          ),
        );

        expect(store.data.products, hasLength(1));
        expect(store.data.investmentAdjustments, hasLength(1));
        expect(store.data.investmentTransactions, isEmpty);
        expect(store.data.investmentPriceHistory, isEmpty);
        expect(store.holdings['0050']?.quantity, 10);
        expect(store.holdings['0050']?.averageCostMinor, 1500000);
        expect(store.accountBalance('bank'), 1000000);
      },
    );

    test('purchase creates a transaction and debits total cost', () async {
      final now = DateTime.utc(2026, 8, 11);
      final account = Account(
        id: 'bank',
        userId: 'user',
        name: '銀行',
        institution: '',
        type: '銀行帳戶',
        currency: 'TWD',
        openingBalanceMinor: 2000000,
        isActive: true,
        note: '',
        createdAt: now,
        updatedAt: now,
      );
      final store = await _store(AppData(accounts: [account]));

      await store.createInvestmentHolding(
        product: product(now),
        transaction: InvestmentTransaction(
          id: 'purchase',
          userId: 'user',
          date: now,
          type: InvestmentTransactionType.buy,
          productId: '0050',
          quantityMicros: 10000000,
          priceMinor: 10000,
          feeMinor: 1000,
          taxMinor: 500,
          debitAccountId: 'bank',
          note: '建立庫存',
        ),
      );

      expect(store.data.products, hasLength(1));
      expect(store.data.investmentTransactions, hasLength(1));
      expect(store.data.investmentAdjustments, isEmpty);
      expect(store.accountBalance('bank'), 1898500);
      expect(store.holdings['0050']?.averageCostMinor, 10150);
    });
  });

  group('credit card charge ownership', () {
    final now = DateTime.utc(2026, 8, 11);
    const card = CreditCard(
      id: 'card',
      userId: 'user',
      name: '測試卡',
      bank: '測試銀行',
      lastFour: '1234',
      closingDay: 15,
      dueDay: 28,
      autoDebitDay: 28,
      debitAccountId: 'bank',
      isActive: true,
      note: '',
    );

    Expense expense(String id, int amount, {String? billId}) => Expense(
      id: id,
      userId: 'user',
      date: now,
      amountMinor: amount,
      paymentMethod: PaymentMethod.creditCard,
      item: id,
      category: '餐飲',
      cardId: card.id,
      billId: billId,
      merchant: '',
      note: '',
      isNecessary: true,
    );

    CardBill bill(String id, List<String> chargeIds) => CardBill(
      id: id,
      userId: 'user',
      cardId: card.id,
      month: '2026-08',
      chargeIds: chargeIds,
      manualAdjustmentMinor: 0,
      paidMinor: 0,
      dueDate: now,
      autoDebitDate: now,
      note: '',
    );

    test(
      'unbilled total excludes billed charges and restores after delete',
      () async {
        final store = await _store(
          AppData(
            cards: const [card],
            expenses: [expense('billed', 10000), expense('unbilled', 25000)],
            bills: [
              bill('bill', const ['expense:billed']),
            ],
          ),
        );

        expect(store.unbilledCardMinor(card.id), 25000);
        expect(store.pendingCardMinor, 35000);

        await store.deleteBill('bill');

        expect(store.unbilledCardMinor(card.id), 35000);
        expect(store.pendingCardMinor, 35000);
      },
    );

    test(
      'explicit bill wins duplicate legacy references and reassignment is rejected',
      () async {
        final first = bill('first', const ['expense:charge']);
        final second = bill('second', const ['expense:charge']);
        final store = await _store(
          AppData(
            cards: const [card],
            expenses: [expense('charge', 12000, billId: second.id)],
            bills: [first, second],
          ),
        );

        expect(store.cardBillForCharge('expense:charge')?.id, second.id);
        expect(store.billAmount(first), 0);
        expect(store.billAmount(second), 12000);

        await store.upsertBill(bill('third', const ['expense:charge']));

        expect(store.data.bills, hasLength(2));
        expect(store.lastSyncError, contains('已屬於其他帳單'));
      },
    );

    test('reminders expose semantic navigation destinations', () async {
      final today = DateTime.now();
      final store = await _store(
        AppData(
          accounts: [
            Account(
              id: 'bank',
              userId: 'user',
              name: '扣款帳戶',
              institution: '銀行',
              type: '銀行帳戶',
              currency: 'TWD',
              openingBalanceMinor: 0,
              isActive: true,
              note: '',
              createdAt: today,
              updatedAt: today,
            ),
          ],
          cards: const [card],
          expenses: [expense('charge', 12000)],
          bills: [
            CardBill(
              id: 'bill',
              userId: 'user',
              cardId: card.id,
              month: '2026-08',
              chargeIds: const ['expense:charge'],
              manualAdjustmentMinor: 0,
              paidMinor: 0,
              dueDate: today,
              autoDebitDate: today,
              note: '',
            ),
          ],
          recurringExpenses: [
            const RecurringExpense(
              id: 'telecom',
              userId: 'user',
              item: '手機月租',
              category: '通訊',
              amountMinor: 59900,
              paymentMethod: PaymentMethod.telecomBill,
              dayOfMonth: 10,
              startMonth: '2026-08',
              telecomDebitAccountId: 'bank',
              isActive: true,
              isNecessary: true,
              note: '',
            ),
          ],
          telecomBillPayments: [
            TelecomBillPayment(
              id: 'telecom-payment',
              userId: 'user',
              recurringExpenseId: 'telecom',
              month: '2026-08',
              expenseIds: const [],
              amountMinor: 59900,
              paidAt: today,
              debitAccountId: 'bank',
              balanceInsufficient: true,
            ),
          ],
        ),
      );

      expect(
        store.reminders.map((item) => item.destination),
        containsAll(const [
          ReminderDestination.cards,
          ReminderDestination.expenses,
        ]),
      );
    });
  });

  group('credit-card statement reconciliation v9', () {
    const card = CreditCard(
      id: 'card-v9',
      userId: 'user',
      name: '核對卡',
      bank: '測試銀行',
      lastFour: '9988',
      closingDay: 31,
      dueDay: 15,
      autoDebitDay: 31,
      debitAccountId: 'bank-v9',
      isActive: true,
      note: '',
      liabilityAccountId: 'liability-v9',
    );
    final bank = Account(
      id: 'bank-v9',
      userId: 'user',
      name: '扣款帳戶',
      institution: '測試銀行',
      type: '活存',
      currency: 'TWD',
      openingBalanceMinor: 100000,
      isActive: true,
      note: '',
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
    );
    final liability = Account(
      id: 'liability-v9',
      userId: 'user',
      name: '核對卡未繳',
      institution: '測試銀行',
      type: '信用卡負債',
      currency: 'TWD',
      openingBalanceMinor: 0,
      isActive: true,
      note: '',
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
      kind: FinancialAccountKind.liability,
    );

    test('month-end cycle dates clamp and cross months', () async {
      final store = await _store(
        AppData(accounts: [bank, liability], cards: const [card]),
      );
      final dates = store.cardBillingDates(card, 2028, 2);
      expect(dates.closingDate, DateTime(2028, 2, 29));
      expect(dates.dueDate, DateTime(2028, 3, 15));
      expect(dates.autoDebitDate, DateTime(2028, 3, 31));
    });

    test(
      'actual amount controls liability and supports multiple payments',
      () async {
        final expense = Expense(
          id: 'charge-v9',
          userId: 'user',
          date: DateTime(2026, 8, 10),
          amountMinor: 10000,
          paymentMethod: PaymentMethod.creditCard,
          item: '消費',
          category: '其他',
          accountId: null,
          cardId: card.id,
          merchant: '',
          note: '',
          isNecessary: true,
        );
        final store = await _store(
          AppData(
            accounts: [bank, liability],
            cards: const [card],
            expenses: [expense],
          ),
        );
        await store.upsertExpense(expense);
        final bill = CardBill(
          id: 'bill-v9',
          userId: 'user',
          cardId: card.id,
          month: '2026-08',
          chargeIds: const ['expense:charge-v9'],
          manualAdjustmentMinor: 0,
          paidMinor: 0,
          dueDate: DateTime(2026, 9, 15),
          autoDebitDate: DateTime(2026, 9, 30),
          note: '',
          statementAmountMinor: 12000,
          reconciliationReason: CardBillReconciliationReason.feeOrInterest,
        );
        await store.upsertBill(bill);
        final saved = store.data.bills.single;
        expect(store.calculatedBillAmount(saved), 10000);
        expect(store.reconciliationDifference(saved), 2000);
        expect(store.accountBalance(liability.id), 12000);

        await store.upsertBillPayment(
          billId: saved.id,
          paymentId: 'first',
          amountMinor: 4000,
          date: DateTime(2026, 9, 10),
          accountId: bank.id,
        );
        expect(store.outstandingBillMinor(store.data.bills.single), 8000);
        expect(
          store.billStatus(store.data.bills.single),
          CardBillStatus.partiallyPaid,
        );

        await store.upsertBillPayment(
          billId: saved.id,
          paymentId: 'second',
          amountMinor: 8000,
          date: DateTime(2026, 9, 12),
          accountId: bank.id,
        );
        expect(store.billPayments(saved.id), hasLength(2));
        expect(store.accountBalance(bank.id), 88000);
        expect(store.accountBalance(liability.id), 0);
        expect(store.billStatus(store.data.bills.single), CardBillStatus.paid);
      },
    );

    test('rejects duplicate month, missing reason, and overpayment', () async {
      final existing = CardBill(
        id: 'existing-v9',
        userId: 'user',
        cardId: card.id,
        month: '2026-08',
        chargeIds: const [],
        manualAdjustmentMinor: 0,
        paidMinor: 0,
        dueDate: DateTime(2026, 9, 15),
        autoDebitDate: DateTime(2026, 9, 30),
        note: '',
        statementAmountMinor: 10000,
        reconciliationReason: CardBillReconciliationReason.feeOrInterest,
      );
      final store = await _store(
        AppData(
          accounts: [bank, liability],
          cards: const [card],
          bills: [existing],
        ),
      );
      await store.upsertBill(
        existing.copyWith(
          month: '2026-09',
          statementAmountMinor: 5000,
          reconciliationReason: CardBillReconciliationReason.none,
        ),
      );
      expect(store.lastSyncError, contains('差異原因'));

      await store.upsertBill(
        CardBill(
          id: 'duplicate-v9',
          userId: 'user',
          cardId: card.id,
          month: '2026-08',
          chargeIds: const [],
          manualAdjustmentMinor: 0,
          paidMinor: 0,
          dueDate: DateTime(2026, 9, 15),
          autoDebitDate: DateTime(2026, 9, 30),
          note: '',
          statementAmountMinor: 10000,
          reconciliationReason: CardBillReconciliationReason.feeOrInterest,
        ),
      );
      expect(store.lastSyncError, contains('已有此月份'));

      await store.upsertBillPayment(
        billId: existing.id,
        paymentId: 'too-much',
        amountMinor: 10001,
        date: DateTime(2026, 9, 1),
        accountId: bank.id,
      );
      expect(store.lastSyncError, contains('不得超過'));
    });
  });

  test('CSV includes BOM and escapes commas, quotes, and newlines', () {
    final csv = encodeCsv([
      ['名稱', '備註'],
      ['午餐,飲料', '他說"已付"\n完成'],
    ]);
    expect(csv.startsWith('\uFEFF'), isTrue);
    expect(csv, contains('"午餐,飲料"'));
    expect(csv, contains('"他說""已付""\n完成"'));
  });
}

GroupOrder _collectionOrder({required String method, String? accountId}) {
  final now = DateTime.now();
  return GroupOrder(
    id: 'collection',
    userId: 'user',
    name: '代收測試',
    date: now,
    platform: '店家',
    cardId: 'card',
    totalMinor: 30000,
    deliveryFeeMinor: 0,
    serviceFeeMinor: 0,
    discountMinor: 0,
    splitMethod: SplitMethod.equal,
    note: '',
    participants: [
      const OrderParticipant(
        id: 'self',
        name: '我',
        isSelf: true,
        itemName: 'A',
        itemAmountMinor: 15000,
        sharedFeeMinor: 0,
        discountMinor: 0,
        status: CollectionStatus.paid,
        collectionMethod: '',
        collectionAccountId: null,
        token: 'self',
        note: '',
      ),
      OrderParticipant(
        id: 'friend',
        name: '朋友',
        isSelf: false,
        itemName: 'B',
        itemAmountMinor: 15000,
        sharedFeeMinor: 0,
        discountMinor: 0,
        status: CollectionStatus.unpaid,
        collectionMethod: method,
        collectionAccountId: accountId,
        token: 'friend',
        note: '',
      ),
    ],
  );
}

Future<AppStore> _store(AppData seed) async {
  final store = AppStore(
    authRepository: _FakeAuth(),
    financeRepository: _MemoryFinance(seed),
    csvExportService: _FakeCsv(),
  );
  await store.initialize();
  return store;
}

class _FakeAuth implements AuthRepository {
  final controller = StreamController<bool>.broadcast();
  bool signedIn = true;

  @override
  Stream<bool> get authStateChanges => controller.stream;
  @override
  String? get currentUserId => signedIn ? 'user' : null;
  @override
  String? get currentUserDisplayName => signedIn ? '測試使用者' : null;
  @override
  bool get isSignedIn => signedIn;
  @override
  Future<void> signInWithLine({String? returnPath}) async {
    signedIn = true;
    controller.add(true);
  }

  @override
  Future<void> signOut() async {
    signedIn = false;
    controller.add(false);
  }
}

class _MemoryFinance implements FinanceRepository {
  _MemoryFinance(this.value);
  AppData value;
  int revision = 0;

  @override
  Future<SaveResult> clear() async {
    value = const AppData();
    return SaveResult(revision: ++revision, updatedAt: DateTime.now());
  }

  @override
  Future<FinanceSnapshot> load() async =>
      FinanceSnapshot(data: value, revision: revision, cloudExists: true);
  @override
  Future<SaveResult> save(AppData data) async {
    value = data;
    return SaveResult(revision: ++revision, updatedAt: DateTime.now());
  }

  @override
  Future<FinanceSnapshot> resolveInitialMigration(
    InitialMigrationAction action,
  ) => load();
}

class _FakeCsv implements CsvExportService {
  @override
  Future<void> export(String fileName, List<List<Object?>> rows) async {}
}
