import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quick_ledger/ui_lab/forui_demo.dart';
import 'package:quick_ledger/ui_lab/shadcn_demo.dart';

Future<void> _addCategory(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(800, 1400));
  await tester.pumpAndSettle();
  expect(find.text('支出分類'), findsOneWidget);
  expect(find.text('醫療'), findsOneWidget);

  await tester.tap(find.text('新增分類').last);
  await tester.pumpAndSettle();
  expect(find.text('建立一個新的支出分類'), findsOneWidget);

  // Submitting empty shows the validation error.
  await tester.tap(find.text('建立'));
  await tester.pumpAndSettle();
  expect(find.text('請輸入名稱'), findsOneWidget);

  await tester.enterText(find.byType(EditableText).first, '寵物');
  await tester.tap(find.text('建立'));
  await tester.pumpAndSettle();
  expect(find.text('建立一個新的支出分類'), findsNothing);
  expect(find.text('寵物'), findsWidgets);
  await tester.binding.setSurfaceSize(null);
}

void main() {
  testWidgets('shadcn_ui demo adds a category', (tester) async {
    await tester.pumpWidget(
      ShadcnDemoApp(dark: false, onToggleTheme: () {}, onSwitchLibrary: () {}),
    );
    await _addCategory(tester);
  });

  testWidgets('forui demo adds a category', (tester) async {
    await tester.pumpWidget(
      ForuiDemoApp(dark: false, onToggleTheme: () {}, onSwitchLibrary: () {}),
    );
    await _addCategory(tester);
  });
}
