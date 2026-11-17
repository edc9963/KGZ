import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:forui/forui.dart';

import 'design_tokens.dart';

/// The Figma type family, matching `presentation/theme.dart`.
const _font = 'Noto Sans TC';
const _fontFallback = ['Microsoft JhengHei', 'sans-serif'];

/// Builds a forui [FThemeData] from the app's own [AppSemanticColors], so
/// forui widgets use the KGZ palette ("Warm Meadow & Melody" light / "Stellar
/// Night & Comet Stage" dark) instead of forui's stock Neutral theme.
///
/// Token mapping (forui ← KGZ):
/// * background / foreground ← background / text
/// * primary / primaryForeground ← primary / onPrimary (honey yellow, comet cyan)
/// * secondary / secondaryForeground ← accentPale / accentPaleText — the same
///   quiet accent wash Material tonal buttons and chips use in [buildAppTheme]
/// * muted / mutedForeground ← subtle / textMuted
/// * destructive, error ← expense
/// * card / border ← surface / border
///
/// Pair it with `buildAppTheme(brightness)` as the MaterialApp theme so any
/// remaining Material widgets and `context.colors` keep working alongside.
FThemeData buildForuiTheme(Brightness brightness, {bool touch = false}) {
  final kgz = brightness == Brightness.dark
      ? AppSemanticColors.dark
      : AppSemanticColors.light;
  final isDark = brightness == Brightness.dark;

  final colors = FColors(
    brightness: brightness,
    systemOverlayStyle: isDark
        ? SystemUiOverlayStyle.light
        : SystemUiOverlayStyle.dark,
    barrier: isDark ? const Color(0x7A000000) : const Color(0x3326231F),
    background: kgz.background,
    foreground: kgz.text,
    primary: kgz.primary,
    primaryForeground: kgz.onPrimary,
    secondary: kgz.accentPale,
    secondaryForeground: kgz.accentPaleText,
    muted: kgz.subtle,
    mutedForeground: kgz.textMuted,
    destructive: kgz.expense,
    // White on the light rose clears 4.5:1; the bright dark-mode rose needs
    // the night-navy ground instead, mirroring onPrimary.
    destructiveForeground: isDark ? kgz.background : Colors.white,
    error: kgz.expense,
    errorForeground: isDark ? kgz.background : Colors.white,
    card: kgz.surface,
    border: kgz.border,
    // Expose the full KGZ token set to forui-styled code too:
    // `context.theme.colors.extension<AppSemanticColors>()`.
    extensions: [kgz],
  );

  // Same family as the Material theme instead of forui's bundled Inter, so
  // digits and Latin text match the rest of the app.
  final typeface = FTypeface.inherit(
    colors: colors,
    touch: touch,
    fontFamily: _font,
    fontFamilyFallback: _fontFallback,
  );
  final typography = FTypography(display: typeface, body: typeface);

  // KGZ's rounder corners: fields and buttons 14 (theme.dart fieldRadius),
  // cards 20. forui reads `md` for buttons/fields and `lg` for cards.
  final style =
      FStyle.inherit(
        colors: colors,
        typography: typography,
        touch: touch,
      ).copyWith(
        borderRadius: const FBorderRadius(
          sm: BorderRadius.all(Radius.circular(10)),
          md: BorderRadius.all(Radius.circular(14)),
          lg: BorderRadius.all(Radius.circular(20)),
          xl: BorderRadius.all(Radius.circular(24)),
        ),
      );

  // Figma cards: borderless with a soft warm shadow in light mode; in dark
  // mode the shadow is transparent and a hairline border separates the card
  // from the night-navy ground (same as cardTheme in theme.dart).
  final baseCard = FCardStyle.inherit(
    colors: colors,
    typography: typography,
    style: style,
    touch: touch,
  );
  final cardStyle = FCardStyle(
    decoration: ShapeDecoration(
      color: kgz.surface,
      shape: RoundedSuperellipseBorder(
        side: isDark ? BorderSide(color: kgz.border) : BorderSide.none,
        borderRadius: const BorderRadius.all(Radius.circular(20)),
      ),
      shadows: isDark
          ? const []
          : [
              BoxShadow(
                color: kgz.cardShadow,
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
    ),
    titleTextStyle: baseCard.titleTextStyle,
    subtitleTextStyle: baseCard.subtitleTextStyle,
    padding: baseCard.padding,
  );

  return FThemeData(
    colors: colors,
    touch: touch,
    typography: typography,
    style: style,
    cardStyle: cardStyle,
    debugLabel:
        'KGZ ${isDark ? 'Dark' : 'Light'} ${touch ? 'Touch' : 'Desktop'}',
  );
}

final _themeCache = <(Brightness, bool), FThemeData>{};

/// Cached [buildForuiTheme]; FThemeData is large, so build each variant once.
FThemeData kgzForuiTheme(Brightness brightness, {bool touch = false}) =>
    _themeCache.putIfAbsent((
      brightness,
      touch,
    ), () => buildForuiTheme(brightness, touch: touch));

/// Whether forui should use its touch sizing (larger hit targets) — true on
/// phones and tablets, including their web browsers.
bool get kgzPrefersTouch => switch (defaultTargetPlatform) {
  TargetPlatform.android ||
  TargetPlatform.iOS ||
  TargetPlatform.fuchsia => true,
  _ => false,
};

/// `MaterialApp.builder` that puts forui's theme and toaster under every
/// route. It follows the Material theme MaterialApp already resolved (light,
/// dark or system), so the two never disagree. Use it on every MaterialApp,
/// tests included, or forui widgets throw for a missing FTheme.
Widget kgzForuiBuilder(BuildContext context, Widget? child) => FTheme(
  data: kgzForuiTheme(Theme.of(context).brightness, touch: kgzPrefersTouch),
  child: FToaster(child: child ?? const SizedBox.shrink()),
);

/// Rebuilds [child] from scratch whenever the engine reports newly loaded
/// fonts ([PaintingBinding.systemFonts]).
///
/// Needed around forui widgets that size themselves with
/// IntrinsicWidth/IntrinsicHeight, notably [FBadge]. On web, CanvasKit only
/// downloads the CJK fallback font (Noto Sans TC is not bundled) after the
/// first frame; those widgets keep the measurement taken with the missing
/// glyphs, so characters such as "內建" render as blank space until something
/// else forces a relayout. Re-keying the subtree throws that stale
/// measurement away. Cheap for small, stateless leaves like badges, but don't
/// wrap stateful subtrees, which would lose their state.
class RelayoutOnFontChange extends StatefulWidget {
  const RelayoutOnFontChange({required this.child, super.key});

  final Widget child;

  @override
  State<RelayoutOnFontChange> createState() => _RelayoutOnFontChangeState();
}

class _RelayoutOnFontChangeState extends State<RelayoutOnFontChange> {
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    PaintingBinding.instance.systemFonts.addListener(_onFontsChanged);
  }

  @override
  void dispose() {
    PaintingBinding.instance.systemFonts.removeListener(_onFontsChanged);
    super.dispose();
  }

  void _onFontsChanged() {
    if (mounted) setState(() => _generation++);
  }

  @override
  Widget build(BuildContext context) =>
      KeyedSubtree(key: ValueKey(_generation), child: widget.child);
}
