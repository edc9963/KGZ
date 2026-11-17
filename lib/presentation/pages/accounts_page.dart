import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:forui/forui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/providers.dart';
import '../../domain/models.dart';
import '../design_tokens.dart';
import 'cards_page.dart';
import 'expenses_page.dart';
import 'investments_page.dart';
import 'orders_page.dart';
import '../widgets/common.dart';

class AccountsPage extends ConsumerWidget {
  const AccountsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final store = ref.watch(appStoreProvider);
    final accounts = store.data.accounts
        .where((item) => item.kind == FinancialAccountKind.asset)
        .toList();
    final canTransfer = store.activeAssetAccounts.length >= 2;
    final mask = store.data.settings.maskBalances;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PageHeader(
          title: '帳戶管理',
          action: Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              FButton(
                variant: FButtonVariant.outline,
                mainAxisSize: MainAxisSize.min,
                onPress: canTransfer
                    ? () => _showTransferDialog(context, ref)
                    : null,
                prefix: const Icon(Icons.swap_horiz),
                child: const Text('轉帳'),
              ),
              FButton(
                mainAxisSize: MainAxisSize.min,
                onPress: () => _showAccountDialog(context, ref),
                prefix: const Icon(Icons.add),
                child: const Text('新增帳戶'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        HeroMetricCard(
          label: '帳戶總餘額',
          value: moneyText(
            store.depositTotalMinor,
            currency: store.data.settings.defaultCurrency,
            mask: mask,
          ),
          compactValue: compactMoneyText(
            store.depositTotalMinor,
            currency: store.data.settings.defaultCurrency,
            mask: mask,
          ),
          icon: Icons.account_balance_wallet_outlined,
        ),
        const SizedBox(height: 12),
        SecondaryMetrics(
          child: ResponsiveGrid(
            minWidth: 210,
            children: [
              SummaryCard(
                label: '信用卡負債',
                value: moneyText(
                  store.pendingCardDefaultMinor,
                  currency: store.data.settings.defaultCurrency,
                  mask: mask,
                ),
                compactValue: compactMoneyText(
                  store.pendingCardDefaultMinor,
                  currency: store.data.settings.defaultCurrency,
                  mask: mask,
                ),
                icon: Icons.credit_card_outlined,
                tone: Theme.of(context).colorScheme.error,
              ),
              SummaryCard(
                label: '代訂應收款',
                value: moneyText(
                  store.receivablesDefaultMinor,
                  currency: store.data.settings.defaultCurrency,
                  mask: mask,
                ),
                compactValue: compactMoneyText(
                  store.receivablesDefaultMinor,
                  currency: store.data.settings.defaultCurrency,
                  mask: mask,
                ),
                icon: Icons.request_quote_outlined,
              ),
              SummaryCard(
                label: '淨資產',
                value: moneyText(
                  store.netWorthMinor,
                  currency: store.data.settings.defaultCurrency,
                  mask: mask,
                ),
                compactValue: compactMoneyText(
                  store.netWorthMinor,
                  currency: store.data.settings.defaultCurrency,
                  mask: mask,
                ),
                icon: Icons.insights_outlined,
                tone: context.colors.asset,
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        if (accounts.isEmpty)
          EmptyState(
            icon: Icons.account_balance_wallet_outlined,
            title: '還沒有帳戶',
            message: '新增第一個帳戶，首頁就會開始計算資產。',
            action: FButton(
              mainAxisSize: MainAxisSize.min,
              onPress: () => _showAccountDialog(context, ref),
              child: const Text('新增帳戶'),
            ),
          )
        else
          Column(
            children: [
              for (var index = 0; index < accounts.length; index++) ...[
                _AccountRow(
                  account: accounts[index],
                  balance: store.accountBalance(accounts[index].id),
                  mask: mask,
                  onTap: () => _showLedgerDialog(context, ref, accounts[index]),
                  onEdit: accounts[index].id == systemCashAccountId
                      ? null
                      : () => _showAccountDialog(context, ref, accounts[index]),
                  onAdjust: () =>
                      _showAdjustmentDialog(context, ref, accounts[index]),
                  onTransfer: canTransfer && accounts[index].isActive
                      ? () => _showTransferDialog(
                          context,
                          ref,
                          fromAccount: accounts[index],
                        )
                      : null,
                  onMerge:
                      accounts[index].id == systemCashAccountId ||
                          !accounts.any(
                            (item) =>
                                item.id != accounts[index].id &&
                                item.currency == accounts[index].currency,
                          )
                      ? null
                      : () => _showMergeDialog(context, ref, accounts[index]),
                  onDelete: accounts[index].id == systemCashAccountId
                      ? null
                      : () async {
                          if (await confirmDelete(context, '帳戶')) {
                            await store.deleteAccount(accounts[index].id);
                          }
                        },
                ),
              ],
            ],
          ),
        const SizedBox(height: 18),
        FAccordion(
          children: [
            FAccordionItem(
              title: Text('餘額計算方式', style: TextStyle(fontSize: 13)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: Text('期初餘額加上收支、投資、繳款與調整；編輯來源紀錄後自動重算。'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _showLedgerDialog(
    BuildContext context,
    WidgetRef ref,
    Account originalAccount,
  ) async {
    await showFDialog<void>(
      useRootNavigator: true,
      context: context,
      builder: (dialogContext, _, _) => Consumer(
        builder: (context, dialogRef, _) {
          final store = dialogRef.watch(appStoreProvider);
          final account =
              store.accountById(originalAccount.id) ?? originalAccount;
          final entries = store.accountLedgerEntries(account.id);
          final size = MediaQuery.sizeOf(context);
          return KgzDialog(
            title: Row(
              children: [
                Expanded(child: Text('${account.name} 扣／入帳明細')),
                FTooltip(
                  tipBuilder: (context, _) => Text('關閉'),
                  child: FButton.icon(
                    variant: FButtonVariant.ghost,
                    onPress: () => Navigator.pop(dialogContext),
                    semanticsLabel: '關閉',
                    child: const Icon(Icons.close),
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: math.min(680.0, size.width - 128.0),
              height: math.min(620.0, size.height - 180.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${account.institution}・${account.type}・${account.currency}',
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '目前餘額 ${moneyText(store.accountBalance(account.id), currency: account.currency, mask: store.data.settings.maskBalances)}',
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.w900),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (entries.isEmpty)
                    const Expanded(
                      child: EmptyState(
                        icon: Icons.receipt_long_outlined,
                        title: '尚無扣／入帳紀錄',
                        message: '新增消費、收款或餘額調整後會顯示在這裡。',
                      ),
                    )
                  else
                    Expanded(
                      child: ListView.separated(
                        key: const ValueKey('account-ledger-list'),
                        itemCount: entries.length,
                        separatorBuilder: (_, __) => FDivider(),
                        itemBuilder: (context, index) {
                          final entry = entries[index];
                          final positive = entry.amountMinor >= 0;
                          return FItem(
                            key: ValueKey(
                              'ledger-${entry.sourceType}-${entry.sourceId}',
                            ),
                            prefix: FAvatar.raw(
                              style: FAvatarStyleDelta.delta(
                                backgroundColor: positive
                                    ? context.colors.incomePale
                                    : context.colors.expensePale,
                              ),
                              child: Icon(
                                positive ? Icons.south_west : Icons.north_east,
                                color: positive
                                    ? context.colors.income
                                    : context.colors.expense,
                              ),
                            ),
                            title: Text(
                              entry.label.isEmpty
                                  ? _sourceLabel(entry.sourceType)
                                  : entry.label,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${dateText(entry.date)}・${_sourceLabel(entry.sourceType)}',
                                ),
                                Text(
                                  '${positive ? '+' : '−'}${moneyText(entry.amountMinor.abs(), currency: account.currency, mask: store.data.settings.maskBalances)}',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w900,
                                    color: positive
                                        ? context.colors.income
                                        : context.colors.expense,
                                  ),
                                ),
                              ],
                            ),
                            suffix: KgzPopoverMenu<String>(
                              semanticsLabel: '明細操作',
                              entries: [
                                KgzMenuEntry('edit', '編輯'),
                                if (entry.sourceType != 'openingBalance')
                                  KgzMenuEntry(
                                    'delete',
                                    entry.sourceType == 'collection'
                                        ? '取消入帳'
                                        : '刪除',
                                    destructive: true,
                                  ),
                              ],
                              onSelected: (value) async {
                                if (value == 'edit') {
                                  await _editLedgerEntry(
                                    context,
                                    dialogRef,
                                    account,
                                    entry,
                                  );
                                } else if (value == 'delete') {
                                  await _deleteLedgerEntry(
                                    context,
                                    dialogRef,
                                    entry,
                                  );
                                }
                              },
                            ),
                          );
                        },
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _editLedgerEntry(
    BuildContext context,
    WidgetRef ref,
    Account account,
    LedgerEffect entry,
  ) async {
    final store = ref.read(appStoreProvider);
    switch (entry.sourceType) {
      case 'openingBalance':
        if (account.id != systemCashAccountId) {
          await _showAccountDialog(context, ref, account);
        }
      case 'balanceAdjustment':
        final item = store.data.balanceAdjustments
            .where((item) => item.id == entry.sourceId)
            .firstOrNull;
        if (item != null) {
          await _showAdjustmentDialog(context, ref, account, item);
        }
      case 'transfer':
        final item = store.data.transactions
            .where((item) => item.id == entry.sourceId)
            .firstOrNull;
        if (item != null) {
          await _showTransferDialog(context, ref, existing: item);
        }
      case 'expense':
        await _pushEditor(
          context,
          ExpensesPage(
            editExpenseId: entry.sourceId,
            returnOnEditorClose: true,
          ),
        );
      case 'income':
        await _pushEditor(
          context,
          ExpensesPage(editIncomeId: entry.sourceId, returnOnEditorClose: true),
        );
      case 'investment':
        await _pushEditor(
          context,
          InvestmentsPage(
            editTransactionId: entry.sourceId,
            returnOnEditorClose: true,
          ),
        );
      case 'cardPayment':
        await _pushEditor(
          context,
          CardsPage(editBillId: entry.sourceId, returnOnEditorClose: true),
        );
      case 'collection':
        if (entry.parentSourceId != null) {
          await Navigator.of(context).push<void>(
            MaterialPageRoute(
              builder: (_) =>
                  OrderEditorLauncher(orderId: entry.parentSourceId!),
            ),
          );
        }
    }
  }

  Future<void> _deleteLedgerEntry(
    BuildContext context,
    WidgetRef ref,
    LedgerEffect entry,
  ) async {
    final store = ref.read(appStoreProvider);
    if (entry.sourceType == 'collection') {
      final confirmed = await _confirmCancelCollection(context);
      if (confirmed && entry.parentSourceId != null) {
        await store.cancelParticipantCollection(
          entry.parentSourceId!,
          entry.sourceId,
        );
      }
      return;
    }
    final label = switch (entry.sourceType) {
      'balanceAdjustment' => '餘額調整',
      'transfer' => '轉帳',
      'expense' => '消費',
      'income' => '收入',
      'investment' => '投資交易',
      'cardPayment' => '信用卡帳單',
      _ => '紀錄',
    };
    if (!await confirmDelete(context, label)) return;
    switch (entry.sourceType) {
      case 'balanceAdjustment':
        await store.deleteBalanceAdjustment(entry.sourceId);
      case 'transfer':
        await store.deleteAccountTransfer(entry.sourceId);
      case 'expense':
        await store.deleteExpense(entry.sourceId);
      case 'income':
        await store.deleteIncome(entry.sourceId);
      case 'investment':
        await store.deleteInvestmentTransaction(entry.sourceId);
      case 'cardPayment':
        await store.deleteBill(entry.sourceId);
    }
  }

  Future<void> _pushEditor(BuildContext context, Widget page) => Navigator.of(
    context,
  ).push<void>(MaterialPageRoute(builder: (_) => _EditorHost(child: page)));

  Future<bool> _confirmCancelCollection(BuildContext context) async =>
      await showFDialog<bool>(
        useRootNavigator: true,
        context: context,
        builder: (context, _, _) => KgzDialog(
          title: const Text('取消入帳？'),
          content: const Text('這位參與者將恢復為未收款，代訂本身不會被刪除。'),
          actions: [
            FButton(
              variant: FButtonVariant.ghost,
              mainAxisSize: MainAxisSize.min,
              onPress: () => Navigator.pop(context, false),
              child: const Text('返回'),
            ),
            FButton(
              mainAxisSize: MainAxisSize.min,
              onPress: () => Navigator.pop(context, true),
              child: const Text('取消入帳'),
            ),
          ],
        ),
      ) ??
      false;

  String _sourceLabel(String type) => switch (type) {
    'openingBalance' => '期初餘額',
    'balanceAdjustment' => '餘額調整',
    'transfer' => '帳戶轉帳',
    'expense' => '消費扣帳',
    'income' => '收入入帳',
    'investment' => '投資交易',
    'cardPayment' => '信用卡扣款',
    'collection' => '代訂收款',
    _ => '帳務紀錄',
  };

  Future<void> _showAccountDialog(
    BuildContext context,
    WidgetRef ref, [
    Account? existing,
  ]) async {
    final store = ref.read(appStoreProvider);
    final name = TextEditingController(text: existing?.name);
    final institution = TextEditingController(text: existing?.institution);
    final balance = TextEditingController(
      text: existing == null
          ? ''
          : (existing.openingBalanceMinor / 100).toString(),
    );
    final note = TextEditingController(text: existing?.note);
    var type = existing?.type ?? '銀行帳戶';
    var currency = existing?.currency ?? 'TWD';
    var active = existing?.isActive ?? true;
    final formKey = GlobalKey<FormState>();
    await showFDialog<void>(
      useRootNavigator: true,
      context: context,
      builder: (dialogContext, _, _) => StatefulBuilder(
        builder: (context, setState) => KgzDialog(
          title: Text(existing == null ? '新增帳戶' : '編輯帳戶'),
          content: SizedBox(
            width: 480,
            child: Form(
              key: formKey,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FTextFormField(
                      control: FTextFieldControl.managed(controller: name),
                      label: Text('帳戶名稱'),
                      validator: (value) =>
                          value == null || value.trim().isEmpty
                          ? '請輸入帳戶名稱'
                          : null,
                    ),
                    const SizedBox(height: 12),
                    FTextFormField(
                      control: FTextFieldControl.managed(
                        controller: institution,
                      ),
                      label: Text('銀行／機構'),
                    ),
                    const SizedBox(height: 12),
                    KgzSelect<String>(
                      value: type,
                      label: Text('帳戶類型'),
                      items: const [
                        '銀行帳戶',
                        '現金',
                        '證券交割戶',
                        '外幣帳戶',
                        'LINE Pay / iPASS MONEY',
                        '其他電子支付',
                      ].map((item) => KgzSelectItem(item, item)).toList(),
                      onChanged: (value) => setState(() => type = value!),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: KgzSelect<String>(
                            value: currency,
                            label: Text('幣別'),
                            items: const [
                              'TWD',
                              'USD',
                              'JPY',
                              'EUR',
                            ].map((item) => KgzSelectItem(item, item)).toList(),
                            onChanged: (value) =>
                                setState(() => currency = value!),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: MoneyField(
                            controller: balance,
                            label: Text('期初餘額'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    FTextFormField(
                      control: FTextFieldControl.managed(controller: note),
                      label: Text('備註'),
                    ),
                    FItem(
                      title: const Text('啟用帳戶'),
                      suffix: FSwitch(
                        value: active,
                        onChange: (value) => setState(() => active = value),
                      ),
                      onPress: () =>
                          ((value) =>
                              setState(() => active = value))(!(active)),
                    ),
                  ],
                ),
              ),
            ),
          ),
          actions: [
            FButton(
              variant: FButtonVariant.ghost,
              mainAxisSize: MainAxisSize.min,
              onPress: () => Navigator.pop(dialogContext),
              child: const Text('取消'),
            ),
            FButton(
              mainAxisSize: MainAxisSize.min,
              onPress: () async {
                if (!formKey.currentState!.validate()) return;
                final now = DateTime.now();
                await store.upsertAccount(
                  Account(
                    id: existing?.id ?? store.newId(),
                    userId: store.userId,
                    name: name.text.trim(),
                    institution: institution.text.trim(),
                    type: type,
                    currency: currency,
                    openingBalanceMinor: parseMoney(balance.text),
                    isActive: active,
                    note: note.text.trim(),
                    createdAt: existing?.createdAt ?? now,
                    updatedAt: now,
                    origin: existing?.origin ?? DataOrigin.user,
                  ),
                );
                if (dialogContext.mounted) Navigator.pop(dialogContext);
              },
              child: const Text('儲存'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showAdjustmentDialog(
    BuildContext context,
    WidgetRef ref,
    Account account, [
    BalanceAdjustment? existing,
  ]) async {
    final store = ref.read(appStoreProvider);
    final amount = TextEditingController(
      text: existing == null ? '' : (existing.amountMinor / 100).toString(),
    );
    final reason = TextEditingController(text: existing?.reason ?? '餘額盤點調整');
    var date = existing?.date ?? DateTime.now();
    var mode = 'difference';
    await showFDialog<void>(
      useRootNavigator: true,
      context: context,
      builder: (dialogContext, _, _) => KgzDialog(
        title: Text(existing == null ? '調整 ${account.name}' : '編輯餘額調整'),
        content: StatefulBuilder(
          builder: (context, setState) => SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '目前餘額：${moneyText(store.accountBalance(account.id), currency: account.currency)}',
                ),
                const SizedBox(height: 16),
                KgzTabBar<String>(
                  tabs: const [
                    ('difference', '增加／減少', Icons.exposure),
                    ('total', '直接改總額', Icons.account_balance_wallet_outlined),
                  ],
                  selected: mode,
                  onSelected: (value) => setState(() => mode = value),
                ),
                const SizedBox(height: 16),
                MoneyField(
                  controller: amount,
                  autofocus: true,
                  label: Text(mode == 'difference' ? '調整金額' : '調整後總額'),
                  description: Text(
                    mode == 'difference' ? '增加填正數，減少填負數' : '輸入希望這個帳戶顯示的總餘額',
                  ),
                ),
                const SizedBox(height: 12),
                KgzValueField(
                  label: '調整日期',
                  value: dateText(date),
                  onTap: () async {
                    final picked = await showKgzDatePicker(
                      context: context,
                      initialDate: date,
                      firstDate: DateTime(2000),
                      lastDate: DateTime.now().add(const Duration(days: 365)),
                    );
                    if (picked != null) setState(() => date = picked);
                  },
                ),
                const SizedBox(height: 12),
                FTextField(
                  control: FTextFieldControl.managed(controller: reason),
                  label: Text('原因'),
                ),
              ],
            ),
          ),
        ),
        actions: [
          FButton(
            variant: FButtonVariant.ghost,
            mainAxisSize: MainAxisSize.min,
            onPress: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          FButton(
            mainAxisSize: MainAxisSize.min,
            onPress: () async {
              final parsed = double.tryParse(
                amount.text.trim().replaceAll(',', ''),
              );
              if (parsed == null) {
                showNotice(dialogContext, '請輸入正確金額', error: true);
                return;
              }
              final entered = (parsed * 100).round();
              final adjustment = mode == 'total'
                  ? entered - store.accountBalance(account.id)
                  : entered;
              if (adjustment == 0) {
                if (dialogContext.mounted) Navigator.pop(dialogContext);
                return;
              }
              await store.upsertBalanceAdjustment(
                BalanceAdjustment(
                  id: existing?.id ?? store.newId(),
                  userId: store.userId,
                  accountId: account.id,
                  amountMinor: adjustment,
                  date: date,
                  reason: reason.text.trim(),
                  origin: existing?.origin ?? DataOrigin.user,
                ),
              );
              if (dialogContext.mounted) Navigator.pop(dialogContext);
            },
            child: const Text('套用調整'),
          ),
        ],
      ),
    );
  }

  Future<void> _showMergeDialog(
    BuildContext context,
    WidgetRef ref,
    Account source,
  ) async {
    final store = ref.read(appStoreProvider);
    final targets = store.data.accounts
        .where(
          (item) =>
              item.kind == FinancialAccountKind.asset &&
              item.id != source.id &&
              item.currency == source.currency,
        )
        .toList();
    if (targets.isEmpty) return;
    var targetId = targets.first.id;
    await showFDialog<void>(
      useRootNavigator: true,
      context: context,
      builder: (dialogContext, _, _) => StatefulBuilder(
        builder: (context, setState) => KgzDialog(
          title: Text('合併 ${source.name}'),
          content: SizedBox(
            width: 460,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('選擇要保留的帳戶：'),
                const SizedBox(height: 12),
                KgzSelect<String>(
                  value: targetId,
                  label: Text('保留帳戶'),
                  items: [
                    for (final account in targets)
                      KgzSelectItem(
                        account.id,
                        '${account.name}・${account.institution}・${account.currency}',
                      ),
                  ],
                  onChanged: (value) =>
                      setState(() => targetId = value ?? targetId),
                ),
                const SizedBox(height: 16),
                Text(
                  '「${source.name}」的餘額與所有帳務紀錄會移到保留帳戶，'
                  '之後刪除這筆重複帳戶。此動作無法復原。',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ),
          ),
          actions: [
            FButton(
              variant: FButtonVariant.ghost,
              mainAxisSize: MainAxisSize.min,
              onPress: () => Navigator.pop(dialogContext),
              child: const Text('取消'),
            ),
            FButton(
              mainAxisSize: MainAxisSize.min,
              onPress: () async {
                await store.mergeAccounts(
                  sourceAccountId: source.id,
                  targetAccountId: targetId,
                );
                if (dialogContext.mounted && store.lastSyncError == null) {
                  Navigator.pop(dialogContext);
                }
              },
              child: const Text('確認合併'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showTransferDialog(
    BuildContext context,
    WidgetRef ref, {
    Account? fromAccount,
    FinancialTransaction? existing,
  }) async {
    final store = ref.read(appStoreProvider);
    final accounts = store.activeAssetAccounts;
    if (accounts.length < 2) return;
    final existingFromId = existing?.impacts
        .where((impact) => impact.amountMinor < 0)
        .firstOrNull
        ?.accountId;
    final existingToId = existing?.impacts
        .where((impact) => impact.amountMinor > 0)
        .firstOrNull
        ?.accountId;
    var fromId = existingFromId ?? fromAccount?.id ?? accounts.first.id;
    var toId =
        existingToId ??
        accounts
            .where(
              (item) =>
                  item.id != fromId &&
                  item.currency == store.accountById(fromId)?.currency,
            )
            .firstOrNull
            ?.id;
    final amount = TextEditingController(
      text: existing == null ? '' : (existing.amountMinor / 100).toString(),
    );
    final note = TextEditingController(text: existing?.note);
    var date = existing?.date ?? DateTime.now();
    final formKey = GlobalKey<FormState>();

    await showFDialog<void>(
      useRootNavigator: true,
      context: context,
      builder: (dialogContext, _, _) => StatefulBuilder(
        builder: (context, setState) {
          final from = store.accountById(fromId)!;
          final compatibleTargets = accounts
              .where(
                (item) => item.id != fromId && item.currency == from.currency,
              )
              .toList();
          if (!compatibleTargets.any((item) => item.id == toId)) {
            toId = compatibleTargets.firstOrNull?.id;
          }
          final to = toId == null ? null : store.accountById(toId!);
          final parsedAmount = parseMoney(amount.text);
          final fromBalance = store.accountBalance(from.id);
          return KgzDialog(
            title: Text(existing == null ? '帳戶間轉帳' : '編輯轉帳'),
            content: SizedBox(
              width: 520,
              child: Form(
                key: formKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      KgzSelect<String>(
                        key: ValueKey('transfer-from-$fromId'),
                        value: fromId,
                        label: const Text('從哪個帳戶轉出'),
                        prefixIcon: const Icon(FLucideIcons.arrowUpRight),
                        items: [
                          for (final account in accounts)
                            KgzSelectItem(
                              account.id,
                              '${account.name}・${moneyText(store.accountBalance(account.id), currency: account.currency)}',
                            ),
                        ],
                        onChanged: (value) => setState(() {
                          fromId = value!;
                          toId = null;
                        }),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Center(
                          child: FTooltip(
                            tipBuilder: (context, _) => Text('交換轉出與轉入帳戶'),
                            child: FButton.icon(
                              variant: FButtonVariant.secondary,
                              onPress: to == null
                                  ? null
                                  : () => setState(() {
                                      final previousFrom = fromId;
                                      fromId = to.id;
                                      toId = previousFrom;
                                    }),
                              semanticsLabel: '交換轉出與轉入帳戶',
                              child: const Icon(Icons.swap_vert),
                            ),
                          ),
                        ),
                      ),
                      KgzSelect<String>(
                        key: ValueKey('transfer-to-$fromId-$toId'),
                        value: toId,
                        label: const Text('轉入哪個帳戶'),
                        prefixIcon: const Icon(FLucideIcons.arrowDownLeft),
                        items: [
                          for (final account in compatibleTargets)
                            KgzSelectItem(
                              account.id,
                              '${account.name}・${moneyText(store.accountBalance(account.id), currency: account.currency)}',
                            ),
                        ],
                        validator: (value) =>
                            value == null ? '沒有可用的同幣別轉入帳戶' : null,
                        onChanged: (value) => setState(() => toId = value),
                      ),
                      const SizedBox(height: 16),
                      MoneyField(
                        controller: amount,
                        autofocus: true,
                        contentTextStyle: Theme.of(context)
                            .textTheme
                            .headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w900),
                        label: Text('轉帳金額'),
                        prefixText: '${from.currency} ',
                        validator: (value) =>
                            parseMoney(value ?? '') <= 0 ? '請輸入大於 0 的金額' : null,
                        onChanged: (_) => setState(() {}),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Theme.of(
                            context,
                          ).colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: _TransferBalancePreview(
                                label: '轉出後',
                                account: from,
                                balance: fromBalance - parsedAmount,
                              ),
                            ),
                            const Icon(Icons.arrow_forward, size: 20),
                            Expanded(
                              child: _TransferBalancePreview(
                                label: '轉入後',
                                account: to,
                                balance: to == null
                                    ? 0
                                    : store.accountBalance(to.id) +
                                          parsedAmount,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      KgzValueField(
                        label: '轉帳日期',
                        value: dateText(date),
                        prefixIcon: Icon(Icons.calendar_today_outlined),
                        onTap: () async {
                          final picked = await showKgzDatePicker(
                            context: context,
                            initialDate: date,
                            firstDate: DateTime(2000),
                            lastDate: DateTime.now().add(
                              const Duration(days: 365),
                            ),
                          );
                          if (picked != null) setState(() => date = picked);
                        },
                      ),
                      const SizedBox(height: 12),
                      FTextField(
                        control: FTextFieldControl.managed(controller: note),
                        label: Text('備註（選填）'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            actions: [
              FButton(
                variant: FButtonVariant.ghost,
                mainAxisSize: MainAxisSize.min,
                onPress: () => Navigator.pop(dialogContext),
                child: const Text('取消'),
              ),
              FButton(
                mainAxisSize: MainAxisSize.min,
                onPress: to == null
                    ? null
                    : () async {
                        if (!formKey.currentState!.validate()) return;
                        await store.upsertAccountTransfer(
                          id: existing?.id ?? store.newId(),
                          fromAccountId: fromId,
                          toAccountId: toId!,
                          amountMinor: parseMoney(amount.text),
                          date: date,
                          note: note.text,
                        );
                        if (dialogContext.mounted &&
                            store.lastSyncError == null) {
                          Navigator.pop(dialogContext);
                        }
                      },
                prefix: const Icon(Icons.swap_horiz),
                child: Text(existing == null ? '確認轉帳' : '儲存轉帳'),
              ),
            ],
          );
        },
      ),
    );
    amount.dispose();
    note.dispose();
  }
}

class _TransferBalancePreview extends StatelessWidget {
  const _TransferBalancePreview({
    required this.label,
    required this.account,
    required this.balance,
  });

  final String label;
  final Account? account;
  final int balance;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: Theme.of(context).textTheme.labelMedium),
      const SizedBox(height: 3),
      Text(
        account == null ? '—' : moneyText(balance, currency: account!.currency),
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontWeight: FontWeight.w900,
          color: balance < 0 ? Theme.of(context).colorScheme.error : null,
        ),
      ),
      Text(
        account?.name ?? '請選擇帳戶',
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.bodySmall,
      ),
    ],
  );
}

class _AccountRow extends StatelessWidget {
  const _AccountRow({
    required this.account,
    required this.balance,
    required this.mask,
    required this.onTap,
    required this.onEdit,
    required this.onAdjust,
    required this.onTransfer,
    required this.onMerge,
    required this.onDelete,
  });

  final Account account;
  final int balance;
  final bool mask;
  final VoidCallback onTap;
  final VoidCallback? onEdit;
  final VoidCallback onAdjust;
  final VoidCallback? onTransfer;
  final VoidCallback? onMerge;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: KgzCard(
      child: FItem(
        prefix: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: account.isActive
                ? context.colors.accentPale
                : context.colors.subtle,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            color: context.colors.accent,
            account.type == '現金'
                ? Icons.payments_outlined
                : Icons.account_balance_outlined,
          ),
        ),
        title: Row(
          children: [
            Flexible(
              child: Text(
                account.name,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            if (!account.isActive)
              const Padding(
                padding: EdgeInsets.only(left: 8),
                child: StatusPill('停用'),
              ),
            if (account.id == systemCashAccountId)
              const Padding(
                padding: EdgeInsets.only(left: 8),
                child: StatusPill('系統'),
              ),
          ],
        ),
        subtitle: Text(
          [
            account.institution,
            account.type,
            account.currency,
          ].where((value) => value.isNotEmpty).join(' · '),
          style: TextStyle(fontSize: 11.5, color: context.colors.textMuted),
        ),
        suffix: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 112),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  moneyText(balance, currency: account.currency, mask: mask),
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
            KgzPopoverMenu<String>(
              semanticsLabel: '更多操作',
              entries: [
                if (onEdit != null) KgzMenuEntry('edit', '編輯'),
                KgzMenuEntry('adjust', '餘額調整'),
                if (onTransfer != null) KgzMenuEntry('transfer', '從這個帳戶轉出'),
                if (onMerge != null) KgzMenuEntry('merge', '合併至其他帳戶'),
                if (onDelete != null)
                  KgzMenuEntry('delete', '刪除', destructive: true),
              ],
              onSelected: (value) {
                if (value == 'edit') onEdit?.call();
                if (value == 'adjust') onAdjust();
                if (value == 'transfer') onTransfer?.call();
                if (value == 'merge') onMerge?.call();
                if (value == 'delete') onDelete?.call();
              },
            ),
          ],
        ),
        onPress: onTap,
      ),
    ),
  );
}

class _EditorHost extends StatelessWidget {
  const _EditorHost({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => FScaffold(
    childPad: false,
    header: SafeArea(
      bottom: false,
      child: FHeader.nested(
        title: const Text('編輯原始資料'),
        prefixes: [
          FHeaderAction.back(
            semanticsLabel: '返回',
            onPress: () => Navigator.maybePop(context),
          ),
        ],
      ),
    ),
    child: SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: child,
      ),
    ),
  );
}
