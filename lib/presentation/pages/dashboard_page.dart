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
    _otherExpanded ??= desktop;
    final records = transactionDisplayRecords(store);

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
          Card(
            color: AppColors.liabilityPale,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Icon(
                    Icons.currency_exchange,
                    color: AppColors.liability,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '缺少 ${store.currenciesMissingFx.join('、')} 對 '
                      '${settings.defaultCurrency} 匯率，相關資產未納入總額。',
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
        ResponsiveGrid(
          minWidth: 160,
          spacing: 12,
          children: [
            SummaryCard(
              label: '淨資產',
              value: moneyText(
                store.netWorthMinor,
                currency: settings.defaultCurrency,
                mask: mask,
              ),
              icon: Icons.auto_graph_rounded,
              tone: AppColors.asset,
              onTap: () => context.go('/reports'),
            ),
            SummaryCard(
              label: '本月收入',
              value: moneyText(
                store.currentMonthIncomeDefaultMinor,
                currency: settings.defaultCurrency,
                mask: mask,
              ),
              icon: Icons.south_west_rounded,
              tone: AppColors.income,
              onTap: () => context.go('/expenses'),
            ),
            SummaryCard(
              label: '本月支出',
              value: moneyText(
                store.currentMonthExpenseDefaultMinor,
                currency: settings.defaultCurrency,
                mask: mask,
              ),
              icon: Icons.north_east_rounded,
              tone: AppColors.expense,
              caption: '不含投資與信用卡繳款',
              onTap: () => context.go('/expenses'),
            ),
            SummaryCard(
              label: '信用卡待繳',
              value: moneyText(
                store.pendingCardDefaultMinor,
                currency: settings.defaultCurrency,
                mask: mask,
              ),
              icon: Icons.credit_card_outlined,
              tone: AppColors.liability,
              onTap: () => context.go('/cards'),
            ),
          ],
        ),
        const SizedBox(height: 18),
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
                      store.depositTotalMinor,
                      currency: settings.defaultCurrency,
                      mask: mask,
                    ),
                    icon: Icons.account_balance_wallet_outlined,
                    tone: const Color(0xFF568EAE),
                    onTap: () => context.go('/accounts'),
                  ),
                  SummaryCard(
                    label: '投資現值',
                    value: moneyText(
                      store.investmentValueMinor,
                      currency: settings.defaultCurrency,
                      mask: mask,
                    ),
                    icon: Icons.trending_up_rounded,
                    tone: const Color(0xFF6075A6),
                    onTap: () => context.go('/investments'),
                  ),
                  SummaryCard(
                    label: '代墊應收款',
                    value: moneyText(
                      store.receivablesDefaultMinor,
                      currency: settings.defaultCurrency,
                      mask: mask,
                    ),
                    icon: Icons.handshake_outlined,
                    tone: const Color(0xFFA36F5A),
                    onTap: () => context.go('/orders'),
                  ),
                  SummaryCard(
                    label: store.currentMonthCollectionResultDefaultMinor >= 0
                        ? '本月代收收益'
                        : '本月代收損失',
                    value: moneyText(
                      store.currentMonthCollectionResultDefaultMinor.abs(),
                      currency: settings.defaultCurrency,
                      mask: mask,
                    ),
                    icon: store.currentMonthCollectionResultDefaultMinor >= 0
                        ? Icons.trending_up
                        : Icons.trending_down,
                    tone: store.currentMonthCollectionResultDefaultMinor >= 0
                        ? AppColors.income
                        : AppColors.expense,
                    onTap: () => context.go('/orders'),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 850;
            final reminder = _ReminderCard(reminders: store.reminders);
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
            color: AppColors.assetPale,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  const Icon(Icons.tips_and_updates_outlined),
                  const SizedBox(width: 14),
                  const Expanded(child: Text('尚無資料。可前往設定產生一組完整測試資料。')),
                  FilledButton.tonal(
                    onPressed: () => context.go('/settings'),
                    child: const Text('前往設定'),
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
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '最近紀錄',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
              const Spacer(),
              TextButton(
                onPressed: () => context.go('/expenses'),
                child: const Text('查看全部'),
              ),
            ],
          ),
          const SizedBox(height: 6),
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
                        ? AppColors.income
                        : AppColors.expense,
                  ),
                ),
              ),
        ],
      ),
    ),
  );
}

class _ReminderCard extends StatelessWidget {
  const _ReminderCard({required this.reminders});
  final List<ReminderItem> reminders;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '今日待處理',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 14),
          if (reminders.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Row(
                children: [
                  Icon(Icons.check_circle_outline, color: AppColors.income),
                  SizedBox(width: 10),
                  Text('今天沒有待處理提醒'),
                ],
              ),
            )
          else
            for (final reminder in reminders)
              Card(
                margin: const EdgeInsets.only(bottom: 10),
                color: reminder.isWarning
                    ? AppColors.liabilityPale
                    : AppColors.assetPale,
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
                                ? AppColors.liability
                                : AppColors.primary,
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
                                  const Text(
                                    '扣款帳戶餘額可能不足',
                                    style: TextStyle(
                                      color: AppColors.liability,
                                      fontSize: 12,
                                    ),
                                  ),
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
        ],
      ),
    ),
  );
}
