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
    this.tone,
    this.caption,
    this.onTap,
    super.key,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color? tone;
  final String? caption;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final color = tone ?? Theme.of(context).colorScheme.primary;
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ColoredBox(color: color, child: const SizedBox(height: 3)),
        Padding(
          padding: const EdgeInsets.all(20),
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
                      padding: const EdgeInsets.all(8),
                      child: Icon(icon, color: color, size: 20),
                    ),
                  ),
                  const Spacer(),
                  Flexible(
                    child: Text(
                      label,
                      textAlign: TextAlign.end,
                      style: const TextStyle(color: AppColors.textMuted),
                    ),
                  ),
                  if (onTap != null) ...[
                    const SizedBox(width: 4),
                    const Icon(
                      Icons.chevron_right,
                      size: 18,
                      color: AppColors.textMuted,
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 18),
              Text(
                value,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: color,
                ),
              ),
              if (caption != null) ...[
                const SizedBox(height: 6),
                Text(
                  caption!,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: AppColors.textMuted),
                ),
              ],
            ],
          ),
        ),
      ],
    );
    return Card(
      clipBehavior: Clip.antiAlias,
      child: onTap == null
          ? content
          : Semantics(
              button: true,
              label: '查看$label',
              child: InkWell(onTap: onTap, child: content),
            ),
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
    super.key,
  });

  final List<Widget> children;
  final double minWidth;
  final double spacing;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final columns = (constraints.maxWidth / minWidth).floor().clamp(1, 4);
      final width = (constraints.maxWidth - spacing * (columns - 1)) / columns;
      return Wrap(
        spacing: spacing,
        runSpacing: spacing,
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
