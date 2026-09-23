import '../../domain/models.dart';
import '../app_store.dart';
import 'first_or_null.dart';
import 'transaction_utils.dart';

/// Credit/debit card CRUD and credit-card bill lifecycle: creating and
/// reconciling a bill, recording payments (manual or auto-debit), and
/// deleting bills or payments.
class CardsManager {
  CardsManager(this._store);

  final AppStore _store;

  AppData get _data => _store.data;

  Future<void> upsertCard(CreditCard card) async {
    final liabilityId = card.isCredit
        ? card.liabilityAccountId ?? 'card-liability-${card.id}'
        : null;
    final normalized = CreditCard(
      id: card.id,
      userId: card.userId,
      name: card.name,
      bank: card.bank,
      lastFour: card.lastFour,
      closingDay: card.closingDay,
      dueDay: card.dueDay,
      autoDebitDay: card.autoDebitDay,
      debitAccountId: card.debitAccountId,
      isActive: card.isActive,
      note: card.note,
      cardType: card.cardType,
      liabilityAccountId: liabilityId,
      origin: card.origin,
    );
    final items = [..._data.cards];
    final index = items.indexWhere((item) => item.id == card.id);
    index < 0 ? items.add(normalized) : items[index] = normalized;
    final accounts = [..._data.accounts];
    final accountIndex = liabilityId == null
        ? -1
        : accounts.indexWhere((item) => item.id == liabilityId);
    final now = DateTime.now();
    if (liabilityId != null) {
      final liability = Account(
        id: liabilityId,
        userId: card.userId,
        name: '${card.name}未繳',
        institution: card.bank,
        type: '信用卡負債',
        currency: 'TWD',
        openingBalanceMinor: accountIndex < 0
            ? 0
            : accounts[accountIndex].openingBalanceMinor,
        isActive: card.isActive,
        note: '信用卡負債帳戶',
        createdAt: accountIndex < 0 ? now : accounts[accountIndex].createdAt,
        updatedAt: now,
        kind: FinancialAccountKind.liability,
        subtype: 'creditCard',
      );
      accountIndex < 0
          ? accounts.add(liability)
          : accounts[accountIndex] = liability;
    }
    await _store.commit(_data.copyWith(cards: items, accounts: accounts));
  }

  Future<void> deleteCard(String id) async {
    final card = _store.ledger.cardById(id);
    if (card == null) return;
    if (_data.bills.any((item) => item.cardId == id) ||
        _data.expenses.any((item) => item.cardId == id) ||
        _data.orders.any((item) => item.cardId == id)) {
      _store.lastSyncError = '無法刪除信用卡，仍被支出、帳單或訂單引用';
      _store.notify();
      return;
    }
    final liabilityId = card.liabilityAccountId;
    await _store.commit(
      _data.copyWith(
        cards: _data.cards.where((item) => item.id != id).toList(),
        accounts: liabilityId == null
            ? _data.accounts
            : _data.accounts.where((item) => item.id != liabilityId).toList(),
      ),
    );
  }

  Future<void> upsertBill(CardBill bill) async {
    if (_store.ledger.cardById(bill.cardId)?.isCredit != true) {
      _store.lastSyncError = '金融卡消費直接扣款，不會產生信用卡帳單';
      _store.notify();
      return;
    }
    // `ensureBillsGenerated()` may have already auto-created a placeholder
    // bill for this card+month (e.g. at app startup, from charges that were
    // already sitting there unbilled) before the caller got a chance to
    // submit their own bill for it -- typically with the real bank
    // statement amount. That placeholder was never actually reconciled or
    // paid against, so drop it here in favour of the caller's bill instead
    // of letting it block this submission as a "duplicate month" (which
    // also made its charges look already claimed by another bill).
    //
    // This only fires when it's an unambiguous 1-for-1 replacement: exactly
    // one other bill occupies this card+month, and it's still untouched.
    // Two or more bills already sharing a month is a pre-existing data
    // situation this method doesn't otherwise try to resolve (see the
    // "credit card charge ownership" tests), so that case -- and a
    // placeholder that WAS already reconciled or has payments recorded
    // against it -- is left alone and still blocks this submission as
    // "duplicate month" below, same as before. See
    // claude/kgz-card-bill-reminder-feature.md §5.
    final sameMonth = _data.bills
        .where(
          (item) =>
              item.id != bill.id &&
              item.cardId == bill.cardId &&
              item.month == bill.month,
        )
        .toList();
    final placeholder =
        sameMonth.length == 1 && _isUnreconciledPlaceholder(sameMonth.single)
        ? sameMonth.single
        : null;
    if (placeholder != null) {
      await _store.commit(
        _data.copyWith(
          bills: _data.bills
              .where((item) => item.id != placeholder.id)
              .toList(),
        ),
      );
      // commit() already reported the failure via lastSyncError/notify; bail
      // out rather than continue against data that still has the
      // placeholder in it.
      if (_store.lastSyncError != null) return;
    }
    final chargeIds = bill.chargeIds.toSet().toList();
    final invalid = chargeIds.where(
      (id) =>
          !_store.ledger.canAssignChargeToBill(id, bill.cardId, billId: bill.id),
    );
    if (invalid.isNotEmpty) {
      _store.lastSyncError = '有刷卡紀錄已屬於其他帳單，請重新確認明細';
      _store.notify();
      return;
    }
    if (!RegExp(r'^\d{4}-(0[1-9]|1[0-2])$').hasMatch(bill.month)) {
      _store.lastSyncError = '帳單月份格式必須為 YYYY-MM';
      _store.notify();
      return;
    }
    if (_data.bills.any(
      (item) =>
          item.id != bill.id &&
          item.cardId == bill.cardId &&
          item.month == bill.month,
    )) {
      _store.lastSyncError = '同一張卡已有此月份帳單';
      _store.notify();
      return;
    }
    final statementAmount =
        bill.statementAmountMinor ??
        (_store.ledger.calculatedBillAmount(bill) + bill.manualAdjustmentMinor)
            .clamp(0, 1 << 62)
            .toInt();
    final paid = _store.ledger.paidBillMinor(bill);
    if (statementAmount < paid) {
      _store.lastSyncError = '實際帳單總額不得低於已繳金額';
      _store.notify();
      return;
    }
    final difference = statementAmount - _store.ledger.calculatedBillAmount(bill);
    if (difference != 0 &&
        bill.reconciliationReason == CardBillReconciliationReason.none) {
      _store.lastSyncError = '帳單有差額時請選擇差異原因';
      _store.notify();
      return;
    }
    if (difference != 0 &&
        bill.reconciliationReason ==
            CardBillReconciliationReason.missingOrOther &&
        bill.reconciliationNote.trim().isEmpty) {
      _store.lastSyncError = '選擇漏登／其他時請填寫差異說明';
      _store.notify();
      return;
    }
    final normalized = CardBill(
      id: bill.id,
      userId: bill.userId,
      cardId: bill.cardId,
      month: bill.month,
      chargeIds: chargeIds,
      manualAdjustmentMinor: 0,
      paidMinor: paid,
      dueDate: bill.dueDate,
      autoDebitDate: bill.autoDebitDate,
      note: bill.note,
      statementAmountMinor: statementAmount,
      reconciliationReason: difference == 0
          ? CardBillReconciliationReason.none
          : bill.reconciliationReason,
      reconciliationNote: difference == 0 ? '' : bill.reconciliationNote.trim(),
      autoDebitState: bill.autoDebitState,
      paidAt:
          _store.ledger.billPayments(bill.id).firstOrNull?.date ?? bill.paidAt,
      reminderDismissed: bill.reminderDismissed,
      origin: bill.origin,
    );
    final items = [..._data.bills];
    final index = items.indexWhere((item) => item.id == bill.id);
    index < 0 ? items.add(normalized) : items[index] = normalized;
    final adjustmentId = 'card-bill-reconciliation:${bill.id}';
    final transactions = _data.transactions
        .where((item) => item.id != adjustmentId)
        .toList();
    final liabilityId = _store.ledger.cardById(bill.cardId)?.liabilityAccountId;
    if (difference != 0 && liabilityId != null) {
      transactions.add(
        FinancialTransaction(
          id: adjustmentId,
          userId: bill.userId,
          date: normalized.dueDate,
          type: FinancialTransactionType.balanceAdjustment,
          label:
              '${_store.ledger.cardById(bill.cardId)?.name ?? '信用卡'} ${bill.month} 帳單核對差額',
          amountMinor: difference.abs(),
          currency: 'TWD',
          note: normalized.reconciliationNote,
          relatedEntityType: 'cardBillReconciliation',
          relatedEntityId: bill.id,
          impacts: [
            AccountImpact(
              accountId: liabilityId,
              amountMinor: difference,
              currency: 'TWD',
            ),
          ],
          origin: bill.origin,
        ),
      );
    }
    _store.lastSyncError = null;
    await _store.commit(_data.copyWith(bills: items, transactions: transactions));
  }

  Future<void> payBill(String id) async {
    final source = _data.bills.where((item) => item.id == id).firstOrNull;
    if (source == null) return;
    final card = _store.ledger.cardById(source.cardId);
    final amount = _store.ledger.outstandingBillMinor(source);
    if (card == null || amount <= 0) return;
    await upsertBillPayment(
      billId: id,
      paymentId: _store.newId(),
      amountMinor: amount,
      date: DateTime.now(),
      accountId: card.debitAccountId,
      note: '自動扣款確認成功',
      autoDebitSucceeded: true,
    );
  }

  Future<void> upsertBillPayment({
    required String billId,
    required String paymentId,
    required int amountMinor,
    required DateTime date,
    required String accountId,
    String note = '',
    bool autoDebitSucceeded = false,
  }) async {
    final bill = _data.bills.where((item) => item.id == billId).firstOrNull;
    final card = bill == null ? null : _store.ledger.cardById(bill.cardId);
    final liabilityId = card?.liabilityAccountId;
    if (bill == null || card == null || liabilityId == null) return;
    final transactionId = paymentId.startsWith('card-payment:')
        ? paymentId
        : 'card-payment:$billId:$paymentId';
    final otherPaid = _store.ledger
        .billPayments(billId)
        .where((item) => item.id != transactionId)
        .fold(0, (sum, item) => sum + item.amountMinor);
    if (amountMinor <= 0 ||
        otherPaid + amountMinor > _store.ledger.billAmount(bill)) {
      _store.lastSyncError = '繳款金額必須大於 0，且不得超過帳單剩餘金額';
      _store.notify();
      return;
    }
    final account = _store.ledger.accountById(accountId);
    if (account == null || account.kind != FinancialAccountKind.asset) {
      _store.lastSyncError = '請選擇有效的扣款帳戶';
      _store.notify();
      return;
    }
    final transaction = FinancialTransaction(
      id: transactionId,
      userId: bill.userId,
      date: date,
      type: FinancialTransactionType.cardPayment,
      label: '${card.name} ${bill.month} 帳單繳款',
      amountMinor: amountMinor,
      currency: account.currency,
      note: note.trim(),
      relatedEntityType: 'cardBill',
      relatedEntityId: billId,
      impacts: [
        AccountImpact(
          accountId: accountId,
          amountMinor: -amountMinor,
          currency: account.currency,
        ),
        AccountImpact(
          accountId: liabilityId,
          amountMinor: -amountMinor,
          currency: 'TWD',
        ),
      ],
      origin: bill.origin,
    );
    final transactions = replaceTransaction(
      _data.transactions,
      transactionId,
      transaction,
    );
    final payments = transactions.where(
      (item) =>
          item.type == FinancialTransactionType.cardPayment &&
          item.relatedEntityType == 'cardBill' &&
          item.relatedEntityId == billId,
    );
    final total = payments.fold(0, (sum, item) => sum + item.amountMinor);
    final latest = payments.fold<DateTime?>(
      null,
      (value, item) =>
          value == null || item.date.isAfter(value) ? item.date : value,
    );
    final bills = [
      for (final item in _data.bills)
        if (item.id == billId)
          item.copyWith(
            paidMinor: total,
            paidAt: latest,
            autoDebitState: autoDebitSucceeded
                ? CardBillAutoDebitState.succeeded
                : item.autoDebitState,
          )
        else
          item,
    ];
    _store.lastSyncError = null;
    await _store.commit(_data.copyWith(bills: bills, transactions: transactions));
  }

  Future<void> deleteBillPayment(String billId, String transactionId) async {
    final transactions = _data.transactions
        .where((item) => item.id != transactionId)
        .toList();
    final remaining = transactions.where(
      (item) =>
          item.type == FinancialTransactionType.cardPayment &&
          item.relatedEntityType == 'cardBill' &&
          item.relatedEntityId == billId,
    );
    final total = remaining.fold(0, (sum, item) => sum + item.amountMinor);
    final latest = remaining.fold<DateTime?>(
      null,
      (value, item) =>
          value == null || item.date.isAfter(value) ? item.date : value,
    );
    await _store.commit(
      _data.copyWith(
        transactions: transactions,
        bills: [
          for (final bill in _data.bills)
            if (bill.id == billId)
              bill.copyWith(
                paidMinor: total,
                paidAt: latest,
                clearPaidAt: latest == null,
                autoDebitState: CardBillAutoDebitState.pending,
              )
            else
              bill,
        ],
      ),
    );
  }

  Future<void> markBillAutoDebitFailed(String billId) async {
    await _store.commit(
      _data.copyWith(
        bills: [
          for (final bill in _data.bills)
            bill.id == billId
                ? bill.copyWith(autoDebitState: CardBillAutoDebitState.failed)
                : bill,
        ],
      ),
    );
  }

  Future<void> deleteBill(String id) => _store.commit(
    _data.copyWith(
      bills: _data.bills.where((item) => item.id != id).toList(),
      transactions: _data.transactions
          .where(
            (item) =>
                item.relatedEntityId != id ||
                (item.relatedEntityType != 'cardBill' &&
                    item.relatedEntityType != 'cardBillReconciliation'),
          )
          .toList(),
    ),
  );

  /// Marks the upcoming-auto-debit reminder for this bill as seen, so it
  /// stops appearing on the dashboard and stops being pushed over LINE.
  /// Does not affect the separate "auto-debit failed"/"overdue" alerts,
  /// which stay visible until the bill is actually settled.
  Future<void> acknowledgeBillReminder(String billId) async {
    final bills = [
      for (final item in _data.bills)
        if (item.id == billId)
          item.copyWith(reminderDismissed: true)
        else
          item,
    ];
    await _store.commit(_data.copyWith(bills: bills));
  }

  /// Auto-creates the bill for each closed billing cycle that already has
  /// unbilled charges but no bill yet, so a bill shows up in "信用卡帳單"
  /// without the user having to remember to tap "新增帳單" every cycle.
  /// There is no bank integration, so the generated bill's statement
  /// amount defaults to the sum of its charges (same as leaving "銀行實際
  /// 帳單總額" blank in the manual dialog); the user still opens the bill
  /// to correct it against the real statement once it arrives.
  Future<void> ensureBillsGenerated() async {
    if (!_store.canWrite) return;
    final now = DateTime.now();
    for (final card in _data.cards) {
      if (!card.isCredit || !card.isActive) continue;
      await _ensureBillsForCard(card, now);
    }
  }

  Future<void> _ensureBillsForCard(CreditCard card, DateTime now) async {
    // The cycle containing `now` is still open; start one cycle back, which
    // has already closed.
    var cursor = DateTime(now.year, now.month);
    if (now.day > card.closingDay) {
      cursor = DateTime(cursor.year, cursor.month + 1);
    }
    cursor = DateTime(cursor.year, cursor.month - 1);

    // Bounded walk backward so a card nobody has opened the app for in a
    // long time can't loop unboundedly; three years of missed cycles is
    // already far beyond what auto-catch-up should attempt silently.
    for (var i = 0; i < 36; i++) {
      final month = _store.ledger.cardBillLabelFor(
        card,
        cursor.year,
        cursor.month,
      );
      if (_data.bills.any(
        (bill) => bill.cardId == card.id && bill.month == month,
      )) {
        // A bill already exists here; assume earlier cycles were already
        // resolved (manually or by a previous run) and stop.
        return;
      }
      final dates = _store.ledger.cardBillingDates(
        card,
        cursor.year,
        cursor.month,
      );
      final previous = DateTime(cursor.year, cursor.month - 1);
      final previousClosing = _store.ledger
          .cardBillingDates(card, previous.year, previous.month)
          .closingDate;
      final chargeIds = <String>[
        for (final expense in _data.expenses)
          if (expense.isCreditCard &&
              expense.cardId == card.id &&
              expense.date.isAfter(previousClosing) &&
              !expense.date.isAfter(dates.closingDate) &&
              _store.ledger.canAssignChargeToBill(
                'expense:${expense.id}',
                card.id,
              ))
            'expense:${expense.id}',
        for (final order in _data.orders)
          if (order.cardId == card.id &&
              order.date.isAfter(previousClosing) &&
              !order.date.isAfter(dates.closingDate) &&
              _store.ledger.canAssignChargeToBill(
                'order:${order.id}',
                card.id,
              ))
            'order:${order.id}',
      ];
      if (chargeIds.isEmpty) {
        // Nothing to bill for this closed cycle; older cycles are assumed
        // already settled.
        return;
      }
      await upsertBill(
        CardBill(
          id: _store.newId(),
          userId: card.userId,
          cardId: card.id,
          month: month,
          chargeIds: chargeIds,
          manualAdjustmentMinor: 0,
          paidMinor: 0,
          dueDate: dates.dueDate,
          autoDebitDate: dates.autoDebitDate,
          note: '',
        ),
      );
      if (_store.lastSyncError != null) return;
      cursor = previous;
    }
  }

  /// True for a bill that has never actually been reconciled against a real
  /// statement or paid against -- i.e. exactly what `_ensureBillsForCard`
  /// produces, and also a manually-created bill nobody has touched yet.
  ///
  /// `upsertBill` always normalizes a saved bill's `statementAmountMinor` to
  /// a concrete number (falling back to the calculated charge total when
  /// the caller left it blank), so a never-reconciled bill can't be
  /// recognized by `statementAmountMinor == null` once it's actually in
  /// `_data.bills` -- it never is. What `upsertBill` does guarantee is that
  /// a bill can only be stored with `reconciliationReason == none` when its
  /// difference from the calculated amount is exactly zero (a nonzero
  /// difference requires a reason). So `reconciliationReason == none`, with
  /// nothing paid against the bill yet, is exactly "still at its
  /// auto-computed default" -- safe to silently replace when a real
  /// submission comes in for the same card+month; see `upsertBill`.
  bool _isUnreconciledPlaceholder(CardBill bill) =>
      bill.reconciliationReason == CardBillReconciliationReason.none &&
      bill.paidMinor == 0 &&
      _store.ledger.billPayments(bill.id).isEmpty;
}
