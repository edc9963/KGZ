import 'package:flutter/material.dart';

import '../domain/models.dart';

/// Colors that stay fixed regardless of the app's light/dark theme —
/// brand-identity hues, and everything tied to the desktop navigation rail's
/// sidebar, which is deliberately always dark graphite in both themes (see
/// the button-hierarchy notes in the design canvas). Anything that instead
/// needs to flip between a light and dark value lives in [AppSemanticColors]
/// and is reached through `context.colors` (see the [AppColorsContext]
/// extension below), not through this class.
abstract final class AppColors {
  /// Net-worth / data color — deliberately decoupled from the interactive
  /// accent so the app has exactly one interactive hue instead of "data that
  /// happens to look like a button." Kept here only as the seed fed to
  /// [ColorScheme.fromSeed]; the themed ink color used on screen is
  /// `context.colors.asset`.
  static const primary = Color(0xFF1F2D33);
  /// Hover/pressed state for a link rendered in the accent hue.
  static const primaryHover = Color(0xFF06606B);

  /// Desktop/tablet navigation rail background — always dark graphite,
  /// independent of the app's overall light/dark theme. Matches the app
  /// icon's own background exactly (`web/icons/quick-ledger-j.svg`), so the
  /// sidebar reads as a direct extension of the brand mark.
  static const graphite = Color(0xFF2B2F33);
  /// Unselected icon/label color on the graphite sidebar.
  static const graphiteMuted = Color(0xFFDCE5E8);

  /// Brand accent (teal-blue, echoes the app icon), used only as the seed
  /// color for [ColorScheme.fromSeed]. UI code should use
  /// `context.colors.accent` instead, which is tuned per theme.
  static const accent = Color(0xFF0D80A0);
  /// Translucent wash of the app icon's cyan, used behind the selected item
  /// in the desktop sidebar's navigation rail indicator — fixed because the
  /// sidebar itself is always dark graphite.
  static const accentSoft = Color(0x2E27C2D4);
  /// The app icon's own cyan (`#27C2D4`), used directly for the desktop
  /// navigation's selected-item icon — on the dark graphite sidebar this
  /// hue clears WCAG AA on its own, so no lightening is needed the way the
  /// old, more muted `context.colors.accent` required. Fixed for the same
  /// reason as [accentSoft].
  static const accentOnDark = Color(0xFF27C2D4);

  /// Level-1 "spotlight" button fill (goose-yellow) — reserved for the
  /// single highest-emphasis action per screen (the quick-entry FAB).
  /// Deliberately used nowhere else, so it keeps reading as "the one main
  /// action" rather than one color among several, and deliberately the same
  /// in both themes so it always pops off the surrounding surface.
  static const highlight = Color(0xFFFFC83D);
  /// Icon/label color on a solid [highlight] fill.
  static const highlightOn = graphite;
  /// Shadow color under a [highlight] surface (e.g. the FAB).
  static const highlightShadow = Color(0x59FFC83D);
  /// Darkened [highlight] hue for text on a light highlight wash (not a
  /// solid fill, where [highlightOn] applies instead).
  static const highlightText = Color(0xFF9C7016);
}

/// Everything that flips between the app's light and dark theme: page and
/// card surfaces, text, borders, and the semantic finance colors
/// (asset/income/expense/liability) plus their pale washes.
///
/// Registered on [ThemeData.extensions] by `buildAppTheme` (see
/// `presentation/theme.dart`) and read back with `context.colors` — the
/// [AppColorsContext] extension below — instead of the old static
/// `AppColors.xxx` constants, so every screen automatically follows the
/// user's light/dark/system choice.
@immutable
class AppSemanticColors extends ThemeExtension<AppSemanticColors> {
  const AppSemanticColors({
    required this.background,
    required this.surface,
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
    required this.accent,
    required this.accentPale,
    required this.accentPaleText,
  });

  /// Desktop/tablet page background.
  final Color background;
  /// Card and sheet surfaces.
  final Color surface;
  /// Mobile app shell background (app bar, scaffold, bottom navigation).
  final Color mobileBackground;
  /// Primary text/ink color.
  final Color text;
  /// Secondary/caption text color.
  final Color textMuted;
  /// Card, divider and input borders.
  final Color border;

  /// Net-worth / data color — deliberately the same as [text] so net worth
  /// reads as ink, not as a colored call-to-action.
  final Color asset;
  final Color assetPale;
  final Color income;
  final Color incomePale;
  final Color expense;
  final Color expensePale;
  final Color liability;
  final Color liabilityPale;

  /// The app's one interactive hue — outlined/text/filled buttons,
  /// interactive icons, and links on ordinary (themed) surfaces.
  final Color accent;
  /// Very light wash of [accent] for pill/badge backgrounds (a selected
  /// top-level tab, an info panel), paired with [accentPaleText].
  final Color accentPale;
  final Color accentPaleText;

  // Light and dark lean into two different registers of the same icon: light
  // reads warm and wool-cream (the highlight gold pushed further into the
  // surfaces themselves), dark reads like the icon's own near-black ground
  // with its cyan stroke lit up on it — a comet against a night sky rather
  // than a muted daytime version of the same blue.
  static const light = AppSemanticColors(
    background: Color(0xFFF4F6F7),
    surface: Colors.white,
    mobileBackground: Color(0xFFFBF3E4),
    text: Color(0xFF1F2D33),
    textMuted: Color(0xFF68777D),
    border: Color(0xFFDCE3E6),
    asset: Color(0xFF1F2D33),
    assetPale: Color(0xFFE4E6E7),
    income: Color(0xFF3B9166),
    incomePale: Color(0xFFE4F0EA),
    expense: Color(0xFFD35645),
    expensePale: Color(0xFFF9E9E7),
    liability: Color(0xFF7A8F3D),
    liabilityPale: Color(0xFFEBEEE2),
    // Deliberately NOT the app icon's brighter cyan (#27C2D4): that hue only
    // clears ~2.2:1 against a white/near-white surface, far short of the
    // 4.5:1 WCAG AA text requires. This value is already the icon's hue
    // pushed as dark as it can go while staying ~85% saturated — it sits
    // right at 4.55:1, so there's no headroom left to make it more vivid
    // without failing contrast on every outlined button label in light mode.
    accent: Color(0xFF0D80A0),
    accentPale: Color(0xFFE2F0F4),
    accentPaleText: Color(0xFF096771),
  );

  static const dark = AppSemanticColors(
    background: Color(0xFF14181A),
    surface: Color(0xFF1E262A),
    mobileBackground: Color(0xFF1B1815),
    text: Color(0xFFEDF1F2),
    textMuted: Color(0xFF93A3A9),
    border: Color(0xFF333D41),
    asset: Color(0xFFEDF1F2),
    assetPale: Color(0xFF2A3236),
    income: Color(0xFF54BD8B),
    incomePale: Color(0xFF203029),
    expense: Color(0xFFE58579),
    expensePale: Color(0xFF382522),
    liability: Color(0xFFA3B95F),
    liabilityPale: Color(0xFF2A2E1F),
    // The app icon's own cyan, used as-is: against every dark surface in
    // this theme it clears WCAG AA with room to spare (6.2–8.3:1), so dark
    // mode is where the interactive color can finally match the icon
    // exactly instead of a muted derivative of it.
    accent: Color(0xFF27C2D4),
    accentPale: Color(0xFF1C2E33),
    accentPaleText: Color(0xFF8FD8E8),
  );

  @override
  AppSemanticColors copyWith({
    Color? background,
    Color? surface,
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
    Color? accent,
    Color? accentPale,
    Color? accentPaleText,
  }) => AppSemanticColors(
    background: background ?? this.background,
    surface: surface ?? this.surface,
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
    accent: accent ?? this.accent,
    accentPale: accentPale ?? this.accentPale,
    accentPaleText: accentPaleText ?? this.accentPaleText,
  );

  @override
  AppSemanticColors lerp(ThemeExtension<AppSemanticColors>? other, double t) {
    if (other is! AppSemanticColors) return this;
    return AppSemanticColors(
      background: Color.lerp(background, other.background, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      mobileBackground: Color.lerp(mobileBackground, other.mobileBackground, t)!,
      text: Color.lerp(text, other.text, t)!,
      textMuted: Color.lerp(textMuted, other.textMuted, t)!,
      border: Color.lerp(border, other.border, t)!,
      asset: Color.lerp(asset, other.asset, t)!,
      assetPale: Color.lerp(assetPale, other.assetPale, t)!,
      income: Color.lerp(income, other.income, t)!,
      incomePale: Color.lerp(incomePale, other.incomePale, t)!,
      expense: Color.lerp(expense, other.expense, t)!,
      expensePale: Color.lerp(expensePale, other.expensePale, t)!,
      liability: Color.lerp(liability, other.liability, t)!,
      liabilityPale: Color.lerp(liabilityPale, other.liabilityPale, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      accentPale: Color.lerp(accentPale, other.accentPale, t)!,
      accentPaleText: Color.lerp(accentPaleText, other.accentPaleText, t)!,
    );
  }
}

/// Reads the current [AppSemanticColors] off the nearest [Theme] — the
/// replacement for the old direct `AppColors.xxx` references. `buildAppTheme`
/// always registers one, so the `!` is safe for any widget under
/// `MaterialApp`.
extension AppColorsContext on BuildContext {
  AppSemanticColors get colors => Theme.of(this).extension<AppSemanticColors>()!;
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
    categoryColorOptions[colorKey] ?? parseHexColor(colorKey) ?? colors.textMuted;

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
  '薪資': (Color(0xFF3B9166), Icons.work_outline),
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
