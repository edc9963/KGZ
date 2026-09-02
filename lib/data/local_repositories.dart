import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/models.dart';
import 'oauth_navigation.dart';
import 'repositories.dart';

class MockAuthRepository implements AuthRepository {
  MockAuthRepository(this._preferences);

  static const _sessionKey = 'quick_ledger_session';
  static const demoUserId = 'demo-line-user';
  final SharedPreferences _preferences;
  final StreamController<bool> _controller = StreamController.broadcast();

  @override
  String? get currentUserId =>
      _preferences.getBool(_sessionKey) == true ? demoUserId : null;

  @override
  String? get currentUserDisplayName => isSignedIn ? 'LINE 使用者' : null;

  @override
  bool get isSignedIn => currentUserId != null;

  @override
  Stream<bool> get authStateChanges => _controller.stream;

  @override
  Future<void> signInWithLine({String? returnPath}) async {
    await _preferences.setBool(_sessionKey, true);
    _controller.add(true);
  }

  @override
  Future<void> signOut() async {
    await _preferences.setBool(_sessionKey, false);
    _controller.add(false);
  }
}

class SupabaseAuthRepository implements AuthRepository {
  SupabaseAuthRepository(this._client) {
    _subscription = _client.auth.onAuthStateChange.listen(
      (event) => _controller.add(event.session != null),
    );
  }

  final SupabaseClient _client;
  final StreamController<bool> _controller = StreamController.broadcast();
  StreamSubscription<AuthState>? _subscription;

  @override
  String? get currentUserId => _client.auth.currentUser?.id;

  @override
  String? get currentUserDisplayName {
    final metadata = _client.auth.currentUser?.userMetadata;
    final value =
        metadata?['name'] ??
        metadata?['full_name'] ??
        metadata?['display_name'];
    return value is String && value.trim().isNotEmpty ? value.trim() : null;
  }

  @override
  bool get isSignedIn => _client.auth.currentSession != null;

  @override
  Stream<bool> get authStateChanges => _controller.stream;

  @override
  Future<void> signInWithLine({String? returnPath}) async {
    const provider = OAuthProvider('custom:line');
    final redirectTo = kIsWeb ? _webOAuthRedirect(returnPath) : null;
    if (kIsWeb) {
      final response = await _client.auth.getOAuthSignInUrl(
        provider: provider,
        redirectTo: redirectTo,
        scopes: 'openid profile',
      );
      navigateToOAuth(response.url);
      return;
    }
    await _client.auth.signInWithOAuth(
      provider,
      redirectTo: redirectTo,
      scopes: 'openid profile',
    );
  }

  String _webOAuthRedirect(String? returnPath) {
    final target = Uri.parse(
      '${Uri.base.origin}${safeAuthReturnPath(returnPath)}',
    );
    return target
        .replace(
          queryParameters: {
            ...target.queryParameters,
            'auth_return': '1',
            'auth_source': isStandaloneDisplayMode() ? 'pwa' : 'browser',
          },
        )
        .toString();
  }

  @override
  Future<void> signOut() => _client.auth.signOut();

  Future<void> dispose() async {
    await _subscription?.cancel();
    await _controller.close();
  }
}

class UnconfiguredAuthRepository implements AuthRepository {
  const UnconfiguredAuthRepository();
  @override
  String? get currentUserId => null;
  @override
  String? get currentUserDisplayName => null;
  @override
  bool get isSignedIn => false;
  @override
  Stream<bool> get authStateChanges => const Stream.empty();
  @override
  Future<void> signInWithLine({String? returnPath}) =>
      throw StateError('尚未設定 SUPABASE_URL 與 SUPABASE_PUBLISHABLE_KEY');
  @override
  Future<void> signOut() async {}
}

String safeAuthReturnPath(String? value) {
  if (value == null || value.isEmpty) return '/dashboard';
  final uri = Uri.tryParse(value);
  if (uri == null ||
      uri.hasScheme ||
      uri.hasAuthority ||
      !uri.path.startsWith('/') ||
      uri.path.startsWith('//') ||
      uri.path == '/login') {
    return '/dashboard';
  }
  return uri.toString();
}

class SharedPreferencesLocalPersistence implements LocalPersistence {
  SharedPreferencesLocalPersistence(this._preferences);
  static const _dataKey = 'quick_ledger_data_v1';
  final SharedPreferences _preferences;

  @override
  Future<String?> read() async => _preferences.getString(_dataKey);

  @override
  Future<void> write(String value) async {
    await _preferences.setString(_dataKey, value);
  }

  @override
  Future<void> clear() async {
    await _preferences.remove(_dataKey);
  }
}

class UserScopedSharedPreferencesPersistence implements LocalPersistence {
  UserScopedSharedPreferencesPersistence(
    this._preferences,
    this._userIdProvider,
  );

  static const _legacyKey = 'quick_ledger_data_v1';
  static const _migrationKey = 'quick_ledger_supabase_auth_migrated_v1';
  final SharedPreferences _preferences;
  final String? Function() _userIdProvider;

  String get _key {
    final userId = _userIdProvider();
    if (userId == null) return 'quick_ledger_data_v2_signed_out';
    return 'quick_ledger_data_v2_$userId';
  }

  Future<void> clearLegacyOnce() async {
    if (_userIdProvider() == null ||
        _preferences.getBool(_migrationKey) == true) {
      return;
    }
    final legacy = _preferences.getString(_legacyKey);
    if (legacy != null && _preferences.getString(_key) == null) {
      await _preferences.setString(_key, legacy);
    }
    // Keep the legacy value as a recovery copy. The cloud repository only
    // marks its own migration complete after a successful cloud write.
    await _preferences.setBool(_migrationKey, true);
  }

  @override
  Future<String?> read() async {
    await clearLegacyOnce();
    return _preferences.getString(_key);
  }

  @override
  Future<void> write(String value) => _preferences.setString(_key, value);

  @override
  Future<void> clear() => _preferences.remove(_key);
}

class LocalFinanceRepository implements FinanceRepository {
  LocalFinanceRepository(this._persistence);
  final LocalPersistence _persistence;
  int _revision = 0;

  @override
  Future<FinanceSnapshot> load() async {
    final encoded = await _persistence.read();
    if (encoded == null || encoded.isEmpty) {
      return const FinanceSnapshot(data: AppData());
    }
    try {
      return FinanceSnapshot(
        data: AppData.fromJson(
          migrateLocalFinanceJson(jsonDecode(encoded) as Json),
        ),
        revision: _revision,
        cloudExists: true,
      );
    } on Object {
      return const FinanceSnapshot(data: AppData());
    }
  }

  @override
  Future<SaveResult> save(AppData data) async {
    await _persistence.write(jsonEncode(data.toJson()));
    _revision += 1;
    return SaveResult(revision: _revision, updatedAt: DateTime.now());
  }

  @override
  Future<SaveResult> clear() async {
    await _persistence.clear();
    _revision += 1;
    return SaveResult(revision: _revision, updatedAt: DateTime.now());
  }

  @override
  Future<FinanceSnapshot> resolveInitialMigration(
    InitialMigrationAction action,
  ) => load();
}

Json migrateLocalFinanceJson(Json source) {
  final version = source['schemaVersion'] as int? ?? 0;
  if (version >= 9) return source;
  if (version == 8) return _migrateBillsToV9(source);
  final normalized = <String, dynamic>{
    ...source,
    'schemaVersion': 9,
    'settings': source['settings'] ?? <String, dynamic>{},
    for (final key in const [
      'accounts',
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
      'investmentPriceHistory',
      'orders',
    ])
      key: source[key] ?? <dynamic>[],
  };
  normalized['accounts'] = [
    for (final raw in normalized['accounts'] as List)
      if (raw is Map)
        {
          ...Map<String, dynamic>.from(raw),
          'openingBalanceDate': raw['openingBalanceDate'] ?? raw['createdAt'],
        },
  ];
  normalized['bills'] = [
    for (final raw in normalized['bills'] as List)
      if (raw is Map)
        {
          ...Map<String, dynamic>.from(raw),
          'paidAt':
              raw['paidAt'] ??
              (((raw['paidMinor'] as int? ?? 0) > 0)
                  ? raw['autoDebitDate']
                  : null),
          'statementAmountMinor': _legacyBillAmount(raw, normalized),
          'reconciliationReason':
              (raw['manualAdjustmentMinor'] as int? ?? 0) == 0
              ? 'none'
              : 'legacyAdjustment',
          'reconciliationNote': (raw['manualAdjustmentMinor'] as int? ?? 0) == 0
              ? ''
              : (raw['note'] as String? ?? ''),
          'autoDebitState': 'pending',
        },
  ];
  if ((normalized['investmentPriceHistory'] as List).isEmpty) {
    normalized['investmentPriceHistory'] = [
      for (final raw in normalized['products'] as List)
        if (raw is Map)
          {
            'productId': raw['id'],
            'priceMinor': raw['currentPriceMinor'],
            'date': raw['priceUpdatedAt'],
            'estimated': true,
          },
    ];
  }
  normalized['orders'] = [
    for (final rawOrder in normalized['orders'] as List)
      if (rawOrder is Map)
        {
          ...Map<String, dynamic>.from(rawOrder),
          'participants': [
            for (final rawParticipant
                in (rawOrder['participants'] as List? ?? const []))
              if (rawParticipant is Map)
                {
                  ...Map<String, dynamic>.from(rawParticipant),
                  'discountEligible':
                      (rawParticipant['discountMinor'] as int? ?? 0) > 0,
                  'discountIsFixed':
                      (rawParticipant['discountMinor'] as int? ?? 0) > 0,
                  'cancelledAt':
                      rawParticipant['cancelledAt'] ??
                      (rawParticipant['status'] == 'cancelled'
                          ? rawOrder['date']
                          : null),
                },
          ],
        },
  ];

  final userId = _firstUserId(normalized);
  final categories = defaultBookkeepingCategories(userId);
  final categoryByKey = <String, BookkeepingCategory>{
    for (final category in categories)
      '${category.kind.name}:${category.name.trim().toLowerCase()}': category,
  };
  void includeCategory(String rawName, BookkeepingCategoryKind kind) {
    final name = rawName.trim();
    if (name.isEmpty) return;
    final key = '${kind.name}:${name.toLowerCase()}';
    if (categoryByKey.containsKey(key)) return;
    final sameKind = categoryByKey.values.where((item) => item.kind == kind);
    categoryByKey[key] = BookkeepingCategory(
      id: 'custom-${kind.name}-${_stableCategoryHash(name)}',
      userId: userId,
      name: name,
      kind: kind,
      iconKey: 'other',
      colorKey: 'slate',
      sortOrder: sameKind.length,
    );
  }

  for (final raw in normalized['expenses'] as List) {
    if (raw is Map) {
      includeCategory(
        raw['category'] as String? ?? '其他',
        BookkeepingCategoryKind.expense,
      );
    }
  }
  for (final raw in normalized['recurringExpenses'] as List) {
    if (raw is Map) {
      includeCategory(
        raw['category'] as String? ?? '其他',
        BookkeepingCategoryKind.expense,
      );
    }
  }
  for (final raw in normalized['incomes'] as List) {
    if (raw is Map) {
      includeCategory(
        raw['category'] as String? ?? '其他收入',
        BookkeepingCategoryKind.income,
      );
    }
  }
  String categoryId(String name, BookkeepingCategoryKind kind) =>
      categoryByKey['${kind.name}:${name.trim().toLowerCase()}']?.id ??
      (kind == BookkeepingCategoryKind.expense
          ? 'expense-other'
          : 'income-other');

  final accounts = <Map<String, dynamic>>[
    for (final raw in normalized['accounts'] as List)
      if (raw is Map) Map<String, dynamic>.from(raw),
  ];
  for (final account in accounts) {
    account['kind'] ??= 'asset';
    account['subtype'] ??= account['type'] == '現金' ? 'cash' : 'bank';
  }
  final accountIds = accounts.map((item) => item['id']).toSet();
  void addSystemAccount({
    required String id,
    required String name,
    required String kind,
    required String subtype,
  }) {
    if (!accountIds.add(id)) return;
    accounts.add({
      'id': id,
      'userId': userId,
      'name': name,
      'institution': '',
      'type': name,
      'currency': 'TWD',
      'openingBalanceMinor': 0,
      'isActive': true,
      'note': '系統帳戶',
      'createdAt': DateTime.utc(2026, 1, 1).toIso8601String(),
      'updatedAt': DateTime.utc(2026, 1, 1).toIso8601String(),
      'kind': kind,
      'subtype': subtype,
      'origin': 'user',
    });
  }

  addSystemAccount(
    id: 'system-receivable',
    name: '代訂應收款',
    kind: 'receivable',
    subtype: 'orderReceivable',
  );
  for (final raw in normalized['cards'] as List) {
    if (raw is! Map) continue;
    if ((raw['cardType'] as String? ?? 'credit') != 'credit') {
      raw['liabilityAccountId'] = null;
      continue;
    }
    final liabilityId =
        raw['liabilityAccountId'] as String? ?? 'card-liability-${raw['id']}';
    raw['liabilityAccountId'] = liabilityId;
    addSystemAccount(
      id: liabilityId,
      name: '${raw['name']}未繳',
      kind: 'liability',
      subtype: 'creditCard',
    );
  }
  normalized['accounts'] = accounts;

  final cardLiabilityById = <String, String>{
    for (final raw in normalized['cards'] as List)
      if (raw is Map && (raw['cardType'] as String? ?? 'credit') == 'credit')
        raw['id'] as String:
            raw['liabilityAccountId'] as String? ??
            'card-liability-${raw['id']}',
  };
  final accountCurrency = <String, String>{
    for (final raw in accounts)
      raw['id'] as String: raw['currency'] as String? ?? 'TWD',
  };
  Map<String, dynamic> impact(String accountId, int amount) => {
    'accountId': accountId,
    'amountMinor': amount,
    'currency': accountCurrency[accountId] ?? 'TWD',
  };
  final transactions = <Map<String, dynamic>>[];

  for (final raw in normalized['balanceAdjustments'] as List) {
    if (raw is! Map) continue;
    transactions.add({
      'id': 'balance:${raw['id']}',
      'userId': raw['userId'] ?? userId,
      'date': raw['date'],
      'type': 'balanceAdjustment',
      'label': raw['reason'] ?? '餘額調整',
      'amountMinor': (raw['amountMinor'] as int).abs(),
      'currency': accountCurrency[raw['accountId']] ?? 'TWD',
      'note': '',
      'relatedEntityType': 'balanceAdjustment',
      'relatedEntityId': raw['id'],
      'impacts': [
        impact(raw['accountId'] as String, raw['amountMinor'] as int),
      ],
      'origin': raw['origin'] ?? 'user',
    });
  }
  for (final raw in normalized['expenses'] as List) {
    if (raw is! Map) continue;
    final amount = raw['amountMinor'] as int;
    final method = raw['paymentMethod'] as String? ?? 'other';
    final impacts = <Map<String, dynamic>>[];
    if (method == 'creditCard' && raw['cardId'] != null) {
      impacts.add(impact(cardLiabilityById[raw['cardId']]!, amount));
    } else if (raw['accountId'] != null) {
      impacts.add(impact(raw['accountId'] as String, -amount));
    }
    transactions.add({
      'id': 'expense:${raw['id']}',
      'userId': raw['userId'] ?? userId,
      'date': raw['date'],
      'type': 'expense',
      'label': raw['item'],
      'amountMinor': amount,
      'currency': 'TWD',
      'categoryId': categoryId(
        raw['category'] as String? ?? '其他',
        BookkeepingCategoryKind.expense,
      ),
      'note': raw['note'] ?? '',
      'relatedEntityType': 'expense',
      'relatedEntityId': raw['id'],
      'impacts': impacts,
      'origin': raw['origin'] ?? 'user',
    });
  }
  for (final raw in normalized['incomes'] as List) {
    if (raw is! Map) continue;
    final accountId = raw['accountId'] as String;
    transactions.add({
      'id': 'income:${raw['id']}',
      'userId': raw['userId'] ?? userId,
      'date': raw['date'],
      'type': 'income',
      'label': raw['item'],
      'amountMinor': raw['amountMinor'],
      'currency': accountCurrency[accountId] ?? 'TWD',
      'categoryId': categoryId(
        raw['category'] as String? ?? '其他收入',
        BookkeepingCategoryKind.income,
      ),
      'note': raw['note'] ?? '',
      'relatedEntityType': 'income',
      'relatedEntityId': raw['id'],
      'impacts': [impact(accountId, raw['amountMinor'] as int)],
      'origin': raw['origin'] ?? 'user',
    });
  }
  for (final raw in normalized['investmentTransactions'] as List) {
    if (raw is! Map) continue;
    final gross =
        ((raw['quantityMicros'] as int) * (raw['priceMinor'] as int) / 1000000)
            .round();
    final type = raw['type'] as String;
    final isInflow = const {'sell', 'redeem', 'dividend'}.contains(type);
    final accountId = isInflow
        ? raw['creditAccountId'] as String?
        : raw['debitAccountId'] as String?;
    final amount = isInflow
        ? gross -
              (raw['feeMinor'] as int? ?? 0) -
              (raw['taxMinor'] as int? ?? 0)
        : gross +
              (raw['feeMinor'] as int? ?? 0) +
              (raw['taxMinor'] as int? ?? 0);
    transactions.add({
      'id': 'investment:${raw['id']}',
      'userId': raw['userId'] ?? userId,
      'date': raw['date'],
      'type': type == 'dividend'
          ? 'investmentDividend'
          : isInflow
          ? 'investmentSell'
          : 'investmentBuy',
      'label': '投資${isInflow ? '入帳' : '扣款'}',
      'amountMinor': amount,
      'currency': accountId == null
          ? 'TWD'
          : accountCurrency[accountId] ?? 'TWD',
      'note': raw['note'] ?? '',
      'relatedEntityType': 'investmentTransaction',
      'relatedEntityId': raw['id'],
      'impacts': accountId == null
          ? <Map<String, dynamic>>[]
          : [impact(accountId, isInflow ? amount : -amount)],
      'origin': raw['origin'] ?? 'user',
    });
  }
  for (final raw in normalized['bills'] as List) {
    if (raw is! Map || (raw['paidMinor'] as int? ?? 0) <= 0) continue;
    final cardId = raw['cardId'] as String;
    final card = (normalized['cards'] as List)
        .whereType<Map>()
        .where((item) => item['id'] == cardId)
        .firstOrNull;
    if (card == null) continue;
    final amount = raw['paidMinor'] as int;
    transactions.add({
      'id': 'card-payment:${raw['id']}',
      'userId': raw['userId'] ?? userId,
      'date': raw['paidAt'] ?? raw['autoDebitDate'],
      'type': 'cardPayment',
      'label': '${card['name']} ${raw['month']} 帳單',
      'amountMinor': amount,
      'currency': 'TWD',
      'note': raw['note'] ?? '',
      'relatedEntityType': 'cardBill',
      'relatedEntityId': raw['id'],
      'impacts': [
        impact(card['debitAccountId'] as String, -amount),
        impact(cardLiabilityById[cardId]!, -amount),
      ],
      'origin': raw['origin'] ?? 'user',
    });
  }
  for (final raw in normalized['telecomBillPayments'] as List) {
    if (raw is! Map) continue;
    final accountId = raw['debitAccountId'] as String;
    final amount = raw['amountMinor'] as int;
    transactions.add({
      'id': 'telecom-payment:${raw['id']}',
      'userId': raw['userId'] ?? userId,
      'date': raw['paidAt'],
      'type': 'cardPayment',
      'label': '電信帳單 ${raw['month']}',
      'amountMinor': amount,
      'currency': accountCurrency[accountId] ?? 'TWD',
      'note': '',
      'relatedEntityType': 'telecomBillPayment',
      'relatedEntityId': raw['id'],
      'impacts': [impact(accountId, -amount)],
      'origin': 'user',
    });
  }
  for (final raw in normalized['orders'] as List) {
    if (raw is! Map) continue;
    final participants = raw['participants'] as List? ?? const [];
    int due(Map participant) {
      final rawCalculated =
          (participant['itemAmountMinor'] as int? ?? 0) +
          (participant['sharedFeeMinor'] as int? ?? 0) -
          (participant['discountMinor'] as int? ?? 0);
      final calculated = rawCalculated < 0 ? 0 : rawCalculated;
      return participant['finalDueMinor'] as int? ??
          participant['suggestedDueMinor'] as int? ??
          calculated;
    }

    final receivable = participants
        .whereType<Map>()
        .where(
          (item) => item['isSelf'] != true && item['status'] != 'cancelled',
        )
        .fold<int>(0, (sum, item) => sum + due(item));
    final liabilityId = cardLiabilityById[raw['cardId']];
    transactions.add({
      'id': 'order-charge:${raw['id']}',
      'userId': raw['userId'] ?? userId,
      'date': raw['date'],
      'type': 'orderCharge',
      'label': raw['name'],
      'amountMinor': raw['totalMinor'],
      'currency': 'TWD',
      'categoryId': categoryId('餐飲', BookkeepingCategoryKind.expense),
      'note': raw['note'] ?? '',
      'relatedEntityType': 'groupOrder',
      'relatedEntityId': raw['id'],
      'impacts': [
        if (liabilityId != null) impact(liabilityId, raw['totalMinor'] as int),
        if (receivable > 0) impact('system-receivable', receivable),
      ],
      'origin': raw['origin'] ?? 'user',
    });
    for (final participant in participants.whereType<Map>().where(
      (item) => item['isSelf'] != true && item['status'] == 'paid',
    )) {
      final accountId = participant['collectionAccountId'] as String?;
      if (accountId == null) continue;
      final amount = due(participant);
      transactions.add({
        'id': 'order-collection:${raw['id']}:${participant['id']}',
        'userId': raw['userId'] ?? userId,
        'date': participant['collectedAt'] ?? raw['date'],
        'type': 'orderCollection',
        'label': '${raw['name']}－${participant['name']}',
        'amountMinor': amount,
        'currency': 'TWD',
        'note': participant['note'] ?? '',
        'relatedEntityType': 'orderParticipant',
        'relatedEntityId': participant['id'],
        'impacts': [
          impact(accountId, amount),
          impact('system-receivable', -amount),
        ],
        'origin': raw['origin'] ?? 'user',
      });
    }
  }

  final settings = Map<String, dynamic>.from(normalized['settings'] as Map);
  settings['defaultExpenseCategoryId'] = categoryId(
    settings['defaultCategory'] as String? ?? '餐飲',
    BookkeepingCategoryKind.expense,
  );
  normalized['settings'] = settings;
  normalized['categories'] = categoryByKey.values
      .map((item) => item.toJson())
      .toList();
  normalized['transactions'] = transactions;
  return normalized;
}

Json _migrateBillsToV9(Json source) {
  final normalized = <String, dynamic>{...source, 'schemaVersion': 9};
  normalized['bills'] = [
    for (final raw in source['bills'] as List? ?? const [])
      if (raw is Map)
        {
          ...Map<String, dynamic>.from(raw),
          'statementAmountMinor':
              raw['statementAmountMinor'] ?? _legacyBillAmount(raw, source),
          'reconciliationReason':
              raw['reconciliationReason'] ??
              ((raw['manualAdjustmentMinor'] as int? ?? 0) == 0
                  ? 'none'
                  : 'legacyAdjustment'),
          'reconciliationNote':
              raw['reconciliationNote'] ??
              ((raw['manualAdjustmentMinor'] as int? ?? 0) == 0
                  ? ''
                  : (raw['note'] as String? ?? '')),
          'autoDebitState': raw['autoDebitState'] ?? 'pending',
        },
  ];
  return normalized;
}

int _legacyBillAmount(Map rawBill, Map source) {
  var total = rawBill['manualAdjustmentMinor'] as int? ?? 0;
  final chargeIds = (rawBill['chargeIds'] as List? ?? const [])
      .whereType<String>();
  final expenses = {
    for (final raw in source['expenses'] as List? ?? const [])
      if (raw is Map && raw['id'] is String)
        raw['id'] as String: raw['amountMinor'] as int? ?? 0,
  };
  final orders = {
    for (final raw in source['orders'] as List? ?? const [])
      if (raw is Map && raw['id'] is String)
        raw['id'] as String: raw['totalMinor'] as int? ?? 0,
  };
  for (final id in chargeIds) {
    if (id.startsWith('expense:')) {
      total += expenses[id.substring('expense:'.length)] ?? 0;
    } else if (id.startsWith('order:')) {
      total += orders[id.substring('order:'.length)] ?? 0;
    }
  }
  return total < 0 ? 0 : total;
}

String _firstUserId(Json data) {
  for (final key in const [
    'accounts',
    'expenses',
    'incomes',
    'cards',
    'orders',
  ]) {
    for (final raw in data[key] as List? ?? const []) {
      if (raw is Map && raw['userId'] is String) return raw['userId'] as String;
    }
  }
  return '';
}

String _stableCategoryHash(String value) {
  var hash = 0;
  for (final unit in value.codeUnits) {
    hash = (hash * 31 + unit) & 0x7fffffff;
  }
  return hash.toRadixString(16);
}
