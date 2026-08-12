import 'package:flutter_test/flutter_test.dart';
import 'package:quick_ledger/data/supabase_finance_repository.dart';
import 'package:quick_ledger/domain/models.dart';

void main() {
  test('merge keeps cloud rows and appends local-only rows', () {
    final now = DateTime.utc(2026, 7, 30);
    final cloud = AppData(
      accounts: [
        _account('same', 'cloud', now),
        _account('cloud-only', 'cloud only', now),
      ],
      settings: UserSettings(
        defaultCategory: '雲端分類',
        fxRates: [
          FxRate(from: 'USD', to: 'TWD', rateMicros: 32000000, updatedAt: now),
        ],
      ),
      incomes: [_income('same-income', 'cloud income', now)],
      investmentPriceHistory: [
        InvestmentPricePoint(productId: 'fund', priceMinor: 100, date: now),
      ],
    );
    final local = AppData(
      accounts: [
        _account('same', 'local', now),
        _account('local-only', 'local only', now),
      ],
      settings: UserSettings(
        defaultCategory: '本機分類',
        fxRates: [
          FxRate(from: 'USD', to: 'TWD', rateMicros: 33000000, updatedAt: now),
          FxRate(from: 'JPY', to: 'TWD', rateMicros: 220000, updatedAt: now),
        ],
      ),
      incomes: [
        _income('same-income', 'local income', now),
        _income('local-income', 'local only income', now),
      ],
      investmentPriceHistory: [
        InvestmentPricePoint(productId: 'fund', priceMinor: 200, date: now),
        InvestmentPricePoint(
          productId: 'fund',
          priceMinor: 250,
          date: now.add(const Duration(days: 1)),
        ),
      ],
    );

    final merged = mergeFinanceData(cloud, local);

    expect(merged.accounts.map((item) => item.id), [
      'same',
      'cloud-only',
      'local-only',
    ]);
    expect(merged.accounts.first.name, 'cloud');
    expect(merged.settings.defaultCategory, '雲端分類');
    expect(merged.settings.fxRates, hasLength(2));
    expect(
      merged.settings.fxRates
          .firstWhere((item) => item.from == 'USD')
          .rateMicros,
      32000000,
    );
    expect(merged.incomes.map((item) => item.id), [
      'same-income',
      'local-income',
    ]);
    expect(merged.incomes.first.item, 'cloud income');
    expect(merged.investmentPriceHistory, hasLength(2));
  });

  test('rewriting ownership preserves ids including demo ids', () {
    final now = DateTime.utc(2026, 7, 30);
    final source = AppData(
      accounts: [_account('demo-bank', 'bank', now)],
      incomes: [_income('income', 'salary', now)],
    );

    final rewritten = rewriteFinanceUserIds(
      source,
      '8d078e02-c5ee-4c76-b975-27cd20bd61bd',
    );

    expect(rewritten.accounts.single.id, 'demo-bank');
    expect(
      rewritten.accounts.single.userId,
      '8d078e02-c5ee-4c76-b975-27cd20bd61bd',
    );
    expect(
      rewritten.incomes.single.userId,
      '8d078e02-c5ee-4c76-b975-27cd20bd61bd',
    );
  });
}

Account _account(String id, String name, DateTime now) => Account(
  id: id,
  userId: 'old-owner',
  name: name,
  institution: '',
  type: '銀行帳戶',
  currency: 'TWD',
  openingBalanceMinor: 0,
  isActive: true,
  note: '',
  createdAt: now,
  updatedAt: now,
);

IncomeEntry _income(String id, String item, DateTime now) => IncomeEntry(
  id: id,
  userId: 'old-owner',
  date: now,
  amountMinor: 100,
  item: item,
  category: '薪資',
  accountId: 'same',
  note: '',
);
