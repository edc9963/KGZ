import 'package:flutter/material.dart';

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
    super.key,
  });

  final String label;
  final Widget? tabs;

  static WorkspaceScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<WorkspaceScope>();

  static String? maybeLabelOf(BuildContext context) => maybeOf(context)?.label;

  @override
  bool updateShouldNotify(WorkspaceScope oldWidget) =>
      label != oldWidget.label || tabs != oldWidget.tabs;
}

/// Drop-in replacement for [AlertDialog] used by every form in the app.
///
/// On phones (< [AppBreakpoints.mobile]) it becomes a full-width sheet
/// anchored to the bottom edge — rounded top corners, a grab handle, a
/// large title and actions stretched to equal-width buttons — matching the
/// Figma quick-entry sheet. On wider screens it stays a centered dialog.
/// It still builds an [AlertDialog] underneath, so semantics, focus
/// handling and `find.byType(AlertDialog)` keep working unchanged.
class KgzDialog extends StatelessWidget {
  const KgzDialog({
    this.title,
    this.content,
    this.actions,
    this.icon,
    this.scrollable = false,
    this.insetPadding,
    this.contentPadding,
    this.titlePadding,
    this.actionsAlignment,
    this.shape,
    super.key,
  });

  final Widget? title;
  final Widget? content;
  final List<Widget>? actions;
  final Widget? icon;
  final bool scrollable;
  final EdgeInsets? insetPadding;
  final EdgeInsetsGeometry? contentPadding;
  final EdgeInsetsGeometry? titlePadding;
  final MainAxisAlignment? actionsAlignment;
  final ShapeBorder? shape;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final phone = MediaQuery.sizeOf(context).width < AppBreakpoints.mobile;
    final titleStyle = Theme.of(context).textTheme.headlineSmall?.copyWith(
      fontWeight: FontWeight.w900,
      color: colors.text,
    );
    if (!phone) {
      return AlertDialog(
        title: title,
        titleTextStyle: titleStyle,
        content: content,
        actions: actions,
        icon: icon,
        scrollable: scrollable,
        insetPadding: insetPadding,
        contentPadding: contentPadding,
        titlePadding: titlePadding,
        actionsAlignment: actionsAlignment,
        shape: shape,
        actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
      );
    }
    final buttons = actions ?? const <Widget>[];
    return AlertDialog(
      alignment: Alignment.bottomCenter,
      insetPadding: insetPadding ?? EdgeInsets.zero,
      shape:
          shape ??
          const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
      icon: icon,
      scrollable: scrollable,
      titlePadding: titlePadding ?? const EdgeInsets.fromLTRB(24, 10, 24, 0),
      contentPadding:
          contentPadding ?? const EdgeInsets.fromLTRB(24, 16, 24, 8),
      title: title == null
          ? null
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 14),
                    decoration: BoxDecoration(
                      color: colors.border,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                DefaultTextStyle.merge(style: titleStyle, child: title!),
              ],
            ),
      content: content,
      actionsPadding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
      actions: buttons.isEmpty
          ? null
          : [
              Row(
                children: [
                  for (var index = 0; index < buttons.length; index++) ...[
                    if (index > 0) const SizedBox(width: 10),
                    Expanded(child: buttons[index]),
                  ],
                ],
              ),
            ],
    );
  }
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
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
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
                  fontSize: 34,
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
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: onTap == null ? content : InkWell(onTap: onTap, child: content),
      ),
    );
  }
}

/// A rounded progress track (Figma "Budget Progress").
class KgzProgressBar extends StatelessWidget {
  const KgzProgressBar({required this.value, this.color, super.key});

  /// 0–1; values outside the range are clamped.
  final double value;
  final Color? color;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(999),
    child: LinearProgressIndicator(
      value: value.clamp(0, 1).toDouble(),
      minHeight: 12,
      color: color ?? context.colors.chartC,
      backgroundColor: context.colors.subtle,
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
  Widget build(BuildContext context) => Card(
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
                TextButton(
                  style: TextButton.styleFrom(
                    minimumSize: const Size(0, 36),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    textStyle: const TextStyle(
                      fontFamily: 'Noto Sans TC',
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  onPressed: onAction,
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
    return Material(
      color: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: colors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
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
        borderRadius: BorderRadius.circular(16),
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
              child: Semantics(
                selected: value == selected,
                button: true,
                child: Material(
                  color: value == selected
                      ? colors.selection
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => onSelected(value),
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
              ),
            ),
        ],
      ),
    );
  }
}
