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
            color: context.colors.liabilityPale,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(
                    Icons.currency_exchange,
                    color: context.colors.liability,
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
                    tone: const Color(0xFF568EAE),
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
                    tone: const Color(0xFF6075A6),
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
                    tone: const Color(0xFFA36F5A),
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
        const SizedBox(height: 18),
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
                  const Icon(Icons.tips_and_updates_outlined),
                  const SizedBox(width: 14),
                  const Expanded(child: Text('新增第一個帳戶，開始掌握收支與資產。')),
                  FilledButton.tonal(
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
                        ? context.colors.income
                        : context.colors.expense,
                  ),
                ),
              ),
        ],
      ),
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
                color: reminder.isWarning
                    ? context.colors.liabilityPale
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
                                ? context.colors.liability
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
                                      color: context.colors.liability,
                                      fontSize: 12,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          if (reminder.billId != null &&
                              onAcknowledge != null)
                            IconButton(
                              tooltip: '已確認，這筆帳單不用再提醒',
                              icon: const Icon(Icons.check_circle_outline),
                              onPressed: () =>
                                  onAcknowledge!(reminder.billId!),
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
