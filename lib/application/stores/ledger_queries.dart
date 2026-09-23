import '../../domain/models.dart';
import 'first_or_null.dart';

/// Read-only, derived views over [AppData] — account balances, the unified
/// ledger, credit-card bill status, monthly aggregates, currency
/// conversion and the net-worth/reminder summaries built on top of them.
///
/// Every member here is a pure function of the current [AppData] snapshot:
/// nothing in this file calls `commit` or mutates anything. Domain managers
/// (in this same folder) and [AppStore] itself both read through this class
/// instead of duplicating these computations, which is also why so many
/// members here call each other directly (e.g. [billAmount] calling
/// [calculatedBillAmount]) — they are siblings on one class, not spread
/// across files.
class LedgerQueries {
  LedgerQueries(this._getData);

  final AppData Function() _getData;
  AppData get _data => _getData();

  // ---------------------------------------------------------------------
  // Identity-based memoization for the handful of getters below that scan
  // the *entire* dataset (every transaction/expense/income/investment/bill/
  // order): [ledgerEffects], [cardChargeBills] and [holdings]. Several other
  // getters in this file call these once per account/bill/product (e.g.
  // [accountBalance] calls [ledgerEffects], and [depositTotalMinor] calls
  // [accountBalance] once per asset account), so a single widget rebuild
  // that touches a handful of summary numbers could previously trigger a
  // dozen or more full-dataset scans back to back — the main cause of the
  // visible frame drops/jank when switching tabs. [AppData] is only ever
  // replaced wholesale via `AppStore.commit` (every write in this folder's
  // managers builds a new instance through `copyWith`/`fromJson`, never
  // mutates the existing one in place), so a reference-identity check on
  // [_data] is enough to know a cached result is still valid.
  // ---------------------------------------------------------------------

  AppData? _ledgerEffectsFor;
  List<LedgerEffect>? _ledgerEffectsCache;

  AppData? _cardChargeBillsFor;
  Map<String, CardBill>? _cardChargeBillsCache;

  AppData? _holdingsFor;
  Map<String, Holding>? _holdingsCache;

  // ---------------------------------------------------------------------
  // Categories
  // ---------------------------------------------------------------------

  List<BookkeepingCategory> categoriesFor(
    BookkeepingCategoryKind kind, {
    bool activeOnly = false,
  }) {
    final result =
        _data.categories
            .where(
              (item) => item.kind == kind && (!activeOnly || item.isActive),
            )
            .toList()
          ..sort((a, b) {
            final byOrder = a.sortOrder.compareTo(b.sortOrder);
            return byOrder != 0 ? byOrder : a.name.compareTo(b.name);
          });
    return result;
  }

  BookkeepingCategory? categoryById(String? id) =>
      _data.categories.where((item) => item.id == id).firstOrNull;

  BookkeepingCategory? categoryByName(
    String name,
    BookkeepingCategoryKind kind,
  ) => _data.categories
      .where(
        (item) =>
            item.kind == kind &&
            item.name.trim().toLowerCase() == name.trim().toLowerCase(),
      )
      .firstOrNull;

  List<String> categoryNamesFor(
    BookkeepingCategoryKind kind, {
    String? includeInactiveName,
  }) {
    final names = categoriesFor(
      kind,
      activeOnly: true,
    ).map((item) => item.name).toList();
    if (includeInactiveName != null && !names.contains(includeInactiveName)) {
      names.add(includeInactiveName);
    }
    return names;
  }

  String categoryName(String? id, {String fallback = '其他'}) =>
      categoryById(id)?.name ?? fallback;

  bool isCategoryUsed(BookkeepingCategory category) =>
      _data.transactions.any((item) => item.categoryId == category.id) ||
      (category.kind == BookkeepingCategoryKind.expense
          ? _data.expenses.any((item) => item.category == category.name) ||
                _data.recurringExpenses.any(
                  (item) => item.category == category.name,
                )
          : _data.incomes.any((item) => item.category == category.name));

  // ---------------------------------------------------------------------
  // Accounts
  // ---------------------------------------------------------------------

  List<Account> get bankTransferAccounts => _data.accounts
      .where(
        (item) =>
            item.isActive && item.type == '銀行帳戶' && item.currency == 'TWD',
      )
      .toList();

  /// Active asset accounts that can actually receive or pay money.
  /// Internal liability and receivable ledger accounts are intentionally
  /// excluded from user-facing account selectors.
  List<Account> get activeAssetAccounts => _data.accounts
      .where(
        (item) => item.isActive && item.kind == FinancialAccountKind.asset,
      )
      .toList();

  String get lastCollectionMethod {
    final collected =
        _data.orders
            .expand((order) => order.participants)
            .where(
              (item) =>
                  !item.isSelf &&
                  item.status == CollectionStatus.paid &&
                  item.collectedAt != null &&
                  supportedCollectionMethods.contains(item.collectionMethod),
            )
            .toList()
          ..sort((a, b) => b.collectedAt!.compareTo(a.collectedAt!));
    return collected.firstOrNull?.collectionMethod ??
        collectionMethodBankTransfer;
  }

  /// The collection method (and, for bank transfer, which account) most
  /// recently used to actually collect payment from the 代訂 participant
  /// named [name], based on their paid history across past orders. Returns
  /// null when there's no matching paid record for that name yet, so
  /// callers can fall back to [lastCollectionMethod] instead.
  ({String method, String? accountId})? collectionPreferenceForMember(
    String name,
  ) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return null;
    final matches =
        _data.orders
            .expand((order) => order.participants)
            .where(
              (item) =>
                  !item.isSelf &&
                  item.name.trim() == trimmed &&
                  item.status == CollectionStatus.paid &&
                  item.collectedAt != null &&
                  supportedCollectionMethods.contains(item.collectionMethod),
            )
            .toList()
          ..sort((a, b) => b.collectedAt!.compareTo(a.collectedAt!));
    final match = matches.firstOrNull;
    if (match == null) return null;
    return (method: match.collectionMethod, accountId: match.collectionAccountId);
  }

  String? get defaultBankTransferAccountId {
    final configured = _data.settings.defaultCollectionAccountId;
    if (bankTransferAccounts.any((item) => item.id == configured)) {
      return configured;
    }
    return bankTransferAccounts.firstOrNull?.id;
  }

  Account? accountById(String? id) =>
      _data.accounts.where((item) => item.id == id).firstOrNull;

  int accountBalance(String accountId) {
    final account = _data.accounts
        .where((item) => item.id == accountId)
        .firstOrNull;
    if (account == null) return 0;
    if (account.kind != FinancialAccountKind.asset) {
      return account.openingBalanceMinor +
          _data.transactions
              .expand((transaction) => transaction.impacts)
              .where((impact) => impact.accountId == accountId)
              .fold(0, (sum, impact) => sum + impact.amountMinor);
    }
    return account.openingBalanceMinor +
        ledgerEffects
            .where((effect) => effect.accountId == accountId)
            .fold(0, (sum, effect) => sum + effect.amountMinor);
  }

  List<LedgerEffect> accountLedgerEntries(String accountId) {
    final account = accountById(accountId);
    if (account == null) return const [];
    final entries = <LedgerEffect>[
      if (account.openingBalanceMinor != 0)
        LedgerEffect(
          sourceType: 'openingBalance',
          sourceId: account.id,
          accountId: account.id,
          amountMinor: account.openingBalanceMinor,
          label: '期初餘額',
          date: account.effectiveOpeningBalanceDate,
        ),
      ...ledgerEffects.where((effect) => effect.accountId == accountId),
    ];
    entries.sort((a, b) {
      final byDate = b.date.compareTo(a.date);
      return byDate != 0 ? byDate : b.sourceId.compareTo(a.sourceId);
    });
    return entries;
  }

  /// The unified ledger: every account-affecting record (transactions,
  /// balance adjustments, incomes, cash/debit expenses, investment moves,
  /// card-bill payments, telecom-bill payments and order collections)
  /// projected into one list of [LedgerEffect]s, skipping anything already
  /// mirrored into [AppData.transactions] so nothing is counted twice.
  List<LedgerEffect> get ledgerEffects {
    final data = _data;
    final cached = _ledgerEffectsCache;
    if (cached != null && identical(_ledgerEffectsFor, data)) return cached;
    final effects = <LedgerEffect>[];
    final mirrored = _data.transactions.map((item) => item.id).toSet();
    for (final transaction in _data.transactions) {
      final sourceType = switch (transaction.type) {
        FinancialTransactionType.investmentBuy ||
        FinancialTransactionType.investmentSell ||
        FinancialTransactionType.investmentDividend => 'investment',
        FinancialTransactionType.orderCollection => 'collection',
        FinancialTransactionType.cardPayment
            when transaction.relatedEntityType == 'telecomBillPayment' =>
          'telecomBillPayment',
        _ => transaction.relatedEntityType ?? transaction.type.name,
      };
      final sourceId = transaction.relatedEntityId ?? transaction.id;
      final parentSourceId =
          transaction.type == FinancialTransactionType.orderCollection &&
              transaction.id.startsWith('order-collection:')
          ? transaction.id.split(':')[1]
          : null;
      for (final impact in transaction.impacts) {
        effects.add(
          LedgerEffect(
            sourceType: sourceType,
            sourceId: sourceId,
            parentSourceId: parentSourceId,
            accountId: impact.accountId,
            amountMinor: impact.amountMinor,
            label: transaction.label,
            date: transaction.date,
          ),
        );
      }
    }
    for (final adjustment in _data.balanceAdjustments) {
      if (mirrored.contains('balance:${adjustment.id}')) continue;
      effects.add(
        LedgerEffect(
          sourceType: 'balanceAdjustment',
          sourceId: adjustment.id,
          accountId: adjustment.accountId,
          amountMinor: adjustment.amountMinor,
          label: adjustment.reason,
          date: adjustment.date,
        ),
      );
    }
    for (final income in _data.incomes) {
      if (mirrored.contains('income:${income.id}')) continue;
      effects.add(
        LedgerEffect(
          sourceType: 'income',
          sourceId: income.id,
          accountId: income.accountId,
          amountMinor: income.amountMinor,
          label: income.item,
          date: income.date,
        ),
      );
    }
    for (final expense in _data.expenses.where(
      (item) =>
          !item.isCreditCard && item.paymentMethod != PaymentMethod.telecomBill,
    )) {
      if (mirrored.contains('expense:${expense.id}')) continue;
      if (expense.accountId != null) {
        effects.add(
          LedgerEffect(
            sourceType: 'expense',
            sourceId: expense.id,
            accountId: expense.accountId!,
            amountMinor: -expense.amountMinor,
            label: expense.item,
            date: expense.date,
          ),
        );
      }
    }
    for (final transaction in _data.investmentTransactions) {
      if (mirrored.contains('investment:${transaction.id}')) continue;
      final gross = transaction.grossMinor;
      switch (transaction.type) {
        case InvestmentTransactionType.buy:
        case InvestmentTransactionType.subscribe:
          if (transaction.debitAccountId != null) {
            effects.add(
              LedgerEffect(
                sourceType: 'investment',
                sourceId: transaction.id,
                accountId: transaction.debitAccountId!,
                amountMinor:
                    -(gross + transaction.feeMinor + transaction.taxMinor),
                label: transaction.type.label,
                date: transaction.date,
              ),
            );
          }
        case InvestmentTransactionType.sell:
        case InvestmentTransactionType.redeem:
          if (transaction.creditAccountId != null) {
            effects.add(
              LedgerEffect(
                sourceType: 'investment',
                sourceId: transaction.id,
                accountId: transaction.creditAccountId!,
                amountMinor:
                    gross - transaction.feeMinor - transaction.taxMinor,
                label: transaction.type.label,
                date: transaction.date,
              ),
            );
          }
        case InvestmentTransactionType.dividend:
          if (transaction.creditAccountId != null) {
            effects.add(
              LedgerEffect(
                sourceType: 'investment',
                sourceId: transaction.id,
                accountId: transaction.creditAccountId!,
                amountMinor:
                    gross - transaction.feeMinor - transaction.taxMinor,
                label: transaction.type.label,
                date: transaction.date,
              ),
            );
          }
        case InvestmentTransactionType.transferIn:
        case InvestmentTransactionType.transferOut:
          break;
      }
    }
    for (final bill in _data.bills) {
      if (bill.paidMinor <= 0) continue;
      if (billPayments(bill.id).isNotEmpty) continue;
      final card = cardById(bill.cardId);
      if (card != null) {
        effects.add(
          LedgerEffect(
            sourceType: 'cardPayment',
            sourceId: bill.id,
            accountId: card.debitAccountId,
            amountMinor: -bill.paidMinor,
            label: '${card.name} ${bill.month} 帳單',
            date: bill.paidAt ?? bill.autoDebitDate,
          ),
        );
      }
    }
    for (final payment in _data.telecomBillPayments) {
      if (mirrored.contains('telecom-payment:${payment.id}')) continue;
      effects.add(
        LedgerEffect(
          sourceType: 'telecomBillPayment',
          sourceId: payment.id,
          accountId: payment.debitAccountId,
          amountMinor: -payment.amountMinor,
          label: '電信帳單 ${payment.month}',
          date: payment.paidAt,
        ),
      );
    }
    for (final order in _data.orders) {
      for (final participant in order.participants.where(
        (item) =>
            !item.isSelf &&
            item.status == CollectionStatus.paid &&
            item.collectionAccountId != null,
      )) {
        if (mirrored.contains(
          'order-collection:${order.id}:${participant.id}',
        )) {
          continue;
        }
        effects.add(
          LedgerEffect(
            sourceType: 'collection',
            sourceId: participant.id,
            parentSourceId: order.id,
            accountId: participant.collectionAccountId!,
            amountMinor: participant.dueMinor,
            label: '${order.name}－${participant.name}',
            date: participant.collectedAt ?? order.date,
          ),
        );
      }
    }
    _ledgerEffectsFor = data;
    return _ledgerEffectsCache = effects;
  }

  // ---------------------------------------------------------------------
  // Cards, bills and charges
  // ---------------------------------------------------------------------

  CreditCard? cardById(String? id) =>
      _data.cards.where((item) => item.id == id).firstOrNull;
  RecurringExpense? get activeTelecomExpense => _data.recurringExpenses
      .where((item) => item.isActive && item.isTelecom)
      .firstOrNull;
  InvestmentProduct? productById(String? id) =>
      _data.products.where((item) => item.id == id).firstOrNull;

  String? cardIdForCharge(String chargeId) {
    if (chargeId.startsWith('expense:')) {
      final id = chargeId.substring('expense:'.length);
      final expense = _data.expenses
          .where((item) => item.id == id)
          .firstOrNull;
      return expense?.isCreditCard == true ? expense?.cardId : null;
    }
    if (chargeId.startsWith('order:')) {
      final id = chargeId.substring('order:'.length);
      return _data.orders.where((item) => item.id == id).firstOrNull?.cardId;
    }
    return null;
  }

  String? _explicitBillIdForCharge(String chargeId) {
    if (chargeId.startsWith('expense:')) {
      final id = chargeId.substring('expense:'.length);
      return _data.expenses.where((item) => item.id == id).firstOrNull?.billId;
    }
    if (chargeId.startsWith('order:')) {
      final id = chargeId.substring('order:'.length);
      return _data.orders.where((item) => item.id == id).firstOrNull?.billId;
    }
    return null;
  }

  Map<String, CardBill> get cardChargeBills {
    final data = _data;
    final cached = _cardChargeBillsCache;
    if (cached != null && identical(_cardChargeBillsFor, data)) return cached;
    final owners = <String, CardBill>{};
    final billsById = {for (final bill in _data.bills) bill.id: bill};
    final referenced = <String>{
      for (final bill in _data.bills) ...bill.chargeIds,
    };
    for (final chargeId in referenced) {
      final explicitId = _explicitBillIdForCharge(chargeId);
      final explicit = billsById[explicitId];
      if (explicit != null &&
          explicit.chargeIds.contains(chargeId) &&
          cardIdForCharge(chargeId) == explicit.cardId) {
        owners[chargeId] = explicit;
      }
    }
    for (final bill in _data.bills) {
      for (final chargeId in bill.chargeIds) {
        if (cardIdForCharge(chargeId) == bill.cardId) {
          owners.putIfAbsent(chargeId, () => bill);
        }
      }
    }
    _cardChargeBillsFor = data;
    return _cardChargeBillsCache = owners;
  }

  CardBill? cardBillForCharge(String chargeId) => cardChargeBills[chargeId];

  bool canAssignChargeToBill(String chargeId, String cardId, {String? billId}) {
    if (cardIdForCharge(chargeId) != cardId) return false;
    final owner = cardBillForCharge(chargeId);
    return owner == null || owner.id == billId;
  }

  int unbilledCardMinor(String cardId) {
    final billed = cardChargeBills.keys.toSet();
    final expenses = _data.expenses
        .where(
          (item) =>
              item.isCreditCard &&
              item.cardId == cardId &&
              !billed.contains('expense:${item.id}'),
        )
        .fold(0, (sum, item) => sum + item.amountMinor);
    final orders = _data.orders
        .where(
          (item) =>
              item.cardId == cardId && !billed.contains('order:${item.id}'),
        )
        .fold(0, (sum, item) => sum + item.totalMinor);
    return expenses + orders;
  }

  int calculatedBillAmount(CardBill bill) {
    var amount = 0;
    final owners = cardChargeBills;
    for (final id in bill.chargeIds.toSet()) {
      final owner = owners[id];
      if (owner != null && owner.id != bill.id) continue;
      if (id.startsWith('expense:')) {
        final expenseId = id.substring('expense:'.length);
        amount += _data.expenses
            .where((item) => item.id == expenseId)
            .fold(0, (sum, item) => sum + item.amountMinor);
      } else if (id.startsWith('order:')) {
        final orderId = id.substring('order:'.length);
        amount += _data.orders
            .where((item) => item.id == orderId)
            .fold(0, (sum, item) => sum + item.totalMinor);
      }
    }
    return amount < 0 ? 0 : amount;
  }

  int billAmount(CardBill bill) =>
      bill.statementAmountMinor ??
      (calculatedBillAmount(bill) + bill.manualAdjustmentMinor)
          .clamp(0, 1 << 62)
          .toInt();

  int reconciliationDifference(CardBill bill) =>
      billAmount(bill) - calculatedBillAmount(bill);

  List<FinancialTransaction> billPayments(String billId) {
    final result = _data.transactions
        .where(
          (item) =>
              item.type == FinancialTransactionType.cardPayment &&
              item.relatedEntityType == 'cardBill' &&
              item.relatedEntityId == billId,
        )
        .toList();
    result.sort((a, b) => b.date.compareTo(a.date));
    return result;
  }

  int paidBillMinor(CardBill bill) {
    final payments = billPayments(bill.id);
    return payments.isEmpty
        ? bill.paidMinor
        : payments.fold(0, (sum, item) => sum + item.amountMinor);
  }

  int outstandingBillMinor(CardBill bill) =>
      (billAmount(bill) - paidBillMinor(bill)).clamp(0, 1 << 62).toInt();

  CardBillStatus billStatus(CardBill bill, {DateTime? now}) {
    final paid = paidBillMinor(bill);
    if (outstandingBillMinor(bill) == 0) return CardBillStatus.paid;
    if (bill.autoDebitState == CardBillAutoDebitState.failed) {
      return CardBillStatus.debitFailed;
    }
    final instant = now ?? DateTime.now();
    final today = DateTime(instant.year, instant.month, instant.day);
    final due = DateTime(
      bill.dueDate.year,
      bill.dueDate.month,
      bill.dueDate.day,
    );
    if (today.isAfter(due)) return CardBillStatus.overdue;
    if (paid > 0) return CardBillStatus.partiallyPaid;
    final debit = DateTime(
      bill.autoDebitDate.year,
      bill.autoDebitDate.month,
      bill.autoDebitDate.day,
    );
    final days = debit.difference(today).inDays;
    return days >= 0 && days <= 3
        ? CardBillStatus.debitSoon
        : CardBillStatus.unpaid;
  }

  ({DateTime closingDate, DateTime dueDate, DateTime autoDebitDate})
  cardBillingDates(CreditCard card, int year, int month) {
    DateTime clamped(int y, int m, int day) {
      final last = DateTime(y, m + 1, 0).day;
      return DateTime(y, m, day.clamp(1, last));
    }

    final closing = clamped(year, month, card.closingDay);
    DateTime afterClosing(int day) {
      final nextMonth = day <= card.closingDay;
      return clamped(year, month + (nextMonth ? 1 : 0), day);
    }

    return (
      closingDate: closing,
      dueDate: afterClosing(card.dueDay),
      autoDebitDate: afterClosing(card.autoDebitDay),
    );
  }

  // `cardBillingDates` above is keyed by the "cursor" month whose closing
  // date ends the cycle (e.g. a card that closes on the 1st has its Jul
  // 2–Aug 1 cycle keyed by cursor month = August). `CardBill.month` is
  // instead labelled by the month the cycle *starts* in (Jul 2–Aug 1 would
  // be the "July" bill), since that's the month most of its charges land in
  // and matches how people talk about "this month's card bill". These two
  // helpers convert between the two.
  DateTime cardCycleStart(CreditCard card, int cursorYear, int cursorMonth) {
    final previous = DateTime(cursorYear, cursorMonth - 1);
    final previousClosing = cardBillingDates(
      card,
      previous.year,
      previous.month,
    ).closingDate;
    return previousClosing.add(const Duration(days: 1));
  }

  String cardBillLabelFor(CreditCard card, int cursorYear, int cursorMonth) {
    final start = cardCycleStart(card, cursorYear, cursorMonth);
    return '${start.year}-${start.month.toString().padLeft(2, '0')}';
  }

  /// Inverse of [cardBillLabelFor]: given a bill's label month, finds the
  /// cursor month to pass into [cardBillingDates] to get that bill's actual
  /// closing/due/auto-debit dates. Almost always `labelMonth + 1`, except
  /// when the card's closing day gets clamped to the last day of the label
  /// month (e.g. closingDay 29–31 landing in February), in which case the
  /// cycle both starts and is keyed by the same calendar month.
  ({int year, int month}) cardCycleCursorForLabel(
    CreditCard card,
    int labelYear,
    int labelMonth,
  ) {
    for (final candidate in [
      DateTime(labelYear, labelMonth + 1),
      DateTime(labelYear, labelMonth),
    ]) {
      final start = cardCycleStart(card, candidate.year, candidate.month);
      if (start.year == labelYear && start.month == labelMonth) {
        return (year: candidate.year, month: candidate.month);
      }
    }
    // Should be unreachable given the two candidates above cover both
    // possible outcomes of the clamped-closing-day edge case; fall back to
    // the common case rather than throwing.
    final fallback = DateTime(labelYear, labelMonth + 1);
    return (year: fallback.year, month: fallback.month);
  }

  int get pendingCardMinor {
    final ownedCharges = cardChargeBills.keys.toSet();
    final unbilledExpenses = _data.expenses
        .where(
          (item) =>
              item.isCreditCard && !ownedCharges.contains('expense:${item.id}'),
        )
        .fold(0, (sum, item) => sum + item.amountMinor);
    final unbilledOrders = _data.orders
        .where((item) => !ownedCharges.contains('order:${item.id}'))
        .fold(0, (sum, item) => sum + item.totalMinor);
    final outstandingBills = _data.bills.fold(0, (sum, bill) {
      final remaining = billAmount(bill) - paidBillMinor(bill);
      return sum + (remaining < 0 ? 0 : remaining);
    });
    return unbilledExpenses + unbilledOrders + outstandingBills;
  }

  int get pendingTelecomMinor {
    final paidExpenseIds = <String>{
      for (final payment in _data.telecomBillPayments) ...payment.expenseIds,
    };
    return _data.expenses
        .where(
          (item) =>
              item.paymentMethod == PaymentMethod.telecomBill &&
              !paidExpenseIds.contains(item.id),
        )
        .fold(0, (sum, item) => sum + item.amountMinor);
  }

  // ---------------------------------------------------------------------
  // Monthly and net-worth aggregates
  // ---------------------------------------------------------------------

  int get currentMonthExpenseMinor {
    final now = DateTime.now();
    final expenses = _data.expenses
        .where(
          (item) => item.date.year == now.year && item.date.month == now.month,
        )
        .fold(0, (sum, item) => sum + item.amountMinor);
    final orders = _data.orders
        .where(
          (item) => item.date.year == now.year && item.date.month == now.month,
        )
        .fold(0, (sum, item) => sum + item.selfExpenseMinor);
    return expenses + orders;
  }

  int get currentMonthCollectionResultMinor {
    final now = DateTime.now();
    return _data.orders.fold(0, (orderSum, order) {
      return orderSum +
          order.participants
              .where(
                (participant) =>
                    !participant.isSelf &&
                    participant.status == CollectionStatus.paid &&
                    participant.collectedAt?.year == now.year &&
                    participant.collectedAt?.month == now.month,
              )
              .fold(0, (sum, participant) {
                return sum + participant.collectionResultMinor;
              });
    });
  }

  int get currentMonthCollectionResultDefaultMinor =>
      convertToDefault(currentMonthCollectionResultMinor, 'TWD') ?? 0;

  int get receivablesMinor =>
      _data.orders.fold(0, (sum, order) => sum + order.outstandingMinor);

  int get receivablesDefaultMinor =>
      convertToDefault(receivablesMinor, 'TWD') ?? 0;

  int get pendingCardDefaultMinor =>
      convertToDefault(pendingCardMinor, 'TWD') ?? 0;
  int get pendingTelecomDefaultMinor =>
      convertToDefault(pendingTelecomMinor, 'TWD') ?? 0;

  int get currentMonthExpenseDefaultMinor =>
      convertToDefault(currentMonthExpenseMinor, 'TWD') ?? 0;

  int get currentMonthIncomeDefaultMinor {
    final now = DateTime.now();
    var total = 0;
    for (final income in _data.incomes.where(
      (item) => item.date.year == now.year && item.date.month == now.month,
    )) {
      final currency =
          accountById(income.accountId)?.currency ??
          _data.settings.defaultCurrency;
      final converted = convertToDefault(income.amountMinor, currency);
      if (converted != null) total += converted;
    }
    return total;
  }

  int get currentMonthBalanceDefaultMinor =>
      currentMonthIncomeDefaultMinor - currentMonthExpenseDefaultMinor;

  FxRate? fxRateFor(String currency) {
    if (currency == _data.settings.defaultCurrency) {
      return FxRate(
        from: currency,
        to: currency,
        rateMicros: 1000000,
        updatedAt: DateTime.now(),
      );
    }
    final rates =
        _data.settings.fxRates
            .where(
              (rate) =>
                  rate.from == currency &&
                  rate.to == _data.settings.defaultCurrency,
            )
            .toList()
          ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return rates.firstOrNull;
  }

  int? convertToDefault(int minor, String currency) {
    final rate = fxRateFor(currency);
    if (rate == null) return null;
    return (minor * rate.rateMicros / 1000000).round();
  }

  Set<String> get currenciesMissingFx {
    final currencies = <String>{
      ..._data.accounts.map((item) => item.currency),
      ..._data.products.map((item) => item.currency),
      if (_data.expenses.isNotEmpty ||
          _data.orders.isNotEmpty ||
          _data.bills.isNotEmpty)
        'TWD',
    };
    return currencies
        .where(
          (currency) =>
              currency != _data.settings.defaultCurrency &&
              fxRateFor(currency) == null,
        )
        .toSet();
  }

  int get depositTotalMinor {
    var total = 0;
    for (final account in _data.accounts.where(
      (item) => item.kind == FinancialAccountKind.asset,
    )) {
      final converted = convertToDefault(
        accountBalance(account.id),
        account.currency,
      );
      if (converted != null) total += converted;
    }
    return total;
  }

  Map<String, Holding> get holdings {
    final data = _data;
    final cached = _holdingsCache;
    if (cached != null && identical(_holdingsFor, data)) return cached;
    final result = <String, Holding>{};
    for (final product in _data.products) {
      final events =
          <
              ({
                DateTime date,
                InvestmentTransaction? tx,
                InvestmentAdjustment? adjustment,
              })
            >[
              ..._data.investmentTransactions
                  .where((item) => item.productId == product.id)
                  .map((item) => (date: item.date, tx: item, adjustment: null)),
              ..._data.investmentAdjustments
                  .where((item) => item.productId == product.id)
                  .map((item) => (date: item.date, tx: null, adjustment: item)),
            ]
            ..sort((a, b) => a.date.compareTo(b.date));
      var quantity = 0;
      var averageCost = 0;
      for (final event in events) {
        final adjustment = event.adjustment;
        if (adjustment != null) {
          quantity = adjustment.quantityMicros;
          averageCost = adjustment.averageCostMinor;
          continue;
        }
        final transaction = event.tx!;
        switch (transaction.type) {
          case InvestmentTransactionType.buy:
          case InvestmentTransactionType.subscribe:
          case InvestmentTransactionType.transferIn:
            final incomingCost =
                transaction.type == InvestmentTransactionType.transferIn
                ? transaction.grossMinor
                : transaction.grossMinor +
                      transaction.feeMinor +
                      transaction.taxMinor;
            final totalCost =
                (quantity * averageCost / 1000000).round() + incomingCost;
            quantity += transaction.quantityMicros;
            averageCost = quantity == 0
                ? 0
                : (totalCost * 1000000 / quantity).round();
          case InvestmentTransactionType.sell:
          case InvestmentTransactionType.redeem:
          case InvestmentTransactionType.transferOut:
            final remaining = quantity - transaction.quantityMicros;
            quantity = remaining < 0 ? 0 : remaining;
            if (quantity == 0) averageCost = 0;
          case InvestmentTransactionType.dividend:
            break;
        }
      }
      result[product.id] = Holding(
        productId: product.id,
        quantityMicros: quantity,
        averageCostMinor: averageCost,
      );
    }
    _holdingsFor = data;
    return _holdingsCache = result;
  }

  int get investmentValueMinor {
    var total = 0;
    for (final product in _data.products) {
      final holding = holdings[product.id];
      if (holding == null) continue;
      final value =
          (holding.quantityMicros * product.currentPriceMinor / 1000000)
              .round();
      final converted = convertToDefault(value, product.currency);
      if (converted != null) total += converted;
    }
    return total;
  }

  int get totalAssetsMinor =>
      depositTotalMinor + investmentValueMinor + receivablesDefaultMinor;
  int get netWorthMinor =>
      totalAssetsMinor - pendingCardDefaultMinor - pendingTelecomDefaultMinor;

  List<ReminderItem> get reminders {
    if (!_data.settings.remindersEnabled) return const [];
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final items = <ReminderItem>[];
    for (final bill in _data.bills) {
      final remaining = billAmount(bill) - paidBillMinor(bill);
      final outstanding = remaining < 0 ? 0 : remaining;
      if (outstanding == 0) continue;
      final card = cardById(bill.cardId);
      final balance = card == null ? 0 : accountBalance(card.debitAccountId);
      final status = billStatus(bill, now: now);
      if (status == CardBillStatus.debitFailed ||
          status == CardBillStatus.overdue) {
        items.add(
          ReminderItem(
            title: status == CardBillStatus.debitFailed ? '自動扣款失敗' : '信用卡帳單已逾期',
            subtitle:
                '${card?.name ?? '信用卡'} ${bill.month}・未繳 ${(outstanding / 100).toStringAsFixed(2)}',
            date: status == CardBillStatus.debitFailed
                ? bill.autoDebitDate
                : bill.dueDate,
            isWarning: true,
            destination: ReminderDestination.cards,
            // No `billId`: dismissing only suppresses the upcoming-auto-
            // debit reminder below, not a failed/overdue alert, so the
            // dashboard shouldn't offer a "don't remind me" action here.
          ),
        );
        continue;
      }
      if (bill.reminderDismissed) continue;
      final debit = DateTime(
        bill.autoDebitDate.year,
        bill.autoDebitDate.month,
        bill.autoDebitDate.day,
      );
      final days = debit.difference(today).inDays;
      if (days == 3 || days == 1 || days == 0) {
        items.add(
          ReminderItem(
            title: days == 0 ? '今天將自動扣款' : '$days 天後自動扣款',
            subtitle: '${card?.name ?? '信用卡'} ${bill.month}',
            date: debit,
            isWarning: balance < outstanding,
            destination: ReminderDestination.cards,
            billId: bill.id,
          ),
        );
      }
    }
    for (final payment in _data.telecomBillPayments.where(
      (item) => item.balanceInsufficient,
    )) {
      final rule = _data.recurringExpenses
          .where((item) => item.id == payment.recurringExpenseId)
          .firstOrNull;
      items.add(
        ReminderItem(
          title: '電信帳單扣款後餘額不足',
          subtitle:
              '${rule?.item ?? '電信帳單'}・${accountById(payment.debitAccountId)?.name ?? '指定帳戶'}・${payment.month}',
          date: payment.paidAt,
          isWarning: true,
          destination: ReminderDestination.expenses,
        ),
      );
    }
    items.sort((a, b) => a.date.compareTo(b.date));
    return items;
  }
}
