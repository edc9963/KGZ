import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quick_ledger/presentation/theme.dart';
import 'package:quick_ledger/presentation/widgets/common.dart';

Widget _host(
  TextEditingController controller, {
  ValueChanged<String>? onChanged,
}) => MaterialApp(
  theme: buildAppTheme(Brightness.light),
  home: Scaffold(
    body: MoneyField(controller: controller, onChanged: onChanged),
  ),
);

void main() {
  testWidgets('desktop MoneyField accepts typed digits and filters letters', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    final controller = TextEditingController();
    String? changed;
    await tester.pumpWidget(_host(controller, onChanged: (v) => changed = v));

    await tester.enterText(find.byType(TextField), '-12a3.5');
    await tester.pump();

    expect(controller.text, '-123.5');
    expect(changed, '-123.5');
    expect(find.text('小算盤'), findsNothing);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('desktop calculator opens from the suffix icon', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    final controller = TextEditingController();
    await tester.pumpWidget(_host(controller));

    await tester.tap(find.byIcon(Icons.calculate_outlined));
    await tester.pumpAndSettle();
    expect(find.text('小算盤'), findsOneWidget);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('calculator accepts numeric keypad input and Enter', (
    tester,
  ) async {
    final controller = TextEditingController();
    await tester.pumpWidget(_host(controller));
    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();

    for (final key in [
      LogicalKeyboardKey.numpad1,
      LogicalKeyboardKey.numpad2,
      LogicalKeyboardKey.numpadAdd,
      LogicalKeyboardKey.numpad3,
      LogicalKeyboardKey.numpadMultiply,
      LogicalKeyboardKey.numpad2,
      LogicalKeyboardKey.numpadEnter,
    ]) {
      await tester.sendKeyEvent(key);
      await tester.pump();
    }
    await tester.pumpAndSettle();

    // (12 + 3) × 2, evaluated left to right like the on-screen keys.
    expect(controller.text, '30');
    expect(find.text('小算盤'), findsNothing);
  });

  testWidgets('calculator accepts main-row digits and Backspace', (
    tester,
  ) async {
    final controller = TextEditingController();
    await tester.pumpWidget(_host(controller));
    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.digit4);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit5);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit6);
    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(controller.text, '45');
  });
}
