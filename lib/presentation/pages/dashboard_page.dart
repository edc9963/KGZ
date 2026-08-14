import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../application/providers.dart';
import '../../domain/models.dart';
import '../design_tokens.dart';
import '../transaction_display.dart';
import '../widgets/common.dart';

class DashboardPage extends ConsumerWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final store = ref.watch(appStoreProvider);
    final settings = store.data.settings;
    final mask = settings.maskBalances;
    final records = transactionDisplayRecords(store);

    return LayoutBuilder(
      builder: (context, constraints) {
        final desktop = constraints.maxWidth >= AppBreakpoints.desktop;
        final mobile = constraints.maxWidth < AppBreakpoints.mobile;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PageHeader(
              title: '財務總覽',
              subtitle: '${DateFormat('yyyy 年 M 月', 'zh_TW').format(DateTime.now())}・掌握本月現金流與待辦',
              action: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Tooltip(
                    message: mask ? '顯示所有金額' : '隱藏所有金額',
                    child: Semantics(
                      button: true,
                      label: mask ? '顯示所有金額' : '隱藏所有金額',
                      child: IconButton.filledTonal(
                        onPressed: () => store.updateSettings(
                          settings.copyWith(maskBalances: !mask),
                        ),
                        icon: Icon(
                          mask
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                        ),
                      ),
                    ),
                  ),
                  if (!mobile) ...[
                    const SizedBox(width: 10),
                    FilledButton.icon(
                      onPressed: store.canWrite
                          ? () => context.go('/expenses?create=expense')
                          : null,
                      icon: const Icon(Icons.add),
                      label: const Text('快速記帳'),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 24),
            if (store.currenciesMissingFx.isNotEmpty) ...[
              _NoticeBanner(
                icon: Icons.currency_exchange_rounded,
                title: '部分資產尚未計入',
                message:
                    '缺少 ${store.currenciesMissingFx.join('、')} 對 ${settings.defaultCurrency} 匯率，總額可能低於實際金額。',
                actionLabel: '前往設定',
                onAction: () => context.go('/settings'),
              ),
              const SizedBox(height: 16),
            ],
            _PrimaryOverview(
              desktop: desktop,
              mask: mask,
              currency: settings.defaultCurrency,
              netWorth: store.netWorthMinor,
              income: store.currentMonthIncomeDefaultMinor,
              expense: store.currentMonthExpenseDefaultMinor,
              pendingCard: store.pendingCardDefaultMinor,
            ),
            const SizedBox(height: 24),
            const _SectionHeading(
              title: '資產與往來',
              subtitle: '快速查看各類資產與本月代收結果',
            ),
            const SizedBox(height: 12),
            ResponsiveGrid(
              minWidth: mobile ? 150 : 190,
              spacing: 12,
              children: [
                _CompactMetric(
                  label: '存款合計',
                  value: moneyText(
                    store.depositTotalMinor,
                    currency: settings.defaultCurrency,
                    mask: mask,
                  ),
                  icon: Icons.account_balance_wallet_outlined,
                  tone: AppColors.asset,
                  onTap: () => context.go('/accounts'),
                ),
                _CompactMetric(
                  label: '投資現值',
                  value: moneyText(
                    store.investmentValueMinor,
                    currency: settings.defaultCurrency,
                    mask: mask,
                  ),
                  icon: Icons.show_chart_rounded,
                  tone: const Color(0xFF6075A6),
                  onTap: () => context.go('/investments'),
                ),
                _CompactMetric(
                  label: '代墊應收款',
                  value: moneyText(
                    store.receivablesDefaultMinor,
                    currency: settings.defaultCurrency,
                    mask: mask,
                  ),
                  icon: Icons.handshake_outlined,
                  tone: AppColors.liability,
                  onTap: () => context.go('/orders'),
                ),
                _CompactMetric(
                  label: store.currentMonthCollectionResultDefaultMinor >= 0
                      ? '本月代收收益'
                      : '本月代收損失',
                  value:
                      '${store.currentMonthCollectionResultDefaultMinor >= 0 ? '+' : '-'}${moneyText(store.currentMonthCollectionResultDefaultMinor.abs(), currency: settings.defaultCurrency, mask: mask)}',
                  icon: store.currentMonthCollectionResultDefaultMinor >= 0
                      ? Icons.trending_up_rounded
                      : Icons.trending_down_rounded,
                  tone: store.currentMonthCollectionResultDefaultMinor >= 0
                      ? AppColors.income
                      : AppColors.expense,
                  onTap: () => context.go('/orders'),
                ),
              ],
            ),
            const SizedBox(height: 24),
            LayoutBuilder(
              builder: (context, lowerConstraints) {
                final twoColumns = lowerConstraints.maxWidth >= 820;
                final reminder = _ReminderCard(reminders: store.reminders);
                final activity = _RecentActivityCard(
                  records: records,
                  mask: mask,
                );
                if (!twoColumns) {
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
              _EmptyDataBanner(onAction: () => context.go('/settings')),
            ],
          ],
        );
      },
    );
  }
}

class _PrimaryOverview extends StatelessWidget {
  const _PrimaryOverview({
    required this.desktop,
    required this.mask,
    required this.currency,
    required this.netWorth,
    required this.income,
    required this.expense,
    required this.pendingCard,
  });

  final bool desktop;
  final bool mask;
  final String currency;
  final int netWorth;
  final int income;
  final int expense;
  final int pendingCard;

  @override
  Widget build(BuildContext context) {
    final hero = _NetWorthCard(
      value: moneyText(netWorth, currency: currency, mask: mask),
      onTap: () => context.go('/reports'),
    );
    final monthly = ResponsiveGrid(
      minWidth: 170,
      spacing: 12,
      children: [
        _MonthlyMetric(
          label: '本月收入',
          value: '+${moneyText(income, currency: currency, mask: mask)}',
          icon: Icons.south_west_rounded,
          tone: AppColors.income,
          onTap: () => context.go('/expenses'),
        ),
        _MonthlyMetric(
          label: '本月支出',
          value: '-${moneyText(expense, currency: currency, mask: mask)}',
          caption: '不含投資與信用卡繳款',
          icon: Icons.north_east_rounded,
          tone: AppColors.expense,
          onTap: () => context.go('/expenses'),
        ),
        _MonthlyMetric(
          label: '信用卡待繳',
          value: moneyText(pendingCard, currency: currency, mask: mask),
          caption: '尚未繳清帳單',
          icon: Icons.credit_card_outlined,
          tone: AppColors.liability,
          onTap: () => context.go('/cards'),
        ),
      ],
    );

    if (!desktop) {
      return Column(children: [hero, const SizedBox(height: 12), monthly]);
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(flex: 4, child: hero),
        const SizedBox(width: 12),
        Expanded(flex: 6, child: monthly),
      ],
    );
  }
}

class _NetWorthCard extends StatelessWidget {
  const _NetWorthCard({required this.value, required this.onTap});
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
    margin: EdgeInsets.zero,
    clipBehavior: Clip.antiAlias,
    child: Semantics(
      button: true,
      label: '查看淨資產報表，$value',
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: AppColors.assetPale,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.account_balance_wallet_outlined,
                      color: AppColors.asset,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      '淨資產',
                      style: TextStyle(
                        color: AppColors.textMuted,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const Icon(Icons.arrow_forward_rounded, size: 20),
                ],
              ),
              const SizedBox(height: 22),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  value,
                  maxLines: 1,
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    color: AppColors.text,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -.6,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                '所有資產扣除信用卡待繳',
                style: TextStyle(color: AppColors.textMuted, fontSize: 13),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _MonthlyMetric extends StatelessWidget {
  const _MonthlyMetric({
    required this.label,
    required this.value,
    required this.icon,
    required this.tone,
    required this.onTap,
    this.caption,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color tone;
  final VoidCallback onTap;
  final String? caption;

  @override
  Widget build(BuildContext context) => Card(
    margin: EdgeInsets.zero,
    clipBehavior: Clip.antiAlias,
    child: Semantics(
      button: true,
      label: '$label，$value',
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, color: tone, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      label,
                      style: const TextStyle(
                        color: AppColors.textMuted,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  value,
                  maxLines: 1,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: tone,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              if (caption != null) ...[
                const SizedBox(height: 7),
                Text(
                  caption!,
                  maxLines: 2,
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 12,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    ),
  );
}

class _CompactMetric extends StatelessWidget {
  const _CompactMetric({
    required this.label,
    required this.value,
    required this.icon,
    required this.tone,
    required this.onTap,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color tone;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
    margin: EdgeInsets.zero,
    clipBehavior: Clip.antiAlias,
    child: Semantics(
      button: true,
      label: '$label，$value',
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 126),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(icon, color: tone, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        label,
                        style: const TextStyle(
                          color: AppColors.textMuted,
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    const Icon(
                      Icons.chevron_right,
                      color: AppColors.textMuted,
                      size: 18,
                    ),
                  ],
                ),
                const Spacer(),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    value,
                    maxLines: 1,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: AppColors.text,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({required this.title, required this.subtitle});
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        title,
        style: Theme.of(
          context,
        ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
      ),
      const SizedBox(height: 4),
      Text(
        subtitle,
        style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
      ),
    ],
  );
}

class _NoticeBanner extends StatelessWidget {
  const _NoticeBanner({
    required this.icon,
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.onAction,
  });
  final IconData icon;
  final String title;
  final String message;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.liabilityPale,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppColors.liability),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 3),
                Text(message, style: const TextStyle(fontSize: 13)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          TextButton(onPressed: onAction, child: Text(actionLabel)),
        ],
      ),
    ),
  );
}

class _RecentActivityCard extends StatelessWidget {
  const _RecentActivityCard({required this.records, required this.mask});
  final List<TransactionDisplayRecord> records;
  final bool mask;

  @override
  Widget build(BuildContext context) => Card(
    margin: EdgeInsets.zero,
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '最近紀錄',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
                ),
              ),
              TextButton(
                onPressed: () => context.go('/expenses'),
                child: const Text('查看全部'),
              ),
            ],
          ),
          const Text(
            '最近 5 筆收支動態',
            style: TextStyle(color: AppColors.textMuted, fontSize: 13),
          ),
          const SizedBox(height: 10),
          if (records.isEmpty)
            const EmptyState(
              icon: Icons.receipt_long_outlined,
              title: '還沒有收支紀錄',
              message: '完成第一筆記帳後，交易會顯示在這裡。',
            )
          else
            for (final record in records.take(5))
              _TransactionRow(record: record, mask: mask),
        ],
      ),
    ),
  );
}

class _TransactionRow extends StatelessWidget {
  const _TransactionRow({required this.record, required this.mask});
  final TransactionDisplayRecord record;
  final bool mask;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Row(
      children: [
        CategoryAvatar(category: record.category),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                record.item,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  CategoryBadge(category: record.category),
                  Text(
                    dateText(record.date),
                    style: const TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        Flexible(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerRight,
            child: Text(
              '${record.isIncome ? '+' : '-'}${moneyText(record.amountMinor, currency: record.currency, mask: mask)}',
              maxLines: 1,
              style: TextStyle(
                fontWeight: FontWeight.w900,
                color: record.isIncome ? AppColors.income : AppColors.expense,
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

class _ReminderCard extends StatelessWidget {
  const _ReminderCard({required this.reminders});
  final List<ReminderItem> reminders;

  @override
  Widget build(BuildContext context) => Card(
    margin: EdgeInsets.zero,
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '今日待處理',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 4),
          Text(
            reminders.isEmpty ? '目前沒有需要處理的項目' : '共 ${reminders.length} 項提醒',
            style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
          ),
          const SizedBox(height: 14),
          if (reminders.isEmpty)
            const _ReminderEmptyState()
          else
            for (final reminder in reminders)
              _ReminderRow(reminder: reminder),
        ],
      ),
    ),
  );
}

class _ReminderEmptyState extends StatelessWidget {
  const _ReminderEmptyState();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: AppColors.incomePale,
      borderRadius: BorderRadius.circular(12),
    ),
    child: const Row(
      children: [
        Icon(Icons.check_circle_outline, color: AppColors.income),
        SizedBox(width: 10),
        Expanded(
          child: Text(
            '今天沒有待處理提醒',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
      ],
    ),
  );
}

class _ReminderRow extends StatelessWidget {
  const _ReminderRow({required this.reminder});
  final ReminderItem reminder;

  @override
  Widget build(BuildContext context) {
    final tone = reminder.isWarning ? AppColors.liability : AppColors.primary;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: reminder.isWarning
            ? AppColors.liabilityPale
            : AppColors.assetPale,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: Semantics(
          button: true,
          label: '前往處理${reminder.title}',
          child: InkWell(
            onTap: () => context.go(switch (reminder.destination) {
              ReminderDestination.cards => '/cards',
              ReminderDestination.expenses => '/expenses',
            }),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 64),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      reminder.isWarning
                          ? Icons.warning_amber_rounded
                          : Icons.notifications_none,
                      color: tone,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            reminder.title,
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            reminder.subtitle,
                            style: const TextStyle(fontSize: 13),
                          ),
                          if (reminder.isWarning) ...[
                            const SizedBox(height: 4),
                            const Text(
                              '注意：扣款帳戶餘額可能不足',
                              style: TextStyle(
                                color: AppColors.liability,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyDataBanner extends StatelessWidget {
  const _EmptyDataBanner({required this.onAction});
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: AppColors.assetPale,
      borderRadius: BorderRadius.circular(14),
    ),
    child: Wrap(
      spacing: 14,
      runSpacing: 12,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        const Icon(Icons.account_balance_outlined, color: AppColors.asset),
        const Text(
          '尚無帳戶資料，前往設定建立測試資料即可開始。',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        FilledButton.tonal(
          onPressed: onAction,
          child: const Text('前往設定'),
        ),
      ],
    ),
  );
}
