import '../../domain/models.dart';
import '../app_store.dart';
import 'transaction_utils.dart';

/// Investment product CRUD, buy/sell/dividend/adjustment transactions, and
/// mirroring them into the unified [FinancialTransaction] ledger.
///
/// Linking a product to a market-catalogue quote lives in
/// [MarketDataManager] instead, since that also depends on the cached
/// catalogue itself.
class InvestmentsManager {
  InvestmentsManager(this._store);

  final AppStore _store;

  AppData get _data => _store.data;

  Future<void> upsertProduct(InvestmentProduct product) async {
    final items = [..._data.products];
    final index = items.indexWhere((item) => item.id == product.id);
    final previous = index < 0 ? null : items[index];
    index < 0 ? items.add(product) : items[index] = product;
    final history = [..._data.investmentPriceHistory];
    if (previous == null ||
        previous.currentPriceMinor != product.currentPriceMinor ||
        previous.priceUpdatedAt != product.priceUpdatedAt) {
      final day = DateTime(
        product.priceUpdatedAt.year,
        product.priceUpdatedAt.month,
        product.priceUpdatedAt.day,
      );
      history.removeWhere(
        (item) =>
            item.productId == product.id &&
            item.date.year == day.year &&
            item.date.month == day.month &&
            item.date.day == day.day,
      );
      history.add(
        InvestmentPricePoint(
          productId: product.id,
          priceMinor: product.currentPriceMinor,
          date: product.priceUpdatedAt,
        ),
      );
    }
    await _store.commit(
      _data.copyWith(products: items, investmentPriceHistory: history),
    );
  }

  Future<void> createInvestmentHolding({
    required InvestmentProduct product,
    InvestmentAdjustment? adjustment,
    InvestmentTransaction? transaction,
  }) async {
    assert(
      (adjustment == null) != (transaction == null),
      'Provide exactly one holding source.',
    );
    assert(
      (adjustment?.productId ?? transaction?.productId) == product.id,
      'The holding source must reference the supplied product.',
    );

    final products = [..._data.products];
    final productIndex = products.indexWhere((item) => item.id == product.id);
    final previous = productIndex < 0 ? null : products[productIndex];
    productIndex < 0 ? products.add(product) : products[productIndex] = product;

    final history = [..._data.investmentPriceHistory];
    if (product.currentPriceMinor > 0 &&
        (previous == null ||
            previous.currentPriceMinor != product.currentPriceMinor ||
            previous.priceUpdatedAt != product.priceUpdatedAt)) {
      final day = DateTime(
        product.priceUpdatedAt.year,
        product.priceUpdatedAt.month,
        product.priceUpdatedAt.day,
      );
      history.removeWhere(
        (item) =>
            item.productId == product.id &&
            item.date.year == day.year &&
            item.date.month == day.month &&
            item.date.day == day.day,
      );
      history.add(
        InvestmentPricePoint(
          productId: product.id,
          priceMinor: product.currentPriceMinor,
          date: product.priceUpdatedAt,
        ),
      );
    }

    final adjustments = [..._data.investmentAdjustments];
    if (adjustment != null) adjustments.add(adjustment);
    final transactions = [..._data.investmentTransactions];
    if (transaction != null) transactions.add(transaction);

    await _store.commit(
      _data.copyWith(
        products: products,
        investmentAdjustments: adjustments,
        investmentTransactions: transactions,
        investmentPriceHistory: history,
        transactions: transaction == null
            ? _data.transactions
            : replaceTransaction(
                _data.transactions,
                'investment:${transaction.id}',
                _investmentFinancialTransaction(transaction),
              ),
      ),
    );
  }

  Future<void> deleteProduct(String id) => _store.commit(
    _data.copyWith(
      products: _data.products.where((item) => item.id != id).toList(),
      investmentTransactions: _data.investmentTransactions
          .where((item) => item.productId != id)
          .toList(),
      investmentAdjustments: _data.investmentAdjustments
          .where((item) => item.productId != id)
          .toList(),
      investmentPriceHistory: _data.investmentPriceHistory
          .where((item) => item.productId != id)
          .toList(),
      transactions: _data.transactions
          .where(
            (item) =>
                item.relatedEntityType != 'investmentTransaction' ||
                !_data.investmentTransactions
                    .where((transaction) => transaction.productId == id)
                    .any(
                      (transaction) => transaction.id == item.relatedEntityId,
                    ),
          )
          .toList(),
      reconciliations: _data.reconciliations
          .where(
            (item) =>
                item.targetType != ReconciliationTargetType.investment ||
                item.targetId != id,
          )
          .toList(),
    ),
  );

  Future<void> upsertInvestmentTransaction(
    InvestmentTransaction transaction,
  ) async {
    final items = [..._data.investmentTransactions];
    final index = items.indexWhere((item) => item.id == transaction.id);
    index < 0 ? items.add(transaction) : items[index] = transaction;
    await _store.commit(
      _data.copyWith(
        investmentTransactions: items,
        transactions: replaceTransaction(
          _data.transactions,
          'investment:${transaction.id}',
          _investmentFinancialTransaction(transaction),
        ),
      ),
    );
  }

  Future<void> deleteInvestmentTransaction(String id) => _store.commit(
    _data.copyWith(
      investmentTransactions: _data.investmentTransactions
          .where((item) => item.id != id)
          .toList(),
      transactions: _data.transactions
          .where((item) => item.id != 'investment:$id')
          .toList(),
    ),
  );

  Future<void> upsertInvestmentAdjustment(
    InvestmentAdjustment adjustment,
  ) async {
    final items = [..._data.investmentAdjustments];
    final index = items.indexWhere((item) => item.id == adjustment.id);
    index < 0 ? items.add(adjustment) : items[index] = adjustment;
    await _store.commit(_data.copyWith(investmentAdjustments: items));
  }

  /// Deleting a snapshot that a 對帳 booked also deletes that
  /// reconciliation record, same as for account balance adjustments.
  Future<void> deleteInvestmentAdjustment(String id) => _store.commit(
    _data.copyWith(
      investmentAdjustments: _data.investmentAdjustments
          .where((item) => item.id != id)
          .toList(),
      reconciliations: _data.reconciliations
          .where(
            (item) =>
                item.targetType != ReconciliationTargetType.investment ||
                item.adjustmentId != id,
          )
          .toList(),
    ),
  );

  /// 投資對帳: compares the holding the books show for [productId] at the
  /// end of [date] with the units (and, optionally, average cost) the
  /// broker reports. When they differ, an [InvestmentAdjustment] snapshot
  /// dated at the end of that day resets the holding to the broker's
  /// figures — later transactions still apply on top of it. A
  /// [ReconciliationRecord] keeps both sides, plus their market values at
  /// the product's current price.
  Future<void> reconcileInvestment({
    required String productId,
    required int actualQuantityMicros,
    required DateTime date,
    int? actualAverageCostMinor,
    String note = '',
  }) async {
    final product = _store.ledger.productById(productId);
    if (product == null) {
      _store.lastSyncError = '找不到這個投資商品';
      _store.notify();
      return;
    }
    if (actualQuantityMicros < 0 ||
        (actualAverageCostMinor != null && actualAverageCostMinor < 0)) {
      _store.lastSyncError = '持有數量與平均成本不可為負數';
      _store.notify();
      return;
    }
    final day = DateTime(date.year, date.month, date.day);
    final book = _store.ledger.holdingAt(productId, day);
    final actualAverageCost = actualQuantityMicros == 0
        ? 0
        : actualAverageCostMinor ?? book.averageCostMinor;
    final changed =
        actualQuantityMicros != book.quantityMicros ||
        actualAverageCost != book.averageCostMinor;
    final trimmedNote = note.trim();
    final adjustmentId = changed ? _store.newId() : null;
    int valueOf(int quantityMicros) =>
        (quantityMicros * product.currentPriceMinor / 1000000).round();
    final record = ReconciliationRecord(
      id: _store.newId(),
      userId: _store.userId,
      targetType: ReconciliationTargetType.investment,
      targetId: productId,
      date: day,
      bookBalanceMinor: valueOf(book.quantityMicros),
      actualBalanceMinor: valueOf(actualQuantityMicros),
      currency: product.currency,
      adjustmentId: adjustmentId,
      note: trimmedNote,
      createdAt: DateTime.now(),
      bookQuantityMicros: book.quantityMicros,
      actualQuantityMicros: actualQuantityMicros,
      bookAverageCostMinor: book.averageCostMinor,
      actualAverageCostMinor: actualAverageCost,
      origin: product.origin,
    );
    _store.lastSyncError = null;
    await _store.commit(
      _data.copyWith(
        reconciliations: [..._data.reconciliations, record],
        investmentAdjustments: adjustmentId == null
            ? null
            : [
                ..._data.investmentAdjustments,
                InvestmentAdjustment(
                  id: adjustmentId,
                  userId: _store.userId,
                  productId: productId,
                  // End of the checked day, so the snapshot replaces the
                  // result of that day's own trades instead of being
                  // replayed before them.
                  date: DateTime(day.year, day.month, day.day, 23, 59, 59),
                  quantityMicros: actualQuantityMicros,
                  averageCostMinor: actualAverageCost,
                  reason: trimmedNote.isEmpty
                      ? '對帳調整'
                      : '對帳調整：$trimmedNote',
                  origin: product.origin,
                ),
              ],
      ),
    );
  }

  FinancialTransaction _investmentFinancialTransaction(
    InvestmentTransaction transaction,
  ) {
    final inflow = const {
      InvestmentTransactionType.sell,
      InvestmentTransactionType.redeem,
      InvestmentTransactionType.dividend,
    }.contains(transaction.type);
    final amount = inflow
        ? transaction.grossMinor - transaction.feeMinor - transaction.taxMinor
        : transaction.grossMinor + transaction.feeMinor + transaction.taxMinor;
    final accountId = inflow
        ? transaction.creditAccountId
        : transaction.debitAccountId;
    final type = transaction.type == InvestmentTransactionType.dividend
        ? FinancialTransactionType.investmentDividend
        : inflow
        ? FinancialTransactionType.investmentSell
        : FinancialTransactionType.investmentBuy;
    return FinancialTransaction(
      id: 'investment:${transaction.id}',
      userId: transaction.userId,
      date: transaction.date,
      type: type,
      label: _store.ledger.productById(transaction.productId)?.name ?? '投資交易',
      amountMinor: amount,
      currency:
          _store.ledger.productById(transaction.productId)?.currency ??
          _store.ledger.accountById(accountId)?.currency ??
          'TWD',
      note: transaction.note,
      relatedEntityType: 'investmentTransaction',
      relatedEntityId: transaction.id,
      impacts: accountId == null
          ? const []
          : [
              AccountImpact(
                accountId: accountId,
                amountMinor: inflow ? amount : -amount,
                currency: _store.ledger.accountById(accountId)?.currency ?? 'TWD',
              ),
            ],
      origin: transaction.origin,
    );
  }
}
