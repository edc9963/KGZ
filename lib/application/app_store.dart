import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../data/repositories.dart';
import '../data/ocr_models.dart';
import '../domain/models.dart';
import 'stores/accounts_manager.dart';
import 'stores/cards_manager.dart';
import 'stores/categories_manager.dart';
import 'stores/csv_export_manager.dart';
import 'stores/demo_data_manager.dart';
import 'stores/expenses_manager.dart';
import 'stores/first_or_null.dart';
import 'stores/investments_manager.dart';
import 'stores/ledger_queries.dart';
import 'stores/market_data_manager.dart';
import 'stores/orders_manager.dart';

/// The app's single [ChangeNotifier]: session/auth state, the cloud-synced
/// [AppData] snapshot, and every read or write derived from it.
///
/// This class is a thin facade kept for source compatibility with the UI
/// layer, which already depends on one `appStoreProvider` exposing every
/// getter and mutator by name (`appStore.upsertAccount(...)`,
/// `appStore.netWorthMinor`, ...). The actual logic lives in the domain
/// managers and the [LedgerQueries] read layer under `stores/`, grouped by
/// what they are primarily responsible for — not by which collections they
/// touch, since almost every write here (see e.g. `AccountsManager
/// .deleteAccount` or `AccountsManager.mergeAccounts`) legitimately reads
/// or rewrites several collections at once. Each member below is either
/// infrastructure that stays here (session, cloud sync, the repositories)
/// or a one-line forward to the manager that owns it; the forwards keep
/// their original name, parameters and defaults so every existing call
/// site keeps compiling unchanged.
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
       _orderImport = orderImportRepository,
       _publicCollection = publicCollectionRepository,
       _uuid = uuid {
    ledger = LedgerQueries(() => data);
    marketData = MarketDataManager(this, marketDataRepository);
    accounts = AccountsManager(this);
    expenses = ExpensesManager(this);
    cards = CardsManager(this);
    investments = InvestmentsManager(this);
    orders = OrdersManager(this);
    categories = CategoriesManager(this);
    demoData = DemoDataManager(this);
    csv = CsvExportManager(this, csvExportService);
  }

  final AuthRepository _auth;
  final FinanceRepository _finance;
  final OrderImportRepository? _orderImport;
  final PublicCollectionRepository? _publicCollection;
  final Uuid _uuid;
  StreamSubscription<bool>? _authSubscription;

  /// Read-only derived views (account balances, the unified ledger, bill
  /// status, monthly/net-worth aggregates, category lookups). See
  /// [LedgerQueries].
  late final LedgerQueries ledger;

  /// The market (TWSE/ETF) catalogue cache, quote refresh, and linking a
  /// product to a catalogue entry. See [MarketDataManager].
  late final MarketDataManager marketData;

  /// Account CRUD, transfers and balance adjustments. See [AccountsManager].
  late final AccountsManager accounts;

  /// Expense, recurring-expense and income CRUD. See [ExpensesManager].
  late final ExpensesManager expenses;

  /// Card CRUD and the credit-card bill lifecycle. See [CardsManager].
  late final CardsManager cards;

  /// Investment product and transaction CRUD. See [InvestmentsManager].
  late final InvestmentsManager investments;

  /// Group-order CRUD and collection status changes. See [OrdersManager].
  late final OrdersManager orders;

  /// Bookkeeping-category CRUD. See [CategoriesManager].
  late final CategoriesManager categories;

  /// Sample/demo data generation for Settings. See [DemoDataManager].
  late final DemoDataManager demoData;

  /// CSV exports offered from Settings. See [CsvExportManager].
  late final CsvExportManager csv;

  AppData data = const AppData();
  bool initialized = false;
  bool isOffline = false;
  bool isSaving = false;
  bool hasConflict = false;
  String? lastSyncError;
  AppData? localMigrationCandidate;
  DateTime? cloudUpdatedAt;
  bool cloudExists = false;

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

  /// Notifies listeners. Domain managers under `stores/` call this instead
  /// of `notifyListeners()` directly, since that method is `@protected` and
  /// only visible to subclasses of [ChangeNotifier] — not to sibling
  /// classes in another file.
  void notify() => notifyListeners();

  Future<void> initialize() async {
    await loadFinance();
    if (isSignedIn && !isOffline) {
      unawaited(marketData.refreshMarketData());
    }
    _authSubscription = _auth.authStateChanges.listen((_) async {
      await loadFinance();
      if (isSignedIn && !isOffline) {
        await marketData.refreshMarketData();
      }
    });
    initialized = true;
    notifyListeners();
  }

  /// Reloads the cloud finance snapshot. Public (despite being for internal
  /// orchestration only) because [MarketDataManager.refreshMarketData]
  /// needs a fresh snapshot after a quote refresh.
  Future<void> loadFinance() async {
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
      if (canWrite) {
        // Awaited rather than fire-and-forget: this used to be
        // `unawaited(...)`, which raced any bill the caller creates for the
        // same card+month right after `initialize()`/`loadFinance()`
        // returns. When this background pass won that race it would create
        // its own (unreconciled) bill first, and the caller's own
        // `upsertBill()` would then be rejected as a duplicate for that
        // month — see docs/kgz-card-bill-reminder-feature.md §5 for the bug
        // this fixes. Awaiting makes bill auto-generation finish, or fail,
        // before this call returns, so there is nothing left to race.
        try {
          await cards.ensureBillsGenerated();
        } on Object catch (error) {
          // Don't let a bill-generation hiccup masquerade as the "can't
          // reach the cloud" error below; the snapshot load above already
          // succeeded.
          debugPrint('Auto bill generation failed: $error');
        }
      }
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
    await loadFinance();
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

  /// Persists [next] as the new [data] snapshot, handling the
  /// offline/conflict/in-flight guard and the saving/error state around it.
  /// Public (despite being for internal orchestration only) so every
  /// domain manager under `stores/` can commit through the same path.
  Future<void> commit(AppData next) async {
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

  // ---------------------------------------------------------------------
  // Ledger / derived-query forwards — see [LedgerQueries].
  // ---------------------------------------------------------------------

  List<BookkeepingCategory> categoriesFor(
    BookkeepingCategoryKind kind, {
    bool activeOnly = false,
  }) => ledger.categoriesFor(kind, activeOnly: activeOnly);

  BookkeepingCategory? categoryById(String? id) => ledger.categoryById(id);

  BookkeepingCategory? categoryByName(
    String name,
    BookkeepingCategoryKind kind,
  ) => ledger.categoryByName(name, kind);

  List<String> categoryNamesFor(
    BookkeepingCategoryKind kind, {
    String? includeInactiveName,
  }) => ledger.categoryNamesFor(kind, includeInactiveName: includeInactiveName);

  String categoryName(String? id, {String fallback = '其他'}) =>
      ledger.categoryName(id, fallback: fallback);

  bool isCategoryUsed(BookkeepingCategory category) =>
      ledger.isCategoryUsed(category);

  List<Account> get bankTransferAccounts => ledger.bankTransferAccounts;
  List<Account> get activeAssetAccounts => ledger.activeAssetAccounts;
  String get lastCollectionMethod => ledger.lastCollectionMethod;
  ({String method, String? accountId})? collectionPreferenceForMember(
    String name,
  ) => ledger.collectionPreferenceForMember(name);
  String? get defaultBankTransferAccountId =>
      ledger.defaultBankTransferAccountId;

  Account? accountById(String? id) => ledger.accountById(id);
  int accountBalance(String accountId) => ledger.accountBalance(accountId);
  List<LedgerEffect> accountLedgerEntries(String accountId) =>
      ledger.accountLedgerEntries(accountId);
  List<LedgerEffect> get ledgerEffects => ledger.ledgerEffects;

  CreditCard? cardById(String? id) => ledger.cardById(id);
  RecurringExpense? get activeTelecomExpense => ledger.activeTelecomExpense;
  InvestmentProduct? productById(String? id) => ledger.productById(id);
  String? cardIdForCharge(String chargeId) => ledger.cardIdForCharge(chargeId);
  Map<String, CardBill> get cardChargeBills => ledger.cardChargeBills;
  CardBill? cardBillForCharge(String chargeId) =>
      ledger.cardBillForCharge(chargeId);
  bool canAssignChargeToBill(String chargeId, String cardId, {String? billId}) =>
      ledger.canAssignChargeToBill(chargeId, cardId, billId: billId);
  int unbilledCardMinor(String cardId) => ledger.unbilledCardMinor(cardId);
  int calculatedBillAmount(CardBill bill) => ledger.calculatedBillAmount(bill);
  int billAmount(CardBill bill) => ledger.billAmount(bill);
  int reconciliationDifference(CardBill bill) =>
      ledger.reconciliationDifference(bill);
  List<FinancialTransaction> billPayments(String billId) =>
      ledger.billPayments(billId);
  int paidBillMinor(CardBill bill) => ledger.paidBillMinor(bill);
  int outstandingBillMinor(CardBill bill) => ledger.outstandingBillMinor(bill);
  CardBillStatus billStatus(CardBill bill, {DateTime? now}) =>
      ledger.billStatus(bill, now: now);
  ({DateTime closingDate, DateTime dueDate, DateTime autoDebitDate})
  cardBillingDates(CreditCard card, int year, int month) =>
      ledger.cardBillingDates(card, year, month);
  String cardBillLabelFor(CreditCard card, int cursorYear, int cursorMonth) =>
      ledger.cardBillLabelFor(card, cursorYear, cursorMonth);
  ({int year, int month}) cardCycleCursorForLabel(
    CreditCard card,
    int labelYear,
    int labelMonth,
  ) => ledger.cardCycleCursorForLabel(card, labelYear, labelMonth);

  int get pendingCardMinor => ledger.pendingCardMinor;
  int get pendingTelecomMinor => ledger.pendingTelecomMinor;
  int get currentMonthExpenseMinor => ledger.currentMonthExpenseMinor;
  int get currentMonthCollectionResultMinor =>
      ledger.currentMonthCollectionResultMinor;
  int get currentMonthCollectionResultDefaultMinor =>
      ledger.currentMonthCollectionResultDefaultMinor;
  int get receivablesMinor => ledger.receivablesMinor;
  int get receivablesDefaultMinor => ledger.receivablesDefaultMinor;
  int get pendingCardDefaultMinor => ledger.pendingCardDefaultMinor;
  int get pendingTelecomDefaultMinor => ledger.pendingTelecomDefaultMinor;
  int get currentMonthExpenseDefaultMinor =>
      ledger.currentMonthExpenseDefaultMinor;
  int get currentMonthIncomeDefaultMinor =>
      ledger.currentMonthIncomeDefaultMinor;
  int get currentMonthBalanceDefaultMinor =>
      ledger.currentMonthBalanceDefaultMinor;

  FxRate? fxRateFor(String currency) => ledger.fxRateFor(currency);
  int? convertToDefault(int minor, String currency) =>
      ledger.convertToDefault(minor, currency);
  Set<String> get currenciesMissingFx => ledger.currenciesMissingFx;
  int get depositTotalMinor => ledger.depositTotalMinor;
  Map<String, Holding> get holdings => ledger.holdings;
  int get investmentValueMinor => ledger.investmentValueMinor;
  int get totalAssetsMinor => ledger.totalAssetsMinor;
  int get netWorthMinor => ledger.netWorthMinor;
  List<ReminderItem> get reminders => ledger.reminders;

  // ---------------------------------------------------------------------
  // Market data forwards — see [MarketDataManager].
  // ---------------------------------------------------------------------

  List<MarketInstrument> get marketCatalog => marketData.marketCatalog;
  bool get isLoadingMarketCatalog => marketData.isLoadingMarketCatalog;
  String? get marketDataError => marketData.marketDataError;

  Future<void> ensureMarketCatalog({bool forceRefresh = false}) =>
      marketData.ensureMarketCatalog(forceRefresh: forceRefresh);
  List<MarketInstrument> searchMarketCatalog(String query) =>
      marketData.searchMarketCatalog(query);
  Future<void> refreshMarketData() => marketData.refreshMarketData();
  Map<String, MarketInstrument> get existingMarketLinkCandidates =>
      marketData.existingMarketLinkCandidates;
  Future<void> linkMarketProducts(Map<String, MarketInstrument> links) =>
      marketData.linkMarketProducts(links);
  Future<void> unlinkMarketProduct(String productId) =>
      marketData.unlinkMarketProduct(productId);

  // ---------------------------------------------------------------------
  // Accounts forwards — see [AccountsManager].
  // ---------------------------------------------------------------------

  Future<void> upsertAccount(Account account) => accounts.upsertAccount(account);
  Future<void> mergeAccounts({
    required String sourceAccountId,
    required String targetAccountId,
  }) => accounts.mergeAccounts(
    sourceAccountId: sourceAccountId,
    targetAccountId: targetAccountId,
  );
  Future<void> deleteAccount(String id) => accounts.deleteAccount(id);
  Future<void> addBalanceAdjustment(BalanceAdjustment adjustment) =>
      accounts.addBalanceAdjustment(adjustment);
  Future<void> upsertAccountTransfer({
    required String id,
    required String fromAccountId,
    required String toAccountId,
    required int amountMinor,
    required DateTime date,
    String note = '',
  }) => accounts.upsertAccountTransfer(
    id: id,
    fromAccountId: fromAccountId,
    toAccountId: toAccountId,
    amountMinor: amountMinor,
    date: date,
    note: note,
  );
  Future<void> deleteAccountTransfer(String id) =>
      accounts.deleteAccountTransfer(id);
  Future<void> upsertBalanceAdjustment(BalanceAdjustment adjustment) =>
      accounts.upsertBalanceAdjustment(adjustment);
  Future<void> deleteBalanceAdjustment(String id) =>
      accounts.deleteBalanceAdjustment(id);

  // ---------------------------------------------------------------------
  // Expenses / incomes forwards — see [ExpensesManager].
  // ---------------------------------------------------------------------

  Future<void> upsertExpense(Expense expense) => expenses.upsertExpense(expense);
  Future<void> deleteExpense(String id) => expenses.deleteExpense(id);
  Future<void> upsertRecurringExpense(RecurringExpense expense) =>
      expenses.upsertRecurringExpense(expense);
  Future<void> setRecurringExpenseActive(String id, bool active) =>
      expenses.setRecurringExpenseActive(id, active);
  Future<void> upsertIncome(IncomeEntry income) => expenses.upsertIncome(income);
  Future<void> deleteIncome(String id) => expenses.deleteIncome(id);

  // ---------------------------------------------------------------------
  // Cards / bills forwards — see [CardsManager].
  // ---------------------------------------------------------------------

  Future<void> upsertCard(CreditCard card) => cards.upsertCard(card);
  Future<void> deleteCard(String id) => cards.deleteCard(id);
  Future<void> upsertBill(CardBill bill) => cards.upsertBill(bill);
  Future<void> payBill(String id) => cards.payBill(id);
  Future<void> upsertBillPayment({
    required String billId,
    required String paymentId,
    required int amountMinor,
    required DateTime date,
    required String accountId,
    String note = '',
    bool autoDebitSucceeded = false,
  }) => cards.upsertBillPayment(
    billId: billId,
    paymentId: paymentId,
    amountMinor: amountMinor,
    date: date,
    accountId: accountId,
    note: note,
    autoDebitSucceeded: autoDebitSucceeded,
  );
  Future<void> deleteBillPayment(String billId, String transactionId) =>
      cards.deleteBillPayment(billId, transactionId);
  Future<void> markBillAutoDebitFailed(String billId) =>
      cards.markBillAutoDebitFailed(billId);
  Future<void> deleteBill(String id) => cards.deleteBill(id);
  Future<void> acknowledgeBillReminder(String billId) =>
      cards.acknowledgeBillReminder(billId);

  // ---------------------------------------------------------------------
  // Investments forwards — see [InvestmentsManager].
  // ---------------------------------------------------------------------

  Future<void> upsertProduct(InvestmentProduct product) =>
      investments.upsertProduct(product);
  Future<void> createInvestmentHolding({
    required InvestmentProduct product,
    InvestmentAdjustment? adjustment,
    InvestmentTransaction? transaction,
  }) => investments.createInvestmentHolding(
    product: product,
    adjustment: adjustment,
    transaction: transaction,
  );
  Future<void> deleteProduct(String id) => investments.deleteProduct(id);
  Future<void> upsertInvestmentTransaction(InvestmentTransaction transaction) =>
      investments.upsertInvestmentTransaction(transaction);
  Future<void> deleteInvestmentTransaction(String id) =>
      investments.deleteInvestmentTransaction(id);
  Future<void> upsertInvestmentAdjustment(InvestmentAdjustment adjustment) =>
      investments.upsertInvestmentAdjustment(adjustment);
  Future<void> deleteInvestmentAdjustment(String id) =>
      investments.deleteInvestmentAdjustment(id);

  // ---------------------------------------------------------------------
  // Orders forwards — see [OrdersManager].
  // ---------------------------------------------------------------------

  Future<void> upsertOrder(GroupOrder order) => orders.upsertOrder(order);
  Future<void> deleteOrder(String id) => orders.deleteOrder(id);
  Future<void> updateParticipantStatus(
    String orderId,
    String participantId,
    CollectionStatus status,
  ) => orders.updateParticipantStatus(orderId, participantId, status);
  Future<void> cancelParticipantCollection(
    String orderId,
    String participantId,
  ) => orders.cancelParticipantCollection(orderId, participantId);
  Future<bool> confirmParticipantCollection(
    String orderId,
    String participantId,
  ) => orders.confirmParticipantCollection(orderId, participantId);

  // ---------------------------------------------------------------------
  // Categories / settings forwards — see [CategoriesManager].
  // ---------------------------------------------------------------------

  Future<void> addCategory({
    required BookkeepingCategoryKind kind,
    required String name,
    required String iconKey,
    required String colorKey,
  }) => categories.addCategory(
    kind: kind,
    name: name,
    iconKey: iconKey,
    colorKey: colorKey,
  );
  Future<void> updateCategory(BookkeepingCategory category) =>
      categories.updateCategory(category);
  Future<void> setCategoryActive(String id, bool active) =>
      categories.setCategoryActive(id, active);
  Future<void> reorderCategories(
    BookkeepingCategoryKind kind,
    List<String> orderedIds,
  ) => categories.reorderCategories(kind, orderedIds);
  Future<void> mergeCategory(String sourceId, String targetId) =>
      categories.mergeCategory(sourceId, targetId);
  Future<void> deleteCategory(String id) => categories.deleteCategory(id);

  Future<void> updateSettings(UserSettings settings) =>
      commit(data.copyWith(settings: settings));

  // ---------------------------------------------------------------------
  // 代訂 saved members — a quick-pick list of recent participant names.
  // ---------------------------------------------------------------------

  static const int _maxSavedOrderMembers = 30;

  /// Saves [name] to the front of the saved-members list (bumping it to the
  /// front if it's already saved), so it shows up first in the recent-people
  /// dropdown next time.
  Future<void> saveOrderMember(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return Future<void>.value();
    final members = [
      trimmed,
      ...data.settings.savedOrderMembers.where((item) => item != trimmed),
    ];
    if (members.length > _maxSavedOrderMembers) {
      members.removeRange(_maxSavedOrderMembers, members.length);
    }
    return updateSettings(
      data.settings.copyWith(savedOrderMembers: members),
    );
  }

  Future<void> removeOrderMember(String name) => updateSettings(
    data.settings.copyWith(
      savedOrderMembers: data.settings.savedOrderMembers
          .where((item) => item != name)
          .toList(),
    ),
  );

  // ---------------------------------------------------------------------
  // Demo data forwards — see [DemoDataManager].
  // ---------------------------------------------------------------------

  Future<void> generateDemoData() => demoData.generateDemoData();
  Future<void> clearDemoData() => demoData.clearDemoData();

  // ---------------------------------------------------------------------
  // CSV export forwards — see [CsvExportManager].
  // ---------------------------------------------------------------------

  Future<void> exportAccounts() => csv.exportAccounts();
  Future<void> exportExpenses() => csv.exportExpenses();
  Future<void> exportIncomes() => csv.exportIncomes();
  Future<void> exportInvestments() => csv.exportInvestments();
  Future<void> exportBills() => csv.exportBills();
  Future<void> exportOrders() => csv.exportOrders();

  String newId() => _uuid.v4();

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }
}
