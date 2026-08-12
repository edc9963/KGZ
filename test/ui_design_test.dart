import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quick_ledger/presentation/design_tokens.dart';
import 'package:quick_ledger/presentation/widgets/common.dart';

void main() {
  test('known categories use the approved semantic palette', () {
    expect(categoryVisual('餐飲').color, const Color(0xFFE4765B));
    expect(categoryVisual('交通').color, const Color(0xFF568EAE));
    expect(categoryVisual('購物').color, const Color(0xFF9277A6));
    expect(categoryVisual('薪資').color, AppColors.income);
    expect(categoryVisual('投資收益').color, const Color(0xFF6075A6));
  });

  test('unknown category fallback is deterministic', () {
    final first = categoryVisual('寵物用品');
    final second = categoryVisual('寵物用品');
    expect(second.color, first.color);
    expect(second.pale, first.pale);
  });

  testWidgets('category avatar and badge share the category color', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Row(
          children: [
            CategoryAvatar(category: '餐飲'),
            CategoryBadge(category: '餐飲'),
          ],
        ),
      ),
    );

    final avatar = tester.widget<CircleAvatar>(find.byType(CircleAvatar));
    expect(avatar.backgroundColor, categoryVisual('餐飲').pale);
    expect(find.text('餐飲'), findsOneWidget);
  });

  testWidgets('actionable summary card exposes semantics and handles taps', (
    tester,
  ) async {
    var taps = 0;
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 240,
            child: SummaryCard(
              label: '淨資產',
              value: r'$1,000',
              icon: Icons.account_balance_wallet_outlined,
              onTap: () => taps += 1,
            ),
          ),
        ),
      ),
    );

    expect(find.bySemanticsLabel(RegExp('查看淨資產')), findsOneWidget);
    await tester.tap(find.text('淨資產'));
    expect(taps, 1);
    semantics.dispose();
  });
}
