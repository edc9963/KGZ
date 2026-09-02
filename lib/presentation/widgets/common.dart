import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../application/app_store.dart';
import '../design_tokens.dart';

String moneyText(int minor, {String currency = 'TWD', bool mask = false}) {
  if (mask) return '$currency ••••••';
  final digits = currency == 'TWD' || currency == 'JPY' ? 0 : 2;
  return NumberFormat.currency(
    locale: 'zh_TW',
    symbol: currency == 'TWD' ? r'NT$' : currency,
    decimalDigits: digits,
  ).format(minor / 100);
}

String compactMoneyText(
  int minor, {
  String currency = 'TWD',
  bool mask = false,
}) {
  if (mask) return '$currency ••••••';
  final major = minor / 100;
  if (major.abs() < 10000) {
    return moneyText(minor, currency: currency);
  }
  final divisor = major.abs() >= 100000000 ? 100000000 : 10000;
  final unit = divisor == 100000000 ? '億' : '萬';
  final scaled = major.abs() / divisor;
  final truncated = (scaled * 10).floor() / 10;
  final amount = NumberFormat('0.#', 'zh_TW').format(truncated);
  final sign = minor < 0 ? '-' : '';
  final symbol = currency == 'TWD' ? r'NT$' : currency;
  return '$sign$symbol$amount$unit';
}

String dateText(DateTime date) => DateFormat('yyyy/MM/dd').format(date);

int parseMoney(String text) =>
    ((double.tryParse(text.replaceAll(',', '')) ?? 0) * 100).round();

double parseQuantity(String text) =>
    double.tryParse(text.replaceAll(',', '')) ?? 0;

class PageHeader extends StatelessWidget {
  const PageHeader({
    required this.title,
    required this.subtitle,
    this.action,
    super.key,
  });

  final String title;
  final String subtitle;
  final Widget? action;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final heading = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: AppColors.textMuted),
          ),
        ],
      );
      if (constraints.maxWidth < AppBreakpoints.mobile && action != null) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            heading,
            const SizedBox(height: 14),
            Align(alignment: Alignment.centerLeft, child: action!),
          ],
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: heading),
          if (action != null) ...[
            const SizedBox(width: 16),
            Flexible(child: action!),
          ],
        ],
      );
    },
  );
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    required this.icon,
    required this.title,
    required this.message,
    this.action,
    super.key,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 16),
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(message, textAlign: TextAlign.center),
          if (action != null) ...[const SizedBox(height: 16), action!],
        ],
      ),
    ),
  );
}

class SummaryCard extends StatelessWidget {
  const SummaryCard({
    required this.label,
    required this.value,
    required this.icon,
    this.compactValue,
    this.tone,
    this.caption,
    this.onTap,
    super.key,
  });

  final String label;
  final String value;
  final String? compactValue;
  final IconData icon;
  final Color? tone;
  final String? caption;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final color = tone ?? Theme.of(context).colorScheme.primary;
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 200;
        final valueStyle =
            (compact
                    ? Theme.of(context).textTheme.titleLarge
                    : Theme.of(context).textTheme.headlineSmall)
                ?.copyWith(fontWeight: FontWeight.w800, color: color);
        final valuePainter = TextPainter(
          text: TextSpan(text: value, style: valueStyle),
          maxLines: 1,
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
        )..layout();
        final valueWidth = constraints.maxWidth - (compact ? 28 : 40);
        const minimumFullValueScale = .64;
        final useCompactValue =
            compact &&
            compactValue != null &&
            valuePainter.width * minimumFullValueScale > valueWidth;
        final shownValue = useCompactValue ? compactValue! : value;
        final content = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ColoredBox(color: color, child: const SizedBox(height: 3)),
            Padding(
              padding: EdgeInsets.all(compact ? 14 : 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: .12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Padding(
                          padding: EdgeInsets.all(compact ? 6 : 8),
                          child: Icon(
                            icon,
                            color: color,
                            size: compact ? 18 : 20,
                          ),
                        ),
                      ),
                      SizedBox(width: compact ? 8 : 12),
                      Expanded(
                        child: Text(
                          label,
                          textAlign: TextAlign.end,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: AppColors.textMuted),
                        ),
                      ),
                      if (onTap != null) ...[
                        const SizedBox(width: 4),
                        Icon(
                          Icons.chevron_right,
                          size: compact ? 16 : 18,
                          color: AppColors.textMuted,
                        ),
                      ],
                    ],
                  ),
                  SizedBox(height: compact ? 12 : 18),
                  SizedBox(
                    width: double.infinity,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(shownValue, maxLines: 1, style: valueStyle),
                    ),
                  ),
                  if (caption != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      caption!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        );
        return Semantics(
          button: onTap != null,
          label:
              '${onTap == null ? '' : '查看'}$label，$value${caption == null ? '' : '，$caption'}',
          excludeSemantics: true,
          child: Card(
            clipBehavior: Clip.antiAlias,
            child: onTap == null
                ? content
                : InkWell(onTap: onTap, child: content),
          ),
        );
      },
    );
  }
}

class CategoryBadge extends StatelessWidget {
  const CategoryBadge({required this.category, super.key});

  final String category;

  @override
  Widget build(BuildContext context) {
    final visual = categoryVisual(category);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: visual.pale,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        category,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: visual.color,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class CategoryAvatar extends StatelessWidget {
  const CategoryAvatar({required this.category, super.key});

  final String category;

  @override
  Widget build(BuildContext context) {
    final visual = categoryVisual(category);
    return CircleAvatar(
      backgroundColor: visual.pale,
      foregroundColor: visual.color,
      child: Icon(visual.icon),
    );
  }
}

class ResponsiveGrid extends StatelessWidget {
  const ResponsiveGrid({
    required this.children,
    this.minWidth = 230,
    this.spacing = 16,
    this.mobileSpacing = 12,
    this.mobileColumns = 2,
    super.key,
  });

  final List<Widget> children;
  final double minWidth;
  final double spacing;
  final double mobileSpacing;
  final int mobileColumns;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      if (children.isEmpty) return const SizedBox.shrink();
      final mobile = constraints.maxWidth < AppBreakpoints.mobile;
      final effectiveSpacing = mobile ? mobileSpacing : spacing;
      final columns = mobile
          ? mobileColumns.clamp(1, children.length)
          : (constraints.maxWidth / minWidth).floor().clamp(
              1,
              children.length.clamp(1, 4),
            );
      final width =
          (constraints.maxWidth - effectiveSpacing * (columns - 1)) / columns;
      return Wrap(
        spacing: effectiveSpacing,
        runSpacing: effectiveSpacing,
        children: children
            .map((child) => SizedBox(width: width, child: child))
            .toList(),
      );
    },
  );
}

Future<bool> confirmDelete(BuildContext context, String label) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('刪除$label？'),
        content: const Text('相關金額將立即重新計算，此動作無法復原。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('刪除'),
          ),
        ],
      ),
    ) ??
    false;

void showSaved(BuildContext context, [String message = '已儲存']) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

String accountName(AppStore store, String? id) =>
    store.accountById(id)?.name ?? '未指定';
