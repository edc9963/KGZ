import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../application/providers.dart';
import '../../domain/models.dart';
import '../design_tokens.dart';
import '../transaction_display.dart';
import '../widgets/common.dart';

class DashboardPage extends ConsumerStatefulWidget {
  const DashboardPage({super.key});

  @override
  ConsumerState<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends ConsumerState<DashboardPage> {
  bool? _otherExpanded;

  @override
  Widget build(BuildContext context) {
    final store = ref.watch(appStoreProvider);
    final settings = store.data.settings;
    final mask = settings.maskBalances;
    final desktop = MediaQuery.sizeOf(context).width >= 1100;
    _otherExpanded ??= false;
    final records = transactionDisplayRecords(store);
    // Each of these is read more than once below (net worth is itself built
    // from the deposit/investment/receivables/card figures, and the "其他
    // 財務摘要" section repeats several of them again), so they're computed
    // once here and reused instead of calling the store getter again at
    // each call site.
    final netWorth = store.netWorthMinor;
    final currentMonthIncome = store.currentMonthIncomeDefaultMinor;
    final currentMonthExpense = store.currentMonthExpenseDefaultMinor;
    final pendingCard = store.pendingCardDefaultMinor;
    final depositTotal = store.depositTotalMinor;
    final investmentValue = store.investmentValueMinor;
    final receivables = store.receivablesDefaultMinor;
    final collectionResult = store.currentMonthCollectionResultDefaultMinor;
    final currency = settings.defaultCurrency;
    final now = DateTime.now();
    final monthBalance = currentMonthIncome - currentMonthExpense;
    final spentRatio = currentMonthIncome <= 0
        ? (currentMonthExpense > 0 ? 1.0 : 0.0)
        : currentMonthExpense / currentMonthIncome;
    final daysLeft = DateTime(now.year, now.month + 1, 0).day - now.day;
    final monthSpending = <String, int>{};
    for (final record in records) {
      if (record.isIncome ||
          record.currency != currency ||
          record.date.year != now.year ||
          record.date.month != now.month) {
        continue;
      }
      monthSpending.update(
        record.category,
        (value) => value + record.amountMinor,
        ifAbsent: () => record.amountMinor,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PageHeader(
          title: '財務總覽',
          subtitle: DateFormat('yyyy 年 M 月', 'zh_TW').format(DateTime.now()),
          action: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton.filledTonal(
                tooltip: mask ? '顯示金額' : '隱藏金額',
                onPressed: () => store.updateSettings(
                  settings.copyWith(maskBalances: !mask),
                ),
                icon: Icon(
                  mask
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                ),
              ),
              if (desktop) ...[
                const SizedBox(width: 10),
                FilledButton.icon(
                  onPressed: store.canWrite
                      ? () => context.go('/expenses?create=expense')
                      : null,
                  icon: const Icon(Icons.add),
                  label: const Text('記一筆'),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 24),
        if (store.currenciesMissingFx.isNotEmpty) ...[
          InfoNote(
            '缺少 ${store.currenciesMissingFx.join('、')} 對 '
            '${settings.defaultCurrency} 匯率，相關資產未納入總額。',
            warn: true,
            icon: Icons.currency_exchange,
          ),
          const SizedBox(height: 16),
        ],
        // Figma "本月剩餘預算" hero: this month's income minus spending, how
        // much of the income is already spent, and the days left.
        HeroMetricCard(
          label: '本月結餘',
          value: moneyText(monthBalance, currency: currency, mask: mask),
          badge: StatusPill(
            spentRatio <= .8 ? '● 節奏良好' : '● 支出偏高',
            tone: spentRatio <= .8 ? PillTone.ok : PillTone.warn,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Text(
                    '已花費 ${(spentRatio * 100).round()}%',
                    style: TextStyle(
                      color: context.colors.textMuted,
                      fontSize: 12.5,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '距月底 $daysLeft 天',
                    style: TextStyle(
                      color: context.colors.textMuted,
                      fontSize: 12.5,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              KgzProgressBar(
                value: spentRatio,
                color: spentRatio > .8 ? context.colors.chartA : null,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _HeroFigure(
                      label: '收入',
                      value:
                          '+ ${moneyText(currentMonthIncome, currency: currency, mask: mask)}',
                      color: context.colors.income,
                    ),
                  ),
                  _HeroFigure(
                    label: '支出',
                    value:
                        '− ${moneyText(currentMonthExpense, currency: currency, mask: mask)}',
                    color: context.colors.expense,
                    end: true,
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        ResponsiveGrid(
          minWidth: 160,
          spacing: 12,
          children: [
            SummaryCard(
              label: '淨資產',
              value: moneyText(
                netWorth,
                currency: settings.defaultCurrency,
                mask: mask,
              ),
              compactValue: compactMoneyText(
                netWorth,
                currency: settings.defaultCurrency,
                mask: mask,
              ),
              icon: Icons.auto_graph_rounded,
              tone: context.colors.asset,
              onTap: () => context.go('/reports'),
            ),
            SummaryCard(
              label: '本月收入',
              value: moneyText(
                currentMonthIncome,
                currency: settings.defaultCurrency,
                mask: mask,
              ),
              compactValue: compactMoneyText(
                currentMonthIncome,
                currency: settings.defaultCurrency,
                mask: mask,
              ),
              icon: Icons.south_west_rounded,
              tone: context.colors.income,
              onTap: () => context.go('/expenses'),
            ),
            SummaryCard(
              label: '本月支出',
              value: moneyText(
                currentMonthExpense,
                currency: settings.defaultCurrency,
                mask: mask,
              ),
              compactValue: compactMoneyText(
                currentMonthExpense,
                currency: settings.defaultCurrency,
                mask: mask,
              ),
              icon: Icons.north_east_rounded,
              tone: context.colors.expense,
              onTap: () => context.go('/expenses'),
            ),
            SummaryCard(
              label: '信用卡待繳',
              value: moneyText(
                pendingCard,
                currency: settings.defaultCurrency,
                mask: mask,
              ),
              compactValue: compactMoneyText(
                pendingCard,
                currency: settings.defaultCurrency,
                mask: mask,
              ),
              icon: Icons.credit_card_outlined,
              tone: context.colors.liability,
              onTap: () => context.go('/cards'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _SpendingCard(spending: monthSpending, currency: currency, mask: mask),
        const SizedBox(height: 12),
        Card(
          child: ExpansionTile(
            initiallyExpanded: _otherExpanded!,
            onExpansionChanged: (value) => _otherExpanded = value,
            title: const Text(
              '其他財務摘要',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            subtitle: const Text('存款、投資、代墊與代收結果'),
            childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            children: [
              ResponsiveGrid(
                minWidth: 180,
                spacing: 12,
                children: [
                  SummaryCard(
                    label: '存款合計',
                    value: moneyText(
                      depositTotal,
                      currency: settings.defaultCurrency,
                      mask: mask,
                    ),
                    compactValue: compactMoneyText(
                      depositTotal,
                      currency: settings.defaultCurrency,
                      mask: mask,
                    ),
                    icon: Icons.account_balance_wallet_outlined,
                    tone: context.colors.asset,
                    onTap: () => context.go('/accounts'),
                  ),
                  SummaryCard(
                    label: '投資現值',
                    value: moneyText(
                      investmentValue,
                      currency: settings.defaultCurrency,
                      mask: mask,
                    ),
                    compactValue: compactMoneyText(
                      investmentValue,
                      currency: settings.defaultCurrency,
                      mask: mask,
                    ),
                    icon: Icons.trending_up_rounded,
                    tone: context.colors.chartB,
                    onTap: () => context.go('/investments'),
                  ),
                  SummaryCard(
                    label: '代墊應收款',
                    value: moneyText(
                      receivables,
                      currency: settings.defaultCurrency,
                      mask: mask,
                    ),
                    compactValue: compactMoneyText(
                      receivables,
                      currency: settings.defaultCurrency,
                      mask: mask,
                    ),
                    icon: Icons.handshake_outlined,
                    tone: context.colors.warn,
                    onTap: () => context.go('/orders'),
                  ),
                  SummaryCard(
                    label: collectionResult >= 0 ? '本月代收收益' : '本月代收損失',
                    value: moneyText(
                      collectionResult.abs(),
                      currency: settings.defaultCurrency,
                      mask: mask,
                    ),
                    compactValue: compactMoneyText(
                      collectionResult.abs(),
                      currency: settings.defaultCurrency,
                      mask: mask,
                    ),
                    icon: collectionResult >= 0
                        ? Icons.trending_up
                        : Icons.trending_down,
                    tone: collectionResult >= 0
                        ? context.colors.income
                        : context.colors.expense,
                    onTap: () => context.go('/orders'),
                  ),
                ],
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () => context.go('/reports'),
                  icon: const Icon(Icons.insert_chart_outlined_rounded),
                  label: const Text('查看完整報表'),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 850;
            final reminder = _ReminderCard(
              reminders: store.reminders,
              onAcknowledge: store.canWrite
                  ? (billId) => store.acknowledgeBillReminder(billId)
                  : null,
            );
            final activity = _RecentActivityCard(records: records, mask: mask);
            if (!wide) {
              return Column(
                children: [reminder, const SizedBox(height: 16), activity],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 4, child: reminder),
                const SizedBox(width: 16),
                Expanded(flex: 6, child: activity),
              ],
            );
          },
        ),
        if (store.data.accounts.isEmpty) ...[
          const SizedBox(height: 20),
          Card(
            color: context.colors.assetPale,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  Icon(
                    Icons.tips_and_updates_outlined,
                    color: context.colors.asset,
                  ),
                  const SizedBox(width: 14),
                  const Expanded(child: Text('新增第一個帳戶，開始掌握收支與資產。')),
                  FilledButton(
                    onPressed: () => context.go('/accounts'),
                    child: const Text('新增帳戶'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _RecentActivityCard extends StatelessWidget {
  const _RecentActivityCard({required this.records, required this.mask});

  final List<TransactionDisplayRecord> records;
  final bool mask;

  @override
  Widget build(BuildContext context) => SectionCard(
    title: '最近紀錄',
    actionLabel: '查看全部',
    onAction: () => context.go('/expenses'),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (records.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 32),
            child: Center(child: Text('還沒有收支紀錄')),
          )
        else
          for (final record in records.take(5))
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: CategoryAvatar(category: record.category),
              title: Row(
                children: [
                  Flexible(child: Text(record.item)),
                  const SizedBox(width: 8),
                  CategoryBadge(category: record.category),
                ],
              ),
              subtitle: Text(dateText(record.date)),
              trailing: Text(
                '${record.isIncome ? '+' : '-'}${moneyText(record.amountMinor, currency: record.currency, mask: mask)}',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: record.isIncome
                      ? context.colors.income
                      : context.colors.expense,
                ),
              ),
            ),
      ],
    ),
  );
}

class _ReminderCard extends StatelessWidget {
  const _ReminderCard({required this.reminders, this.onAcknowledge});
  final List<ReminderItem> reminders;
  // Called with a reminder's `billId` when the user confirms they've seen
  // it; null while the user can't write (read-only session).
  final ValueChanged<String>? onAcknowledge;

  @override
  Widget build(BuildContext context) => SectionCard(
    title: '今日待處理',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (reminders.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Row(
              children: [
                Icon(Icons.check_circle_outline, color: context.colors.income),
                const SizedBox(width: 10),
                const Text('今天沒有待處理提醒'),
              ],
            ),
          )
        else
          for (final reminder in reminders)
            Card(
              margin: const EdgeInsets.only(bottom: 10),
              elevation: 0,
              color: reminder.isWarning
                  ? context.colors.warnPale
                  : context.colors.accentPale,
              clipBehavior: Clip.antiAlias,
              child: Semantics(
                button: true,
                label: '前往處理${reminder.title}',
                child: InkWell(
                  onTap: () => context.go(switch (reminder.destination) {
                    ReminderDestination.cards => '/cards',
                    ReminderDestination.expenses => '/expenses',
                  }),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      children: [
                        Icon(
                          reminder.isWarning
                              ? Icons.warning_amber_rounded
                              : Icons.notifications_none,
                          color: reminder.isWarning
                              ? context.colors.warn
                              : context.colors.accent,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                reminder.title,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              Text(reminder.subtitle),
                              if (reminder.isWarning)
                                Text(
                                  '扣款帳戶餘額可能不足',
                                  style: TextStyle(
                                    color: context.colors.warn,
                                    fontSize: 12,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        if (reminder.billId != null && onAcknowledge != null)
                          IconButton(
                            tooltip: '已確認，這筆帳單不用再提醒',
                            icon: const Icon(Icons.check_circle_outline),
                            onPressed: () => onAcknowledge!(reminder.billId!),
                          ),
                        const Icon(Icons.chevron_right),
                      ],
                    ),
                  ),
                ),
              ),
            ),
      ],
    ),
  );
}

/// Small label + colored figure under the dashboard hero's progress bar.
class _HeroFigure extends StatelessWidget {
  const _HeroFigure({
    required this.label,
    required this.value,
    required this.color,
    this.end = false,
  });

  final String label;
  final String value;
  final Color color;
  final bool end;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: end ? CrossAxisAlignment.end : CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: TextStyle(color: context.colors.textMuted, fontSize: 12),
      ),
      Text(
        value,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w800,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    ],
  );
}

/// Figma "支出分析": a donut of this month's spending by category beside a
/// bar per category, both in each category's own color.
class _SpendingCard extends StatelessWidget {
  const _SpendingCard({
    required this.spending,
    required this.currency,
    required this.mask,
  });

  final Map<String, int> spending;
  final String currency;
  final bool mask;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final entries = spending.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final top = entries.take(5).toList();
    final total = entries.fold<int>(0, (sum, entry) => sum + entry.value);
    return SectionCard(
      title: '支出分析',
      actionLabel: '本月',
      onAction: () => context.go('/reports'),
      child: total <= 0
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text(
                  '本月還沒有支出',
                  style: TextStyle(color: colors.textMuted),
                ),
              ),
            )
          : Row(
              children: [
                SizedBox.square(
                  dimension: 120,
                  child: CustomPaint(
                    painter: _DonutPainter([
                      for (final entry in top)
                        (
                          entry.value / total,
                          categoryVisual(entry.key, colors).color,
                        ),
                    ], colors.subtle),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            top.first.key,
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 13,
                            ),
                          ),
                          Text(
                            '${(top.first.value * 100 / total).round()}%',
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 15,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: Column(
                    children: [
                      for (final entry in top)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            children: [
                              SizedBox(
                                width: 56,
                                child: Text(
                                  entry.key,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 12.5),
                                ),
                              ),
                              Expanded(
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(999),
                                  child: LinearProgressIndicator(
                                    value: entry.value / top.first.value,
                                    minHeight: 8,
                                    color: categoryVisual(
                                      entry.key,
                                      colors,
                                    ).color,
                                    backgroundColor: colors.subtle,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Text(
                                mask
                                    ? '••••'
                                    : '${(entry.value * 100 / total).round()}%',
                                style: const TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

class _DonutPainter extends CustomPainter {
  _DonutPainter(this.parts, this.track);

  final List<(double, Color)> parts;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 18.0;
    final rect = (Offset.zero & size).deflate(stroke / 2);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;
    canvas.drawArc(rect, 0, math.pi * 2, false, paint..color = track);
    var start = -math.pi / 2;
    for (final (fraction, color) in parts) {
      final sweep = fraction * math.pi * 2;
      canvas.drawArc(
        rect,
        start,
        math.max(sweep - .04, .01),
        false,
        paint..color = color,
      );
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(_DonutPainter oldDelegate) =>
      oldDelegate.parts != parts || oldDelegate.track != track;
}
