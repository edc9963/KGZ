import 'package:flutter/material.dart';

import '../domain/models.dart';

/// Colors that stay fixed regardless of the app's light/dark theme. Since
/// the Figma redesign ("KGZ / Fintech Redesign v1") every surface — the
/// desktop sidebar included — follows the theme, so only seed and
/// third-party brand hues live here. Anything that flips between light and
/// dark lives in [AppSemanticColors] and is reached through
/// `context.colors` (see the [AppColorsContext] extension below).
abstract final class AppColors {
  /// Seed for [ColorScheme.fromSeed]; on-screen colors come from
  /// `context.colors` instead.
  static const accent = Color(0xFFF4C84D);

  /// LINE Login's own brand green — fixed by LINE's brand guidelines.
  static const lineGreen = Color(0xFF06C755);
}

/// Everything that flips between the app's light and dark theme: page and
/// card surfaces, text, borders, the interactive hues and the semantic
/// finance colors (asset/income/expense/liability) plus their pale washes.
///
/// Values come from the Figma redesign: "Warm Meadow & Melody" (light —
/// cream ground, honey-yellow actions, rose selection) and "Stellar Night &
/// Comet Stage" (dark — night-navy ground, comet-cyan actions, bright-orange
/// selection). Registered on [ThemeData.extensions] by `buildAppTheme` (see
/// `presentation/theme.dart`) and read back with `context.colors`.
@immutable
class AppSemanticColors extends ThemeExtension<AppSemanticColors> {
  const AppSemanticColors({
    required this.background,
    required this.surface,
    required this.subtle,
    required this.mobileBackground,
    required this.text,
    required this.textMuted,
    required this.border,
    required this.asset,
    required this.assetPale,
    required this.income,
    required this.incomePale,
    required this.expense,
    required this.expensePale,
    required this.liability,
    required this.liabilityPale,
    required this.warn,
    required this.warnPale,
    required this.accent,
    required this.accentPale,
    required this.accentPaleText,
    required this.primary,
    required this.onPrimary,
    required this.selection,
    required this.onSelection,
    required this.chartA,
    required this.chartB,
    required this.chartC,
    required this.cardShadow,
  });

  /// Page background.
  final Color background;

  /// Card and sheet surfaces.
  final Color surface;

  /// Quiet fill for tracks, inactive segments and keypad-like controls.
  final Color subtle;

  /// Mobile app shell background — the same ground as [background] since
  /// the redesign, kept as its own name for existing call sites.
  final Color mobileBackground;

  /// Primary text/ink color.
  final Color text;

  /// Secondary/caption text color.
  final Color textMuted;

  /// Card, divider and input borders.
  final Color border;

  /// Balance figures on stat cards (honey gold in light, comet cyan in dark,
  /// as on the Figma dashboard's 可用餘額 card).
  final Color asset;
  final Color assetPale;
  final Color income;
  final Color incomePale;
  final Color expense;
  final Color expensePale;
  final Color liability;
  final Color liabilityPale;

  /// Needs-attention state: low OCR confidence, pending collection, notes
  /// warning about a side effect.
  final Color warn;
  final Color warnPale;

  /// Links, icons and other interactive ink on ordinary surfaces.
  final Color accent;

  /// Pale wash behind a selected nav item or an info note, paired with
  /// [accentPaleText].
  final Color accentPale;
  final Color accentPaleText;

  /// The one solid action color: primary buttons, switches, checkboxes and
  /// the quick-entry FAB (Figma "Primary Action" component).
  final Color primary;
  final Color onPrimary;

  /// Selected tab / segment fill (Figma segmented control).
  final Color selection;
  final Color onSelection;

  /// Categorical chart series, in order.
  final Color chartA;
  final Color chartB;
  final Color chartC;

  /// Shadow under cards in light mode; transparent in dark mode, where cards
  /// separate from the ground by their surface color alone.
  final Color cardShadow;

  static const light = AppSemanticColors(
    background: Color(0xFFFBF6F0),
    surface: Colors.white,
    subtle: Color(0xFFF4EDE0),
    mobileBackground: Color(0xFFFBF6F0),
    text: Color(0xFF26231F),
    textMuted: Color(0xFF7D7974),
    border: Color(0xFFEFE7DA),
    // Darker than the Figma swatches where the hue is used as text, so
    // figures on white still clear WCAG AA (4.5:1).
    asset: Color(0xFFA87B12),
    assetPale: Color(0xFFFCF3DC),
    income: Color(0xFF3B8A71),
    incomePale: Color(0xFFE6F3EE),
    expense: Color(0xFFC4505D),
    expensePale: Color(0xFFFBEAEC),
    liability: Color(0xFFC4505D),
    liabilityPale: Color(0xFFFBEAEC),
    warn: Color(0xFFA5670C),
    warnPale: Color(0xFFFDF1DC),
    accent: Color(0xFF9C720F),
    accentPale: Color(0xFFFDF3D8),
    accentPaleText: Color(0xFF6E510B),
    primary: Color(0xFFF4C84D),
    onPrimary: Color(0xFF26231F),
    selection: Color(0xFFF0B4B9),
    onSelection: Color(0xFF26231F),
    chartA: Color(0xFFDF8088),
    chartB: Color(0xFFF4C84D),
    chartC: Color(0xFF68B39B),
    cardShadow: Color(0x14503C14),
  );

  static const dark = AppSemanticColors(
    background: Color(0xFF0D0E15),
    surface: Color(0xFF171B27),
    subtle: Color(0xFF232A3A),
    mobileBackground: Color(0xFF0D0E15),
    text: Color(0xFFF2F4F8),
    textMuted: Color(0xFF8D96AA),
    border: Color(0xFF222838),
    asset: Color(0xFF00CFFF),
    assetPale: Color(0xFF0F2633),
    income: Color(0xFF00E676),
    incomePale: Color(0xFF0E2A1F),
    expense: Color(0xFFFF6685),
    expensePale: Color(0xFF33182A),
    liability: Color(0xFFFF6685),
    liabilityPale: Color(0xFF33182A),
    warn: Color(0xFFFFB547),
    warnPale: Color(0xFF33281A),
    accent: Color(0xFF00CFFF),
    accentPale: Color(0xFF10283A),
    accentPaleText: Color(0xFF7FE3FF),
    primary: Color(0xFF00CFFF),
    onPrimary: Color(0xFF0D0E15),
    selection: Color(0xFFFF8A1F),
    onSelection: Color(0xFF0D0E15),
    chartA: Color(0xFFFF6685),
    chartB: Color(0xFFA98BFF),
    chartC: Color(0xFF00CFFF),
    cardShadow: Color(0x00000000),
  );

  @override
  AppSemanticColors copyWith({
    Color? background,
    Color? surface,
    Color? subtle,
    Color? mobileBackground,
    Color? text,
    Color? textMuted,
    Color? border,
    Color? asset,
    Color? assetPale,
    Color? income,
    Color? incomePale,
    Color? expense,
    Color? expensePale,
    Color? liability,
    Color? liabilityPale,
    Color? warn,
    Color? warnPale,
    Color? accent,
    Color? accentPale,
    Color? accentPaleText,
    Color? primary,
    Color? onPrimary,
    Color? selection,
    Color? onSelection,
    Color? chartA,
    Color? chartB,
    Color? chartC,
    Color? cardShadow,
  }) => AppSemanticColors(
    background: background ?? this.background,
    surface: surface ?? this.surface,
    subtle: subtle ?? this.subtle,
    mobileBackground: mobileBackground ?? this.mobileBackground,
    text: text ?? this.text,
    textMuted: textMuted ?? this.textMuted,
    border: border ?? this.border,
    asset: asset ?? this.asset,
    assetPale: assetPale ?? this.assetPale,
    income: income ?? this.income,
    incomePale: incomePale ?? this.incomePale,
    expense: expense ?? this.expense,
    expensePale: expensePale ?? this.expensePale,
    liability: liability ?? this.liability,
    liabilityPale: liabilityPale ?? this.liabilityPale,
    warn: warn ?? this.warn,
    warnPale: warnPale ?? this.warnPale,
    accent: accent ?? this.accent,
    accentPale: accentPale ?? this.accentPale,
    accentPaleText: accentPaleText ?? this.accentPaleText,
    primary: primary ?? this.primary,
    onPrimary: onPrimary ?? this.onPrimary,
    selection: selection ?? this.selection,
    onSelection: onSelection ?? this.onSelection,
    chartA: chartA ?? this.chartA,
    chartB: chartB ?? this.chartB,
    chartC: chartC ?? this.chartC,
    cardShadow: cardShadow ?? this.cardShadow,
  );

  @override
  AppSemanticColors lerp(ThemeExtension<AppSemanticColors>? other, double t) {
    if (other is! AppSemanticColors) return this;
    Color mix(Color a, Color b) => Color.lerp(a, b, t)!;
    return AppSemanticColors(
      background: mix(background, other.background),
      surface: mix(surface, other.surface),
      subtle: mix(subtle, other.subtle),
      mobileBackground: mix(mobileBackground, other.mobileBackground),
      text: mix(text, other.text),
      textMuted: mix(textMuted, other.textMuted),
      border: mix(border, other.border),
      asset: mix(asset, other.asset),
      assetPale: mix(assetPale, other.assetPale),
      income: mix(income, other.income),
      incomePale: mix(incomePale, other.incomePale),
      expense: mix(expense, other.expense),
      expensePale: mix(expensePale, other.expensePale),
      liability: mix(liability, other.liability),
      liabilityPale: mix(liabilityPale, other.liabilityPale),
      warn: mix(warn, other.warn),
      warnPale: mix(warnPale, other.warnPale),
      accent: mix(accent, other.accent),
      accentPale: mix(accentPale, other.accentPale),
      accentPaleText: mix(accentPaleText, other.accentPaleText),
      primary: mix(primary, other.primary),
      onPrimary: mix(onPrimary, other.onPrimary),
      selection: mix(selection, other.selection),
      onSelection: mix(onSelection, other.onSelection),
      chartA: mix(chartA, other.chartA),
      chartB: mix(chartB, other.chartB),
      chartC: mix(chartC, other.chartC),
      cardShadow: mix(cardShadow, other.cardShadow),
    );
  }
}

/// Fixed series palette for pie charts whose slices carry a white label on
/// the fill: the Figma chart hues (rose, honey, mint, violet, cyan) pushed
/// dark enough for white text, and kept the same in both themes.
const pieChartPalette = <Color>[
  Color(0xFFC85F6B),
  Color(0xFFB0800E),
  Color(0xFF3E8C74),
  Color(0xFF7A62C4),
  Color(0xFF1A8BAD),
];

/// Reads the current [AppSemanticColors] off the nearest [Theme] — the
/// replacement for the old direct `AppColors.xxx` references. `buildAppTheme`
/// always registers one, so the `!` is safe for any widget under
/// `MaterialApp`.
extension AppColorsContext on BuildContext {
  AppSemanticColors get colors =>
      Theme.of(this).extension<AppSemanticColors>()!;
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
  // Richer than before — a genuine violet rather than a grayed-out mauve,
  // so it reads as its own color choice next to indigo/rose instead of
  // sitting between them.
  'purple': Color(0xFF8868A8),
  'rose': Color(0xFFBC7182),
  'indigo': Color(0xFF6075A6),
  'cyan': Color(0xFF4B8E9F),
  'brown': Color(0xFFA36F5A),
  'slate': Color(0xFF748A96),
  // A true warm orange — the gap the old palette had between coral (more
  // red) and amber (more brown/gold).
  'orange': Color(0xFFD6813A),
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

/// Parses a `#RRGGBB` (or bare `RRGGBB`) hex string into a fully-opaque
/// [Color]. Returns null if [value] isn't a valid 6-digit hex color — used
/// to tell a user-picked custom category color (stored directly as its hex
/// string in [BookkeepingCategory.colorKey]) apart from a plain, unrecognized
/// key.
Color? parseHexColor(String value) {
  final match = RegExp(r'^#?([0-9A-Fa-f]{6})$').firstMatch(value.trim());
  if (match == null) return null;
  return Color(int.parse('FF${match.group(1)}', radix: 16));
}

/// Renders [color] back as an uppercase `#RRGGBB` hex string, the inverse of
/// [parseHexColor].
String colorToHex(Color color) =>
    '#${(color.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

/// Resolves a stored [BookkeepingCategory.colorKey] to an actual [Color] —
/// either one of the curated [categoryColorOptions] swatches, or a
/// user-chosen custom color stored directly as a `#RRGGBB` hex string (see
/// [CategoryColorPicker] in `presentation/widgets/common.dart`). Falls back
/// to [AppSemanticColors.textMuted] for an unrecognized/legacy key.
Color resolveCategoryColorKey(String colorKey, AppSemanticColors colors) =>
    categoryColorOptions[colorKey] ??
    parseHexColor(colorKey) ??
    colors.textMuted;

/// [colors] resolves the pale wash against the current theme's surface
/// (light or dark) instead of always blending against white, so custom
/// category chips stay legible in dark mode too.
CategoryVisual bookkeepingCategoryVisual(
  BookkeepingCategory category,
  AppSemanticColors colors,
) {
  final color = resolveCategoryColorKey(category.colorKey, colors);
  return CategoryVisual(
    color,
    Color.alphaBlend(color.withValues(alpha: .12), colors.surface),
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

// The hue/icon pairing below is each category's fixed visual identity and
// stays the same across themes; only the pale wash (computed in
// [categoryVisual] against the current theme's surface) changes with
// light/dark.
const _categoryVisuals = <String, (Color, IconData)>{
  '餐飲': (Color(0xFFD2664B), Icons.restaurant_outlined),
  '交通': (Color(0xFF4179C8), Icons.directions_subway_outlined),
  '購物': (Color(0xFFB83D66), Icons.shopping_bag_outlined),
  '居家': (Color(0xFF719681), Icons.home_outlined),
  '房租': (Color(0xFF719681), Icons.home_outlined),
  '水電瓦斯': (Color(0xFF4E9295), Icons.bolt_outlined),
  '娛樂': (Color(0xFF6A44A7), Icons.movie_outlined),
  '醫療': (Color(0xFFBC7182), Icons.medical_services_outlined),
  '訂閱': (Color(0xFF6075A6), Icons.event_repeat_outlined),
  '保險': (Color(0xFF748A96), Icons.health_and_safety_outlined),
  '旅遊': (Color(0xFF4B8E9F), Icons.flight_outlined),
  '投資': (Color(0xFF6075A6), Icons.trending_up_outlined),
  '投資收益': (Color(0xFF6075A6), Icons.query_stats_outlined),
  '股息收入': (Color(0xFF6075A6), Icons.query_stats_outlined),
  '代訂墊付': (Color(0xFFA36F5A), Icons.groups_outlined),
  '代訂本人消費': (Color(0xFFD2664B), Icons.restaurant_outlined),
  '薪資': (Color(0xFF3B8A71), Icons.work_outline),
  '獎金': (Color(0xFF3C88A8), Icons.emoji_events_outlined),
  '利息': (Color(0xFF6075A6), Icons.savings_outlined),
  '自由業': (Color(0xFF568EAE), Icons.laptop_outlined),
  '租金': (Color(0xFF719681), Icons.home_work_outlined),
  '退款': (Color(0xFFB8893E), Icons.replay_outlined),
  '其他': (Color(0xFF7B8B91), Icons.more_horiz),
  '其他收入': (Color(0xFF7B8B91), Icons.more_horiz),
};

const _fallbackVisuals = <(Color, IconData)>[
  (Color(0xFF568EAE), Icons.label_outline),
  (Color(0xFF9277A6), Icons.label_outline),
  (Color(0xFF719681), Icons.label_outline),
  (Color(0xFFB8893E), Icons.label_outline),
  (Color(0xFFBC7182), Icons.label_outline),
  (Color(0xFF6075A6), Icons.label_outline),
];

/// [colors] resolves the pale wash against the current theme's surface
/// (light or dark) instead of always blending against white, so category
/// chips/avatars stay legible in dark mode too.
CategoryVisual categoryVisual(String category, AppSemanticColors colors) {
  final (color, icon) = _categoryVisuals[category] ?? _fallbackFor(category);
  return CategoryVisual(
    color,
    Color.alphaBlend(color.withValues(alpha: .12), colors.surface),
    icon,
  );
}

(Color, IconData) _fallbackFor(String category) {
  var checksum = 0;
  for (final unit in category.codeUnits) {
    checksum = (checksum * 31 + unit) & 0x7fffffff;
  }
  return _fallbackVisuals[checksum % _fallbackVisuals.length];
}
