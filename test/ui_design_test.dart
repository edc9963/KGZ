import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quick_ledger/presentation/design_tokens.dart';
import 'package:quick_ledger/presentation/widgets/common.dart';

void main() {
  test('compact money keeps small values and abbreviates large values', () {
    expect(compactMoneyText(999900), r'NT$9,999');
    expect(compactMoneyText(1000000), r'NT$1萬');
    expect(compactMoneyText(1234000), r'NT$1.2萬');
    expect(compactMoneyText(99999900), r'NT$99.9萬');
    expect(compactMoneyText(34000000000), r'NT$3.4億');
    expect(compactMoneyText(-1234000, currency: 'USD'), r'-USD1.2萬');
    expect(compactMoneyText(34000000000, mask: true), 'TWD ••••••');
  });

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

  testWidgets(
    'compact summary card shows abbreviation but announces full value',
    (tester) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        const MaterialApp(
          home: Center(
            child: SizedBox(
              width: 120,
              child: SummaryCard(
                label: '本人信用卡消費',
                value: r'NT$123,456',
                compactValue: r'NT$12.3萬',
                icon: Icons.credit_card,
              ),
            ),
          ),
        ),
      );

      expect(find.text(r'NT$12.3萬'), findsOneWidget);
      expect(find.text(r'NT$123,456'), findsNothing);
      expect(
        find.bySemanticsLabel(RegExp(r'本人信用卡消費，NT\$123,456')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      semantics.dispose();
    },
  );

  testWidgets('compact card keeps the full amount while it fits', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Center(
          child: SizedBox(
            width: 173,
            child: SummaryCard(
              label: '本月支出',
              value: r'NT$50,000',
              compactValue: r'NT$5萬',
              icon: Icons.north_east_rounded,
            ),
          ),
        ),
      ),
    );

    expect(find.text(r'NT$50,000'), findsOneWidget);
    expect(find.text(r'NT$5萬'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final width in [288.0, 358.0, 398.0, 600.0, 1024.0]) {
    testWidgets('summary grid uses expected columns at ${width.toInt()}px', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: SizedBox(
              width: width,
              child: ResponsiveGrid(
                children: [
                  for (var i = 0; i < 4; i++)
                    SummaryCard(
                      key: ValueKey('summary-$i'),
                      label: '摘要 $i',
                      value: r'NT$123,456',
                      compactValue: r'NT$12.3萬',
                      icon: Icons.account_balance_wallet_outlined,
                    ),
                ],
              ),
            ),
          ),
        ),
      );

      final first = tester.getTopLeft(find.byKey(const ValueKey('summary-0')));
      final second = tester.getTopLeft(find.byKey(const ValueKey('summary-1')));
      final third = tester.getTopLeft(find.byKey(const ValueKey('summary-2')));
      expect(second.dy, first.dy);
      if (width == 1024) {
        expect(third.dy, first.dy);
        expect(
          tester.getTopLeft(find.byKey(const ValueKey('summary-3'))).dy,
          first.dy,
        );
      } else {
        expect(third.dy, greaterThan(first.dy));
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('compact summary card tolerates 1.3 text scaling', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(1.3)),
          child: Center(
            child: SizedBox(
              width: 138,
              child: SummaryCard(
                label: '本人信用卡消費金額',
                value: r'NT$123,456,789',
                compactValue: r'NT$1.2億',
                caption: '這是一段最多顯示兩行的必要提示文字',
                icon: Icons.credit_card,
              ),
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
  });
}
