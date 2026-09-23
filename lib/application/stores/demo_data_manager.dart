import '../../domain/models.dart';
import '../app_store.dart';

/// Generates or clears the sample data shown from Settings, so a new user
/// can see what a populated workspace looks like before entering their
/// own numbers. Every record it creates is tagged [DataOrigin.demo] so
/// [clearDemoData] can remove exactly those records (and anything that
/// referenced them) without touching real data.
class DemoDataManager {
  DemoDataManager(this._store);

  final AppStore _store;

  AppData get _data => _store.data;

  Future<void> generateDemoData() async {
    await clearDemoData();
    final now = DateTime.now();
    final bank = Account(
      id: 'demo-bank',
      userId: _store.userId,
      name: '薪轉帳戶',
      institution: '玉山銀行',
      type: '銀行帳戶',
      currency: 'TWD',
      openingBalanceMinor: 128600000,
      isActive: true,
      note: '主要扣款帳戶',
      createdAt: now,
      updatedAt: now,
      origin: DataOrigin.demo,
    );
    final linePay = Account(
      id: 'demo-linepay',
      userId: _store.userId,
      name: 'LINE Pay',
      institution: 'LINE Pay',
      type: '電子支付',
      currency: 'TWD',
      openingBalanceMinor: 368000,
      isActive: true,
      note: '',
      createdAt: now,
      updatedAt: now,
      origin: DataOrigin.demo,
    );
    final usd = Account(
      id: 'demo-usd',
      userId: _store.userId,
      name: '美元存款',
      institution: '國泰世華',
      type: '外幣帳戶',
      currency: 'USD',
      openingBalanceMinor: 248000,
      isActive: true,
      note: '',
      createdAt: now,
      updatedAt: now,
      origin: DataOrigin.demo,
    );
    final card = CreditCard(
      id: 'demo-card',
      userId: _store.userId,
      name: '玉山 U Bear',
      bank: '玉山銀行',
      lastFour: '1688',
      closingDay: 15,
      dueDay: 28,
      autoDebitDay: now.add(const Duration(days: 1)).day,
      debitAccountId: bank.id,
      isActive: true,
      note: '',
      origin: DataOrigin.demo,
    );
    final expenses = [
      Expense(
        id: 'demo-expense-lunch',
        userId: _store.userId,
        date: now.subtract(const Duration(days: 2)),
        amountMinor: 14500,
        paymentMethod: PaymentMethod.creditCard,
        item: '午餐',
        category: '餐飲',
        cardId: card.id,
        merchant: '巷口食堂',
        note: '',
        isNecessary: true,
        origin: DataOrigin.demo,
      ),
      Expense(
        id: 'demo-expense-metro',
        userId: _store.userId,
        date: now.subtract(const Duration(days: 1)),
        amountMinor: 4000,
        paymentMethod: PaymentMethod.linePay,
        item: '捷運加值',
        category: '交通',
        accountId: linePay.id,
        merchant: '台北捷運',
        note: '',
        isNecessary: true,
        origin: DataOrigin.demo,
      ),
    ];
    final income = IncomeEntry(
      id: 'demo-income-salary',
      userId: _store.userId,
      date: now.subtract(const Duration(days: 6)),
      amountMinor: 7200000,
      item: '本月薪資',
      category: '薪資',
      accountId: bank.id,
      note: '測試資料',
      origin: DataOrigin.demo,
    );
    final product = InvestmentProduct(
      id: 'demo-product',
      userId: _store.userId,
      symbol: '0050',
      name: '元大台灣50',
      type: 'ETF',
      currency: 'TWD',
      currentPriceMinor: 19650,
      priceUpdatedAt: now,
      note: '價格為測試資料',
      origin: DataOrigin.demo,
    );
    final transaction = InvestmentTransaction(
      id: 'demo-investment',
      userId: _store.userId,
      date: now.subtract(const Duration(days: 20)),
      type: InvestmentTransactionType.buy,
      productId: product.id,
      quantityMicros: 1000 * 1000000,
      priceMinor: 18800,
      feeMinor: 26600,
      taxMinor: 0,
      debitAccountId: bank.id,
      note: '',
      origin: DataOrigin.demo,
    );
    final order = GroupOrder(
      id: 'demo-order',
      userId: _store.userId,
      name: '週五午餐',
      date: now.subtract(const Duration(days: 1)),
      platform: 'foodpanda',
      cardId: card.id,
      totalMinor: 57000,
      deliveryFeeMinor: 6000,
      serviceFeeMinor: 3000,
      discountMinor: 3000,
      splitMethod: SplitMethod.equal,
      note: '付款後請按我已付款',
      origin: DataOrigin.demo,
      participants: [
        OrderParticipant(
          id: 'demo-person-self',
          name: '我',
          isSelf: true,
          itemName: '雞腿飯',
          itemAmountMinor: 17000,
          sharedFeeMinor: 3000,
          discountMinor: 1000,
          status: CollectionStatus.paid,
          collectionMethod: '',
          collectionAccountId: null,
          token: 'demo-self',
          collectedAt: now,
          note: '',
        ),
        OrderParticipant(
          id: 'demo-person-a',
          name: '王小明',
          isSelf: false,
          itemName: '牛肉飯',
          itemAmountMinor: 18000,
          sharedFeeMinor: 3000,
          discountMinor: 1000,
          status: CollectionStatus.unpaid,
          collectionMethod: collectionMethodCash,
          collectionAccountId: systemCashAccountId,
          token: _store.newId(),
          note: '',
        ),
        OrderParticipant(
          id: 'demo-person-b',
          name: '陳怡君',
          isSelf: false,
          itemName: '排骨飯',
          itemAmountMinor: 16000,
          sharedFeeMinor: 3000,
          discountMinor: 1000,
          status: CollectionStatus.pending,
          collectionMethod: collectionMethodBankTransfer,
          collectionAccountId: bank.id,
          token: _store.newId(),
          note: '',
        ),
      ],
    );
    final bill = CardBill(
      id: 'demo-bill',
      userId: _store.userId,
      cardId: card.id,
      month: '${now.year}-${now.month.toString().padLeft(2, '0')}',
      chargeIds: ['expense:${expenses.first.id}'],
      manualAdjustmentMinor: 0,
      paidMinor: 0,
      dueDate: now.add(const Duration(days: 8)),
      autoDebitDate: now.add(const Duration(days: 1)),
      note: '',
      origin: DataOrigin.demo,
    );
    final rates = [
      FxRate(from: 'USD', to: 'TWD', rateMicros: 32680000, updatedAt: now),
    ];
    await _store.commit(
      _data.copyWith(
        settings: _data.settings.copyWith(
          defaultCollectionAccountId: bank.id,
          bankQrData: 'BANK:808;ACCOUNT:012345678901',
          bankAccountInfo: '玉山銀行 808｜帳號 0123-4567-8901',
          fxRates: rates,
        ),
        accounts: [..._data.accounts, bank, linePay, usd],
        expenses: [..._data.expenses, ...expenses],
        incomes: [..._data.incomes, income],
        cards: [..._data.cards, card],
        bills: [..._data.bills, bill],
        products: [..._data.products, product],
        investmentTransactions: [..._data.investmentTransactions, transaction],
        investmentPriceHistory: [
          ..._data.investmentPriceHistory,
          InvestmentPricePoint(
            productId: product.id,
            priceMinor: product.currentPriceMinor,
            date: product.priceUpdatedAt,
          ),
        ],
        orders: [..._data.orders, order],
      ),
    );
  }

  Future<void> clearDemoData() async {
    final demoAccountIds = _data.accounts
        .where((item) => item.origin == DataOrigin.demo)
        .map((item) => item.id)
        .toSet();
    final demoCardIds = _data.cards
        .where((item) => item.origin == DataOrigin.demo)
        .map((item) => item.id)
        .toSet();
    final demoProductIds = _data.products
        .where((item) => item.origin == DataOrigin.demo)
        .map((item) => item.id)
        .toSet();
    await _store.commit(
      _data.copyWith(
        accounts: _data.accounts
            .where((item) => item.origin != DataOrigin.demo)
            .toList(),
        balanceAdjustments: _data.balanceAdjustments
            .where(
              (item) =>
                  item.origin != DataOrigin.demo &&
                  !demoAccountIds.contains(item.accountId),
            )
            .toList(),
        expenses: _data.expenses
            .where((item) => item.origin != DataOrigin.demo)
            .toList(),
        incomes: _data.incomes
            .where((item) => item.origin != DataOrigin.demo)
            .toList(),
        cards: _data.cards
            .where((item) => item.origin != DataOrigin.demo)
            .toList(),
        bills: _data.bills
            .where(
              (item) =>
                  item.origin != DataOrigin.demo &&
                  !demoCardIds.contains(item.cardId),
            )
            .toList(),
        products: _data.products
            .where((item) => item.origin != DataOrigin.demo)
            .toList(),
        investmentTransactions: _data.investmentTransactions
            .where(
              (item) =>
                  item.origin != DataOrigin.demo &&
                  !demoProductIds.contains(item.productId),
            )
            .toList(),
        investmentAdjustments: _data.investmentAdjustments
            .where(
              (item) =>
                  item.origin != DataOrigin.demo &&
                  !demoProductIds.contains(item.productId),
            )
            .toList(),
        investmentPriceHistory: _data.investmentPriceHistory
            .where((item) => !demoProductIds.contains(item.productId))
            .toList(),
        orders: _data.orders
            .where((item) => item.origin != DataOrigin.demo)
            .toList(),
      ),
    );
  }
}
