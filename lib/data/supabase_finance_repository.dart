import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/models.dart';
import 'local_repositories.dart';
import 'repositories.dart';

class SupabaseFinanceRepository implements FinanceRepository {
  SupabaseFinanceRepository({
    required SupabaseClient client,
    required LocalPersistence cache,
    required SharedPreferences preferences,
    required String? Function() userIdProvider,
  }) : _client = client,
       _cache = cache,
       _preferences = preferences,
       _userIdProvider = userIdProvider;

  static const _migrationPrefix = 'quick_ledger_cloud_migration_v1_';
  final SupabaseClient _client;
  final LocalPersistence _cache;
  final SharedPreferences _preferences;
  final String? Function() _userIdProvider;

  int _revision = 0;
  bool _cloudExists = false;
  DateTime? _cloudUpdatedAt;
  AppData _cloudData = const AppData();
  AppData? _localCandidate;

  String? get _migrationKey {
    final userId = _userIdProvider();
    return userId == null ? null : '$_migrationPrefix$userId';
  }

  @override
  Future<FinanceSnapshot> load() async {
    final cached = await _readCache();
    try {
      final raw = await _client.rpc('load_finance_data');
      final response = Map<String, dynamic>.from(raw as Map);
      _revision = (response['revision'] as num?)?.toInt() ?? 0;
      _cloudExists = response['exists'] as bool? ?? false;
      _cloudUpdatedAt = response['updatedAt'] == null
          ? null
          : DateTime.parse(response['updatedAt'].toString());
      _cloudData = AppData.fromJson(
        migrateLocalFinanceJson(
          Map<String, dynamic>.from(response['data'] as Map? ?? const {}),
        ),
      );

      final migrationResolved =
          _migrationKey != null && _preferences.getBool(_migrationKey!) == true;
      _localCandidate =
          !migrationResolved && cached != null && hasFinanceData(cached)
          ? cached
          : null;

      if (_localCandidate == null) {
        await _writeCache(_cloudData);
      }
      return _snapshot();
    } on FinanceConflictException {
      rethrow;
    } on Object catch (error) {
      if (cached == null) {
        throw FinanceConnectionException(error);
      }
      return FinanceSnapshot(
        data: cached,
        revision: _revision,
        updatedAt: _cloudUpdatedAt,
        cloudExists: _cloudExists,
        isOffline: true,
      );
    }
  }

  @override
  Future<SaveResult> save(AppData data) async {
    final normalized = rewriteFinanceUserIds(data, _requireUserId());
    try {
      final raw = await _client.rpc(
        'save_finance_data',
        params: {'expected_revision': _revision, 'data': normalized.toJson()},
      );
      final result = _parseSaveResult(raw);
      _cloudData = normalized;
      _cloudExists = true;
      _cloudUpdatedAt = result.updatedAt;
      _localCandidate = null;
      await _markMigrationResolved();
      await _writeCache(normalized);
      return result;
    } on FinanceConflictException {
      rethrow;
    } on Object catch (error) {
      throw FinanceConnectionException(error);
    }
  }

  @override
  Future<SaveResult> clear() async {
    try {
      final raw = await _client.rpc(
        'clear_finance_data',
        params: {'expected_revision': _revision},
      );
      final result = _parseSaveResult(raw);
      _cloudData = const AppData();
      _cloudExists = true;
      _cloudUpdatedAt = result.updatedAt;
      _localCandidate = null;
      await _markMigrationResolved();
      await _writeCache(_cloudData);
      return result;
    } on FinanceConflictException {
      rethrow;
    } on Object catch (error) {
      throw FinanceConnectionException(error);
    }
  }

  @override
  Future<FinanceSnapshot> resolveInitialMigration(
    InitialMigrationAction action,
  ) async {
    final local = _localCandidate;
    if (local == null) return _snapshot();

    switch (action) {
      case InitialMigrationAction.useCloud:
        _localCandidate = null;
        await _markMigrationResolved();
        await _writeCache(_cloudData);
      case InitialMigrationAction.uploadLocal:
      case InitialMigrationAction.replaceCloud:
        await save(local);
      case InitialMigrationAction.merge:
        await save(mergeFinanceData(_cloudData, local));
    }
    return _snapshot();
  }

  SaveResult _parseSaveResult(Object? raw) {
    final response = Map<String, dynamic>.from(raw as Map);
    final revision = (response['revision'] as num?)?.toInt() ?? _revision;
    if (response['status'] == 'conflict') {
      throw FinanceConflictException(revision);
    }
    final updatedAt = DateTime.parse(response['updatedAt'].toString());
    _revision = revision;
    return SaveResult(revision: revision, updatedAt: updatedAt);
  }

  FinanceSnapshot _snapshot() => FinanceSnapshot(
    data: _cloudData,
    revision: _revision,
    updatedAt: _cloudUpdatedAt,
    cloudExists: _cloudExists,
    localCandidate: _localCandidate,
  );

  String _requireUserId() {
    final userId = _userIdProvider();
    if (userId == null) {
      throw const FinanceConnectionException('尚未登入');
    }
    return userId;
  }

  Future<AppData?> _readCache() async {
    final encoded = await _cache.read();
    if (encoded == null || encoded.isEmpty) return null;
    try {
      return AppData.fromJson(
        migrateLocalFinanceJson(
          Map<String, dynamic>.from(jsonDecode(encoded) as Map),
        ),
      );
    } on Object {
      return null;
    }
  }

  Future<void> _writeCache(AppData data) =>
      _cache.write(jsonEncode(data.toJson()));

  Future<void> _markMigrationResolved() async {
    final key = _migrationKey;
    if (key != null) await _preferences.setBool(key, true);
  }
}

bool hasFinanceData(AppData data) =>
    data.transactions.isNotEmpty ||
    data.accounts.isNotEmpty ||
    data.balanceAdjustments.isNotEmpty ||
    data.expenses.isNotEmpty ||
    data.recurringExpenses.isNotEmpty ||
    data.recurringExpenseOccurrences.isNotEmpty ||
    data.telecomBillPayments.isNotEmpty ||
    data.incomes.isNotEmpty ||
    data.cards.isNotEmpty ||
    data.bills.isNotEmpty ||
    data.products.isNotEmpty ||
    data.investmentTransactions.isNotEmpty ||
    data.investmentAdjustments.isNotEmpty ||
    data.investmentPriceHistory.isNotEmpty ||
    data.orders.isNotEmpty ||
    data.settings.toJson().toString() !=
        const UserSettings().toJson().toString();

int financeItemCount(AppData data) =>
    data.categories.length +
    data.transactions.length +
    data.accounts.length +
    data.balanceAdjustments.length +
    data.expenses.length +
    data.recurringExpenses.length +
    data.recurringExpenseOccurrences.length +
    data.telecomBillPayments.length +
    data.incomes.length +
    data.cards.length +
    data.bills.length +
    data.products.length +
    data.investmentTransactions.length +
    data.investmentAdjustments.length +
    data.investmentPriceHistory.length +
    data.orders.length;

AppData rewriteFinanceUserIds(AppData data, String userId) {
  final json = data.toJson();
  for (final key in const [
    'accounts',
    'categories',
    'transactions',
    'balanceAdjustments',
    'expenses',
    'recurringExpenses',
    'recurringExpenseOccurrences',
    'telecomBillPayments',
    'incomes',
    'cards',
    'bills',
    'products',
    'investmentTransactions',
    'investmentAdjustments',
    'orders',
  ]) {
    for (final raw in json[key] as List) {
      (raw as Map<String, dynamic>)['userId'] = userId;
    }
  }
  return AppData.fromJson(json);
}

AppData mergeFinanceData(AppData cloud, AppData local) => AppData(
  schemaVersion: 7,
  settings: _mergeSettings(cloud.settings, local.settings),
  categories: _cloudFirst(
    cloud.categories,
    local.categories,
    (item) => item.id,
  ),
  transactions: _cloudFirst(
    cloud.transactions,
    local.transactions,
    (item) => item.id,
  ),
  accounts: _cloudFirst(cloud.accounts, local.accounts, (item) => item.id),
  balanceAdjustments: _cloudFirst(
    cloud.balanceAdjustments,
    local.balanceAdjustments,
    (item) => item.id,
  ),
  expenses: _cloudFirst(cloud.expenses, local.expenses, (item) => item.id),
  recurringExpenses: _cloudFirst(
    cloud.recurringExpenses,
    local.recurringExpenses,
    (item) => item.id,
  ),
  recurringExpenseOccurrences: _cloudFirst(
    cloud.recurringExpenseOccurrences,
    local.recurringExpenseOccurrences,
    (item) => item.id,
  ),
  telecomBillPayments: _cloudFirst(
    cloud.telecomBillPayments,
    local.telecomBillPayments,
    (item) => item.id,
  ),
  incomes: _cloudFirst(cloud.incomes, local.incomes, (item) => item.id),
  cards: _cloudFirst(cloud.cards, local.cards, (item) => item.id),
  bills: _cloudFirst(cloud.bills, local.bills, (item) => item.id),
  products: _cloudFirst(cloud.products, local.products, (item) => item.id),
  investmentTransactions: _cloudFirst(
    cloud.investmentTransactions,
    local.investmentTransactions,
    (item) => item.id,
  ),
  investmentAdjustments: _cloudFirst(
    cloud.investmentAdjustments,
    local.investmentAdjustments,
    (item) => item.id,
  ),
  investmentPriceHistory: _cloudFirst(
    cloud.investmentPriceHistory,
    local.investmentPriceHistory,
    (item) =>
        '${item.productId}/${item.date.toIso8601String().substring(0, 10)}',
  ),
  orders: _cloudFirst(cloud.orders, local.orders, (item) => item.id),
);

List<T> _cloudFirst<T>(List<T> cloud, List<T> local, String Function(T) id) {
  final cloudIds = cloud.map(id).toSet();
  return [...cloud, ...local.where((item) => !cloudIds.contains(id(item)))];
}

UserSettings _mergeSettings(UserSettings cloud, UserSettings local) {
  final cloudKeys = {
    for (final rate in cloud.fxRates)
      '${rate.from}/${rate.to}/${rate.updatedAt.toIso8601String().substring(0, 10)}',
  };
  return UserSettings(
    defaultCurrency: cloud.defaultCurrency,
    defaultPaymentMethod: cloud.defaultPaymentMethod,
    defaultCategory: cloud.defaultCategory,
    defaultExpenseCategoryId: cloud.defaultExpenseCategoryId,
    defaultCollectionAccountId: cloud.defaultCollectionAccountId,
    linePayQrData: cloud.linePayQrData,
    bankQrData: cloud.bankQrData,
    bankAccountInfo: cloud.bankAccountInfo,
    remindersEnabled: cloud.remindersEnabled,
    lineRemindersEnabled: cloud.lineRemindersEnabled,
    maskBalances: cloud.maskBalances,
    fxRates: [
      ...cloud.fxRates,
      ...local.fxRates.where(
        (rate) => !cloudKeys.contains(
          '${rate.from}/${rate.to}/${rate.updatedAt.toIso8601String().substring(0, 10)}',
        ),
      ),
    ],
  );
}
