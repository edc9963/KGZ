typedef Json = Map<String, dynamic>;
typedef CurrencyCode = String;
typedef CollectionToken = String;

const collectionMethodCash = '現金';
const collectionMethodBankTransfer = '銀行轉帳';
const supportedCollectionMethods = <String>[
  collectionMethodCash,
  collectionMethodBankTransfer,
];
const systemCashAccountId = 'system-cash';

enum DataOrigin { user, demo }

enum BookkeepingCategoryKind { expense, income }

enum FinancialAccountKind { asset, liability, receivable }

enum FinancialTransactionType {
  expense,
  income,
  transfer,
  cardPayment,
  balanceAdjustment,
  investmentBuy,
  investmentSell,
  investmentDividend,
  orderCharge,
  orderCollection,
}

class BookkeepingCategory {
  const BookkeepingCategory({
    required this.id,
    required this.userId,
    required this.name,
    required this.kind,
    required this.iconKey,
    required this.colorKey,
    required this.sortOrder,
    this.isActive = true,
    this.isBuiltIn = false,
    this.mergedIntoCategoryId,
  });

  final String id;
  final String userId;
  final String name;
  final BookkeepingCategoryKind kind;
  final String iconKey;
  final String colorKey;
  final int sortOrder;
  final bool isActive;
  final bool isBuiltIn;
  final String? mergedIntoCategoryId;

  BookkeepingCategory copyWith({
    String? name,
    String? iconKey,
    String? colorKey,
    int? sortOrder,
    bool? isActive,
    String? mergedIntoCategoryId,
    bool clearMergedInto = false,
  }) => BookkeepingCategory(
    id: id,
    userId: userId,
    name: name ?? this.name,
    kind: kind,
    iconKey: iconKey ?? this.iconKey,
    colorKey: colorKey ?? this.colorKey,
    sortOrder: sortOrder ?? this.sortOrder,
    isActive: isActive ?? this.isActive,
    isBuiltIn: isBuiltIn,
    mergedIntoCategoryId: clearMergedInto
        ? null
        : (mergedIntoCategoryId ?? this.mergedIntoCategoryId),
  );

  Json toJson() => {
    'id': id,
    'userId': userId,
    'name': name,
    'kind': kind.name,
    'iconKey': iconKey,
    'colorKey': colorKey,
    'sortOrder': sortOrder,
    'isActive': isActive,
    'isBuiltIn': isBuiltIn,
    'mergedIntoCategoryId': mergedIntoCategoryId,
  };

  factory BookkeepingCategory.fromJson(Json json) => BookkeepingCategory(
    id: json['id'] as String,
    userId: json['userId'] as String? ?? '',
    name: json['name'] as String,
    kind: BookkeepingCategoryKind.values.byName(json['kind'] as String),
    iconKey: json['iconKey'] as String? ?? 'other',
    colorKey: json['colorKey'] as String? ?? 'slate',
    sortOrder: json['sortOrder'] as int? ?? 0,
    isActive: json['isActive'] as bool? ?? true,
    isBuiltIn: json['isBuiltIn'] as bool? ?? false,
    mergedIntoCategoryId: json['mergedIntoCategoryId'] as String?,
  );
}

const _defaultExpenseCategories = <(String, String, String, String)>[
  ('expense-food', '餐飲', 'restaurant', 'coral'),
  ('expense-transport', '交通', 'transport', 'blue'),
  ('expense-entertainment', '娛樂', 'movie', 'amber'),
  ('expense-subscription', '訂閱', 'repeat', 'indigo'),
  ('expense-rent', '房租', 'home', 'green'),
  ('expense-utilities', '水電瓦斯', 'bolt', 'teal'),
  ('expense-insurance', '保險', 'shield', 'slate'),
  ('expense-medical', '醫療', 'medical', 'rose'),
  ('expense-shopping', '購物', 'shopping', 'purple'),
  ('expense-travel', '旅遊', 'flight', 'cyan'),
  ('expense-investment', '投資', 'trending', 'indigo'),
  ('expense-advance', '代訂墊付', 'groups', 'brown'),
  ('expense-other', '其他', 'other', 'slate'),
];

const _defaultIncomeCategories = <(String, String, String, String)>[
  ('income-salary', '薪資', 'work', 'teal'),
  ('income-bonus', '獎金', 'award', 'blue'),
  ('income-interest', '利息', 'savings', 'indigo'),
  ('income-freelance', '自由業', 'laptop', 'blue'),
  ('income-rent', '租金', 'homeWork', 'green'),
  ('income-refund', '退款', 'refund', 'amber'),
  ('income-other', '其他收入', 'other', 'slate'),
];

List<BookkeepingCategory> defaultBookkeepingCategories([String userId = '']) =>
    [
      for (var i = 0; i < _defaultExpenseCategories.length; i++)
        BookkeepingCategory(
          id: _defaultExpenseCategories[i].$1,
          userId: userId,
          name: _defaultExpenseCategories[i].$2,
          kind: BookkeepingCategoryKind.expense,
          iconKey: _defaultExpenseCategories[i].$3,
          colorKey: _defaultExpenseCategories[i].$4,
          sortOrder: i,
          isBuiltIn: true,
        ),
      for (var i = 0; i < _defaultIncomeCategories.length; i++)
        BookkeepingCategory(
          id: _defaultIncomeCategories[i].$1,
          userId: userId,
          name: _defaultIncomeCategories[i].$2,
          kind: BookkeepingCategoryKind.income,
          iconKey: _defaultIncomeCategories[i].$3,
          colorKey: _defaultIncomeCategories[i].$4,
          sortOrder: i,
          isBuiltIn: true,
        ),
    ];

class AccountImpact {
  const AccountImpact({
    required this.accountId,
    required this.amountMinor,
    required this.currency,
  });

  final String accountId;
  final int amountMinor;
  final CurrencyCode currency;

  Json toJson() => {
    'accountId': accountId,
    'amountMinor': amountMinor,
    'currency': currency,
  };

  factory AccountImpact.fromJson(Json json) => AccountImpact(
    accountId: json['accountId'] as String,
    amountMinor: json['amountMinor'] as int,
    currency: json['currency'] as String? ?? 'TWD',
  );
}

class FinancialTransaction {
  const FinancialTransaction({
    required this.id,
    required this.userId,
    required this.date,
    required this.type,
    required this.label,
    required this.amountMinor,
    required this.currency,
    required this.impacts,
    this.categoryId,
    this.note = '',
    this.relatedEntityType,
    this.relatedEntityId,
    this.origin = DataOrigin.user,
  });

  final String id;
  final String userId;
  final DateTime date;
  final FinancialTransactionType type;
  final String label;
  final int amountMinor;
  final CurrencyCode currency;
  final String? categoryId;
  final String note;
  final String? relatedEntityType;
  final String? relatedEntityId;
  final List<AccountImpact> impacts;
  final DataOrigin origin;

  FinancialTransaction copyWith({
    String? label,
    int? amountMinor,
    String? currency,
    String? categoryId,
    String? note,
    List<AccountImpact>? impacts,
  }) => FinancialTransaction(
    id: id,
    userId: userId,
    date: date,
    type: type,
    label: label ?? this.label,
    amountMinor: amountMinor ?? this.amountMinor,
    currency: currency ?? this.currency,
    categoryId: categoryId ?? this.categoryId,
    note: note ?? this.note,
    relatedEntityType: relatedEntityType,
    relatedEntityId: relatedEntityId,
    impacts: impacts ?? this.impacts,
    origin: origin,
  );

  Json toJson() => {
    'id': id,
    'userId': userId,
    'date': date.toIso8601String(),
    'type': type.name,
    'label': label,
    'amountMinor': amountMinor,
    'currency': currency,
    'categoryId': categoryId,
    'note': note,
    'relatedEntityType': relatedEntityType,
    'relatedEntityId': relatedEntityId,
    'impacts': impacts.map((item) => item.toJson()).toList(),
    'origin': origin.name,
  };

  factory FinancialTransaction.fromJson(Json json) => FinancialTransaction(
    id: json['id'] as String,
    userId: json['userId'] as String? ?? '',
    date: DateTime.parse(json['date'] as String),
    type: FinancialTransactionType.values.byName(json['type'] as String),
    label: json['label'] as String,
    amountMinor: json['amountMinor'] as int,
    currency: json['currency'] as String? ?? 'TWD',
    categoryId: json['categoryId'] as String?,
    note: json['note'] as String? ?? '',
    relatedEntityType: json['relatedEntityType'] as String?,
    relatedEntityId: json['relatedEntityId'] as String?,
    impacts: (json['impacts'] as List? ?? const [])
        .map((item) => AccountImpact.fromJson(item as Json))
        .toList(),
    origin: DataOrigin.values.byName(json['origin'] as String? ?? 'user'),
  );
}

enum PaymentMethod {
  cash('現金'),
  transfer('銀行轉帳'),
  debitCard('簽帳金融卡'),
  creditCard('信用卡'),
  linePay('LINE Pay'),
  jkoPay('街口支付'),
  easyCard('悠遊卡'),
  iPass('一卡通'),
  telecomBill('電信帳單繳費'),
  other('其他');

  const PaymentMethod(this.label);
  final String label;
}

enum InvestmentTransactionType {
  buy('買入'),
  sell('賣出'),
  subscribe('申購'),
  redeem('贖回'),
  dividend('配息'),
  transferIn('轉入'),
  transferOut('轉出');

  const InvestmentTransactionType(this.label);
  final String label;
}

enum CollectionStatus {
  unpaid('未收款'),
  pending('待確認'),
  paid('已收款'),
  cancelled('取消');

  const CollectionStatus(this.label);
  final String label;
}

enum SplitMethod {
  equal('平均分攤'),
  manual('手動調整');

  const SplitMethod(this.label);
  final String label;
}

enum FeeRoundingPolicy { exactRemainder, ceilEachFee }

class Money {
  const Money(this.minorUnits, [this.currency = 'TWD']);

  final int minorUnits;
  final CurrencyCode currency;

  factory Money.fromMajor(num value, [String currency = 'TWD']) =>
      Money((value * 100).round(), currency);

  num get major => minorUnits / 100;

  Money operator +(Money other) {
    _sameCurrency(other);
    return Money(minorUnits + other.minorUnits, currency);
  }

  Money operator -(Money other) {
    _sameCurrency(other);
    return Money(minorUnits - other.minorUnits, currency);
  }

  Money convert(FxRate rate) {
    if (rate.from != currency) {
      throw ArgumentError('匯率幣別不符');
    }
    return Money((minorUnits * rate.rateMicros / 1000000).round(), rate.to);
  }

  void _sameCurrency(Money other) {
    if (currency != other.currency) {
      throw ArgumentError('不可直接加總不同幣別');
    }
  }
}

class FxRate {
  const FxRate({
    required this.from,
    required this.to,
    required this.rateMicros,
    required this.updatedAt,
  });

  final CurrencyCode from;
  final CurrencyCode to;
  final int rateMicros;
  final DateTime updatedAt;

  double get rate => rateMicros / 1000000;

  Json toJson() => {
    'from': from,
    'to': to,
    'rateMicros': rateMicros,
    'updatedAt': updatedAt.toIso8601String(),
  };

  factory FxRate.fromJson(Json json) => FxRate(
    from: json['from'] as String,
    to: json['to'] as String,
    rateMicros: json['rateMicros'] as int,
    updatedAt: DateTime.parse(json['updatedAt'] as String),
  );
}

typedef ExchangeRatePoint = FxRate;

class Account {
  const Account({
    required this.id,
    required this.userId,
    required this.name,
    required this.institution,
    required this.type,
    required this.currency,
    required this.openingBalanceMinor,
    required this.isActive,
    required this.note,
    required this.createdAt,
    required this.updatedAt,
    this.openingBalanceDate,
    this.kind = FinancialAccountKind.asset,
    this.subtype = 'bank',
    this.origin = DataOrigin.user,
  });

  final String id;
  final String userId;
  final String name;
  final String institution;
  final String type;
  final CurrencyCode currency;
  final int openingBalanceMinor;
  final bool isActive;
  final String note;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? openingBalanceDate;
  final FinancialAccountKind kind;
  final String subtype;
  final DataOrigin origin;

  DateTime get effectiveOpeningBalanceDate => openingBalanceDate ?? createdAt;

  Account copyWith({
    String? name,
    String? institution,
    String? type,
    String? currency,
    int? openingBalanceMinor,
    bool? isActive,
    String? note,
    DateTime? updatedAt,
    DateTime? openingBalanceDate,
    FinancialAccountKind? kind,
    String? subtype,
  }) => Account(
    id: id,
    userId: userId,
    name: name ?? this.name,
    institution: institution ?? this.institution,
    type: type ?? this.type,
    currency: currency ?? this.currency,
    openingBalanceMinor: openingBalanceMinor ?? this.openingBalanceMinor,
    isActive: isActive ?? this.isActive,
    note: note ?? this.note,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    openingBalanceDate: openingBalanceDate ?? this.openingBalanceDate,
    kind: kind ?? this.kind,
    subtype: subtype ?? this.subtype,
    origin: origin,
  );

  Json toJson() => {
    'id': id,
    'userId': userId,
    'name': name,
    'institution': institution,
    'type': type,
    'currency': currency,
    'openingBalanceMinor': openingBalanceMinor,
    'isActive': isActive,
    'note': note,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'openingBalanceDate': openingBalanceDate?.toIso8601String(),
    'kind': kind.name,
    'subtype': subtype,
    'origin': origin.name,
  };

  factory Account.fromJson(Json json) => Account(
    id: json['id'] as String,
    userId: json['userId'] as String,
    name: json['name'] as String,
    institution: json['institution'] as String? ?? '',
    type: json['type'] as String,
    currency: json['currency'] as String? ?? 'TWD',
    openingBalanceMinor: json['openingBalanceMinor'] as int,
    isActive: json['isActive'] as bool? ?? true,
    note: json['note'] as String? ?? '',
    createdAt: DateTime.parse(json['createdAt'] as String),
    updatedAt: DateTime.parse(json['updatedAt'] as String),
    openingBalanceDate: json['openingBalanceDate'] == null
        ? null
        : DateTime.parse(json['openingBalanceDate'] as String),
    kind: FinancialAccountKind.values.byName(
      json['kind'] as String? ?? 'asset',
    ),
    subtype: json['subtype'] as String? ?? 'bank',
    origin: DataOrigin.values.byName(json['origin'] as String? ?? 'user'),
  );
}

class BalanceAdjustment {
  const BalanceAdjustment({
    required this.id,
    required this.userId,
    required this.accountId,
    required this.amountMinor,
    required this.date,
    required this.reason,
    this.origin = DataOrigin.user,
  });

  final String id;
  final String userId;
  final String accountId;
  final int amountMinor;
  final DateTime date;
  final String reason;
  final DataOrigin origin;

  Json toJson() => {
    'id': id,
    'userId': userId,
    'accountId': accountId,
    'amountMinor': amountMinor,
    'date': date.toIso8601String(),
    'reason': reason,
    'origin': origin.name,
  };

  factory BalanceAdjustment.fromJson(Json json) => BalanceAdjustment(
    id: json['id'] as String,
    userId: json['userId'] as String,
    accountId: json['accountId'] as String,
    amountMinor: json['amountMinor'] as int,
    date: DateTime.parse(json['date'] as String),
    reason: json['reason'] as String,
    origin: DataOrigin.values.byName(json['origin'] as String? ?? 'user'),
  );
}

class Expense {
  const Expense({
    required this.id,
    required this.userId,
    required this.date,
    required this.amountMinor,
    required this.paymentMethod,
    required this.item,
    required this.category,
    required this.merchant,
    required this.note,
    required this.isNecessary,
    this.accountId,
    this.cardId,
    this.billId,
    this.origin = DataOrigin.user,
  });

  final String id;
  final String userId;
  final DateTime date;
  final int amountMinor;
  final PaymentMethod paymentMethod;
  final String item;
  final String category;
  final String? accountId;
  final String? cardId;
  final String? billId;
  final String merchant;
  final String note;
  final bool isNecessary;
  final DataOrigin origin;

  bool get isCreditCard => paymentMethod == PaymentMethod.creditCard;

  Expense copyWith({
    DateTime? date,
    int? amountMinor,
    PaymentMethod? paymentMethod,
    String? item,
    String? category,
    String? accountId,
    String? cardId,
    String? billId,
    String? merchant,
    String? note,
    bool? isNecessary,
  }) => Expense(
    id: id,
    userId: userId,
    date: date ?? this.date,
    amountMinor: amountMinor ?? this.amountMinor,
    paymentMethod: paymentMethod ?? this.paymentMethod,
    item: item ?? this.item,
    category: category ?? this.category,
    accountId: accountId ?? this.accountId,
    cardId: cardId ?? this.cardId,
    billId: billId ?? this.billId,
    merchant: merchant ?? this.merchant,
    note: note ?? this.note,
    isNecessary: isNecessary ?? this.isNecessary,
    origin: origin,
  );

  Json toJson() => {
    'id': id,
    'userId': userId,
    'date': date.toIso8601String(),
    'amountMinor': amountMinor,
    'paymentMethod': paymentMethod.name,
    'item': item,
    'category': category,
    'accountId': accountId,
    'cardId': cardId,
    'billId': billId,
    'merchant': merchant,
    'note': note,
    'isNecessary': isNecessary,
    'origin': origin.name,
  };

  factory Expense.fromJson(Json json) => Expense(
    id: json['id'] as String,
    userId: json['userId'] as String,
    date: DateTime.parse(json['date'] as String),
    amountMinor: json['amountMinor'] as int,
    paymentMethod: PaymentMethod.values.byName(json['paymentMethod'] as String),
    item: json['item'] as String,
    category: json['category'] as String,
    accountId: json['accountId'] as String?,
    cardId: json['cardId'] as String?,
    billId: json['billId'] as String?,
    merchant: json['merchant'] as String? ?? '',
    note: json['note'] as String? ?? '',
    isNecessary: json['isNecessary'] as bool? ?? false,
    origin: DataOrigin.values.byName(json['origin'] as String? ?? 'user'),
  );
}

DateTime monthlyDueDate(int year, int month, int day) {
  final lastDay = DateTime(year, month + 1, 0).day;
  return DateTime(year, month, day.clamp(1, lastDay));
}

class RecurringExpense {
  const RecurringExpense({
    required this.id,
    required this.userId,
    required this.item,
    required this.category,
    required this.amountMinor,
    required this.paymentMethod,
    required this.dayOfMonth,
    required this.startMonth,
    required this.isActive,
    required this.isNecessary,
    required this.note,
    this.accountId,
    this.cardId,
    this.telecomDebitAccountId,
    this.origin = DataOrigin.user,
  });

  final String id;
  final String userId;
  final String item;
  final String category;
  final int amountMinor;
  final PaymentMethod paymentMethod;
  final int dayOfMonth;
  final String startMonth;
  final String? accountId;
  final String? cardId;
  final String? telecomDebitAccountId;
  final bool isActive;
  final bool isNecessary;
  final String note;
  final DataOrigin origin;

  bool get isTelecom => paymentMethod == PaymentMethod.telecomBill;

  RecurringExpense copyWith({
    String? item,
    String? category,
    int? amountMinor,
    PaymentMethod? paymentMethod,
    int? dayOfMonth,
    String? startMonth,
    String? accountId,
    String? cardId,
    String? telecomDebitAccountId,
    bool? isActive,
    bool? isNecessary,
    String? note,
  }) => RecurringExpense(
    id: id,
    userId: userId,
    item: item ?? this.item,
    category: category ?? this.category,
    amountMinor: amountMinor ?? this.amountMinor,
    paymentMethod: paymentMethod ?? this.paymentMethod,
    dayOfMonth: dayOfMonth ?? this.dayOfMonth,
    startMonth: startMonth ?? this.startMonth,
    accountId: accountId ?? this.accountId,
    cardId: cardId ?? this.cardId,
    telecomDebitAccountId: telecomDebitAccountId ?? this.telecomDebitAccountId,
    isActive: isActive ?? this.isActive,
    isNecessary: isNecessary ?? this.isNecessary,
    note: note ?? this.note,
    origin: origin,
  );

  Json toJson() => {
    'id': id,
    'userId': userId,
    'item': item,
    'category': category,
    'amountMinor': amountMinor,
    'paymentMethod': paymentMethod.name,
    'dayOfMonth': dayOfMonth,
    'startMonth': startMonth,
    'accountId': accountId,
    'cardId': cardId,
    'telecomDebitAccountId': telecomDebitAccountId,
    'isActive': isActive,
    'isNecessary': isNecessary,
    'note': note,
    'origin': origin.name,
  };

  factory RecurringExpense.fromJson(Json json) => RecurringExpense(
    id: json['id'] as String,
    userId: json['userId'] as String,
    item: json['item'] as String,
    category: json['category'] as String? ?? '其他',
    amountMinor: json['amountMinor'] as int,
    paymentMethod: PaymentMethod.values.byName(json['paymentMethod'] as String),
    dayOfMonth: json['dayOfMonth'] as int,
    startMonth: json['startMonth'] as String,
    accountId: json['accountId'] as String?,
    cardId: json['cardId'] as String?,
    telecomDebitAccountId: json['telecomDebitAccountId'] as String?,
    isActive: json['isActive'] as bool? ?? true,
    isNecessary: json['isNecessary'] as bool? ?? false,
    note: json['note'] as String? ?? '',
    origin: DataOrigin.values.byName(json['origin'] as String? ?? 'user'),
  );
}

class RecurringExpenseOccurrence {
  const RecurringExpenseOccurrence({
    required this.id,
    required this.userId,
    required this.recurringExpenseId,
    required this.month,
    required this.expenseId,
    required this.scheduledDate,
  });

  final String id;
  final String userId;
  final String recurringExpenseId;
  final String month;
  final String expenseId;
  final DateTime scheduledDate;

  Json toJson() => {
    'id': id,
    'userId': userId,
    'recurringExpenseId': recurringExpenseId,
    'month': month,
    'expenseId': expenseId,
    'scheduledDate': scheduledDate.toIso8601String(),
  };

  factory RecurringExpenseOccurrence.fromJson(Json json) =>
      RecurringExpenseOccurrence(
        id: json['id'] as String,
        userId: json['userId'] as String,
        recurringExpenseId: json['recurringExpenseId'] as String,
        month: json['month'] as String,
        expenseId: json['expenseId'] as String,
        scheduledDate: DateTime.parse(json['scheduledDate'] as String),
      );
}

class TelecomBillPayment {
  const TelecomBillPayment({
    required this.id,
    required this.userId,
    required this.recurringExpenseId,
    required this.month,
    required this.expenseIds,
    required this.amountMinor,
    required this.paidAt,
    required this.debitAccountId,
    required this.balanceInsufficient,
  });

  final String id;
  final String userId;
  final String recurringExpenseId;
  final String month;
  final List<String> expenseIds;
  final int amountMinor;
  final DateTime paidAt;
  final String debitAccountId;
  final bool balanceInsufficient;

  Json toJson() => {
    'id': id,
    'userId': userId,
    'recurringExpenseId': recurringExpenseId,
    'month': month,
    'expenseIds': expenseIds,
    'amountMinor': amountMinor,
    'paidAt': paidAt.toIso8601String(),
    'debitAccountId': debitAccountId,
    'balanceInsufficient': balanceInsufficient,
  };

  factory TelecomBillPayment.fromJson(Json json) => TelecomBillPayment(
    id: json['id'] as String,
    userId: json['userId'] as String,
    recurringExpenseId: json['recurringExpenseId'] as String,
    month: json['month'] as String,
    expenseIds: (json['expenseIds'] as List? ?? const []).cast<String>(),
    amountMinor: json['amountMinor'] as int,
    paidAt: DateTime.parse(json['paidAt'] as String),
    debitAccountId: json['debitAccountId'] as String,
    balanceInsufficient: json['balanceInsufficient'] as bool? ?? false,
  );
}

class IncomeEntry {
  const IncomeEntry({
    required this.id,
    required this.userId,
    required this.date,
    required this.amountMinor,
    required this.item,
    required this.category,
    required this.accountId,
    required this.note,
    this.origin = DataOrigin.user,
  });

  final String id;
  final String userId;
  final DateTime date;
  final int amountMinor;
  final String item;
  final String category;
  final String accountId;
  final String note;
  final DataOrigin origin;

  IncomeEntry copyWith({
    DateTime? date,
    int? amountMinor,
    String? item,
    String? category,
    String? accountId,
    String? note,
  }) => IncomeEntry(
    id: id,
    userId: userId,
    date: date ?? this.date,
    amountMinor: amountMinor ?? this.amountMinor,
    item: item ?? this.item,
    category: category ?? this.category,
    accountId: accountId ?? this.accountId,
    note: note ?? this.note,
    origin: origin,
  );

  Json toJson() => {
    'id': id,
    'userId': userId,
    'date': date.toIso8601String(),
    'amountMinor': amountMinor,
    'item': item,
    'category': category,
    'accountId': accountId,
    'note': note,
    'origin': origin.name,
  };

  factory IncomeEntry.fromJson(Json json) => IncomeEntry(
    id: json['id'] as String,
    userId: json['userId'] as String,
    date: DateTime.parse(json['date'] as String),
    amountMinor: json['amountMinor'] as int,
    item: json['item'] as String,
    category: json['category'] as String? ?? '其他收入',
    accountId: json['accountId'] as String,
    note: json['note'] as String? ?? '',
    origin: DataOrigin.values.byName(json['origin'] as String? ?? 'user'),
  );
}

class CreditCard {
  const CreditCard({
    required this.id,
    required this.userId,
    required this.name,
    required this.bank,
    required this.lastFour,
    required this.closingDay,
    required this.dueDay,
    required this.autoDebitDay,
    required this.debitAccountId,
    required this.isActive,
    required this.note,
    this.liabilityAccountId,
    this.origin = DataOrigin.user,
  });

  final String id;
  final String userId;
  final String name;
  final String bank;
  final String lastFour;
  final int closingDay;
  final int dueDay;
  final int autoDebitDay;
  final String debitAccountId;
  final bool isActive;
  final String note;
  final String? liabilityAccountId;
  final DataOrigin origin;

  Json toJson() => {
    'id': id,
    'userId': userId,
    'name': name,
    'bank': bank,
    'lastFour': lastFour,
    'closingDay': closingDay,
    'dueDay': dueDay,
    'autoDebitDay': autoDebitDay,
    'debitAccountId': debitAccountId,
    'isActive': isActive,
    'note': note,
    'liabilityAccountId': liabilityAccountId,
    'origin': origin.name,
  };

  factory CreditCard.fromJson(Json json) => CreditCard(
    id: json['id'] as String,
    userId: json['userId'] as String,
    name: json['name'] as String,
    bank: json['bank'] as String,
    lastFour: json['lastFour'] as String,
    closingDay: json['closingDay'] as int,
    dueDay: json['dueDay'] as int,
    autoDebitDay: json['autoDebitDay'] as int,
    debitAccountId: json['debitAccountId'] as String,
    isActive: json['isActive'] as bool? ?? true,
    note: json['note'] as String? ?? '',
    liabilityAccountId: json['liabilityAccountId'] as String?,
    origin: DataOrigin.values.byName(json['origin'] as String? ?? 'user'),
  );
}

class CardBill {
  const CardBill({
    required this.id,
    required this.userId,
    required this.cardId,
    required this.month,
    required this.chargeIds,
    required this.manualAdjustmentMinor,
    required this.paidMinor,
    required this.dueDate,
    required this.autoDebitDate,
    required this.note,
    this.paidAt,
    this.origin = DataOrigin.user,
  });

  final String id;
  final String userId;
  final String cardId;
  final String month;
  final List<String> chargeIds;
  final int manualAdjustmentMinor;
  final int paidMinor;
  final DateTime dueDate;
  final DateTime autoDebitDate;
  final String note;
  final DateTime? paidAt;
  final DataOrigin origin;

  Json toJson() => {
    'id': id,
    'userId': userId,
    'cardId': cardId,
    'month': month,
    'chargeIds': chargeIds,
    'manualAdjustmentMinor': manualAdjustmentMinor,
    'paidMinor': paidMinor,
    'dueDate': dueDate.toIso8601String(),
    'autoDebitDate': autoDebitDate.toIso8601String(),
    'note': note,
    'paidAt': paidAt?.toIso8601String(),
    'origin': origin.name,
  };

  factory CardBill.fromJson(Json json) => CardBill(
    id: json['id'] as String,
    userId: json['userId'] as String,
    cardId: json['cardId'] as String,
    month: json['month'] as String,
    chargeIds: List<String>.from(json['chargeIds'] as List? ?? const []),
    manualAdjustmentMinor: json['manualAdjustmentMinor'] as int? ?? 0,
    paidMinor: json['paidMinor'] as int? ?? 0,
    dueDate: DateTime.parse(json['dueDate'] as String),
    autoDebitDate: DateTime.parse(json['autoDebitDate'] as String),
    note: json['note'] as String? ?? '',
    paidAt: json['paidAt'] == null
        ? null
        : DateTime.parse(json['paidAt'] as String),
    origin: DataOrigin.values.byName(json['origin'] as String? ?? 'user'),
  );
}

class InvestmentProduct {
  const InvestmentProduct({
    required this.id,
    required this.userId,
    required this.symbol,
    required this.name,
    required this.type,
    required this.currency,
    required this.currentPriceMinor,
    required this.priceUpdatedAt,
    required this.note,
    this.origin = DataOrigin.user,
  });

  final String id;
  final String userId;
  final String symbol;
  final String name;
  final String type;
  final CurrencyCode currency;
  final int currentPriceMinor;
  final DateTime priceUpdatedAt;
  final String note;
  final DataOrigin origin;

  Json toJson() => {
    'id': id,
    'userId': userId,
    'symbol': symbol,
    'name': name,
    'type': type,
    'currency': currency,
    'currentPriceMinor': currentPriceMinor,
    'priceUpdatedAt': priceUpdatedAt.toIso8601String(),
    'note': note,
    'origin': origin.name,
  };

  factory InvestmentProduct.fromJson(Json json) => InvestmentProduct(
    id: json['id'] as String,
    userId: json['userId'] as String,
    symbol: json['symbol'] as String,
    name: json['name'] as String,
    type: json['type'] as String,
    currency: json['currency'] as String,
    currentPriceMinor: json['currentPriceMinor'] as int,
    priceUpdatedAt: DateTime.parse(json['priceUpdatedAt'] as String),
    note: json['note'] as String? ?? '',
    origin: DataOrigin.values.byName(json['origin'] as String? ?? 'user'),
  );
}

class InvestmentPricePoint {
  const InvestmentPricePoint({
    required this.productId,
    required this.priceMinor,
    required this.date,
    this.estimated = false,
  });

  final String productId;
  final int priceMinor;
  final DateTime date;
  final bool estimated;

  Json toJson() => {
    'productId': productId,
    'priceMinor': priceMinor,
    'date': date.toIso8601String(),
    'estimated': estimated,
  };

  factory InvestmentPricePoint.fromJson(Json json) => InvestmentPricePoint(
    productId: json['productId'] as String,
    priceMinor: json['priceMinor'] as int,
    date: DateTime.parse(json['date'] as String),
    estimated: json['estimated'] as bool? ?? false,
  );
}

class InvestmentTransaction {
  const InvestmentTransaction({
    required this.id,
    required this.userId,
    required this.date,
    required this.type,
    required this.productId,
    required this.quantityMicros,
    required this.priceMinor,
    required this.feeMinor,
    required this.taxMinor,
    this.debitAccountId,
    this.creditAccountId,
    required this.note,
    this.origin = DataOrigin.user,
  });

  final String id;
  final String userId;
  final DateTime date;
  final InvestmentTransactionType type;
  final String productId;
  final int quantityMicros;
  final int priceMinor;
  final int feeMinor;
  final int taxMinor;
  final String? debitAccountId;
  final String? creditAccountId;
  final String note;
  final DataOrigin origin;

  double get quantity => quantityMicros / 1000000;
  int get grossMinor => (quantityMicros * priceMinor / 1000000).round();

  Json toJson() => {
    'id': id,
    'userId': userId,
    'date': date.toIso8601String(),
    'type': type.name,
    'productId': productId,
    'quantityMicros': quantityMicros,
    'priceMinor': priceMinor,
    'feeMinor': feeMinor,
    'taxMinor': taxMinor,
    'debitAccountId': debitAccountId,
    'creditAccountId': creditAccountId,
    'note': note,
    'origin': origin.name,
  };

  factory InvestmentTransaction.fromJson(Json json) => InvestmentTransaction(
    id: json['id'] as String,
    userId: json['userId'] as String,
    date: DateTime.parse(json['date'] as String),
    type: InvestmentTransactionType.values.byName(json['type'] as String),
    productId: json['productId'] as String,
    quantityMicros: json['quantityMicros'] as int,
    priceMinor: json['priceMinor'] as int,
    feeMinor: json['feeMinor'] as int? ?? 0,
    taxMinor: json['taxMinor'] as int? ?? 0,
    debitAccountId: json['debitAccountId'] as String?,
    creditAccountId: json['creditAccountId'] as String?,
    note: json['note'] as String? ?? '',
    origin: DataOrigin.values.byName(json['origin'] as String? ?? 'user'),
  );
}

class InvestmentAdjustment {
  const InvestmentAdjustment({
    required this.id,
    required this.userId,
    required this.productId,
    required this.date,
    required this.quantityMicros,
    required this.averageCostMinor,
    required this.reason,
    this.origin = DataOrigin.user,
  });

  final String id;
  final String userId;
  final String productId;
  final DateTime date;
  final int quantityMicros;
  final int averageCostMinor;
  final String reason;
  final DataOrigin origin;

  Json toJson() => {
    'id': id,
    'userId': userId,
    'productId': productId,
    'date': date.toIso8601String(),
    'quantityMicros': quantityMicros,
    'averageCostMinor': averageCostMinor,
    'reason': reason,
    'origin': origin.name,
  };

  factory InvestmentAdjustment.fromJson(Json json) => InvestmentAdjustment(
    id: json['id'] as String,
    userId: json['userId'] as String,
    productId: json['productId'] as String,
    date: DateTime.parse(json['date'] as String),
    quantityMicros: json['quantityMicros'] as int,
    averageCostMinor: json['averageCostMinor'] as int,
    reason: json['reason'] as String,
    origin: DataOrigin.values.byName(json['origin'] as String? ?? 'user'),
  );
}

class Holding {
  const Holding({
    required this.productId,
    required this.quantityMicros,
    required this.averageCostMinor,
  });

  final String productId;
  final int quantityMicros;
  final int averageCostMinor;

  double get quantity => quantityMicros / 1000000;
}

class OrderParticipant {
  const OrderParticipant({
    required this.id,
    required this.name,
    required this.isSelf,
    required this.itemName,
    required this.itemAmountMinor,
    required this.sharedFeeMinor,
    required this.discountMinor,
    this.discountEligible = false,
    this.discountIsFixed = false,
    this.suggestedDueMinor,
    this.finalDueMinor,
    required this.status,
    required this.collectionMethod,
    required this.collectionAccountId,
    required this.token,
    this.collectedAt,
    this.cancelledAt,
    required this.note,
  });

  final String id;
  final String name;
  final bool isSelf;
  final String itemName;
  final int itemAmountMinor;
  final int sharedFeeMinor;
  final int discountMinor;
  final bool discountEligible;
  final bool discountIsFixed;
  final int? suggestedDueMinor;
  final int? finalDueMinor;
  final CollectionStatus status;
  final String collectionMethod;
  final String? collectionAccountId;
  final CollectionToken token;
  final DateTime? collectedAt;
  final DateTime? cancelledAt;
  final String note;

  int get calculatedDueMinor {
    final value = itemAmountMinor + sharedFeeMinor - discountMinor;
    return value < 0 ? 0 : value;
  }

  int get dueMinor => finalDueMinor ?? suggestedDueMinor ?? calculatedDueMinor;
  int get adjustmentMinor => dueMinor - calculatedDueMinor;
  int get collectionResultMinor => adjustmentMinor;

  OrderParticipant copyWith({
    int? sharedFeeMinor,
    int? discountMinor,
    bool? discountEligible,
    bool? discountIsFixed,
    int? suggestedDueMinor,
    int? finalDueMinor,
    CollectionStatus? status,
    String? collectionMethod,
    String? collectionAccountId,
    DateTime? collectedAt,
    DateTime? cancelledAt,
    bool clearCollectedAt = false,
    bool clearCancelledAt = false,
  }) => OrderParticipant(
    id: id,
    name: name,
    isSelf: isSelf,
    itemName: itemName,
    itemAmountMinor: itemAmountMinor,
    sharedFeeMinor: sharedFeeMinor ?? this.sharedFeeMinor,
    discountMinor: discountMinor ?? this.discountMinor,
    discountEligible: discountEligible ?? this.discountEligible,
    discountIsFixed: discountIsFixed ?? this.discountIsFixed,
    suggestedDueMinor: suggestedDueMinor ?? this.suggestedDueMinor,
    finalDueMinor: finalDueMinor ?? this.finalDueMinor,
    status: status ?? this.status,
    collectionMethod: collectionMethod ?? this.collectionMethod,
    collectionAccountId: collectionAccountId ?? this.collectionAccountId,
    token: token,
    collectedAt: clearCollectedAt ? null : (collectedAt ?? this.collectedAt),
    cancelledAt: clearCancelledAt ? null : (cancelledAt ?? this.cancelledAt),
    note: note,
  );

  Json toJson() => {
    'id': id,
    'name': name,
    'isSelf': isSelf,
    'itemName': itemName,
    'itemAmountMinor': itemAmountMinor,
    'sharedFeeMinor': sharedFeeMinor,
    'discountMinor': discountMinor,
    'discountEligible': discountEligible,
    'discountIsFixed': discountIsFixed,
    'suggestedDueMinor': suggestedDueMinor,
    'finalDueMinor': finalDueMinor,
    'status': status.name,
    'collectionMethod': collectionMethod,
    'collectionAccountId': collectionAccountId,
    'token': token,
    'collectedAt': collectedAt?.toIso8601String(),
    'cancelledAt': cancelledAt?.toIso8601String(),
    'note': note,
  };

  factory OrderParticipant.fromJson(Json json) => OrderParticipant(
    id: json['id'] as String,
    name: json['name'] as String,
    isSelf: json['isSelf'] as bool? ?? false,
    itemName: json['itemName'] as String,
    itemAmountMinor: json['itemAmountMinor'] as int,
    sharedFeeMinor: json['sharedFeeMinor'] as int? ?? 0,
    discountMinor: json['discountMinor'] as int? ?? 0,
    discountEligible:
        json['discountEligible'] as bool? ??
        (json['discountMinor'] as int? ?? 0) > 0,
    discountIsFixed:
        json['discountIsFixed'] as bool? ??
        (json['discountMinor'] as int? ?? 0) > 0,
    suggestedDueMinor: json['suggestedDueMinor'] as int?,
    finalDueMinor: json['finalDueMinor'] as int?,
    status: CollectionStatus.values.byName(json['status'] as String),
    collectionMethod: json['collectionMethod'] as String? ?? 'LINE Pay',
    collectionAccountId: json['collectionAccountId'] as String?,
    token: json['token'] as String,
    collectedAt: json['collectedAt'] == null
        ? null
        : DateTime.parse(json['collectedAt'] as String),
    cancelledAt: json['cancelledAt'] == null
        ? null
        : DateTime.parse(json['cancelledAt'] as String),
    note: json['note'] as String? ?? '',
  );
}

class GroupOrder {
  const GroupOrder({
    required this.id,
    required this.userId,
    required this.name,
    required this.date,
    required this.platform,
    required this.cardId,
    required this.totalMinor,
    required this.deliveryFeeMinor,
    required this.serviceFeeMinor,
    required this.discountMinor,
    this.includeSelfInDeliveryFee = false,
    this.includeSelfInServiceFee = false,
    this.feeRoundingPolicy = FeeRoundingPolicy.exactRemainder,
    this.importSource,
    this.importWarnings = const [],
    this.reconciliationDifferenceMinor = 0,
    this.paymentLastFour,
    required this.splitMethod,
    required this.note,
    required this.participants,
    this.billId,
    this.origin = DataOrigin.user,
  });

  final String id;
  final String userId;
  final String name;
  final DateTime date;
  final String platform;
  final String cardId;
  final int totalMinor;
  final int deliveryFeeMinor;
  final int serviceFeeMinor;
  final int discountMinor;
  final bool includeSelfInDeliveryFee;
  final bool includeSelfInServiceFee;
  final FeeRoundingPolicy feeRoundingPolicy;
  final String? importSource;
  final List<String> importWarnings;
  final int reconciliationDifferenceMinor;
  final String? paymentLastFour;
  final SplitMethod splitMethod;
  final String note;
  final List<OrderParticipant> participants;
  final String? billId;
  final DataOrigin origin;

  int get selfExpenseMinor => participants
      .where((participant) => participant.isSelf)
      .fold(0, (sum, participant) => sum + participant.calculatedDueMinor);

  int get advanceCardMinor {
    final value = totalMinor - selfExpenseMinor;
    return value < 0 ? 0 : value;
  }

  int get expectedCollectionMinor => participants
      .where(
        (participant) =>
            !participant.isSelf &&
            participant.status != CollectionStatus.cancelled,
      )
      .fold(0, (sum, participant) => sum + participant.dueMinor);

  int get expectedCollectionResultMinor =>
      expectedCollectionMinor - advanceCardMinor;

  int get collectedMinor => participants
      .where(
        (participant) =>
            !participant.isSelf && participant.status == CollectionStatus.paid,
      )
      .fold(0, (sum, participant) => sum + participant.dueMinor);

  int get recognizedCollectionResultMinor => participants
      .where(
        (participant) =>
            !participant.isSelf && participant.status == CollectionStatus.paid,
      )
      .fold(0, (sum, participant) => sum + participant.collectionResultMinor);

  int get outstandingMinor => participants
      .where(
        (participant) =>
            !participant.isSelf &&
            participant.status != CollectionStatus.paid &&
            participant.status != CollectionStatus.cancelled,
      )
      .fold(0, (sum, participant) => sum + participant.dueMinor);

  GroupOrder copyWith({List<OrderParticipant>? participants}) => GroupOrder(
    id: id,
    userId: userId,
    name: name,
    date: date,
    platform: platform,
    cardId: cardId,
    totalMinor: totalMinor,
    deliveryFeeMinor: deliveryFeeMinor,
    serviceFeeMinor: serviceFeeMinor,
    discountMinor: discountMinor,
    includeSelfInDeliveryFee: includeSelfInDeliveryFee,
    includeSelfInServiceFee: includeSelfInServiceFee,
    feeRoundingPolicy: feeRoundingPolicy,
    importSource: importSource,
    importWarnings: importWarnings,
    reconciliationDifferenceMinor: reconciliationDifferenceMinor,
    paymentLastFour: paymentLastFour,
    splitMethod: splitMethod,
    note: note,
    participants: participants ?? this.participants,
    billId: billId,
    origin: origin,
  );

  Json toJson() => {
    'id': id,
    'userId': userId,
    'name': name,
    'date': date.toIso8601String(),
    'platform': platform,
    'cardId': cardId,
    'totalMinor': totalMinor,
    'deliveryFeeMinor': deliveryFeeMinor,
    'serviceFeeMinor': serviceFeeMinor,
    'discountMinor': discountMinor,
    'includeSelfInDeliveryFee': includeSelfInDeliveryFee,
    'includeSelfInServiceFee': includeSelfInServiceFee,
    'feeRoundingPolicy': feeRoundingPolicy.name,
    'importSource': importSource,
    'importWarnings': importWarnings,
    'reconciliationDifferenceMinor': reconciliationDifferenceMinor,
    'paymentLastFour': paymentLastFour,
    'splitMethod': splitMethod.name,
    'note': note,
    'participants': participants.map((item) => item.toJson()).toList(),
    'billId': billId,
    'origin': origin.name,
  };

  factory GroupOrder.fromJson(Json json) => GroupOrder(
    id: json['id'] as String,
    userId: json['userId'] as String,
    name: json['name'] as String,
    date: DateTime.parse(json['date'] as String),
    platform: json['platform'] as String,
    cardId: json['cardId'] as String,
    totalMinor: json['totalMinor'] as int,
    deliveryFeeMinor: json['deliveryFeeMinor'] as int? ?? 0,
    serviceFeeMinor: json['serviceFeeMinor'] as int? ?? 0,
    discountMinor: json['discountMinor'] as int? ?? 0,
    includeSelfInDeliveryFee: json['includeSelfInDeliveryFee'] as bool? ?? true,
    includeSelfInServiceFee: json['includeSelfInServiceFee'] as bool? ?? true,
    feeRoundingPolicy: FeeRoundingPolicy.values.byName(
      json['feeRoundingPolicy'] as String? ?? 'exactRemainder',
    ),
    importSource: json['importSource'] as String?,
    importWarnings: List<String>.from(
      json['importWarnings'] as List? ?? const [],
    ),
    reconciliationDifferenceMinor:
        json['reconciliationDifferenceMinor'] as int? ?? 0,
    paymentLastFour: json['paymentLastFour'] as String?,
    splitMethod: SplitMethod.values.byName(json['splitMethod'] as String),
    note: json['note'] as String? ?? '',
    participants: (json['participants'] as List)
        .map((item) => OrderParticipant.fromJson(item as Json))
        .toList(),
    billId: json['billId'] as String?,
    origin: DataOrigin.values.byName(json['origin'] as String? ?? 'user'),
  );
}

class UserSettings {
  const UserSettings({
    this.defaultCurrency = 'TWD',
    this.defaultPaymentMethod = PaymentMethod.creditCard,
    this.defaultCategory = '餐飲',
    this.defaultExpenseCategoryId = 'expense-food',
    this.defaultCollectionAccountId,
    this.linePayQrData = '',
    this.bankQrData = '',
    this.bankAccountInfo = '',
    this.remindersEnabled = true,
    this.lineRemindersEnabled = false,
    this.maskBalances = false,
    this.fxRates = const [],
  });

  final CurrencyCode defaultCurrency;
  final PaymentMethod defaultPaymentMethod;
  final String defaultCategory;
  final String defaultExpenseCategoryId;
  final String? defaultCollectionAccountId;
  final String linePayQrData;
  final String bankQrData;
  final String bankAccountInfo;
  final bool remindersEnabled;
  final bool lineRemindersEnabled;
  final bool maskBalances;
  final List<FxRate> fxRates;

  UserSettings copyWith({
    String? defaultCurrency,
    PaymentMethod? defaultPaymentMethod,
    String? defaultCategory,
    String? defaultExpenseCategoryId,
    String? defaultCollectionAccountId,
    String? linePayQrData,
    String? bankQrData,
    String? bankAccountInfo,
    bool? remindersEnabled,
    bool? lineRemindersEnabled,
    bool? maskBalances,
    List<FxRate>? fxRates,
  }) => UserSettings(
    defaultCurrency: defaultCurrency ?? this.defaultCurrency,
    defaultPaymentMethod: defaultPaymentMethod ?? this.defaultPaymentMethod,
    defaultCategory: defaultCategory ?? this.defaultCategory,
    defaultExpenseCategoryId:
        defaultExpenseCategoryId ?? this.defaultExpenseCategoryId,
    defaultCollectionAccountId:
        defaultCollectionAccountId ?? this.defaultCollectionAccountId,
    linePayQrData: linePayQrData ?? this.linePayQrData,
    bankQrData: bankQrData ?? this.bankQrData,
    bankAccountInfo: bankAccountInfo ?? this.bankAccountInfo,
    remindersEnabled: remindersEnabled ?? this.remindersEnabled,
    lineRemindersEnabled: lineRemindersEnabled ?? this.lineRemindersEnabled,
    maskBalances: maskBalances ?? this.maskBalances,
    fxRates: fxRates ?? this.fxRates,
  );

  Json toJson() => {
    'defaultCurrency': defaultCurrency,
    'defaultPaymentMethod': defaultPaymentMethod.name,
    'defaultCategory': defaultCategory,
    'defaultExpenseCategoryId': defaultExpenseCategoryId,
    'defaultCollectionAccountId': defaultCollectionAccountId,
    'linePayQrData': linePayQrData,
    'bankQrData': bankQrData,
    'bankAccountInfo': bankAccountInfo,
    'remindersEnabled': remindersEnabled,
    'lineRemindersEnabled': lineRemindersEnabled,
    'maskBalances': maskBalances,
    'fxRates': fxRates.map((rate) => rate.toJson()).toList(),
  };

  factory UserSettings.fromJson(Json json) => UserSettings(
    defaultCurrency: json['defaultCurrency'] as String? ?? 'TWD',
    defaultPaymentMethod: PaymentMethod.values.byName(
      json['defaultPaymentMethod'] as String? ?? 'creditCard',
    ),
    defaultCategory: json['defaultCategory'] as String? ?? '餐飲',
    defaultExpenseCategoryId:
        json['defaultExpenseCategoryId'] as String? ?? 'expense-food',
    defaultCollectionAccountId: json['defaultCollectionAccountId'] as String?,
    linePayQrData: json['linePayQrData'] as String? ?? '',
    bankQrData: json['bankQrData'] as String? ?? '',
    bankAccountInfo: json['bankAccountInfo'] as String? ?? '',
    remindersEnabled: json['remindersEnabled'] as bool? ?? true,
    lineRemindersEnabled: json['lineRemindersEnabled'] as bool? ?? false,
    maskBalances: json['maskBalances'] as bool? ?? false,
    fxRates: (json['fxRates'] as List? ?? const [])
        .map((item) => FxRate.fromJson(item as Json))
        .toList(),
  );
}

class AppData {
  const AppData({
    this.schemaVersion = 7,
    this.settings = const UserSettings(),
    this.categories = const [],
    this.transactions = const [],
    this.accounts = const [],
    this.balanceAdjustments = const [],
    this.expenses = const [],
    this.recurringExpenses = const [],
    this.recurringExpenseOccurrences = const [],
    this.telecomBillPayments = const [],
    this.incomes = const [],
    this.cards = const [],
    this.bills = const [],
    this.products = const [],
    this.investmentTransactions = const [],
    this.investmentAdjustments = const [],
    this.investmentPriceHistory = const [],
    this.orders = const [],
  });

  final int schemaVersion;
  final UserSettings settings;
  final List<BookkeepingCategory> categories;
  final List<FinancialTransaction> transactions;
  final List<Account> accounts;
  final List<BalanceAdjustment> balanceAdjustments;
  final List<Expense> expenses;
  final List<RecurringExpense> recurringExpenses;
  final List<RecurringExpenseOccurrence> recurringExpenseOccurrences;
  final List<TelecomBillPayment> telecomBillPayments;
  final List<IncomeEntry> incomes;
  final List<CreditCard> cards;
  final List<CardBill> bills;
  final List<InvestmentProduct> products;
  final List<InvestmentTransaction> investmentTransactions;
  final List<InvestmentAdjustment> investmentAdjustments;
  final List<InvestmentPricePoint> investmentPriceHistory;
  final List<GroupOrder> orders;

  AppData copyWith({
    UserSettings? settings,
    List<BookkeepingCategory>? categories,
    List<FinancialTransaction>? transactions,
    List<Account>? accounts,
    List<BalanceAdjustment>? balanceAdjustments,
    List<Expense>? expenses,
    List<RecurringExpense>? recurringExpenses,
    List<RecurringExpenseOccurrence>? recurringExpenseOccurrences,
    List<TelecomBillPayment>? telecomBillPayments,
    List<IncomeEntry>? incomes,
    List<CreditCard>? cards,
    List<CardBill>? bills,
    List<InvestmentProduct>? products,
    List<InvestmentTransaction>? investmentTransactions,
    List<InvestmentAdjustment>? investmentAdjustments,
    List<InvestmentPricePoint>? investmentPriceHistory,
    List<GroupOrder>? orders,
  }) => AppData(
    schemaVersion: schemaVersion,
    settings: settings ?? this.settings,
    categories: categories ?? this.categories,
    transactions: transactions ?? this.transactions,
    accounts: accounts ?? this.accounts,
    balanceAdjustments: balanceAdjustments ?? this.balanceAdjustments,
    expenses: expenses ?? this.expenses,
    recurringExpenses: recurringExpenses ?? this.recurringExpenses,
    recurringExpenseOccurrences:
        recurringExpenseOccurrences ?? this.recurringExpenseOccurrences,
    telecomBillPayments: telecomBillPayments ?? this.telecomBillPayments,
    incomes: incomes ?? this.incomes,
    cards: cards ?? this.cards,
    bills: bills ?? this.bills,
    products: products ?? this.products,
    investmentTransactions:
        investmentTransactions ?? this.investmentTransactions,
    investmentAdjustments: investmentAdjustments ?? this.investmentAdjustments,
    investmentPriceHistory:
        investmentPriceHistory ?? this.investmentPriceHistory,
    orders: orders ?? this.orders,
  );

  Json toJson() => {
    'schemaVersion': schemaVersion,
    'settings': settings.toJson(),
    'categories': categories.map((item) => item.toJson()).toList(),
    'transactions': transactions.map((item) => item.toJson()).toList(),
    'accounts': accounts.map((item) => item.toJson()).toList(),
    'balanceAdjustments': balanceAdjustments
        .map((item) => item.toJson())
        .toList(),
    'expenses': expenses.map((item) => item.toJson()).toList(),
    'recurringExpenses': recurringExpenses
        .map((item) => item.toJson())
        .toList(),
    'recurringExpenseOccurrences': recurringExpenseOccurrences
        .map((item) => item.toJson())
        .toList(),
    'telecomBillPayments': telecomBillPayments
        .map((item) => item.toJson())
        .toList(),
    'incomes': incomes.map((item) => item.toJson()).toList(),
    'cards': cards.map((item) => item.toJson()).toList(),
    'bills': bills.map((item) => item.toJson()).toList(),
    'products': products.map((item) => item.toJson()).toList(),
    'investmentTransactions': investmentTransactions
        .map((item) => item.toJson())
        .toList(),
    'investmentAdjustments': investmentAdjustments
        .map((item) => item.toJson())
        .toList(),
    'investmentPriceHistory': investmentPriceHistory
        .map((item) => item.toJson())
        .toList(),
    'orders': orders.map((item) => item.toJson()).toList(),
  };

  factory AppData.fromJson(Json json) => AppData(
    schemaVersion: json['schemaVersion'] as int? ?? 1,
    settings: UserSettings.fromJson(json['settings'] as Json? ?? {}),
    categories: _decode(json, 'categories', BookkeepingCategory.fromJson),
    transactions: _decode(json, 'transactions', FinancialTransaction.fromJson),
    accounts: _decode(json, 'accounts', Account.fromJson),
    balanceAdjustments: _decode(
      json,
      'balanceAdjustments',
      BalanceAdjustment.fromJson,
    ),
    expenses: _decode(json, 'expenses', Expense.fromJson),
    recurringExpenses: _decode(
      json,
      'recurringExpenses',
      RecurringExpense.fromJson,
    ),
    recurringExpenseOccurrences: _decode(
      json,
      'recurringExpenseOccurrences',
      RecurringExpenseOccurrence.fromJson,
    ),
    telecomBillPayments: _decode(
      json,
      'telecomBillPayments',
      TelecomBillPayment.fromJson,
    ),
    incomes: _decode(json, 'incomes', IncomeEntry.fromJson),
    cards: _decode(json, 'cards', CreditCard.fromJson),
    bills: _decode(json, 'bills', CardBill.fromJson),
    products: _decode(json, 'products', InvestmentProduct.fromJson),
    investmentTransactions: _decode(
      json,
      'investmentTransactions',
      InvestmentTransaction.fromJson,
    ),
    investmentAdjustments: _decode(
      json,
      'investmentAdjustments',
      InvestmentAdjustment.fromJson,
    ),
    investmentPriceHistory: _decode(
      json,
      'investmentPriceHistory',
      InvestmentPricePoint.fromJson,
    ),
    orders: _decode(json, 'orders', GroupOrder.fromJson),
  );

  static List<T> _decode<T>(Json json, String key, T Function(Json) factory) =>
      (json[key] as List? ?? const [])
          .map((item) => factory(item as Json))
          .toList();
}

class LedgerEffect {
  const LedgerEffect({
    required this.sourceType,
    required this.sourceId,
    required this.accountId,
    required this.amountMinor,
    required this.label,
    required this.date,
    this.parentSourceId,
  });

  final String sourceType;
  final String sourceId;
  final String accountId;
  final int amountMinor;
  final String label;
  final DateTime date;
  final String? parentSourceId;
}

enum ReminderDestination { cards, expenses }

class ReminderItem {
  const ReminderItem({
    required this.title,
    required this.subtitle,
    required this.date,
    required this.isWarning,
    required this.destination,
  });

  final String title;
  final String subtitle;
  final DateTime date;
  final bool isWarning;
  final ReminderDestination destination;
}
