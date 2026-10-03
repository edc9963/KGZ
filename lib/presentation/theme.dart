import 'package:flutter/material.dart';

import 'design_tokens.dart';

/// Builds the app's [ThemeData] for either brightness. Both the light and
/// dark theme share this one function — only the [AppSemanticColors]
/// instance backing them differs — so a color change here (or in
/// [AppSemanticColors]) automatically applies to both. The resolved
/// [AppSemanticColors] is registered as a [ThemeExtension] so screens can
/// read it back via `context.colors` (see `AppColorsContext` in
/// design_tokens.dart).
/// The Figma type family. Spelled out on every component text style below:
/// a component style that names no family falls back to the platform
/// default instead of [ThemeData.fontFamily].
const _font = 'Noto Sans TC';

ThemeData buildAppTheme(Brightness brightness) {
  final colors = brightness == Brightness.dark
      ? AppSemanticColors.dark
      : AppSemanticColors.light;
  final scheme = ColorScheme.fromSeed(
    seedColor: AppColors.accent,
    brightness: brightness,
    primary: colors.primary,
    onPrimary: colors.onPrimary,
    // Tonal buttons and chips sit on the quiet accent wash; the loud
    // selection hue is reserved for segmented controls and tabs.
    secondaryContainer: colors.accentPale,
    onSecondaryContainer: colors.accentPaleText,
    surface: colors.surface,
    onSurface: colors.text,
    onSurfaceVariant: colors.textMuted,
    outline: colors.border,
    outlineVariant: colors.border,
    error: colors.expense,
  );
  final baseTextTheme =
      (brightness == Brightness.dark ? ThemeData.dark() : ThemeData.light())
          .textTheme
          .copyWith(
            headlineLarge: const TextStyle(
              fontSize: 32,
              height: 1.2,
              fontWeight: FontWeight.w900,
            ),
            headlineMedium: const TextStyle(
              fontSize: 26,
              height: 1.3,
              fontWeight: FontWeight.w900,
            ),
            headlineSmall: const TextStyle(
              fontSize: 22,
              height: 1.3,
              fontWeight: FontWeight.w800,
            ),
            titleLarge: const TextStyle(fontSize: 20, height: 1.35),
            titleMedium: const TextStyle(fontSize: 16, height: 1.4),
            bodyLarge: const TextStyle(fontSize: 16, height: 1.55),
            bodyMedium: const TextStyle(fontSize: 15, height: 1.5),
            bodySmall: const TextStyle(fontSize: 13, height: 1.45),
          );
  const fieldRadius = BorderRadius.all(Radius.circular(14));
  const buttonShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.all(Radius.circular(16)),
  );
  WidgetStateProperty<Color?> selectedFill(Color on, Color off) =>
      WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected) ? on : off,
      );
  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: colors.background,
    canvasColor: colors.background,
    extensions: [colors],
    fontFamily: _font,
    fontFamilyFallback: const ['Microsoft JhengHei', 'sans-serif'],
    // Figma cards: borderless with a soft warm shadow in light mode; in dark
    // mode the shadow is transparent and the surface color alone separates
    // the card from the night-navy ground.
    cardTheme: CardThemeData(
      elevation: brightness == Brightness.dark ? 0 : 2,
      shadowColor: colors.cardShadow,
      surfaceTintColor: Colors.transparent,
      margin: EdgeInsets.zero,
      color: colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: const BorderRadius.all(Radius.circular(20)),
        side: brightness == Brightness.dark
            ? BorderSide(color: colors.border)
            : BorderSide.none,
      ),
    ),
    listTileTheme: ListTileThemeData(
      iconColor: colors.textMuted,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(18)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: colors.surface,
      labelStyle: TextStyle(fontFamily: _font, color: colors.textMuted),
      floatingLabelStyle: TextStyle(
        fontFamily: _font,
        color: colors.text,
        fontWeight: FontWeight.w700,
      ),
      border: OutlineInputBorder(
        borderRadius: fieldRadius,
        borderSide: BorderSide(color: colors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: fieldRadius,
        borderSide: BorderSide(color: colors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: fieldRadius,
        borderSide: BorderSide(color: colors.primary, width: 2),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: colors.background,
      indicatorColor: colors.accentPale,
      selectedIconTheme: IconThemeData(color: colors.accent),
      unselectedIconTheme: IconThemeData(color: colors.textMuted),
      selectedLabelTextStyle: TextStyle(
        fontFamily: _font,
        color: colors.text,
        fontWeight: FontWeight.w800,
      ),
      unselectedLabelTextStyle: TextStyle(
        fontFamily: _font,
        color: colors.textMuted,
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: colors.background,
      indicatorColor: colors.accentPale,
      surfaceTintColor: Colors.transparent,
      indicatorShape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          color: states.contains(WidgetState.selected)
              ? colors.accent
              : colors.textMuted,
        ),
      ),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
          fontFamily: _font,
          fontSize: 12,
          fontWeight: states.contains(WidgetState.selected)
              ? FontWeight.w800
              : FontWeight.w500,
          color: states.contains(WidgetState.selected)
              ? colors.text
              : colors.textMuted,
        ),
      ),
    ),
    drawerTheme: DrawerThemeData(backgroundColor: colors.background),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: colors.primary,
      foregroundColor: colors.onPrimary,
      extendedTextStyle: const TextStyle(
        fontFamily: _font,
        fontWeight: FontWeight.w800,
      ),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: colors.background,
      foregroundColor: colors.text,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: colors.background,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(24)),
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: colors.background,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: colors.surface,
      surfaceTintColor: Colors.transparent,
    ),
    dividerTheme: DividerThemeData(color: colors.border),
    // Figma "Primary Action": a solid honey-yellow (light) / comet-cyan
    // (dark) pill with dark ink — the filled, highest-emphasis button.
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(48, AppSpacing.controlMinHeight),
        backgroundColor: colors.primary,
        foregroundColor: colors.onPrimary,
        disabledBackgroundColor: colors.subtle,
        disabledForegroundColor: colors.textMuted,
        textStyle: const TextStyle(
          fontFamily: _font,
          fontWeight: FontWeight.w800,
        ),
        shape: buttonShape,
      ),
    ),
    // Secondary actions: a quiet outline in ink color, so the filled
    // primary action stays the one colored button on screen.
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(48, AppSpacing.controlMinHeight),
        foregroundColor: colors.text,
        backgroundColor: colors.surface,
        side: BorderSide(color: colors.border),
        textStyle: const TextStyle(
          fontFamily: _font,
          fontWeight: FontWeight.w700,
        ),
        shape: buttonShape,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: const Size(48, AppSpacing.controlMinHeight),
        foregroundColor: colors.accent,
        textStyle: const TextStyle(
          fontFamily: _font,
          fontWeight: FontWeight.w700,
        ),
        shape: buttonShape,
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(foregroundColor: colors.text),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        shape: const WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(12)),
          ),
        ),
        backgroundColor: selectedFill(colors.selection, colors.surface),
        foregroundColor: selectedFill(colors.onSelection, colors.textMuted),
        side: WidgetStatePropertyAll(BorderSide(color: colors.border)),
        textStyle: const WidgetStatePropertyAll(
          TextStyle(fontFamily: _font, fontWeight: FontWeight.w700),
        ),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: colors.surface,
      selectedColor: colors.primary,
      checkmarkColor: colors.onPrimary,
      secondarySelectedColor: colors.primary,
      labelStyle: TextStyle(fontFamily: _font, color: colors.text),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(999)),
      ),
      side: BorderSide(color: colors.border),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: selectedFill(colors.onPrimary, colors.surface),
      trackColor: selectedFill(colors.primary, colors.subtle),
      trackOutlineColor: WidgetStatePropertyAll(colors.border),
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: selectedFill(colors.primary, Colors.transparent),
      checkColor: WidgetStatePropertyAll(colors.onPrimary),
      side: BorderSide(color: colors.textMuted, width: 1.5),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(6)),
      ),
    ),
    radioTheme: RadioThemeData(
      fillColor: selectedFill(colors.primary, colors.textMuted),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: colors.primary,
      linearTrackColor: colors.subtle,
    ),
    tabBarTheme: TabBarThemeData(
      labelColor: colors.text,
      unselectedLabelColor: colors.textMuted,
      indicatorColor: colors.primary,
      dividerColor: colors.border,
    ),
    textTheme: baseTextTheme.apply(
      bodyColor: colors.text,
      displayColor: colors.text,
      fontFamily: _font,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: colors.text,
      contentTextStyle: TextStyle(fontFamily: _font, color: colors.background),
      actionTextColor: colors.primary,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(14)),
      ),
    ),
  );
}
