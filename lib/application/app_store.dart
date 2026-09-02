import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../data/repositories.dart';
import '../data/ocr_models.dart';
import '../domain/models.dart';

class AppStore extends ChangeNotifier {
  AppStore({
    required AuthRepository authRepository,
    required FinanceRepository financeRepository,
    required CsvExportService csvExportService,
    OrderImportRepository? orderImportRepository,
    PublicCollectionRepository? publicCollectionRepository,
    MarketDataRepository? marketDataRepository,
    Uuid uuid = const Uuid(),
  }) : _auth = authRepository,
       _finance = financeRepository,
       _csv = csvExportService,
       _orderImport = orderImportRepository,
       _publicCollection = publicCollectionRepository,
       _marketData = marketDataRepository,
       _uuid = uuid;

  final AuthRepository _auth;
  final FinanceRepository _finance;
  final CsvExportService _csv;
  final OrderImportRepository? _orderImport;
  final PublicCollectionRepository? _publicCollection;
  final MarketDataRepository? _marketData;
  final Uuid _uuid;
  StreamSubscription<bool>? _authSubscription;

  AppData data = const AppData();
  bool initialized = false;
  bool isOffline = false;
  bool isSaving = false;
  bool hasConflict = false;
  String? lastSyncError;
  AppData? localMigrationCandidate;
  DateTime? cloudUpdatedAt;
  bool cloudExists = false;
  List<MarketInstrument> marketCatalog = const [];
  bool isLoadingMarketCatalog = false;
  String? marketDataError;

  bool get isSignedIn => _auth.isSignedIn;
  String get userId => _auth.currentUserId ?? 'demo-line-user';
  String? get userDisplayName => _auth.currentUserDisplayName;
  bool get needsInitialMigration => localMigrationCandidate != null;
  bool get canWrite =>
      isSignedIn &&
      !isOffline &&
      !isSaving &&
      !hasConflict &&
      !needsInitialMigration;

  Future<void> initialize() async {
    await _loadFinance();
    if (isSignedIn && !isOffline) {
      unawaited(refreshMarketData());
    }
    _authSubscription = _auth.authStateChanges.listen((_) async {
      await _loadFinance();
      if (isSignedIn && !isOffline) {
        await refreshMarketData();
      }
    });
    initialized = true;
    notifyListeners();
  }

  Future<void> ensureMarketCatalog({bool forceRefresh = false}) async {
    final repository = _marketData;
    if (repository == null || isLoadingMarketCatalog) return;
    if (!forceRefresh && marketCatalog.isNotEmpty) return;
    isLoadingMarketCatalog = true;
    marketDataError = null;
    notifyListeners();
    try {
      marketCatalog = await repository.loadCatalog(forceRefresh: forceRefresh);
    } on Object catch (error) {
      debugPrint('Market catalogue load failed: $error');
      marketDataError = '上市商品資料暫時無法取得';
    } finally {
      isLoadingMarketCatalog = false;
      notifyListeners();
    }
  }

  List<MarketInstrument> searchMarketCatalog(String query) {
    final normalized = query.trim().toUpperCase().replaceAll(
      RegExp(r'\s+'),
      '',
    );
    if (normalized.length < 2) return const [];
    final result = marketCatalog
        .where(
          (item) =>
              item.symbol.toUpperCase().contains(normalized) ||
              item.name.replaceAll(RegExp(r'\s+'), '').contains(normalized),
        )
        .toList();
    result.sort((left, right) {
      final exact = (left.symbol == normalized ? 0 : 1).compareTo(
        right.symbol == normalized ? 0 : 1,
      );
      if (exact != 0) return exact;
      final prefix = (left.symbol.startsWith(normalized) ? 0 : 1).compareTo(
        right.symbol.startsWith(normalized) ? 0 : 1,
      );
      return prefix != 0 ? prefix : left.symbol.compareTo(right.symbol);
    });
    return result.take(8).toList();
  }

  Future<void> refreshMarketData() async {
    final repository = _marketData;
    if (repository == null || !isSignedIn || isOffline) return;
    await ensureMarketCatalog();
    final symbols = data.products
        .where((item) => item.usesAutomaticQuote)
        .map((item) => item.marketSymbol!)
        .toSet();
    if (symbols.isEmpty) return;
    try {
      await repository.quotes(symbols);
      await _loadFinance();
    } on Object catch (error) {
      debugPrint('Market quote refresh failed: $error');
      marketDataError = '收盤價更新失敗，暫時沿用最後有效價格';
      notifyListeners();
    }
  }

  Map<String, MarketInstrument> get existingMarketLinkCandidates {
    final result = <String, MarketInstrument>{};
    for (final product in data.products.where(
      (item) => !item.usesAutomaticQuote && item.symbol.trim().isNotEmpty,
    )) {
      final symbol = product.symbol.trim().toUpperCase();
      final match = marketCatalog
          .where((item) => item.symbol == symbol)
          .firstOrNull;
      if (match != null) result[product.id] = match;
    }
    return result;
  }

  Future<void> linkMarketProducts(Map<String, MarketInstrument> links) async {
    if (links.isEmpty) return;
    final now = DateTime.now();
    final products = [
      for (final product in data.products)
        if (links[product.id] case final instrument?)
          product.copyWith(
            symbol: instrument.symbol,
            name: instrument.name,
            type: instrument.type,
            currency: instrument.currency,
            currentPriceMinor: instrument.closePriceMinor,
            priceUpdatedAt: instrument.quoteDate ?? now,
            priceSource: 'twse',
            market: instrument.market,
            marketSymbol: instrument.symbol,
            quoteLinkedAt: now,
          )
        else
          product,
    ];
    await _commit(data.copyWith(products: products));
  }

  Future<void> unlinkMarketProduct(String productId) async {
    await _commit(
      data.copyWith(
        products: [
          for (final product in data.products)
            if (product.id == productId)
              product.copyWith(
                priceSource: 'manual',
                clearMarketLink: true,
                priceUpdatedAt: DateTime.now(),
              )
            else
              product,
        ],
      ),
    );
  }

  Future<void> _loadFinance() async {
    if (!isSignedIn) {
      data = const AppData();
      isOffline = false;
      cloudExists = false;
      cloudUpdatedAt = null;
      localMigrationCandidate = null;
      hasConflict = false;
      lastSyncError = null;
      notifyListeners();
      return;
    }
    try {
      final snapshot = await _finance.load();
      _applySnapshot(snapshot);
      lastSyncError = snapshot.isOffline ? '目前離線，資料僅供查看' : null;
    } on Object catch (error) {
      isOffline = true;
      debugPrint('Finance load failed: $error');
      lastSyncError = '目前無法連線到雲端，資料僅供查看';
    }
    notifyListeners();
  }

  void _applySnapshot(FinanceSnapshot snapshot) {
    data = _withSystemCashAccount(snapshot.data);
    isOffline = snapshot.isOffline;
    cloudExists = snapshot.cloudExists;
    cloudUpdatedAt = snapshot.updatedAt;
    localMigrationCandidate = snapshot.localCandidate;
    hasConflict = false;
  }

  AppData _withSystemCashAccount(AppData source) {
    final createdAt = DateTime.utc(2026, 1, 1);
    final accounts = [...source.accounts];
    if (!accounts.any((item) => item.id == systemCashAccountId)) {
      accounts.insert(
        0,
        Account(
          id: systemCashAccountId,
          userId: userId,
          name: '現金',
          institution: '',
          type: '現金',
          currency: 'TWD',
          openingBalanceMinor: 0,
          isActive: true,
          note: '系統固定帳戶',
          createdAt: createdAt,
          updatedAt: createdAt,
          subtype: 'cash',
        ),
      );
    }
    if (!accounts.any((item) => item.id == 'system-receivable')) {
      accounts.add(
        Account(
          id: 'system-receivable',
          userId: userId,
          name: '代訂應收款',
          institution: '',
          type: '應收款',
          currency: 'TWD',
          openingBalanceMinor: 0,
          isActive: true,
          note: '系統帳戶',
          createdAt: createdAt,
          updatedAt: createdAt,
          kind: FinancialAccountKind.receivable,
          subtype: 'orderReceivable',
        ),
      );
    }
    final cards = <CreditCard>[];
    for (final card in source.cards) {
      final liabilityId =
          card.liabilityAccountId ?? 'card-liability-${card.id}';
      if (card.isCredit && !accounts.any((item) => item.id == liabilityId)) {
        accounts.add(
          Account(
            id: liabilityId,
            userId: userId,
            name: '${card.name}未繳',
            institution: card.bank,
            type: '信用卡負債',
            currency: 'TWD',
            openingBalanceMinor: 0,
            isActive: card.isActive,
            note: '信用卡負債帳戶',
            createdAt: createdAt,
            updatedAt: createdAt,
            kind: FinancialAccountKind.liability,
            subtype: 'creditCard',
          ),
        );
      }
      cards.add(
        CreditCard(
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
          liabilityAccountId: card.isCredit ? liabilityId : null,
          origin: card.origin,
        ),
      );
    }
    final categories = source.categories.isEmpty
        ? defaultBookkeepingCategories(userId)
        : source.categories;
    final defaultCategory = categories
        .where(
          (item) =>
              item.kind == BookkeepingCategoryKind.expense &&
              item.name == source.settings.defaultCategory,
        )
        .firstOrNull;
    return source.copyWith(
      accounts: accounts,
      cards: cards,
      categories: categories,
      settings: source.settings.copyWith(
        defaultExpenseCategoryId:
            defaultCategory?.id ?? source.settings.defaultExpenseCategoryId,
      ),
    );
  }

  List<BookkeepingCategory> categoriesFor(
    BookkeepingCategoryKind kind, {
    bool activeOnly = false,
  }) {
    final result =
        data.categories
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
      data.categories.where((item) => item.id == id).firstOrNull;

  BookkeepingCategory? categoryByName(
    String name,
    BookkeepingCategoryKind kind,
  ) => data.categories
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

  List<Account> get bankTransferAccounts => data.accounts
      .where(
        (item) =>
            item.isActive && item.type == '銀行帳戶' && item.currency == 'TWD',
      )
      .toList();

  /// Active asset accounts that can actually receive or pay money.
  /// Internal liability and receivable ledger accounts are intentionally
  /// excluded from user-facing account selectors.
  List<Account> get activeAssetAccounts => data.accounts
      .where((item) => item.isActive && item.kind == FinancialAccountKind.asset)
      .toList();

  String get lastCollectionMethod {
    final collected =
        data.orders
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

  String? get defaultBankTransferAccountId {
    final configured = data.settings.defaultCollectionAccountId;
    if (bankTransferAccounts.any((item) => item.id == configured)) {
      return configured;
    }
    return bankTransferAccounts.firstOrNull?.id;
  }

  Future<void> resolveInitialMigration(InitialMigrationAction action) async {
    if (localMigrationCandidate == null || isSaving) return;
    isSaving = true;
    lastSyncError = null;
    notifyListeners();
    try {
      final snapshot = await _finance.resolveInitialMigration(action);
      _applySnapshot(snapshot);
    } on FinanceConflictException catch (error) {
      hasConflict = true;
      lastSyncError = error.toString();
    } on Object catch (error) {
      debugPrint('Initial migration failed: $error');
      lastSyncError = '資料處理失敗，請稍後再試';
    } finally {
      isSaving = false;
      notifyListeners();
    }
  }

  Future<void> reloadCloud() async {
    hasConflict = false;
    lastSyncError = null;
    await _loadFinance();
  }

  Future<void> signIn({String? returnPath}) =>
      _auth.signInWithLine(returnPath: returnPath);
  Future<void> signOut() => _auth.signOut();
  Future<PublicCollectionDetails?> loadPublicCollection(String token) {
    final repository = _publicCollection;
    if (repository == null) {
      throw StateError('尚未設定雲端收款服務');
    }
    return repository.load(token);
  }

  Future<void> markPublicCollectionPending(String token) {
    final repository = _publicCollection;
    if (repository == null) {
      throw StateError('尚未設定雲端收款服務');
    }
    return repository.markPending(token);
  }

  Future<ImportedOrder> importUberEats(
    List<ImportImage> images, {
    OcrProgressCallback? onProgress,
  }) {
    final repository = _orderImport;
    if (repository == null) {
      throw StateError('尚未設定 Supabase 截圖辨識服務');
    }
    return repository.importUberEats(images, onProgress: onProgress);
  }

  Future<void> _commit(AppData next) async {
    if (!canWrite) {
      lastSyncError = isOffline
          ? '目前離線，無法修改資料'
          : hasConflict
          ? '雲端資料已更新，請先重新載入'
          : needsInitialMigration
          ? '請先選擇如何處理本機資料'
          : '資料正在同步，請稍候';
      notifyListeners();
      return;
    }
    isSaving = true;
    lastSyncError = null;
    notifyListeners();
    try {
      final result = await _finance.save(next);
      data = next;
      cloudExists = true;
      cloudUpdatedAt = result.updatedAt;
    } on FinanceConflictException catch (error) {
      hasConflict = true;
      lastSyncError = error.toString();
    } on Object catch (error) {
      debugPrint('Finance save failed: $error');
      lastSyncError = '同步失敗，資料尚未儲存，請稍後再試';
    } finally {
      isSaving = false;
      notifyListeners();
    }
  }

  int accountBalance(String accountId) {
    final account = data.accounts
        .where((item) => item.id == accountId)
        .firstOrNull;
    if (account == null) return 0;
    if (account.kind != FinancialAccountKind.asset) {
      return account.openingBalanceMinor +
          data.transactions
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

  List<LedgerEffect> get ledgerEffects {
    final effects = <LedgerEffect>[];
    final mirrored = data.transactions.map((item) => item.id).toSet();
    for (final transaction in data.transactions) {
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
    for (final adjustment in data.balanceAdjustments) {
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
    for (final income in data.incomes) {
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
    for (final expense in data.expenses.where(
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
    for (final transaction in data.investmentTransactions) {
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
    for (final bill in data.bills) {
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
    for (final payment in data.telecomBillPayments) {
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
    for (final order in data.orders) {
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
    return effects;
  }

  Account? accountById(String? id) =>
      data.accounts.where((item) => item.id == id).firstOrNull;
  CreditCard? cardById(String? id) =>
      data.cards.where((item) => item.id == id).firstOrNull;
  RecurringExpense? get activeTelecomExpense => data.recurringExpenses
      .where((item) => item.isActive && item.isTelecom)
      .firstOrNull;
  InvestmentProduct? productById(String? id) =>
      data.products.where((item) => item.id == id).firstOrNull;

  String? cardIdForCharge(String chargeId) {
    if (chargeId.startsWith('expense:')) {
      final id = chargeId.substring('expense:'.length);
      final expense = data.expenses.where((item) => item.id == id).firstOrNull;
      return expense?.isCreditCard == true ? expense?.cardId : null;
    }
    if (chargeId.startsWith('order:')) {
      final id = chargeId.substring('order:'.length);
      return data.orders.where((item) => item.id == id).firstOrNull?.cardId;
    }
    return null;
  }

  String? _explicitBillIdForCharge(String chargeId) {
    if (chargeId.startsWith('expense:')) {
      final id = chargeId.substring('expense:'.length);
      return data.expenses.where((item) => item.id == id).firstOrNull?.billId;
    }
    if (chargeId.startsWith('order:')) {
      final id = chargeId.substring('order:'.length);
      return data.orders.where((item) => item.id == id).firstOrNull?.billId;
    }
    return null;
  }

  Map<String, CardBill> get cardChargeBills {
    final owners = <String, CardBill>{};
    final billsById = {for (final bill in data.bills) bill.id: bill};
    final referenced = <String>{
      for (final bill in data.bills) ...bill.chargeIds,
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
    for (final bill in data.bills) {
      for (final chargeId in bill.chargeIds) {
        if (cardIdForCharge(chargeId) == bill.cardId) {
          owners.putIfAbsent(chargeId, () => bill);
        }
      }
    }
    return owners;
  }

  CardBill? cardBillForCharge(String chargeId) => cardChargeBills[chargeId];

  bool canAssignChargeToBill(String chargeId, String cardId, {String? billId}) {
    if (cardIdForCharge(chargeId) != cardId) return false;
    final owner = cardBillForCharge(chargeId);
    return owner == null || owner.id == billId;
  }

  int unbilledCardMinor(String cardId) {
    final billed = cardChargeBills.keys.toSet();
    final expenses = data.expenses
        .where(
          (item) =>
              item.isCreditCard &&
              item.cardId == cardId &&
              !billed.contains('expense:${item.id}'),
        )
        .fold(0, (sum, item) => sum + item.amountMinor);
    final orders = data.orders
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
        amount += data.expenses
            .where((item) => item.id == expenseId)
            .fold(0, (sum, item) => sum + item.amountMinor);
      } else if (id.startsWith('order:')) {
        final orderId = id.substring('order:'.length);
        amount += data.orders
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
    final result = data.transactions
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

  int get pendingCardMinor {
    final ownedCharges = cardChargeBills.keys.toSet();
    final unbilledExpenses = data.expenses
        .where(
          (item) =>
              item.isCreditCard && !ownedCharges.contains('expense:${item.id}'),
        )
        .fold(0, (sum, item) => sum + item.amountMinor);
    final unbilledOrders = data.orders
        .where((item) => !ownedCharges.contains('order:${item.id}'))
        .fold(0, (sum, item) => sum + item.totalMinor);
    final outstandingBills = data.bills.fold(0, (sum, bill) {
      final remaining = billAmount(bill) - paidBillMinor(bill);
      return sum + (remaining < 0 ? 0 : remaining);
    });
    return unbilledExpenses + unbilledOrders + outstandingBills;
  }

  int get pendingTelecomMinor {
    final paidExpenseIds = <String>{
      for (final payment in data.telecomBillPayments) ...payment.expenseIds,
    };
    return data.expenses
        .where(
          (item) =>
              item.paymentMethod == PaymentMethod.telecomBill &&
              !paidExpenseIds.contains(item.id),
        )
        .fold(0, (sum, item) => sum + item.amountMinor);
  }

  int get currentMonthExpenseMinor {
    final now = DateTime.now();
    final expenses = data.expenses
        .where(
          (item) => item.date.year == now.year && item.date.month == now.month,
        )
        .fold(0, (sum, item) => sum + item.amountMinor);
    final orders = data.orders
        .where(
          (item) => item.date.year == now.year && item.date.month == now.month,
        )
        .fold(0, (sum, item) => sum + item.selfExpenseMinor);
    return expenses + orders;
  }

  int get currentMonthCollectionResultMinor {
    final now = DateTime.now();
    return data.orders.fold(0, (orderSum, order) {
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
      data.orders.fold(0, (sum, order) => sum + order.outstandingMinor);

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
    for (final income in data.incomes.where(
      (item) => item.date.year == now.year && item.date.month == now.month,
    )) {
      final currency =
          accountById(income.accountId)?.currency ??
          data.settings.defaultCurrency;
      final converted = convertToDefault(income.amountMinor, currency);
      if (converted != null) total += converted;
    }
    return total;
  }

  int get currentMonthBalanceDefaultMinor =>
      currentMonthIncomeDefaultMinor - currentMonthExpenseDefaultMinor;

  FxRate? fxRateFor(String currency) {
    if (currency == data.settings.defaultCurrency) {
      return FxRate(
        from: currency,
        to: currency,
        rateMicros: 1000000,
        updatedAt: DateTime.now(),
      );
    }
    final rates =
        data.settings.fxRates
            .where(
              (rate) =>
                  rate.from == currency &&
                  rate.to == data.settings.defaultCurrency,
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
      ...data.accounts.map((item) => item.currency),
      ...data.products.map((item) => item.currency),
      if (data.expenses.isNotEmpty ||
          data.orders.isNotEmpty ||
          data.bills.isNotEmpty)
        'TWD',
    };
    return currencies
        .where(
          (currency) =>
              currency != data.settings.defaultCurrency &&
              fxRateFor(currency) == null,
        )
        .toSet();
  }

  int get depositTotalMinor {
    var total = 0;
    for (final account in data.accounts.where(
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
    final result = <String, Holding>{};
    for (final product in data.products) {
      final events =
          <
              ({
                DateTime date,
                InvestmentTransaction? tx,
                InvestmentAdjustment? adjustment,
              })
            >[
              ...data.investmentTransactions
                  .where((item) => item.productId == product.id)
                  .map((item) => (date: item.date, tx: item, adjustment: null)),
              ...data.investmentAdjustments
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
    return result;
  }

  int get investmentValueMinor {
    var total = 0;
    for (final product in data.products) {
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
    if (!data.settings.remindersEnabled) return const [];
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final items = <ReminderItem>[];
    for (final bill in data.bills) {
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
          ),
        );
        continue;
      }
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
          ),
        );
      }
    }
    for (final payment in data.telecomBillPayments.where(
      (item) => item.balanceInsufficient,
    )) {
      final rule = data.recurringExpenses
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

  Future<void> upsertAccount(Account account) async {
    if (account.id == systemCashAccountId) {
      lastSyncError = '系統現金帳戶不可編輯';
      notifyListeners();
      return;
    }
    final items = [...data.accounts];
    final index = items.indexWhere((item) => item.id == account.id);
    final adjustments = [...data.balanceAdjustments];
    var normalized = account;
    if (index >= 0) {
      final previous = items[index];
      final difference =
          account.openingBalanceMinor - previous.openingBalanceMinor;
      if (difference != 0) {
        adjustments.add(
          BalanceAdjustment(
            id: newId(),
            userId: userId,
            accountId: account.id,
            amountMinor: difference,
            date: DateTime.now(),
            reason: '期初餘額修改轉列調整',
            origin: account.origin,
          ),
        );
        normalized = account.copyWith(
          openingBalanceMinor: previous.openingBalanceMinor,
          openingBalanceDate: previous.openingBalanceDate,
        );
      }
    }
    index < 0 ? items.add(normalized) : items[index] = normalized;
    await _commit(
      data.copyWith(accounts: items, balanceAdjustments: adjustments),
    );
  }

  Future<void> mergeAccounts({
    required String sourceAccountId,
    required String targetAccountId,
  }) async {
    if (sourceAccountId == targetAccountId) {
      lastSyncError = '請選擇不同的保留帳戶';
      notifyListeners();
      return;
    }
    if (sourceAccountId == systemCashAccountId) {
      lastSyncError = '系統現金帳戶不可被合併';
      notifyListeners();
      return;
    }
    final source = accountById(sourceAccountId);
    final target = accountById(targetAccountId);
    if (source == null || target == null) {
      lastSyncError = '找不到要合併的帳戶';
      notifyListeners();
      return;
    }
    if (source.kind != FinancialAccountKind.asset ||
        target.kind != FinancialAccountKind.asset) {
      lastSyncError = '只能合併資產帳戶';
      notifyListeners();
      return;
    }
    if (source.currency != target.currency) {
      lastSyncError = '不同幣別的帳戶無法合併';
      notifyListeners();
      return;
    }

    final json = data.toJson();
    final accounts = (json['accounts'] as List).cast<Map<String, dynamic>>();
    final targetJson = accounts.firstWhere(
      (item) => item['id'] == targetAccountId,
    );
    targetJson['openingBalanceMinor'] =
        target.openingBalanceMinor + source.openingBalanceMinor;
    final earliestOpening =
        source.effectiveOpeningBalanceDate.isBefore(
          target.effectiveOpeningBalanceDate,
        )
        ? source.effectiveOpeningBalanceDate
        : target.effectiveOpeningBalanceDate;
    targetJson['openingBalanceDate'] = earliestOpening.toIso8601String();
    targetJson['updatedAt'] = DateTime.now().toIso8601String();
    accounts.removeWhere((item) => item['id'] == sourceAccountId);

    void replaceField(Map<String, dynamic> item, String key) {
      if (item[key] == sourceAccountId) item[key] = targetAccountId;
    }

    for (final raw in json['transactions'] as List) {
      final transaction = raw as Map<String, dynamic>;
      final totals = <String, int>{};
      for (final impactRaw in transaction['impacts'] as List) {
        final impact = impactRaw as Map<String, dynamic>;
        replaceField(impact, 'accountId');
        final key = '${impact['accountId']}\u0000${impact['currency']}';
        totals[key] = (totals[key] ?? 0) + impact['amountMinor'] as int;
      }
      transaction['impacts'] = [
        for (final entry in totals.entries)
          if (entry.value != 0)
            {
              'accountId': entry.key.split('\u0000').first,
              'currency': entry.key.split('\u0000').last,
              'amountMinor': entry.value,
            },
      ];
    }
    for (final raw in json['balanceAdjustments'] as List) {
      replaceField(raw as Map<String, dynamic>, 'accountId');
    }
    for (final raw in json['expenses'] as List) {
      replaceField(raw as Map<String, dynamic>, 'accountId');
    }
    for (final raw in json['recurringExpenses'] as List) {
      final item = raw as Map<String, dynamic>;
      replaceField(item, 'accountId');
      replaceField(item, 'telecomDebitAccountId');
    }
    for (final raw in json['telecomBillPayments'] as List) {
      replaceField(raw as Map<String, dynamic>, 'debitAccountId');
    }
    for (final raw in json['incomes'] as List) {
      replaceField(raw as Map<String, dynamic>, 'accountId');
    }
    for (final raw in json['cards'] as List) {
      replaceField(raw as Map<String, dynamic>, 'debitAccountId');
    }
    for (final raw in json['investmentTransactions'] as List) {
      final item = raw as Map<String, dynamic>;
      replaceField(item, 'debitAccountId');
      replaceField(item, 'creditAccountId');
    }
    for (final raw in json['orders'] as List) {
      final order = raw as Map<String, dynamic>;
      for (final participantRaw in order['participants'] as List) {
        replaceField(
          participantRaw as Map<String, dynamic>,
          'collectionAccountId',
        );
      }
    }
    replaceField(
      json['settings'] as Map<String, dynamic>,
      'defaultCollectionAccountId',
    );

    await _commit(AppData.fromJson(json));
  }

  Future<void> deleteAccount(String id) async {
    if (id == systemCashAccountId) {
      lastSyncError = '系統現金帳戶不可刪除';
      notifyListeners();
      return;
    }
    final references = <String>[
      if (data.cards.any((item) => item.debitAccountId == id)) '卡片綁定帳戶',
      if (data.expenses.any((item) => item.accountId == id)) '支出',
      if (data.recurringExpenses.any(
        (item) => item.accountId == id || item.telecomDebitAccountId == id,
      ))
        '固定支出',
      if (data.telecomBillPayments.any((item) => item.debitAccountId == id))
        '電信帳單',
      if (data.incomes.any((item) => item.accountId == id)) '收入',
      if (data.investmentTransactions.any(
        (item) => item.debitAccountId == id || item.creditAccountId == id,
      ))
        '投資交易',
      if (data.transactions.any(
        (item) =>
            item.type == FinancialTransactionType.transfer &&
            item.impacts.any((impact) => impact.accountId == id),
      ))
        '轉帳紀錄',
      if (data.orders.any(
        (order) => order.participants.any(
          (participant) => participant.collectionAccountId == id,
        ),
      ))
        '收款紀錄',
      if (data.settings.defaultCollectionAccountId == id) '預設收款設定',
    ];
    if (references.isNotEmpty) {
      lastSyncError = '無法刪除帳戶，仍被${references.join('、')}引用';
      notifyListeners();
      return;
    }
    await _commit(
      data.copyWith(
        accounts: data.accounts.where((item) => item.id != id).toList(),
      ),
    );
  }

  Future<void> addBalanceAdjustment(BalanceAdjustment adjustment) =>
      upsertBalanceAdjustment(adjustment);

  Future<void> upsertAccountTransfer({
    required String id,
    required String fromAccountId,
    required String toAccountId,
    required int amountMinor,
    required DateTime date,
    String note = '',
  }) async {
    final from = accountById(fromAccountId);
    final to = accountById(toAccountId);
    if (from == null || to == null || !from.isActive || !to.isActive) {
      lastSyncError = '請選擇已啟用的轉出與轉入帳戶';
      notifyListeners();
      return;
    }
    if (from.id == to.id) {
      lastSyncError = '轉出與轉入帳戶不能相同';
      notifyListeners();
      return;
    }
    if (from.currency != to.currency) {
      lastSyncError = '目前僅支援相同幣別的帳戶間轉帳';
      notifyListeners();
      return;
    }
    if (amountMinor <= 0) {
      lastSyncError = '轉帳金額必須大於 0';
      notifyListeners();
      return;
    }
    lastSyncError = null;
    final transactionId = id.startsWith('transfer:') ? id : 'transfer:$id';
    await _commit(
      data.copyWith(
        transactions: _replaceTransaction(
          transactionId,
          FinancialTransaction(
            id: transactionId,
            userId: userId,
            date: date,
            type: FinancialTransactionType.transfer,
            label: '${from.name} → ${to.name}',
            amountMinor: amountMinor,
            currency: from.currency,
            note: note.trim(),
            impacts: [
              AccountImpact(
                accountId: from.id,
                amountMinor: -amountMinor,
                currency: from.currency,
              ),
              AccountImpact(
                accountId: to.id,
                amountMinor: amountMinor,
                currency: to.currency,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> deleteAccountTransfer(String id) => _commit(
    data.copyWith(
      transactions: data.transactions.where((item) => item.id != id).toList(),
    ),
  );

  Future<void> upsertBalanceAdjustment(BalanceAdjustment adjustment) async {
    final items = [...data.balanceAdjustments];
    final index = items.indexWhere((item) => item.id == adjustment.id);
    index < 0 ? items.add(adjustment) : items[index] = adjustment;
    await _commit(
      data.copyWith(
        balanceAdjustments: items,
        transactions: _replaceTransaction(
          'balance:${adjustment.id}',
          FinancialTransaction(
            id: 'balance:${adjustment.id}',
            userId: adjustment.userId,
            date: adjustment.date,
            type: FinancialTransactionType.balanceAdjustment,
            label: adjustment.reason,
            amountMinor: adjustment.amountMinor.abs(),
            currency: accountById(adjustment.accountId)?.currency ?? 'TWD',
            impacts: [
              AccountImpact(
                accountId: adjustment.accountId,
                amountMinor: adjustment.amountMinor,
                currency: accountById(adjustment.accountId)?.currency ?? 'TWD',
              ),
            ],
            relatedEntityType: 'balanceAdjustment',
            relatedEntityId: adjustment.id,
            origin: adjustment.origin,
          ),
        ),
      ),
    );
  }

  Future<void> deleteBalanceAdjustment(String id) => _commit(
    data.copyWith(
      balanceAdjustments: data.balanceAdjustments
          .where((item) => item.id != id)
          .toList(),
      transactions: data.transactions
          .where((item) => item.id != 'balance:$id')
          .toList(),
    ),
  );

  Future<void> upsertExpense(Expense expense) async {
    if (expense.paymentMethod == PaymentMethod.debitCard) {
      final card = cardById(expense.cardId);
      if (card == null || !card.isDebit || !card.isActive) {
        lastSyncError = '請選擇已啟用的金融卡';
        notifyListeners();
        return;
      }
      expense = expense.copyWith(accountId: card.debitAccountId);
    }
    final items = [...data.expenses];
    final index = items.indexWhere((item) => item.id == expense.id);
    index < 0 ? items.add(expense) : items[index] = expense;
    await _commit(
      data.copyWith(
        expenses: items,
        transactions: _replaceTransaction(
          'expense:${expense.id}',
          _expenseTransaction(expense),
        ),
      ),
    );
  }

  Future<void> deleteExpense(String id) async {
    if (data.recurringExpenseOccurrences.any((item) => item.expenseId == id) ||
        data.telecomBillPayments.any((item) => item.expenseIds.contains(id))) {
      lastSyncError = '已入帳的固定支出或電信帳單不可刪除';
      notifyListeners();
      return;
    }
    await _commit(
      data.copyWith(
        expenses: data.expenses.where((item) => item.id != id).toList(),
        transactions: data.transactions
            .where((item) => item.id != 'expense:$id')
            .toList(),
      ),
    );
  }

  Future<void> upsertRecurringExpense(RecurringExpense expense) async {
    if (expense.isTelecom &&
        expense.isActive &&
        data.recurringExpenses.any(
          (item) => item.id != expense.id && item.isActive && item.isTelecom,
        )) {
      lastSyncError = '只能啟用一組電信帳單固定支出';
      notifyListeners();
      return;
    }
    final items = [...data.recurringExpenses];
    final index = items.indexWhere((item) => item.id == expense.id);
    index < 0 ? items.add(expense) : items[index] = expense;
    await _commit(data.copyWith(recurringExpenses: items));
  }

  Future<void> setRecurringExpenseActive(String id, bool active) async {
    final existing = data.recurringExpenses
        .where((item) => item.id == id)
        .firstOrNull;
    if (existing == null) return;
    await upsertRecurringExpense(existing.copyWith(isActive: active));
  }

  Future<void> upsertIncome(IncomeEntry income) async {
    final items = [...data.incomes];
    final index = items.indexWhere((item) => item.id == income.id);
    index < 0 ? items.add(income) : items[index] = income;
    await _commit(
      data.copyWith(
        incomes: items,
        transactions: _replaceTransaction(
          'income:${income.id}',
          _incomeTransaction(income),
        ),
      ),
    );
  }

  Future<void> deleteIncome(String id) => _commit(
    data.copyWith(
      incomes: data.incomes.where((item) => item.id != id).toList(),
      transactions: data.transactions
          .where((item) => item.id != 'income:$id')
          .toList(),
    ),
  );

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
    final items = [...data.cards];
    final index = items.indexWhere((item) => item.id == card.id);
    index < 0 ? items.add(normalized) : items[index] = normalized;
    final accounts = [...data.accounts];
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
    await _commit(data.copyWith(cards: items, accounts: accounts));
  }

  Future<void> deleteCard(String id) async {
    final card = cardById(id);
    if (card == null) return;
    if (data.bills.any((item) => item.cardId == id) ||
        data.expenses.any((item) => item.cardId == id) ||
        data.orders.any((item) => item.cardId == id)) {
      lastSyncError = '無法刪除信用卡，仍被支出、帳單或訂單引用';
      notifyListeners();
      return;
    }
    final liabilityId = card.liabilityAccountId;
    await _commit(
      data.copyWith(
        cards: data.cards.where((item) => item.id != id).toList(),
        accounts: liabilityId == null
            ? data.accounts
            : data.accounts.where((item) => item.id != liabilityId).toList(),
      ),
    );
  }

  Future<void> upsertBill(CardBill bill) async {
    if (cardById(bill.cardId)?.isCredit != true) {
      lastSyncError = '金融卡消費直接扣款，不會產生信用卡帳單';
      notifyListeners();
      return;
    }
    final chargeIds = bill.chargeIds.toSet().toList();
    final invalid = chargeIds.where(
      (id) => !canAssignChargeToBill(id, bill.cardId, billId: bill.id),
    );
    if (invalid.isNotEmpty) {
      lastSyncError = '有刷卡紀錄已屬於其他帳單，請重新確認明細';
      notifyListeners();
      return;
    }
    if (!RegExp(r'^\d{4}-(0[1-9]|1[0-2])$').hasMatch(bill.month)) {
      lastSyncError = '帳單月份格式必須為 YYYY-MM';
      notifyListeners();
      return;
    }
    if (data.bills.any(
      (item) =>
          item.id != bill.id &&
          item.cardId == bill.cardId &&
          item.month == bill.month,
    )) {
      lastSyncError = '同一張卡已有此月份帳單';
      notifyListeners();
      return;
    }
    final statementAmount =
        bill.statementAmountMinor ??
        (calculatedBillAmount(bill) + bill.manualAdjustmentMinor)
            .clamp(0, 1 << 62)
            .toInt();
    final paid = paidBillMinor(bill);
    if (statementAmount < paid) {
      lastSyncError = '實際帳單總額不得低於已繳金額';
      notifyListeners();
      return;
    }
    final difference = statementAmount - calculatedBillAmount(bill);
    if (difference != 0 &&
        bill.reconciliationReason == CardBillReconciliationReason.none) {
      lastSyncError = '帳單有差額時請選擇差異原因';
      notifyListeners();
      return;
    }
    if (difference != 0 &&
        bill.reconciliationReason ==
            CardBillReconciliationReason.missingOrOther &&
        bill.reconciliationNote.trim().isEmpty) {
      lastSyncError = '選擇漏登／其他時請填寫差異說明';
      notifyListeners();
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
      paidAt: billPayments(bill.id).firstOrNull?.date ?? bill.paidAt,
      origin: bill.origin,
    );
    final items = [...data.bills];
    final index = items.indexWhere((item) => item.id == bill.id);
    index < 0 ? items.add(normalized) : items[index] = normalized;
    final adjustmentId = 'card-bill-reconciliation:${bill.id}';
    final transactions = data.transactions
        .where((item) => item.id != adjustmentId)
        .toList();
    final liabilityId = cardById(bill.cardId)?.liabilityAccountId;
    if (difference != 0 && liabilityId != null) {
      transactions.add(
        FinancialTransaction(
          id: adjustmentId,
          userId: bill.userId,
          date: normalized.dueDate,
          type: FinancialTransactionType.balanceAdjustment,
          label: '${cardById(bill.cardId)?.name ?? '信用卡'} ${bill.month} 帳單核對差額',
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
    lastSyncError = null;
    await _commit(data.copyWith(bills: items, transactions: transactions));
  }

  Future<void> payBill(String id) async {
    final source = data.bills.where((item) => item.id == id).firstOrNull;
    if (source == null) return;
    final card = cardById(source.cardId);
    final amount = outstandingBillMinor(source);
    if (card == null || amount <= 0) return;
    await upsertBillPayment(
      billId: id,
      paymentId: newId(),
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
    final bill = data.bills.where((item) => item.id == billId).firstOrNull;
    final card = bill == null ? null : cardById(bill.cardId);
    final liabilityId = card?.liabilityAccountId;
    if (bill == null || card == null || liabilityId == null) return;
    final transactionId = paymentId.startsWith('card-payment:')
        ? paymentId
        : 'card-payment:$billId:$paymentId';
    final otherPaid = billPayments(billId)
        .where((item) => item.id != transactionId)
        .fold(0, (sum, item) => sum + item.amountMinor);
    if (amountMinor <= 0 || otherPaid + amountMinor > billAmount(bill)) {
      lastSyncError = '繳款金額必須大於 0，且不得超過帳單剩餘金額';
      notifyListeners();
      return;
    }
    final account = accountById(accountId);
    if (account == null || account.kind != FinancialAccountKind.asset) {
      lastSyncError = '請選擇有效的扣款帳戶';
      notifyListeners();
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
    final transactions = _replaceTransaction(transactionId, transaction);
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
      for (final item in data.bills)
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
    lastSyncError = null;
    await _commit(data.copyWith(bills: bills, transactions: transactions));
  }

  Future<void> deleteBillPayment(String billId, String transactionId) async {
    final transactions = data.transactions
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
    await _commit(
      data.copyWith(
        transactions: transactions,
        bills: [
          for (final bill in data.bills)
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
    await _commit(
      data.copyWith(
        bills: [
          for (final bill in data.bills)
            bill.id == billId
                ? bill.copyWith(autoDebitState: CardBillAutoDebitState.failed)
                : bill,
        ],
      ),
    );
  }

  Future<void> deleteBill(String id) => _commit(
    data.copyWith(
      bills: data.bills.where((item) => item.id != id).toList(),
      transactions: data.transactions
          .where(
            (item) =>
                item.relatedEntityId != id ||
                (item.relatedEntityType != 'cardBill' &&
                    item.relatedEntityType != 'cardBillReconciliation'),
          )
          .toList(),
    ),
  );

  Future<void> upsertProduct(InvestmentProduct product) async {
    final items = [...data.products];
    final index = items.indexWhere((item) => item.id == product.id);
    final previous = index < 0 ? null : items[index];
    index < 0 ? items.add(product) : items[index] = product;
    final history = [...data.investmentPriceHistory];
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
    await _commit(
      data.copyWith(products: items, investmentPriceHistory: history),
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

    final products = [...data.products];
    final productIndex = products.indexWhere((item) => item.id == product.id);
    final previous = productIndex < 0 ? null : products[productIndex];
    productIndex < 0 ? products.add(product) : products[productIndex] = product;

    final history = [...data.investmentPriceHistory];
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

    final adjustments = [...data.investmentAdjustments];
    if (adjustment != null) adjustments.add(adjustment);
    final transactions = [...data.investmentTransactions];
    if (transaction != null) transactions.add(transaction);

    await _commit(
      data.copyWith(
        products: products,
        investmentAdjustments: adjustments,
        investmentTransactions: transactions,
        investmentPriceHistory: history,
        transactions: transaction == null
            ? data.transactions
            : _replaceTransaction(
                'investment:${transaction.id}',
                _investmentFinancialTransaction(transaction),
              ),
      ),
    );
  }

  Future<void> deleteProduct(String id) => _commit(
    data.copyWith(
      products: data.products.where((item) => item.id != id).toList(),
      investmentTransactions: data.investmentTransactions
          .where((item) => item.productId != id)
          .toList(),
      investmentAdjustments: data.investmentAdjustments
          .where((item) => item.productId != id)
          .toList(),
      investmentPriceHistory: data.investmentPriceHistory
          .where((item) => item.productId != id)
          .toList(),
      transactions: data.transactions
          .where(
            (item) =>
                item.relatedEntityType != 'investmentTransaction' ||
                !data.investmentTransactions
                    .where((transaction) => transaction.productId == id)
                    .any(
                      (transaction) => transaction.id == item.relatedEntityId,
                    ),
          )
          .toList(),
    ),
  );

  Future<void> upsertInvestmentTransaction(
    InvestmentTransaction transaction,
  ) async {
    final items = [...data.investmentTransactions];
    final index = items.indexWhere((item) => item.id == transaction.id);
    index < 0 ? items.add(transaction) : items[index] = transaction;
    await _commit(
      data.copyWith(
        investmentTransactions: items,
        transactions: _replaceTransaction(
          'investment:${transaction.id}',
          _investmentFinancialTransaction(transaction),
        ),
      ),
    );
  }

  Future<void> deleteInvestmentTransaction(String id) => _commit(
    data.copyWith(
      investmentTransactions: data.investmentTransactions
          .where((item) => item.id != id)
          .toList(),
      transactions: data.transactions
          .where((item) => item.id != 'investment:$id')
          .toList(),
    ),
  );

  Future<void> upsertInvestmentAdjustment(
    InvestmentAdjustment adjustment,
  ) async {
    final items = [...data.investmentAdjustments];
    final index = items.indexWhere((item) => item.id == adjustment.id);
    index < 0 ? items.add(adjustment) : items[index] = adjustment;
    await _commit(data.copyWith(investmentAdjustments: items));
  }

  Future<void> deleteInvestmentAdjustment(String id) => _commit(
    data.copyWith(
      investmentAdjustments: data.investmentAdjustments
          .where((item) => item.id != id)
          .toList(),
    ),
  );

  Future<void> upsertOrder(GroupOrder order) async {
    final items = [...data.orders];
    final index = items.indexWhere((item) => item.id == order.id);
    index < 0 ? items.add(order) : items[index] = order;
    await _commit(
      data.copyWith(
        orders: items,
        transactions: _replaceTransaction(
          'order-charge:${order.id}',
          _orderFinancialTransaction(order),
        ),
      ),
    );
  }

  Future<void> deleteOrder(String id) => _commit(
    data.copyWith(
      orders: data.orders.where((item) => item.id != id).toList(),
      transactions: data.transactions
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
    final orders = data.orders.map((order) {
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
    await _commit(
      data.copyWith(
        orders: orders,
        transactions:
            [
              for (final item in data.transactions)
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
    final order = data.orders.where((item) => item.id == orderId).firstOrNull;
    final participant = order?.participants
        .where((item) => item.id == participantId)
        .firstOrNull;
    if (participant == null || participant.isSelf) {
      lastSyncError = '找不到這筆待收款資料';
      notifyListeners();
      return false;
    }

    String accountId;
    if (participant.collectionMethod == collectionMethodCash) {
      accountId = systemCashAccountId;
    } else if (participant.collectionMethod == collectionMethodBankTransfer) {
      final selected = participant.collectionAccountId;
      if (!bankTransferAccounts.any((item) => item.id == selected)) {
        lastSyncError = '請先選擇啟用中的 TWD 銀行轉入帳戶';
        notifyListeners();
        return false;
      }
      accountId = selected!;
    } else {
      lastSyncError = '請先將收款方式改為現金或銀行轉帳';
      notifyListeners();
      return false;
    }

    final orders = data.orders.map((item) {
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
    await _commit(
      data.copyWith(
        orders: orders,
        transactions: _replaceTransaction(collection.id, collection),
      ),
    );
    return true;
  }

  bool isCategoryUsed(BookkeepingCategory category) =>
      data.transactions.any((item) => item.categoryId == category.id) ||
      (category.kind == BookkeepingCategoryKind.expense
          ? data.expenses.any((item) => item.category == category.name) ||
                data.recurringExpenses.any(
                  (item) => item.category == category.name,
                )
          : data.incomes.any((item) => item.category == category.name));

  Future<void> addCategory({
    required BookkeepingCategoryKind kind,
    required String name,
    required String iconKey,
    required String colorKey,
  }) async {
    final normalized = name.trim();
    if (!_validateCategoryName(normalized, kind)) return;
    await _commit(
      data.copyWith(
        categories: [
          ...data.categories,
          BookkeepingCategory(
            id: newId(),
            userId: userId,
            name: normalized,
            kind: kind,
            iconKey: iconKey,
            colorKey: colorKey,
            sortOrder: categoriesFor(kind).length,
          ),
        ],
      ),
    );
  }

  Future<void> updateCategory(BookkeepingCategory category) async {
    final normalized = category.name.trim();
    if (!_validateCategoryName(
      normalized,
      category.kind,
      exceptId: category.id,
    )) {
      return;
    }
    final previous = categoryById(category.id);
    if (previous == null) return;
    final renamed = previous.name != normalized;
    await _commit(
      data.copyWith(
        categories: [
          for (final item in data.categories)
            if (item.id == category.id)
              category.copyWith(name: normalized)
            else
              item,
        ],
        expenses: renamed && category.kind == BookkeepingCategoryKind.expense
            ? [
                for (final item in data.expenses)
                  if (item.category == previous.name)
                    item.copyWith(category: normalized)
                  else
                    item,
              ]
            : data.expenses,
        recurringExpenses:
            renamed && category.kind == BookkeepingCategoryKind.expense
            ? [
                for (final item in data.recurringExpenses)
                  if (item.category == previous.name)
                    item.copyWith(category: normalized)
                  else
                    item,
              ]
            : data.recurringExpenses,
        incomes: renamed && category.kind == BookkeepingCategoryKind.income
            ? [
                for (final item in data.incomes)
                  if (item.category == previous.name)
                    item.copyWith(category: normalized)
                  else
                    item,
              ]
            : data.incomes,
        settings: data.settings.defaultExpenseCategoryId == category.id
            ? data.settings.copyWith(defaultCategory: normalized)
            : data.settings,
      ),
    );
  }

  Future<void> setCategoryActive(String id, bool active) async {
    final category = categoryById(id);
    if (category == null || category.isActive == active) return;
    if (!active && data.settings.defaultExpenseCategoryId == id) {
      lastSyncError = '請先更換預設消費分類';
      notifyListeners();
      return;
    }
    if (!active && categoriesFor(category.kind, activeOnly: true).length <= 1) {
      lastSyncError = '每種記帳類型至少需要一個啟用分類';
      notifyListeners();
      return;
    }
    await _commit(
      data.copyWith(
        categories: [
          for (final item in data.categories)
            if (item.id == id)
              item.copyWith(isActive: active, clearMergedInto: active)
            else
              item,
        ],
      ),
    );
  }

  Future<void> reorderCategories(
    BookkeepingCategoryKind kind,
    List<String> orderedIds,
  ) => _commit(
    data.copyWith(
      categories: [
        for (final item in data.categories)
          if (item.kind == kind)
            item.copyWith(sortOrder: orderedIds.indexOf(item.id))
          else
            item,
      ],
    ),
  );

  Future<void> mergeCategory(String sourceId, String targetId) async {
    final source = categoryById(sourceId);
    final target = categoryById(targetId);
    if (source == null ||
        target == null ||
        source.id == target.id ||
        source.kind != target.kind ||
        !target.isActive) {
      lastSyncError = '只能合併到同類型的啟用分類';
      notifyListeners();
      return;
    }
    final defaultIsSource = data.settings.defaultExpenseCategoryId == source.id;
    await _commit(
      data.copyWith(
        categories: [
          for (final item in data.categories)
            if (item.id == source.id)
              item.copyWith(isActive: false, mergedIntoCategoryId: target.id)
            else
              item,
        ],
        transactions: [
          for (final item in data.transactions)
            if (item.categoryId == source.id)
              item.copyWith(categoryId: target.id)
            else
              item,
        ],
        expenses: source.kind == BookkeepingCategoryKind.expense
            ? [
                for (final item in data.expenses)
                  if (item.category == source.name)
                    item.copyWith(category: target.name)
                  else
                    item,
              ]
            : data.expenses,
        recurringExpenses: source.kind == BookkeepingCategoryKind.expense
            ? [
                for (final item in data.recurringExpenses)
                  if (item.category == source.name)
                    item.copyWith(category: target.name)
                  else
                    item,
              ]
            : data.recurringExpenses,
        incomes: source.kind == BookkeepingCategoryKind.income
            ? [
                for (final item in data.incomes)
                  if (item.category == source.name)
                    item.copyWith(category: target.name)
                  else
                    item,
              ]
            : data.incomes,
        settings: defaultIsSource
            ? data.settings.copyWith(
                defaultCategory: target.name,
                defaultExpenseCategoryId: target.id,
              )
            : data.settings,
      ),
    );
  }

  Future<void> deleteCategory(String id) async {
    final category = categoryById(id);
    if (category == null) return;
    if (category.isBuiltIn || isCategoryUsed(category)) {
      lastSyncError = '已使用或內建分類只能停用或合併';
      notifyListeners();
      return;
    }
    await _commit(
      data.copyWith(
        categories: data.categories.where((item) => item.id != id).toList(),
      ),
    );
  }

  bool _validateCategoryName(
    String name,
    BookkeepingCategoryKind kind, {
    String? exceptId,
  }) {
    if (name.isEmpty || name.runes.length > 20) {
      lastSyncError = '分類名稱需為 1–20 字';
      notifyListeners();
      return false;
    }
    if (data.categories.any(
      (item) =>
          item.id != exceptId &&
          item.kind == kind &&
          item.name.trim().toLowerCase() == name.toLowerCase(),
    )) {
      lastSyncError = '同類型已有相同分類名稱';
      notifyListeners();
      return false;
    }
    return true;
  }

  Future<void> updateSettings(UserSettings settings) =>
      _commit(data.copyWith(settings: settings));

  Future<void> generateDemoData() async {
    await clearDemoData();
    final now = DateTime.now();
    final bank = Account(
      id: 'demo-bank',
      userId: userId,
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
      userId: userId,
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
      userId: userId,
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
      userId: userId,
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
        userId: userId,
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
        userId: userId,
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
      userId: userId,
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
      userId: userId,
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
      userId: userId,
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
      userId: userId,
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
          token: _uuid.v4(),
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
          token: _uuid.v4(),
          note: '',
        ),
      ],
    );
    final bill = CardBill(
      id: 'demo-bill',
      userId: userId,
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
    await _commit(
      data.copyWith(
        settings: data.settings.copyWith(
          defaultCollectionAccountId: bank.id,
          bankQrData: 'BANK:808;ACCOUNT:012345678901',
          bankAccountInfo: '玉山銀行 808｜帳號 0123-4567-8901',
          fxRates: rates,
        ),
        accounts: [...data.accounts, bank, linePay, usd],
        expenses: [...data.expenses, ...expenses],
        incomes: [...data.incomes, income],
        cards: [...data.cards, card],
        bills: [...data.bills, bill],
        products: [...data.products, product],
        investmentTransactions: [...data.investmentTransactions, transaction],
        investmentPriceHistory: [
          ...data.investmentPriceHistory,
          InvestmentPricePoint(
            productId: product.id,
            priceMinor: product.currentPriceMinor,
            date: product.priceUpdatedAt,
          ),
        ],
        orders: [...data.orders, order],
      ),
    );
  }

  Future<void> clearDemoData() async {
    final demoAccountIds = data.accounts
        .where((item) => item.origin == DataOrigin.demo)
        .map((item) => item.id)
        .toSet();
    final demoCardIds = data.cards
        .where((item) => item.origin == DataOrigin.demo)
        .map((item) => item.id)
        .toSet();
    final demoProductIds = data.products
        .where((item) => item.origin == DataOrigin.demo)
        .map((item) => item.id)
        .toSet();
    await _commit(
      data.copyWith(
        accounts: data.accounts
            .where((item) => item.origin != DataOrigin.demo)
            .toList(),
        balanceAdjustments: data.balanceAdjustments
            .where(
              (item) =>
                  item.origin != DataOrigin.demo &&
                  !demoAccountIds.contains(item.accountId),
            )
            .toList(),
        expenses: data.expenses
            .where((item) => item.origin != DataOrigin.demo)
            .toList(),
        incomes: data.incomes
            .where((item) => item.origin != DataOrigin.demo)
            .toList(),
        cards: data.cards
            .where((item) => item.origin != DataOrigin.demo)
            .toList(),
        bills: data.bills
            .where(
              (item) =>
                  item.origin != DataOrigin.demo &&
                  !demoCardIds.contains(item.cardId),
            )
            .toList(),
        products: data.products
            .where((item) => item.origin != DataOrigin.demo)
            .toList(),
        investmentTransactions: data.investmentTransactions
            .where(
              (item) =>
                  item.origin != DataOrigin.demo &&
                  !demoProductIds.contains(item.productId),
            )
            .toList(),
        investmentAdjustments: data.investmentAdjustments
            .where(
              (item) =>
                  item.origin != DataOrigin.demo &&
                  !demoProductIds.contains(item.productId),
            )
            .toList(),
        investmentPriceHistory: data.investmentPriceHistory
            .where((item) => !demoProductIds.contains(item.productId))
            .toList(),
        orders: data.orders
            .where((item) => item.origin != DataOrigin.demo)
            .toList(),
      ),
    );
  }

  Future<void> exportAccounts() => _csv.export('快記帳_帳戶.csv', [
    ['帳戶名稱', '機構', '類型', '幣別', '目前餘額', '啟用', '備註'],
    for (final item in data.accounts)
      [
        item.name,
        item.institution,
        item.type,
        item.currency,
        accountBalance(item.id) / 100,
        item.isActive ? '是' : '否',
        item.note,
      ],
  ]);

  Future<void> exportExpenses() => _csv.export('快記帳_消費.csv', [
    ['日期', '項目', '分類', '金額', '付款方式', '店家', '必要支出', '備註'],
    for (final item in data.expenses)
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
    for (final item in data.incomes)
      [
        item.date.toIso8601String(),
        item.item,
        item.category,
        item.amountMinor / 100,
        accountById(item.accountId)?.name ?? '',
        item.note,
      ],
  ]);

  Future<void> exportInvestments() => _csv.export('快記帳_投資.csv', [
    ['日期', '商品', '類型', '數量', '價格', '手續費', '稅費', '備註'],
    for (final item in data.investmentTransactions)
      [
        item.date.toIso8601String(),
        productById(item.productId)?.name ?? '',
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
    for (final item in data.bills)
      [
        item.month,
        cardById(item.cardId)?.name ?? '',
        billAmount(item) / 100,
        calculatedBillAmount(item) / 100,
        reconciliationDifference(item) / 100,
        item.reconciliationReason.label,
        paidBillMinor(item) / 100,
        outstandingBillMinor(item) / 100,
        billStatus(item).label,
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
    for (final order in data.orders)
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
          accountById(item.collectionAccountId)?.name ?? '',
          item.collectedAt?.toIso8601String() ?? '',
        ],
  ]);

  List<FinancialTransaction> _replaceTransaction(
    String id,
    FinancialTransaction transaction,
  ) => [
    for (final item in data.transactions)
      if (item.id != id) item,
    transaction,
  ];

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
      label: productById(transaction.productId)?.name ?? '投資交易',
      amountMinor: amount,
      currency:
          productById(transaction.productId)?.currency ??
          accountById(accountId)?.currency ??
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
                currency: accountById(accountId)?.currency ?? 'TWD',
              ),
            ],
      origin: transaction.origin,
    );
  }

  FinancialTransaction _orderFinancialTransaction(GroupOrder order) {
    final card = cardById(order.cardId);
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
      categoryId:
          categoryByName('餐飲', BookkeepingCategoryKind.expense)?.id ??
          data.settings.defaultExpenseCategoryId,
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

  FinancialTransaction _expenseTransaction(Expense expense) {
    final impacts = <AccountImpact>[];
    if (expense.isCreditCard) {
      final liabilityId = cardById(expense.cardId)?.liabilityAccountId;
      if (liabilityId != null) {
        impacts.add(
          AccountImpact(
            accountId: liabilityId,
            amountMinor: expense.amountMinor,
            currency: 'TWD',
          ),
        );
      }
    } else if (expense.accountId != null &&
        expense.paymentMethod != PaymentMethod.telecomBill) {
      impacts.add(
        AccountImpact(
          accountId: expense.accountId!,
          amountMinor: -expense.amountMinor,
          currency: accountById(expense.accountId)?.currency ?? 'TWD',
        ),
      );
    }
    return FinancialTransaction(
      id: 'expense:${expense.id}',
      userId: expense.userId,
      date: expense.date,
      type: FinancialTransactionType.expense,
      label: expense.item,
      amountMinor: expense.amountMinor,
      currency: 'TWD',
      categoryId:
          categoryByName(
            expense.category,
            BookkeepingCategoryKind.expense,
          )?.id ??
          data.settings.defaultExpenseCategoryId,
      note: expense.note,
      relatedEntityType: 'expense',
      relatedEntityId: expense.id,
      impacts: impacts,
      origin: expense.origin,
    );
  }

  FinancialTransaction _incomeTransaction(IncomeEntry income) =>
      FinancialTransaction(
        id: 'income:${income.id}',
        userId: income.userId,
        date: income.date,
        type: FinancialTransactionType.income,
        label: income.item,
        amountMinor: income.amountMinor,
        currency: accountById(income.accountId)?.currency ?? 'TWD',
        categoryId: categoryByName(
          income.category,
          BookkeepingCategoryKind.income,
        )?.id,
        note: income.note,
        relatedEntityType: 'income',
        relatedEntityId: income.id,
        impacts: [
          AccountImpact(
            accountId: income.accountId,
            amountMinor: income.amountMinor,
            currency: accountById(income.accountId)?.currency ?? 'TWD',
          ),
        ],
        origin: income.origin,
      );

  String newId() => _uuid.v4();

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }
}

extension FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}
