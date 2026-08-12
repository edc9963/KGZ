import 'package:flutter/material.dart';

import '../domain/models.dart';

abstract final class AppColors {
  static const primary = Color(0xFF2387B8);
  static const primaryHover = Color(0xFF176A91);
  static const graphite = Color(0xFF26343A);
  static const background = Color(0xFFF4F6F7);
  static const surface = Colors.white;
  static const text = Color(0xFF1F2D33);
  static const textMuted = Color(0xFF68777D);
  static const border = Color(0xFFDCE3E6);

  static const asset = primary;
  static const assetPale = Color(0xFFE4F3FA);
  static const income = Color(0xFF2A9D8F);
  static const incomePale = Color(0xFFE5F5F1);
  static const expense = Color(0xFFD65A52);
  static const expensePale = Color(0xFFFBEAE8);
  static const liability = Color(0xFFB07A32);
  static const liabilityPale = Color(0xFFF7F0E5);
}

abstract final class AppBreakpoints {
  static const mobile = 600.0;
  static const desktop = 1024.0;
  static const contentMax = 1440.0;
}

abstract final class AppSpacing {
  static const mobilePage = 16.0;
  static const tabletPage = 24.0;
  static const desktopPage = 32.0;
  static const controlMinHeight = 48.0;
}

class CategoryVisual {
  const CategoryVisual(this.color, this.pale, this.icon);

  final Color color;
  final Color pale;
  final IconData icon;
}

const categoryColorOptions = <String, Color>{
  'blue': Color(0xFF568EAE),
  'teal': Color(0xFF2A9D8F),
  'coral': Color(0xFFE4765B),
  'green': Color(0xFF719681),
  'amber': Color(0xFFB8893E),
  'purple': Color(0xFF9277A6),
  'rose': Color(0xFFBC7182),
  'indigo': Color(0xFF6075A6),
  'cyan': Color(0xFF4B8E9F),
  'brown': Color(0xFFA36F5A),
  'slate': Color(0xFF748A96),
};

const categoryIconOptions = <String, IconData>{
  'restaurant': Icons.restaurant_outlined,
  'transport': Icons.directions_subway_outlined,
  'movie': Icons.movie_outlined,
  'repeat': Icons.event_repeat_outlined,
  'home': Icons.home_outlined,
  'homeWork': Icons.home_work_outlined,
  'bolt': Icons.bolt_outlined,
  'shield': Icons.health_and_safety_outlined,
  'medical': Icons.medical_services_outlined,
  'shopping': Icons.shopping_bag_outlined,
  'flight': Icons.flight_outlined,
  'trending': Icons.trending_up_outlined,
  'groups': Icons.groups_outlined,
  'work': Icons.work_outline,
  'award': Icons.emoji_events_outlined,
  'savings': Icons.savings_outlined,
  'laptop': Icons.laptop_outlined,
  'refund': Icons.replay_outlined,
  'other': Icons.more_horiz,
};

CategoryVisual bookkeepingCategoryVisual(BookkeepingCategory category) {
  final color = categoryColorOptions[category.colorKey] ?? AppColors.textMuted;
  return CategoryVisual(
    color,
    Color.alphaBlend(color.withValues(alpha: .12), Colors.white),
    categoryIconOptions[category.iconKey] ?? Icons.label_outline,
  );
}

const expenseCategoryOptions = <String>[
  '餐飲',
  '交通',
  '娛樂',
  '訂閱',
  '房租',
  '水電瓦斯',
  '保險',
  '醫療',
  '購物',
  '旅遊',
  '投資',
  '代訂墊付',
  '其他',
];

const incomeCategoryOptions = <String>[
  '薪資',
  '獎金',
  '利息',
  '自由業',
  '租金',
  '退款',
  '其他收入',
];

const _categoryVisuals = <String, CategoryVisual>{
  '餐飲': CategoryVisual(
    Color(0xFFE4765B),
    Color(0xFFFBECE8),
    Icons.restaurant_outlined,
  ),
  '交通': CategoryVisual(
    Color(0xFF568EAE),
    Color(0xFFEAF2F6),
    Icons.directions_subway_outlined,
  ),
  '購物': CategoryVisual(
    Color(0xFF9277A6),
    Color(0xFFF1ECF4),
    Icons.shopping_bag_outlined,
  ),
  '居家': CategoryVisual(
    Color(0xFF719681),
    Color(0xFFEBF2ED),
    Icons.home_outlined,
  ),
  '房租': CategoryVisual(
    Color(0xFF719681),
    Color(0xFFEBF2ED),
    Icons.home_outlined,
  ),
  '水電瓦斯': CategoryVisual(
    Color(0xFF4E9295),
    Color(0xFFE7F2F2),
    Icons.bolt_outlined,
  ),
  '娛樂': CategoryVisual(
    Color(0xFFB8893E),
    Color(0xFFF6F0E5),
    Icons.movie_outlined,
  ),
  '醫療': CategoryVisual(
    Color(0xFFBC7182),
    Color(0xFFF6EAED),
    Icons.medical_services_outlined,
  ),
  '訂閱': CategoryVisual(
    Color(0xFF6075A6),
    Color(0xFFEBEEF5),
    Icons.event_repeat_outlined,
  ),
  '保險': CategoryVisual(
    Color(0xFF748A96),
    Color(0xFFEDF1F3),
    Icons.health_and_safety_outlined,
  ),
  '旅遊': CategoryVisual(
    Color(0xFF4B8E9F),
    Color(0xFFE8F2F4),
    Icons.flight_outlined,
  ),
  '投資': CategoryVisual(
    Color(0xFF6075A6),
    Color(0xFFEBEEF5),
    Icons.trending_up_outlined,
  ),
  '投資收益': CategoryVisual(
    Color(0xFF6075A6),
    Color(0xFFEBEEF5),
    Icons.query_stats_outlined,
  ),
  '股息收入': CategoryVisual(
    Color(0xFF6075A6),
    Color(0xFFEBEEF5),
    Icons.query_stats_outlined,
  ),
  '代訂墊付': CategoryVisual(
    Color(0xFFA36F5A),
    Color(0xFFF4ECE8),
    Icons.groups_outlined,
  ),
  '代訂本人消費': CategoryVisual(
    Color(0xFFE4765B),
    Color(0xFFFBECE8),
    Icons.restaurant_outlined,
  ),
  '薪資': CategoryVisual(
    AppColors.income,
    AppColors.incomePale,
    Icons.work_outline,
  ),
  '獎金': CategoryVisual(
    Color(0xFF3C88A8),
    Color(0xFFE6F1F5),
    Icons.emoji_events_outlined,
  ),
  '利息': CategoryVisual(
    Color(0xFF6075A6),
    Color(0xFFEBEEF5),
    Icons.savings_outlined,
  ),
  '自由業': CategoryVisual(
    Color(0xFF568EAE),
    Color(0xFFEAF2F6),
    Icons.laptop_outlined,
  ),
  '租金': CategoryVisual(
    Color(0xFF719681),
    Color(0xFFEBF2ED),
    Icons.home_work_outlined,
  ),
  '退款': CategoryVisual(
    Color(0xFFB8893E),
    Color(0xFFF6F0E5),
    Icons.replay_outlined,
  ),
  '其他': CategoryVisual(Color(0xFF7B8B91), Color(0xFFEEF1F2), Icons.more_horiz),
  '其他收入': CategoryVisual(
    Color(0xFF7B8B91),
    Color(0xFFEEF1F2),
    Icons.more_horiz,
  ),
};

const _fallbackVisuals = <CategoryVisual>[
  CategoryVisual(Color(0xFF568EAE), Color(0xFFEAF2F6), Icons.label_outline),
  CategoryVisual(Color(0xFF9277A6), Color(0xFFF1ECF4), Icons.label_outline),
  CategoryVisual(Color(0xFF719681), Color(0xFFEBF2ED), Icons.label_outline),
  CategoryVisual(Color(0xFFB8893E), Color(0xFFF6F0E5), Icons.label_outline),
  CategoryVisual(Color(0xFFBC7182), Color(0xFFF6EAED), Icons.label_outline),
  CategoryVisual(Color(0xFF6075A6), Color(0xFFEBEEF5), Icons.label_outline),
];

CategoryVisual categoryVisual(String category) {
  final known = _categoryVisuals[category];
  if (known != null) return known;
  var checksum = 0;
  for (final unit in category.codeUnits) {
    checksum = (checksum * 31 + unit) & 0x7fffffff;
  }
  return _fallbackVisuals[checksum % _fallbackVisuals.length];
}
