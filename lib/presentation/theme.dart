import 'package:flutter/material.dart';

import 'design_tokens.dart';

/// Builds the app's [ThemeData] for either brightness. Both the light and
/// dark theme share this one function — only the [AppSemanticColors]
/// instance backing them differs — so a color change here (or in
/// [AppSemanticColors]) automatically applies to both. The resolved
/// [AppSemanticColors] is registered as a [ThemeExtension] so screens can
/// read it back via `context.colors` (see `AppColorsContext` in
/// design_tokens.dart) instead of the old static `AppColors.xxx` constants.
ThemeData buildAppTheme(Brightness brightness) {
  final colors = brightness == Brightness.dark
      ? AppSemanticColors.dark
      : AppSemanticColors.light;
  final scheme = ColorScheme.fromSeed(
    seedColor: AppColors.accent,
    brightness: brightness,
    surface: colors.surface,
    error: colors.expense,
  );
  final baseTextTheme =
      (brightness == Brightness.dark ? ThemeData.dark() : ThemeData.light())
          .textTheme
          .copyWith(
            headlineLarge: const TextStyle(fontSize: 32, height: 1.2),
            headlineMedium: const TextStyle(fontSize: 26, height: 1.25),
            headlineSmall: const TextStyle(fontSize: 22, height: 1.3),
            titleLarge: const TextStyle(fontSize: 20, height: 1.35),
            titleMedium: const TextStyle(fontSize: 16, height: 1.4),
            bodyLarge: const TextStyle(fontSize: 16, height: 1.55),
            bodyMedium: const TextStyle(fontSize: 15, height: 1.5),
            bodySmall: const TextStyle(fontSize: 13, height: 1.45),
          );
  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: colors.background,
    extensions: [colors],
    fontFamilyFallback: const [
      'Noto Sans TC',
      'Microsoft JhengHei',
      'sans-serif',
    ],
    cardTheme: CardThemeData(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: const BorderRadius.all(Radius.circular(16)),
        side: BorderSide(color: colors.border),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: colors.surface,
      border: OutlineInputBorder(
        borderRadius: const BorderRadius.all(Radius.circular(14)),
        borderSide: BorderSide(color: colors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: const BorderRadius.all(Radius.circular(14)),
        borderSide: BorderSide(color: colors.border),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
    ),
    // The desktop navigation rail's sidebar is deliberately always dark
    // graphite in both themes (see AppColors.graphite), so its colors come
    // from the fixed AppColors constants, not from [colors].
    navigationRailTheme: const NavigationRailThemeData(
      backgroundColor: AppColors.graphite,
      indicatorColor: AppColors.accentSoft,
      selectedIconTheme: IconThemeData(color: Colors.white),
      unselectedIconTheme: IconThemeData(color: AppColors.graphiteMuted),
      selectedLabelTextStyle: TextStyle(
        color: Colors.white,
        fontWeight: FontWeight.w700,
      ),
      unselectedLabelTextStyle: TextStyle(color: AppColors.graphiteMuted),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: colors.mobileBackground,
      indicatorColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          color: states.contains(WidgetState.selected)
              ? colors.accent
              : colors.textMuted,
        ),
      ),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
          fontSize: 12,
          fontWeight: states.contains(WidgetState.selected)
              ? FontWeight.w800
              : FontWeight.w500,
          color: states.contains(WidgetState.selected)
              ? colors.accent
              : colors.textMuted,
        ),
      ),
    ),
    // Level-1 "spotlight" treatment: solid highlight (goose-yellow) fill
    // with dark graphite icon/text — the one action per screen that gets
    // a filled, colored button. See the button-hierarchy notes in the
    // design canvas. Fixed across themes, like AppColors.highlight itself.
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: AppColors.highlight,
      foregroundColor: AppColors.highlightOn,
      extendedTextStyle: TextStyle(fontWeight: FontWeight.w800),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: colors.surface,
      foregroundColor: colors.text,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      shape: Border(bottom: BorderSide(color: colors.border)),
    ),
    dividerTheme: DividerThemeData(color: colors.border),
    // Deliberately hollow, not solid-filled: every button in the app (main
    // call-to-action included) reads as an outlined pill so a FilledButton
    // and an OutlinedButton look identical — one consistent button style
    // instead of two competing weights.
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(48, AppSpacing.controlMinHeight),
        backgroundColor: Colors.transparent,
        foregroundColor: colors.accent,
        side: BorderSide(color: colors.accent),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(48, AppSpacing.controlMinHeight),
        foregroundColor: colors.accent,
        side: BorderSide(color: colors.accent),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: const Size(48, AppSpacing.controlMinHeight),
        foregroundColor: colors.accent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        selectedBackgroundColor: colors.accentPale,
        selectedForegroundColor: colors.accentPaleText,
        side: BorderSide(color: colors.border),
      ),
    ),
    chipTheme: ChipThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      side: BorderSide(color: colors.border),
    ),
    textTheme: baseTextTheme.apply(
      bodyColor: colors.text,
      displayColor: colors.text,
    ),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
  );
}
