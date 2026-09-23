import '../../domain/models.dart';
import '../app_store.dart';
import 'first_or_null.dart';
import 'transaction_utils.dart';

/// Group-order CRUD and collection status changes (confirm / cancel a
/// participant's payment), including mirroring an order's charge and each
/// paid participant's collection into the unified [FinancialTransaction]
/// ledger.
class OrdersManager {
  OrdersManager(this._store);

  final AppStore _store;

  AppData get _data => _store.data;

  Future<void> upsertOrder(GroupOrder order) async {
    final items = [..._data.orders];
    final index = items.indexWhere((item) => item.id == order.id);
    index < 0 ? items.add(order) : items[index] = order;
    await _store.commit(
      _data.copyWith(
        orders: items,
        transactions: replaceTransaction(
          _data.transactions,
          'order-charge:${order.id}',
          _orderFinancialTransaction(order),
        ),
      ),
    );
  }

  Future<void> deleteOrder(String id) => _store.commit(
    _data.copyWith(
      orders: _data.orders.where((item) => item.id != id).toList(),
      transactions: _data.transactions
          .where(
            (item) =>
                item.id != 'order-charge:$id' &&
                !item.id.startsWith('order-collection:$id:'),
          )
          .toList(),
    ),
  );

  Future<void> updateParticipantStatus(
    String orderId,
    String participantId,
    CollectionStatus status,
  ) async {
    final orders = _data.orders.map((order) {
      if (order.id != orderId) return order;
      return order.copyWith(
        participants: order.participants.map((participant) {
          if (participant.id != participantId) return participant;
          return participant.copyWith(
            status: status,
            collectedAt: status == CollectionStatus.paid
                ? DateTime.now()
                : null,
            clearCollectedAt: status != CollectionStatus.paid,
            cancelledAt: status == CollectionStatus.cancelled
                ? DateTime.now()
                : null,
            clearCancelledAt: status != CollectionStatus.cancelled,
          );
        }).toList(),
      );
    }).toList();
    final updatedOrder = orders.where((item) => item.id == orderId).firstOrNull;
    await _store.commit(
      _data.copyWith(
        orders: orders,
        transactions:
            [
              for (final item in _data.transactions)
                if (!(status != CollectionStatus.paid &&
                    item.id == 'order-collection:$orderId:$participantId'))
                  item,
              if (updatedOrder != null)
                _orderFinancialTransaction(updatedOrder),
            ].fold<List<FinancialTransaction>>([], (result, item) {
              result.removeWhere((existing) => existing.id == item.id);
              result.add(item);
              return result;
            }),
      ),
    );
  }

  Future<void> cancelParticipantCollection(
    String orderId,
    String participantId,
  ) => updateParticipantStatus(orderId, participantId, CollectionStatus.unpaid);

  Future<bool> confirmParticipantCollection(
    String orderId,
    String participantId,
  ) async {
    final order = _data.orders.where((item) => item.id == orderId).firstOrNull;
    final participant = order?.participants
        .where((item) => item.id == participantId)
        .firstOrNull;
    if (participant == null || participant.isSelf) {
      _store.lastSyncError = '找不到這筆待收款資料';
      _store.notify();
      return false;
    }

    String accountId;
    if (participant.collectionMethod == collectionMethodCash) {
      accountId = systemCashAccountId;
    } else if (participant.collectionMethod == collectionMethodBankTransfer) {
      final selected = participant.collectionAccountId;
      if (!_store.ledger.bankTransferAccounts.any(
        (item) => item.id == selected,
      )) {
        _store.lastSyncError = '請先選擇啟用中的 TWD 銀行轉入帳戶';
        _store.notify();
        return false;
      }
      accountId = selected!;
    } else {
      _store.lastSyncError = '請先將收款方式改為現金或銀行轉帳';
      _store.notify();
      return false;
    }

    final orders = _data.orders.map((item) {
      if (item.id != orderId) return item;
      return item.copyWith(
        participants: item.participants.map((person) {
          if (person.id != participantId) return person;
          return person.copyWith(
            status: CollectionStatus.paid,
            collectionAccountId: accountId,
            collectedAt: DateTime.now(),
            clearCancelledAt: true,
          );
        }).toList(),
      );
    }).toList();
    final collection = FinancialTransaction(
      id: 'order-collection:$orderId:$participantId',
      userId: order!.userId,
      date: DateTime.now(),
      type: FinancialTransactionType.orderCollection,
      label: '${order.name}－${participant.name}',
      amountMinor: participant.dueMinor,
      currency: 'TWD',
      relatedEntityType: 'orderParticipant',
      relatedEntityId: participant.id,
      impacts: [
        AccountImpact(
          accountId: accountId,
          amountMinor: participant.dueMinor,
          currency: 'TWD',
        ),
        AccountImpact(
          accountId: 'system-receivable',
          amountMinor: -participant.dueMinor,
          currency: 'TWD',
        ),
      ],
    );
    await _store.commit(
      _data.copyWith(
        orders: orders,
        transactions: replaceTransaction(
          _data.transactions,
          collection.id,
          collection,
        ),
      ),
    );
    return true;
  }

  FinancialTransaction _orderFinancialTransaction(GroupOrder order) {
    final card = _store.ledger.cardById(order.cardId);
    final liabilityId = card?.isCredit == true
        ? card?.liabilityAccountId
        : null;
    return FinancialTransaction(
      id: 'order-charge:${order.id}',
      userId: order.userId,
      date: order.date,
      type: FinancialTransactionType.orderCharge,
      label: order.name,
      amountMinor: order.totalMinor,
      currency: 'TWD',
      // Mirrors the order's own (isSelf) consumption category so the
      // unified-ledger transaction list matches what the user picked in the
      // 代訂 editor; null (every order created before that was configurable)
      // falls back to the built-in 餐飲 category, same as the reports P&L
      // grouping in `domain/financial_reports.dart`.
      categoryId:
          _store.ledger.categoryById(order.selfExpenseCategoryId)?.id ??
          _store.ledger.categoryById('expense-food')?.id ??
          _store.ledger.categoryByName('餐飲', BookkeepingCategoryKind.expense)?.id ??
          _data.settings.defaultExpenseCategoryId,
      note: order.note,
      relatedEntityType: 'groupOrder',
      relatedEntityId: order.id,
      impacts: [
        if (liabilityId != null)
          AccountImpact(
            accountId: liabilityId,
            amountMinor: order.totalMinor,
            currency: 'TWD',
          ),
        if (order.expectedCollectionMinor > 0)
          AccountImpact(
            accountId: 'system-receivable',
            amountMinor: order.expectedCollectionMinor,
            currency: 'TWD',
          ),
      ],
      origin: order.origin,
    );
  }
}
