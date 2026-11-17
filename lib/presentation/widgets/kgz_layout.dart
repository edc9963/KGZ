import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

import '../design_tokens.dart';

/// Layout pieces from the Figma redesign ("KGZ / Fintech Redesign v1") that
/// pages share: the form dialog, the hero metric card, section cards, status
/// pills, notes and link rows. Colors always come from `context.colors`, so
/// every piece follows the light ("Warm Meadow") / dark ("Stellar Night")
/// theme on its own.

/// Names the current top-level workspace (總覽 / 帳務 / 資產 / 代訂 / 設定)
/// for everything below the app shell, and carries that workspace's tab bar
/// (e.g. 帳戶 · 投資 · 對帳), so a page's `PageHeader` can show the
/// "KGZ / workspace" breadcrumb and place the tabs right under the title —
/// as in the Figma screens — without each page passing them in.
class WorkspaceScope extends InheritedWidget {
  const WorkspaceScope({
    required this.label,
    required super.child,
    this.tabs,
    this.mobileActions,
    this.path = '',
    super.key,
  });

  final String label;
  final Widget? tabs;
  final ValueNotifier<Map<String, Widget?>>? mobileActions;
  final String path;

  static WorkspaceScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<WorkspaceScope>();

  static String? maybeLabelOf(BuildContext context) => maybeOf(context)?.label;

  @override
  bool updateShouldNotify(WorkspaceScope oldWidget) =>
      label != oldWidget.label ||
      tabs != oldWidget.tabs ||
      path != oldWidget.path;
}

/// The form dialog used by every editor in the app, built on forui's
/// [FDialog]. Open it with `showFDialog`.
///
/// It lays out a heavy title, the [content] and a row of [actions]. On
/// phones (< [AppBreakpoints.mobile]) the dialog spans the screen width and
/// the actions stretch to equal-width buttons, matching the Figma quick-entry
/// sheet; on wider screens the actions sit at the trailing edge.
///
/// The entrance animation comes from the enclosing route, so callers don't
/// need to thread `showFDialog`'s `animation` through.
class KgzDialog extends StatelessWidget {
  const KgzDialog({
    this.title,
    this.content,
    this.actions,
    this.maxWidth = double.infinity,
    this.fullWidthOnPhone = false,
    super.key,
  });

  final Widget? title;
  final Widget? content;
  final List<Widget>? actions;

  /// Upper bound for the dialog width on wider screens. Below it the dialog
  /// shrink-wraps its content (like Material's AlertDialog), so a content
  /// `SizedBox(width: 520)` makes a 520-wide dialog.
  final double maxWidth;

  /// Edge-to-edge on phones (no side inset), for large editors.
  final bool fullWidthOnPhone;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final width = MediaQuery.sizeOf(context).width;
    final phone = width < AppBreakpoints.mobile;
    final buttons = actions ?? const <Widget>[];
    return FDialog(
      animation: ModalRoute.of(context)?.animation,
      constraints: phone
          ? BoxConstraints.tightFor(
              width: fullWidthOnPhone ? width : width - 24,
            )
          : BoxConstraints(
              minWidth: 320,
              maxWidth: maxWidth.clamp(320, width - 80),
            ),
      style: phone
          ? FDialogStyleDelta.delta(
              insetPadding: EdgeInsetsGeometryDelta.value(
                EdgeInsets.symmetric(
                  horizontal: fullWidthOnPhone ? 0 : 12,
                  vertical: 16,
                ),
              ),
            )
          : const FDialogStyleDelta.context(),
      builder: (context, style) => KeyedSubtree(
        key: const ValueKey('kgz-dialog-body'),
        child: _shrinkWrap(
          phone,
          Padding(
            padding: phone
                ? const EdgeInsets.fromLTRB(20, 20, 20, 16)
                : const EdgeInsets.fromLTRB(24, 22, 24, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (title != null)
                  DefaultTextStyle.merge(
                    style: style.titleTextStyle.copyWith(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      color: colors.text,
                    ),
                    child: title!,
                  ),
                if (content != null) ...[
                  if (title != null) const SizedBox(height: 16),
                  Flexible(
                    child: DefaultTextStyle.merge(
                      style: style.bodyTextStyle.copyWith(color: colors.text),
                      child: content!,
                    ),
                  ),
                ],
                if (buttons.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  if (phone)
                    Row(
                      children: [
                        for (
                          var index = 0;
                          index < buttons.length;
                          index++
                        ) ...[
                          if (index > 0) const SizedBox(width: 10),
                          Expanded(child: buttons[index]),
                        ],
                      ],
                    )
                  else
                    Wrap(
                      alignment: WrapAlignment.end,
                      spacing: 8,
                      runSpacing: 8,
                      children: buttons,
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// On wider screens size the dialog to its content (Material AlertDialog
  /// behaviour); phones already get a fixed width.
  static Widget _shrinkWrap(bool phone, Widget child) =>
      phone ? child : IntrinsicWidth(child: child);
}

/// The large figure at the top of a page (Figma "本月剩餘預算" card): a muted
/// label, a big tabular number in ink color, and an optional caption and
/// extra content such as a progress bar or a pair of sub-figures.
class HeroMetricCard extends StatelessWidget {
  const HeroMetricCard({
    required this.label,
    required this.value,
    this.caption,
    this.badge,
    this.valueColor,
    this.child,
    this.onTap,
    this.icon,
    this.tone,
    this.compactValue,
    super.key,
  });

  final String label;
  final String value;
  final String? caption;
  final Widget? badge;
  final Color? valueColor;
  final Widget? child;
  final VoidCallback? onTap;

  /// Small tinted icon shown top-right when there is no [badge].
  final IconData? icon;

  /// Same as [valueColor]; named like `SummaryCard.tone` so a page's lead
  /// summary card can be promoted to a hero card unchanged.
  final Color? tone;

  /// Accepted for parity with `SummaryCard`; the hero figure scales down
  /// to fit instead of switching to a compact form.
  final String? compactValue;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final accent = tone ?? valueColor;
    final content = Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(color: colors.textMuted, fontSize: 13),
                ),
              ),
              if (badge != null)
                badge!
              else if (icon != null)
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: (accent ?? colors.accent).withValues(alpha: .12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: Icon(icon, size: 18, color: accent ?? colors.accent),
                  ),
                ),
              if (onTap != null) ...[
                const SizedBox(width: 4),
                Icon(Icons.chevron_right, size: 18, color: colors.textMuted),
              ],
            ],
          ),
          const SizedBox(height: 6),
          SizedBox(
            width: double.infinity,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                maxLines: 1,
                style: TextStyle(
                  fontSize: 32,
                  height: 1.2,
                  fontWeight: FontWeight.w900,
                  color: accent ?? colors.text,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ),
          if (caption != null) ...[
            const SizedBox(height: 4),
            Text(
              caption!,
              style: TextStyle(color: colors.textMuted, fontSize: 12.5),
            ),
          ],
          if (child != null) ...[const SizedBox(height: 14), child!],
        ],
      ),
    );
    return Semantics(
      button: onTap != null,
      label:
          '${onTap == null ? '' : '查看'}$label，$value${caption == null ? '' : '，$caption'}',
      excludeSemantics: true,
      child: KgzCard(onTap: onTap, child: content),
    );
  }
}

/// forui [FCard] that can optionally be tapped as a whole — the base of every
/// card in the app (summary, hero and section cards).
class KgzCard extends StatelessWidget {
  const KgzCard({required this.child, this.onTap, this.color, super.key});

  final Widget child;
  final VoidCallback? onTap;

  /// Background override (e.g. a muted inner card); defaults to the surface.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final card = FCard(
      clipBehavior: Clip.antiAlias,
      style: color == null
          ? const FCardStyleDelta.context()
          : FCardStyleDelta.delta(
              decoration: DecorationDelta.shapeDelta(color: color),
            ),
      child: child,
    );
    if (onTap == null) return card;
    return FTappable(onPress: onTap, excludeSemantics: true, child: card);
  }
}

/// A rounded progress track (Figma "Budget Progress"), drawn with forui's
/// [FDeterminateProgress].
class KgzProgressBar extends StatelessWidget {
  const KgzProgressBar({
    required this.value,
    this.color,
    this.height = 12,
    super.key,
  });

  /// 0–1; values outside the range are clamped.
  final double value;
  final Color? color;
  final double height;

  @override
  Widget build(BuildContext context) => FDeterminateProgress(
    value: value.clamp(0, 1).toDouble(),
    style: FDeterminateProgressStyleDelta.delta(
      constraints: BoxConstraints.tightFor(height: height),
      trackDecoration: DecorationDelta.boxDelta(
        color: context.colors.subtle,
        borderRadius: BorderRadius.circular(999),
      ),
      fillDecoration: DecorationDelta.boxDelta(
        color: color ?? context.colors.chartC,
        borderRadius: BorderRadius.circular(999),
      ),
    ),
  );
}

/// Card with a bold title and an optional trailing link (Figma "支出分析 ·
/// 本月 ›", "最近紀錄 · 查看全部").
class SectionCard extends StatelessWidget {
  const SectionCard({
    required this.title,
    required this.child,
    this.actionLabel,
    this.onAction,
    this.padding = const EdgeInsets.fromLTRB(20, 16, 20, 20),
    super.key,
  });

  final String title;
  final Widget child;
  final String? actionLabel;
  final VoidCallback? onAction;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => KgzCard(
    child: Padding(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              if (actionLabel != null)
                FButton(
                  variant: FButtonVariant.ghost,
                  size: FButtonSizeVariant.sm,
                  mainAxisSize: MainAxisSize.min,
                  onPress: onAction,
                  child: Text('$actionLabel ›'),
                ),
            ],
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    ),
  );
}

/// Keep secondary figures available without pushing the mobile list off screen.
class SecondaryMetrics extends StatelessWidget {
  const SecondaryMetrics({required this.child, super.key});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.sizeOf(context).width >= AppBreakpoints.mobile) return child;
    return FAccordion(
      children: [
        FAccordionItem(
          title: const Text('更多摘要', style: TextStyle(fontSize: 13)),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: child,
          ),
        ),
      ],
    );
  }
}

enum PillTone { ok, warn, action, muted, danger }

/// Small rounded status label (已核對 / 待收款 / 對帳 …).
class StatusPill extends StatelessWidget {
  const StatusPill(this.label, {this.tone = PillTone.muted, super.key});

  final String label;
  final PillTone tone;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final (background, foreground) = switch (tone) {
      PillTone.ok => (colors.incomePale, colors.income),
      PillTone.warn => (colors.warnPale, colors.warn),
      PillTone.action => (colors.accentPale, colors.accentPaleText),
      PillTone.danger => (colors.expensePale, colors.expense),
      PillTone.muted => (colors.subtle, colors.textMuted),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: foreground,
          fontSize: 11.5,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

/// Inline explanation under a list or form: info (accent wash) or warn.
class InfoNote extends StatelessWidget {
  const InfoNote(this.message, {this.warn = false, this.icon, super.key});

  final String message;
  final bool warn;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final foreground = warn ? colors.warn : colors.accentPaleText;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: warn ? colors.warnPale : colors.accentPale,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            icon ??
                (warn
                    ? Icons.warning_amber_rounded
                    : Icons.info_outline_rounded),
            size: 18,
            color: foreground,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: foreground, fontSize: 13, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}

/// Dashed secondary-navigation row ("帳戶間轉帳 ›").
class LinkRow extends StatelessWidget {
  const LinkRow({required this.label, this.onTap, this.icon, super.key});

  final String label;
  final VoidCallback? onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return FTappable(
      onPress: onTap,
      builder: (context, variants, child) => DecoratedBox(
        decoration: BoxDecoration(
          color: variants.contains(FTappableVariant.hovered)
              ? colors.accentPale
              : null,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: colors.border),
        ),
        child: child,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        child: Row(
          children: [
            if (icon != null) ...[
              Icon(icon, size: 18, color: colors.accent),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: colors.accent,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Icon(Icons.chevron_right, color: colors.accent, size: 20),
          ],
        ),
      ),
    );
  }
}

/// Pill tab bar for a page's secondary navigation (Figma segmented control:
/// rose in light mode, bright orange in dark mode).
class KgzTabBar<T> extends StatelessWidget {
  const KgzTabBar({
    required this.tabs,
    required this.selected,
    required this.onSelected,
    super.key,
  });

  final List<(T, String, IconData?)> tabs;
  final T selected;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.border),
        boxShadow: [
          BoxShadow(
            color: colors.cardShadow,
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          for (final (value, label, icon) in tabs)
            Expanded(
              child: FTappable(
                selected: value == selected,
                onPress: () => onSelected(value),
                builder: (context, variants, child) => AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  decoration: BoxDecoration(
                    color: value == selected
                        ? colors.selection
                        : variants.contains(FTappableVariant.hovered)
                        ? colors.subtle
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: child,
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (icon != null) ...[
                        Icon(
                          icon,
                          size: 18,
                          color: value == selected
                              ? colors.onSelection
                              : colors.textMuted,
                        ),
                        const SizedBox(width: 6),
                      ],
                      Flexible(
                        child: Text(
                          label,
                          maxLines: 1,
                          softWrap: false,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: value == selected
                                ? FontWeight.w800
                                : FontWeight.w500,
                            color: value == selected
                                ? colors.onSelection
                                : colors.textMuted,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// One entry of a [KgzPopoverMenu].
class KgzMenuEntry<T> {
  const KgzMenuEntry(
    this.value,
    this.label, {
    this.icon,
    this.destructive = false,
    this.enabled = true,
  });

  final T value;
  final String label;
  final IconData? icon;
  final bool destructive;
  final bool enabled;
}

/// Overflow / action menu on forui's [FPopoverMenu], replacing Material's
/// `PopupMenuButton`: an icon button that opens a list of [entries] and
/// reports the picked one through [onSelected].
///
/// [semanticsLabel] names the trigger for screen readers (and tests).
class KgzPopoverMenu<T> extends StatelessWidget {
  const KgzPopoverMenu({
    required this.entries,
    required this.onSelected,
    required this.semanticsLabel,
    this.icon = const Icon(FLucideIcons.ellipsisVertical),
    this.trigger,
    this.maxHeight = double.infinity,
    this.enabled = true,
    super.key,
  });

  final List<KgzMenuEntry<T>> entries;
  final ValueChanged<T> onSelected;
  final String semanticsLabel;
  final Widget icon;

  /// Custom trigger; it receives the callback that toggles the menu.
  final Widget Function(BuildContext context, VoidCallback toggle)? trigger;
  final double maxHeight;

  /// When false the trigger is shown disabled and the menu can't open.
  final bool enabled;

  @override
  Widget build(BuildContext context) => FPopoverMenu(
    maxHeight: maxHeight,
    menuAnchor: Alignment.topRight,
    childAnchor: Alignment.bottomRight,
    menuBuilder: (context, controller, _) => [
      FItemGroup(
        children: [
          for (final entry in entries)
            FItem(
              variant: entry.destructive
                  ? FItemVariant.destructive
                  : FItemVariant.primary,
              enabled: entry.enabled,
              prefix: entry.icon == null ? null : Icon(entry.icon),
              title: Text(entry.label),
              onPress: () {
                controller.hide();
                onSelected(entry.value);
              },
            ),
        ],
      ),
    ],
    builder: (context, controller, _) =>
        trigger?.call(context, controller.toggle) ??
        FButton.icon(
          variant: FButtonVariant.ghost,
          semanticsLabel: semanticsLabel,
          onPress: enabled ? controller.toggle : null,
          child: icon,
        ),
  );
}

/// One option of a [KgzSelect].
class KgzSelectItem<T> {
  const KgzSelectItem(
    this.value,
    this.label, {
    this.prefix,
    this.subtitle,
    this.enabled = true,
  });

  final T value;

  /// Shown in the list and, once picked, in the field itself.
  final String label;
  final Widget? prefix;
  final String? subtitle;
  final bool enabled;
}

/// Labelled single-choice form field on forui's [FSelect], replacing
/// Material's `DropdownButtonFormField`.
///
/// [value] is the initial selection only (like `initialValue` on the
/// Material field); give the widget a new key to reset it from outside.
/// Passing a null [onChanged] disables the field.
class KgzSelect<T> extends StatelessWidget {
  const KgzSelect({
    required this.items,
    required this.value,
    required this.onChanged,
    this.label,
    this.description,
    this.hint,
    this.validator,
    this.prefixIcon,
    super.key,
  });

  final List<KgzSelectItem<T>> items;
  final T? value;
  final ValueChanged<T?>? onChanged;
  final Widget? label;
  final Widget? description;
  final String? hint;
  final FormFieldValidator<T>? validator;
  final Widget? prefixIcon;

  String _format(T value) {
    for (final item in items) {
      if (item.value == value) return item.label;
    }
    return '';
  }

  @override
  Widget build(BuildContext context) => FSelect<T>.rich(
    control: FSelectControl.managed(initial: value, onChange: onChanged),
    format: _format,
    label: label,
    description: description,
    hint: hint,
    enabled: onChanged != null,
    validator: validator ?? (_) => null,
    prefixBuilder: prefixIcon == null
        ? null
        : (context, style, variants) => Padding(
            padding: const EdgeInsetsDirectional.only(start: 10, end: 2),
            child: prefixIcon,
          ),
    children: [
      for (final item in items)
        FSelectItem<T>(
          value: item.value,
          enabled: item.enabled,
          prefix: item.prefix,
          title: Text(item.label),
          subtitle: item.subtitle == null ? null : Text(item.subtitle!),
        ),
    ],
  );
}

/// Small filled color dot, e.g. a category color in front of its name.
class CategoryDot extends StatelessWidget {
  const CategoryDot({required this.color, this.size = 14, super.key});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: DecoratedBox(
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    ),
  );
}

/// Read-only value shown like a forui text field — e.g. a date that opens a
/// picker when tapped. Replaces Material's `InputDecorator` pattern.
class KgzValueField extends StatelessWidget {
  const KgzValueField({
    required this.label,
    required this.value,
    this.onTap,
    this.prefixIcon,
    this.description,
    this.error,
    super.key,
  });

  final String label;
  final String value;
  final VoidCallback? onTap;
  final Widget? prefixIcon;
  final String? description;
  final String? error;

  @override
  Widget build(BuildContext context) => FTextField(
    control: FTextFieldControl.lifted(
      value: TextEditingValue(text: value),
      onChange: (_) {},
    ),
    readOnly: true,
    canRequestFocus: onTap != null,
    enableInteractiveSelection: false,
    onTap: onTap,
    label: Text(label),
    description: description == null ? null : Text(description!),
    error: error == null ? null : Text(error!),
    prefixBuilder: prefixIcon == null
        ? null
        : (context, style, variants) => Padding(
            padding: const EdgeInsetsDirectional.only(start: 10, end: 2),
            child: prefixIcon,
          ),
    suffixBuilder: onTap == null
        ? null
        : (context, style, variants) => const Padding(
            padding: EdgeInsetsDirectional.only(end: 10),
            child: Icon(FLucideIcons.chevronDown, size: 18),
          ),
  );
}
