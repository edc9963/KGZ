import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';

import '../presentation/design_tokens.dart';

/// Shared, library-agnostic data for the UI library comparison lab, so the
/// shadcn_ui and forui screens render exactly the same content.
class DemoCategory {
  DemoCategory({
    required this.name,
    required this.iconKey,
    required this.colorKey,
    required this.spent,
    required this.budget,
    this.isActive = true,
    this.isBuiltIn = false,
  });

  final String name;
  final String iconKey;
  final String colorKey;
  final int spent;
  final int budget;
  bool isActive;
  final bool isBuiltIn;

  IconData get icon => categoryIconOptions[iconKey] ?? categoryIconOptions['other']!;
  Color get color => categoryColorOptions[colorKey] ?? const Color(0xFF748A96);
  double get ratio => budget == 0 ? 0 : (spent / budget).clamp(0, 1).toDouble();
  bool get isOverBudget => spent > budget;
}

List<DemoCategory> buildDemoCategories() => [
  DemoCategory(name: '餐飲', iconKey: 'restaurant', colorKey: 'coral', spent: 8420, budget: 9000, isBuiltIn: true),
  DemoCategory(name: '交通', iconKey: 'transport', colorKey: 'blue', spent: 1860, budget: 2000, isBuiltIn: true),
  DemoCategory(name: '購物', iconKey: 'shopping', colorKey: 'purple', spent: 5230, budget: 4000),
  DemoCategory(name: '居住', iconKey: 'home', colorKey: 'teal', spent: 18000, budget: 18000, isBuiltIn: true),
  DemoCategory(name: '娛樂', iconKey: 'movie', colorKey: 'amber', spent: 2640, budget: 2500),
  DemoCategory(name: '醫療', iconKey: 'medical', colorKey: 'rose', spent: 480, budget: 1500, isActive: false),
];

/// Color choices offered in the "新增分類" dialog: label → colorKey.
const demoColorChoices = <String, String>{
  '珊瑚紅': 'coral',
  '藍': 'blue',
  '青綠': 'teal',
  '紫': 'purple',
  '琥珀': 'amber',
  '橘': 'orange',
};

final _currency = NumberFormat.currency(locale: 'zh_TW', symbol: r'NT$', decimalDigits: 0);
String formatMoney(int value) => _currency.format(value);
