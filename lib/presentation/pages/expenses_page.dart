import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../application/app_store.dart';
import '../../application/providers.dart';
import '../../domain/models.dart';
import '../design_tokens.dart';
import '../transaction_display.dart';
import '../widgets/common.dart';

enum _RecordTab { all, expense, income, recurring }

enum _DateFilter { month, previousMonth, threeMonths, all }

class ExpensesPage extends ConsumerStatefulWidget {
  const ExpensesPage({
    this.createOnOpen = false,
    this.createIncomeOnOpen = false,
    this.editExpenseId,
    this.editIncomeId,
    this.returnOnEditorClose = false,
    super.key,
  });
  final bool createOnOpen;
  final bool createIncomeOnOpen;
  final String? editExpenseId;
  final String? editIncomeId;
  final bool returnOnEditorClose;

  @override
  ConsumerState<ExpensesPage> createState() => _ExpensesPageState();
}

class _ExpensesPageState extends ConsumerState<ExpensesPage> {
  String _category = '全部';
  bool _opened = false;
  _RecordTab _tab = _RecordTab.all;
  final _search = TextEditingController();
  _DateFilter _dateFilter = _DateFilter.month;
  String? _accountFilter;
  PaymentMethod? _paymentFilter;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if ((widget.createOnOpen ||
            widget.createIncomeOnOpen ||
            widget.editExpenseId != null ||
            widget.editIncomeId != null) &&
        !_opened) {
      _opened = true;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        final store = ref.read(appStoreProvider);
        if (widget.createIncomeOnOpen || widget.editIncomeId != null) {
          setState(() => _tab = _RecordTab.income);
          final existing = widget.editIncomeId == null
              ? null
              : store.data.incomes
                    .where((item) => item.id == widget.editIncomeId)
                    .firstOrNull;
          await _showIncomeDialog(context, existing);
          if (widget.returnOnEditorClose && mounted) Navigator.pop(context);
          return;
        }
        final existing = widget.editExpenseId == null
            ? null
            : store.data.expenses
                  .where((item) => item.id == widget.editExpenseId)
                  .firstOrNull;
        await _showExpenseDialog(context, existing);
        if (widget.returnOnEditorClose && mounted) Navigator.pop(context);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = ref.watch(appStoreProvider);
    final records = transactionDisplayRecords(store);
    final directionRecords = records.where(
      (item) => switch (_tab) {
        _RecordTab.expense => !item.isIncome,
        _RecordTab.income => item.isIncome,
        _ => true,
      },
    );
    final categories = {'全部', ...directionRecords.map((item) => item.category)};
    if (!categories.contains(_category)) _category = '全部';
    final query = _search.text.trim().toLowerCase();
    final now = DateTime.now();
    final monthStart = DateTime(now.year, now.month);
    final previousStart = DateTime(now.year, now.month - 1);
    final threeMonthStart = DateTime(now.year, now.month - 2);
    final filtered = directionRecords
        .where((item) => _category == '全部' || item.category == _category)
        .where(
          (item) => switch (_dateFilter) {
            _DateFilter.month => !item.date.isBefore(monthStart),
            _DateFilter.previousMonth =>
              !item.date.isBefore(previousStart) &&
                  item.date.isBefore(monthStart),
            _DateFilter.threeMonths => !item.date.isBefore(threeMonthStart),
            _DateFilter.all => true,
          },
        )
        .where(
          (item) => _accountFilter == null || item.accountId == _accountFilter,
        )
        .where(
          (item) =>
              _paymentFilter == null || item.paymentMethod == _paymentFilter,
        )
        .where(
          (item) =>
              query.isEmpty ||
              '${item.item} ${item.category} ${item.detail} ${item.expense?.merchant ?? ''} ${item.expense?.note ?? ''} ${item.income?.note ?? ''}'
                  .toLowerCase()
                  .contains(query),
        )
        .toList();
    final mask = store.data.settings.maskBalances;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PageHeader(
          title: '帳務',
          subtitle: '收入與支出各自入帳，信用卡付款仍由帳單流程處理',
          action: FilledButton.icon(
            onPressed: () => switch (_tab) {
              _RecordTab.income => _showIncomeDialog(context),
              _RecordTab.recurring => _showRecurringExpenseDialog(context),
              _ => _showExpenseDialog(context),
            },
            icon: const Icon(Icons.add),
            label: Text(switch (_tab) {
              _RecordTab.income => '新增收入',
              _RecordTab.recurring => '新增固定支出',
              _ => '新增支出',
            }),
          ),
        ),
        const SizedBox(height: 20),
        ResponsiveGrid(
          minWidth: 180,
          spacing: 12,
          children: [
            SummaryCard(
              label: '本月收入',
              value: moneyText(
                store.currentMonthIncomeDefaultMinor,
                currency: store.data.settings.defaultCurrency,
                mask: mask,
              ),
              compactValue: compactMoneyText(
                store.currentMonthIncomeDefaultMinor,
                currency: store.data.settings.defaultCurrency,
                mask: mask,
              ),
              icon: Icons.south_west_rounded,
              tone: AppColors.income,
            ),
            SummaryCard(
              label: '本月支出',
              value: moneyText(
                store.currentMonthExpenseDefaultMinor,
                currency: store.data.settings.defaultCurrency,
                mask: mask,
              ),
              compactValue: compactMoneyText(
                store.currentMonthExpenseDefaultMinor,
                currency: store.data.settings.defaultCurrency,
                mask: mask,
              ),
              icon: Icons.north_east_rounded,
              tone: AppColors.expense,
            ),
            SummaryCard(
              label: '本月結餘',
              value: moneyText(
                store.currentMonthBalanceDefaultMinor,
                currency: store.data.settings.defaultCurrency,
                mask: mask,
              ),
              compactValue: compactMoneyText(
                store.currentMonthBalanceDefaultMinor,
                currency: store.data.settings.defaultCurrency,
                mask: mask,
              ),
              icon: Icons.account_balance_wallet_outlined,
              tone: store.currentMonthBalanceDefaultMinor >= 0
                  ? AppColors.asset
                  : AppColors.expense,
            ),
          ],
        ),
        const SizedBox(height: 18),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SegmentedButton<_RecordTab>(
            segments: const [
              ButtonSegment(value: _RecordTab.all, label: Text('全部')),
              ButtonSegment(value: _RecordTab.expense, label: Text('支出')),
              ButtonSegment(value: _RecordTab.income, label: Text('收入')),
              ButtonSegment(
                value: _RecordTab.recurring,
                label: Text('固定支出'),
                icon: Icon(Icons.event_repeat_outlined),
              ),
            ],
            selected: {_tab},
            onSelectionChanged: (value) => setState(() {
              _tab = value.first;
              _category = '全部';
            }),
          ),
        ),
        const SizedBox(height: 18),
        if (_tab == _RecordTab.recurring)
          _recurringExpenseList(store)
        else ...[
          TextField(
            controller: _search,
            decoration: InputDecoration(
              hintText: '搜尋交易',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _search.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: '清除搜尋',
                      onPressed: () => setState(_search.clear),
                      icon: const Icon(Icons.close),
                    ),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                DropdownButton<_DateFilter>(
                  value: _dateFilter,
                  underline: const SizedBox.shrink(),
                  items: const [
                    DropdownMenuItem(
                      value: _DateFilter.month,
                      child: Text('本月'),
                    ),
                    DropdownMenuItem(
                      value: _DateFilter.previousMonth,
                      child: Text('上月'),
                    ),
                    DropdownMenuItem(
                      value: _DateFilter.threeMonths,
                      child: Text('近三個月'),
                    ),
                    DropdownMenuItem(
                      value: _DateFilter.all,
                      child: Text('全部日期'),
                    ),
                  ],
                  onChanged: (value) => setState(() => _dateFilter = value!),
                ),
                const SizedBox(width: 16),
                DropdownButton<String?>(
                  value: _accountFilter,
                  underline: const SizedBox.shrink(),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('全部帳戶'),
                    ),
                    for (final account in store.activeAssetAccounts)
                      DropdownMenuItem<String?>(
                        value: account.id,
                        child: Text(account.name),
                      ),
                  ],
                  onChanged: (value) => setState(() => _accountFilter = value),
                ),
                const SizedBox(width: 16),
                DropdownButton<PaymentMethod?>(
                  value: _paymentFilter,
                  underline: const SizedBox.shrink(),
                  items: [
                    const DropdownMenuItem<PaymentMethod?>(
                      value: null,
                      child: Text('付款方式'),
                    ),
                    for (final method in PaymentMethod.values)
                      DropdownMenuItem<PaymentMethod?>(
                        value: method,
                        child: Text(method.label),
                      ),
                  ],
                  onChanged: (value) => setState(() => _paymentFilter = value),
                ),
                if (_accountFilter != null ||
                    _paymentFilter != null ||
                    _dateFilter != _DateFilter.month) ...[
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: () => setState(() {
                      _dateFilter = _DateFilter.month;
                      _accountFilter = null;
                      _paymentFilter = null;
                    }),
                    child: const Text('清除篩選'),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final item in categories)
                ChoiceChip(
                  label: Text(item),
                  avatar: item == '全部'
                      ? null
                      : Icon(categoryVisual(item).icon, size: 16),
                  selected: _category == item,
                  onSelected: (_) => setState(() => _category = item),
                ),
            ],
          ),
          const SizedBox(height: 18),
          if (filtered.isEmpty)
            EmptyState(
              icon: Icons.receipt_long_outlined,
              title: '沒有符合條件的收支',
              message: '新增收入或支出後，會依日期顯示在這裡。',
              action: FilledButton(
                onPressed: () => _showExpenseDialog(context),
                child: const Text('新增消費'),
              ),
            )
          else
            LayoutBuilder(
              builder: (context, constraints) {
                final list = _transactionList(store, filtered);
                final chart = _expenseCategoryChart(store);
                if (constraints.maxWidth < 900) {
                  return Column(
                    children: [list, const SizedBox(height: 16), chart],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 7, child: list),
                    const SizedBox(width: 16),
                    Expanded(flex: 4, child: chart),
                  ],
                );
              },
            ),
        ],
      ],
    );
  }

  Widget _transactionList(
    AppStore store,
    List<TransactionDisplayRecord> records,
  ) {
    DateTime? previousDate;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (final record in records) ...[
            if (previousDate == null ||
                !DateUtils.isSameDay(previousDate, record.date))
              Builder(
                builder: (context) {
                  previousDate = record.date;
                  return Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(18, 10, 18, 8),
                    color: AppColors.background,
                    child: Text(
                      _dateGroupLabel(record.date),
                      style: const TextStyle(
                        color: AppColors.textMuted,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  );
                },
              ),
            ListTile(
              contentPadding: const EdgeInsets.fromLTRB(16, 7, 6, 7),
              leading: CategoryAvatar(category: record.category),
              title: Text(
                record.item,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: Wrap(
                spacing: 7,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  CategoryBadge(category: record.category),
                  Text(record.detail),
                ],
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${record.isIncome ? '+' : '-'}${moneyText(record.amountMinor, currency: record.currency, mask: store.data.settings.maskBalances)}',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: record.isIncome
                          ? AppColors.income
                          : AppColors.expense,
                    ),
                  ),
                  if (record.order case final order?)
                    IconButton(
                      tooltip: '查看代訂',
                      onPressed: () => context.go('/orders/${order.id}'),
                      icon: const Icon(Icons.chevron_right),
                    )
                  else
                    PopupMenuButton<String>(
                      tooltip: '紀錄操作',
                      onSelected: (value) =>
                          _handleRecordAction(store, record, value),
                      itemBuilder: (context) => const [
                        PopupMenuItem(value: 'edit', child: Text('編輯')),
                        PopupMenuItem(value: 'delete', child: Text('刪除')),
                      ],
                    ),
                ],
              ),
            ),
            const Divider(height: 1, indent: 76),
          ],
        ],
      ),
    );
  }

  Future<void> _handleRecordAction(
    AppStore store,
    TransactionDisplayRecord record,
    String action,
  ) async {
    if (action == 'edit') {
      if (record.expense case final expense?) {
        await _showExpenseDialog(context, expense);
      } else if (record.income case final income?) {
        await _showIncomeDialog(context, income);
      }
      return;
    }
    if (action != 'delete') return;
    final label = record.isIncome ? '收入' : '消費';
    if (!await confirmDelete(context, label)) return;
    if (record.expense case final expense?) {
      await store.deleteExpense(expense.id);
    } else if (record.income case final income?) {
      await store.deleteIncome(income.id);
    }
  }

  String _dateGroupLabel(DateTime date) {
    final now = DateTime.now();
    if (DateUtils.isSameDay(date, now)) return '今天';
    if (DateUtils.isSameDay(date, now.subtract(const Duration(days: 1)))) {
      return '昨天';
    }
    return dateText(date);
  }

  Widget _expenseCategoryChart(AppStore store) {
    final now = DateTime.now();
    final grouped = <String, int>{};
    for (final expense in store.data.expenses.where(
      (item) => item.date.year == now.year && item.date.month == now.month,
    )) {
      grouped.update(
        expense.category,
        (value) => value + expense.amountMinor,
        ifAbsent: () => expense.amountMinor,
      );
    }
    for (final order in store.data.orders.where(
      (item) => item.date.year == now.year && item.date.month == now.month,
    )) {
      if (order.selfExpenseMinor > 0) {
        grouped.update(
          '餐飲',
          (value) => value + order.selfExpenseMinor,
          ifAbsent: () => order.selfExpenseMinor,
        );
      }
    }
    final entries = grouped.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final total = entries.fold(0, (sum, entry) => sum + entry.value);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '本月支出分類',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 16),
            if (total == 0)
              const SizedBox(
                height: 240,
                child: EmptyState(
                  icon: Icons.donut_large_outlined,
                  title: '尚無本月支出',
                  message: '新增支出後會顯示分類比例。',
                ),
              )
            else ...[
              Semantics(
                label:
                    '本月支出分類：${entries.map((e) => '${e.key} ${e.value}').join('，')}',
                child: SizedBox(
                  height: 210,
                  child: PieChart(
                    PieChartData(
                      centerSpaceRadius: 48,
                      sectionsSpace: 2,
                      sections: [
                        for (final entry in entries)
                          PieChartSectionData(
                            color: categoryVisual(entry.key).color,
                            value: entry.value.toDouble(),
                            radius: 62,
                            title: '${(entry.value / total * 100).round()}%',
                            titleStyle: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              for (final entry in entries.take(6))
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: categoryVisual(entry.key).color,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(child: Text(entry.key)),
                      Text('${(entry.value / total * 100).round()}%'),
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _recurringExpenseList(AppStore store) {
    final items = [...store.data.recurringExpenses]
      ..sort((a, b) {
        if (a.isActive != b.isActive) return a.isActive ? -1 : 1;
        return a.dayOfMonth.compareTo(b.dayOfMonth);
      });
    if (items.isEmpty) {
      return EmptyState(
        icon: Icons.event_repeat_outlined,
        title: '尚無固定支出',
        message: '設定房租、訂閱或電信月租，雲端會在每月指定日期自動入帳。',
        action: FilledButton(
          onPressed: () => _showRecurringExpenseDialog(context),
          child: const Text('新增固定支出'),
        ),
      );
    }
    return Card(
      child: Column(
        children: [
          for (var index = 0; index < items.length; index++) ...[
            ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 18,
                vertical: 8,
              ),
              leading: CircleAvatar(
                child: Icon(
                  items[index].isTelecom
                      ? Icons.phone_android_outlined
                      : Icons.event_repeat_outlined,
                ),
              ),
              title: Text(
                items[index].item,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: Text(
                '每月 ${items[index].dayOfMonth} 日・${items[index].paymentMethod.label}・'
                '${items[index].isActive ? '啟用中' : '已停用'}',
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    moneyText(
                      items[index].amountMinor,
                      mask: store.data.settings.maskBalances,
                    ),
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  PopupMenuButton<String>(
                    onSelected: (value) async {
                      if (value == 'edit') {
                        await _showRecurringExpenseDialog(
                          context,
                          items[index],
                        );
                      } else if (value == 'toggle') {
                        await store.setRecurringExpenseActive(
                          items[index].id,
                          !items[index].isActive,
                        );
                      }
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem(value: 'edit', child: Text('編輯')),
                      PopupMenuItem(
                        value: 'toggle',
                        child: Text(items[index].isActive ? '停用' : '重新啟用'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (index < items.length - 1) const Divider(height: 1, indent: 76),
          ],
        ],
      ),
    );
  }

  Future<void> _showRecurringExpenseDialog(
    BuildContext context, [
    RecurringExpense? existing,
  ]) async {
    final store = ref.read(appStoreProvider);
    final now = DateTime.now();
    final item = TextEditingController(text: existing?.item);
    final amount = TextEditingController(
      text: existing == null ? '' : (existing.amountMinor / 100).toString(),
    );
    final note = TextEditingController(text: existing?.note);
    var category = existing?.category ?? '訂閱';
    var method = existing?.paymentMethod ?? PaymentMethod.transfer;
    var day = existing?.dayOfMonth ?? now.day;
    var startMonth =
        existing?.startMonth ??
        '${now.year}-${now.month.toString().padLeft(2, '0')}';
    var accountId =
        existing?.accountId ??
        store.defaultBankTransferAccountId ??
        store.activeAssetAccounts.firstOrNull?.id;
    var cardId = existing?.cardId;
    cardId ??= method == PaymentMethod.debitCard
        ? store.data.cards.where((card) => card.isDebit).firstOrNull?.id
        : store.data.cards.where((card) => card.isCredit).firstOrNull?.id;
    var telecomDebitAccountId =
        existing?.telecomDebitAccountId ?? store.defaultBankTransferAccountId;
    var necessary = existing?.isNecessary ?? true;
    var active = existing?.isActive ?? true;
    final formKey = GlobalKey<FormState>();

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(existing == null ? '新增固定支出' : '編輯固定支出'),
          content: SizedBox(
            width: 560,
            child: Form(
              key: formKey,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      controller: item,
                      autofocus: true,
                      decoration: const InputDecoration(labelText: '支出項目'),
                      validator: (value) =>
                          value == null || value.trim().isEmpty
                          ? '請輸入項目'
                          : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: amount,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: '每月金額',
                        prefixText: r'NT$ ',
                      ),
                      validator: (value) =>
                          parseMoney(value ?? '') <= 0 ? '金額需大於 0' : null,
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: category,
                      decoration: const InputDecoration(labelText: '分類'),
                      items: store
                          .categoryNamesFor(
                            BookkeepingCategoryKind.expense,
                            includeInactiveName: category,
                          )
                          .map(
                            (value) => DropdownMenuItem(
                              value: value,
                              child: Text(value),
                            ),
                          )
                          .toList(),
                      onChanged: (value) => setState(() => category = value!),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<PaymentMethod>(
                      initialValue: method,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: '付款方式'),
                      items: PaymentMethod.values
                          .map(
                            (value) => DropdownMenuItem(
                              value: value,
                              child: Text(value.label),
                            ),
                          )
                          .toList(),
                      onChanged: (value) => setState(() => method = value!),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<int>(
                            initialValue: day,
                            decoration: const InputDecoration(
                              labelText: '每月執行日',
                            ),
                            items: List.generate(31, (index) => index + 1)
                                .map(
                                  (value) => DropdownMenuItem(
                                    value: value,
                                    child: Text('$value 日'),
                                  ),
                                )
                                .toList(),
                            onChanged: (value) => setState(() => day = value!),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextFormField(
                            initialValue: startMonth,
                            decoration: const InputDecoration(
                              labelText: '生效月份',
                              hintText: 'YYYY-MM',
                            ),
                            validator: (value) =>
                                RegExp(
                                  r'^\d{4}-(0[1-9]|1[0-2])$',
                                ).hasMatch(value ?? '')
                                ? null
                                : '格式需為 YYYY-MM',
                            onChanged: (value) => startMonth = value,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (method == PaymentMethod.creditCard ||
                        method == PaymentMethod.debitCard)
                      DropdownButtonFormField<String>(
                        initialValue:
                            store.data.cards.any(
                              (c) =>
                                  c.id == cardId &&
                                  (method == PaymentMethod.creditCard
                                      ? c.isCredit
                                      : c.isDebit),
                            )
                            ? cardId
                            : null,
                        decoration: InputDecoration(
                          labelText: method == PaymentMethod.creditCard
                              ? '信用卡'
                              : '金融卡',
                          helperText: method == PaymentMethod.debitCard
                              ? '消費會直接扣除卡片綁定的帳戶'
                              : null,
                        ),
                        items: store.data.cards
                            .where(
                              (card) => method == PaymentMethod.creditCard
                                  ? card.isCredit
                                  : card.isDebit,
                            )
                            .map(
                              (card) => DropdownMenuItem(
                                value: card.id,
                                child: Text('${card.name} •${card.lastFour}'),
                              ),
                            )
                            .toList(),
                        validator: (value) => value == null
                            ? '請先新增${method == PaymentMethod.creditCard ? '信用卡' : '金融卡'}'
                            : null,
                        onChanged: (value) => setState(() => cardId = value),
                      )
                    else if (method == PaymentMethod.telecomBill)
                      DropdownButtonFormField<String>(
                        initialValue:
                            store.bankTransferAccounts.any(
                              (a) => a.id == telecomDebitAccountId,
                            )
                            ? telecomDebitAccountId
                            : null,
                        decoration: const InputDecoration(
                          labelText: '電信帳單扣款帳號',
                        ),
                        items: store.bankTransferAccounts
                            .map(
                              (account) => DropdownMenuItem(
                                value: account.id,
                                child: Text(account.name),
                              ),
                            )
                            .toList(),
                        validator: (value) =>
                            value == null ? '請先新增台幣銀行帳戶' : null,
                        onChanged: (value) =>
                            setState(() => telecomDebitAccountId = value),
                      )
                    else
                      DropdownButtonFormField<String>(
                        initialValue:
                            store.activeAssetAccounts.any(
                              (a) => a.id == accountId,
                            )
                            ? accountId
                            : null,
                        decoration: const InputDecoration(labelText: '付款帳戶'),
                        items: store.activeAssetAccounts
                            .map(
                              (account) => DropdownMenuItem(
                                value: account.id,
                                child: Text(account.name),
                              ),
                            )
                            .toList(),
                        validator: (value) => value == null ? '請先新增帳戶' : null,
                        onChanged: (value) => setState(() => accountId = value),
                      ),
                    const SizedBox(height: 8),
                    ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      title: const Text('進階設定'),
                      children: [
                        TextField(
                          controller: note,
                          decoration: const InputDecoration(labelText: '備註'),
                        ),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('必要支出'),
                          value: necessary,
                          onChanged: (value) =>
                              setState(() => necessary = value),
                        ),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('啟用自動入帳'),
                          value: active,
                          onChanged: (value) => setState(() => active = value),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () async {
                if (!formKey.currentState!.validate()) return;
                if (method == PaymentMethod.telecomBill &&
                    active &&
                    store.data.recurringExpenses.any(
                      (rule) =>
                          rule.id != existing?.id &&
                          rule.isActive &&
                          rule.isTelecom,
                    )) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('只能啟用一組電信帳單固定支出')),
                  );
                  return;
                }
                await store.upsertRecurringExpense(
                  RecurringExpense(
                    id: existing?.id ?? store.newId(),
                    userId: store.userId,
                    item: item.text.trim(),
                    category: category,
                    amountMinor: parseMoney(amount.text),
                    paymentMethod: method,
                    dayOfMonth: day,
                    startMonth: startMonth,
                    accountId: method == PaymentMethod.debitCard
                        ? store.cardById(cardId)?.debitAccountId
                        : method != PaymentMethod.creditCard &&
                              method != PaymentMethod.telecomBill
                        ? accountId
                        : null,
                    cardId: method == PaymentMethod.creditCard ? cardId : null,
                    telecomDebitAccountId: method == PaymentMethod.telecomBill
                        ? telecomDebitAccountId
                        : null,
                    isActive: active,
                    isNecessary: necessary,
                    note: note.text.trim(),
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

  Future<void> _showIncomeDialog(
    BuildContext context, [
    IncomeEntry? existing,
  ]) async {
    final store = ref.read(appStoreProvider);
    final item = TextEditingController(text: existing?.item);
    final amount = TextEditingController(
      text: existing == null ? '' : (existing.amountMinor / 100).toString(),
    );
    final note = TextEditingController(text: existing?.note);
    var date = existing?.date ?? DateTime.now();
    var category = existing?.category ?? '薪資';
    var accountId =
        existing?.accountId ??
        store.defaultBankTransferAccountId ??
        store.activeAssetAccounts.firstOrNull?.id;
    final formKey = GlobalKey<FormState>();
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(existing == null ? '新增收入' : '編輯收入'),
          content: SizedBox(
            width: 520,
            child: Form(
              key: formKey,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: TextFormField(
                            controller: item,
                            autofocus: true,
                            decoration: const InputDecoration(
                              labelText: '收入項目',
                            ),
                            validator: (value) =>
                                value == null || value.trim().isEmpty
                                ? '請輸入項目'
                                : null,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextFormField(
                            controller: amount,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: const InputDecoration(labelText: '金額'),
                            validator: (value) =>
                                parseMoney(value ?? '') <= 0 ? '金額需大於 0' : null,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    InkWell(
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: date,
                          firstDate: DateTime(2000),
                          lastDate: DateTime.now().add(
                            const Duration(days: 365),
                          ),
                        );
                        if (picked != null) setDialogState(() => date = picked);
                      },
                      child: InputDecorator(
                        decoration: const InputDecoration(
                          labelText: '收入日期',
                          suffixIcon: Icon(Icons.calendar_today_outlined),
                        ),
                        child: Text(dateText(date)),
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: category,
                      decoration: const InputDecoration(labelText: '收入分類'),
                      items: store
                          .categoryNamesFor(
                            BookkeepingCategoryKind.income,
                            includeInactiveName: category,
                          )
                          .map(
                            (value) => DropdownMenuItem(
                              value: value,
                              child: Text(value),
                            ),
                          )
                          .toList(),
                      onChanged: (value) =>
                          setDialogState(() => category = value!),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue:
                          store.activeAssetAccounts.any(
                            (a) => a.id == accountId,
                          )
                          ? accountId
                          : null,
                      decoration: const InputDecoration(labelText: '收款帳戶'),
                      items: store.activeAssetAccounts
                          .map(
                            (account) => DropdownMenuItem(
                              value: account.id,
                              child: Text(
                                '${account.name}・${account.currency}',
                              ),
                            ),
                          )
                          .toList(),
                      validator: (value) => value == null ? '請先新增帳戶' : null,
                      onChanged: (value) =>
                          setDialogState(() => accountId = value),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: note,
                      decoration: const InputDecoration(labelText: '備註'),
                    ),
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () async {
                if (!formKey.currentState!.validate()) return;
                await store.upsertIncome(
                  IncomeEntry(
                    id: existing?.id ?? store.newId(),
                    userId: store.userId,
                    date: date,
                    amountMinor: parseMoney(amount.text),
                    item: item.text.trim(),
                    category: category,
                    accountId: accountId!,
                    note: note.text.trim(),
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

  Future<void> _showExpenseDialog(
    BuildContext context, [
    Expense? existing,
  ]) async {
    final store = ref.read(appStoreProvider);
    final item = TextEditingController(text: existing?.item);
    final amount = TextEditingController(
      text: existing == null ? '' : (existing.amountMinor / 100).toString(),
    );
    final merchant = TextEditingController(text: existing?.merchant);
    final note = TextEditingController(text: existing?.note);
    var date = existing?.date ?? DateTime.now();
    var category = existing?.category ?? store.data.settings.defaultCategory;
    var method =
        existing?.paymentMethod ?? store.data.settings.defaultPaymentMethod;
    var accountId =
        existing?.accountId ?? store.activeAssetAccounts.firstOrNull?.id;
    var cardId = existing?.cardId;
    cardId ??= method == PaymentMethod.debitCard
        ? store.data.cards
                  .where(
                    (card) =>
                        card.isDebit &&
                        card.debitAccountId == existing?.accountId,
                  )
                  .firstOrNull
                  ?.id ??
              store.data.cards.where((card) => card.isDebit).firstOrNull?.id
        : store.data.cards.where((card) => card.isCredit).firstOrNull?.id;
    var necessary = existing?.isNecessary ?? false;
    final formKey = GlobalKey<FormState>();
    Widget itemField() => TextFormField(
      controller: item,
      autofocus: true,
      decoration: const InputDecoration(labelText: '消費項目'),
      validator: (value) =>
          value == null || value.trim().isEmpty ? '請輸入項目' : null,
    );
    Widget amountField() => TextFormField(
      controller: amount,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: const InputDecoration(labelText: '金額', prefixText: r'NT$ '),
      validator: (value) => parseMoney(value ?? '') <= 0 ? '金額需大於 0' : null,
    );
    Widget categoryField(StateSetter setDialogState) =>
        DropdownButtonFormField<String>(
          initialValue: category,
          decoration: const InputDecoration(labelText: '消費分類'),
          items: store
              .categoryNamesFor(
                BookkeepingCategoryKind.expense,
                includeInactiveName: category,
              )
              .map(
                (value) => DropdownMenuItem(value: value, child: Text(value)),
              )
              .toList(),
          onChanged: (value) => setDialogState(() => category = value!),
        );
    Widget paymentField(StateSetter setDialogState) =>
        DropdownButtonFormField<PaymentMethod>(
          initialValue: method,
          isExpanded: true,
          decoration: const InputDecoration(labelText: '付款方式'),
          items: PaymentMethod.values
              .map(
                (value) =>
                    DropdownMenuItem(value: value, child: Text(value.label)),
              )
              .toList(),
          onChanged: (value) => setDialogState(() => method = value!),
        );
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(existing == null ? '新增消費' : '編輯消費'),
          content: SizedBox(
            width: 520,
            child: Form(
              key: formKey,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    LayoutBuilder(
                      builder: (context, constraints) =>
                          constraints.maxWidth < 360
                          ? Column(
                              children: [
                                itemField(),
                                const SizedBox(height: 12),
                                amountField(),
                              ],
                            )
                          : Row(
                              children: [
                                Expanded(flex: 2, child: itemField()),
                                const SizedBox(width: 12),
                                Expanded(child: amountField()),
                              ],
                            ),
                    ),
                    const SizedBox(height: 12),
                    InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: date,
                          firstDate: DateTime(2000),
                          lastDate: DateTime.now().add(
                            const Duration(days: 365),
                          ),
                        );
                        if (picked != null) setState(() => date = picked);
                      },
                      child: InputDecorator(
                        decoration: const InputDecoration(
                          labelText: '消費日期',
                          suffixIcon: Icon(Icons.calendar_today_outlined),
                        ),
                        child: Text(dateText(date)),
                      ),
                    ),
                    const SizedBox(height: 12),
                    LayoutBuilder(
                      builder: (context, constraints) =>
                          constraints.maxWidth < 360
                          ? Column(
                              children: [
                                categoryField(setState),
                                const SizedBox(height: 12),
                                paymentField(setState),
                              ],
                            )
                          : Row(
                              children: [
                                Expanded(child: categoryField(setState)),
                                const SizedBox(width: 12),
                                Expanded(child: paymentField(setState)),
                              ],
                            ),
                    ),
                    const SizedBox(height: 12),
                    if (method == PaymentMethod.creditCard ||
                        method == PaymentMethod.debitCard)
                      DropdownButtonFormField<String>(
                        initialValue:
                            store.data.cards.any(
                              (item) =>
                                  item.id == cardId &&
                                  (method == PaymentMethod.creditCard
                                      ? item.isCredit
                                      : item.isDebit),
                            )
                            ? cardId
                            : null,
                        decoration: InputDecoration(
                          labelText: method == PaymentMethod.creditCard
                              ? '信用卡'
                              : '金融卡',
                          helperText: method == PaymentMethod.debitCard
                              ? '消費會直接扣除卡片綁定的帳戶'
                              : null,
                        ),
                        items: store.data.cards
                            .where(
                              (card) => method == PaymentMethod.creditCard
                                  ? card.isCredit
                                  : card.isDebit,
                            )
                            .map(
                              (card) => DropdownMenuItem(
                                value: card.id,
                                child: Text('${card.name} •${card.lastFour}'),
                              ),
                            )
                            .toList(),
                        validator: (value) => value == null
                            ? '請先新增${method == PaymentMethod.creditCard ? '信用卡' : '金融卡'}'
                            : null,
                        onChanged: (value) => setState(() => cardId = value),
                      )
                    else if (method == PaymentMethod.telecomBill)
                      InputDecorator(
                        decoration: InputDecoration(
                          labelText: '電信帳單',
                          errorText: store.activeTelecomExpense == null
                              ? '請先到固定支出設定電信月租與扣款帳號'
                              : null,
                          prefixIcon: const Icon(Icons.phone_android_outlined),
                        ),
                        child: Text(store.activeTelecomExpense?.item ?? '尚未設定'),
                      )
                    else
                      DropdownButtonFormField<String>(
                        initialValue:
                            store.activeAssetAccounts.any(
                              (item) => item.id == accountId,
                            )
                            ? accountId
                            : null,
                        decoration: const InputDecoration(labelText: '付款帳戶'),
                        items: store.activeAssetAccounts
                            .map(
                              (account) => DropdownMenuItem(
                                value: account.id,
                                child: Text(account.name),
                              ),
                            )
                            .toList(),
                        validator: (value) => value == null ? '請先新增帳戶' : null,
                        onChanged: (value) => setState(() => accountId = value),
                      ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: merchant,
                      decoration: const InputDecoration(labelText: '店家'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: note,
                      decoration: const InputDecoration(labelText: '備註'),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('必要支出'),
                      value: necessary,
                      onChanged: (value) => setState(() => necessary = value),
                    ),
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () async {
                if (!formKey.currentState!.validate()) return;
                if (method == PaymentMethod.telecomBill &&
                    store.activeTelecomExpense == null) {
                  return;
                }
                await store.upsertExpense(
                  Expense(
                    id: existing?.id ?? store.newId(),
                    userId: store.userId,
                    date: date,
                    amountMinor: parseMoney(amount.text),
                    paymentMethod: method,
                    item: item.text.trim(),
                    category: category,
                    accountId: method == PaymentMethod.debitCard
                        ? store.cardById(cardId)?.debitAccountId
                        : method == PaymentMethod.creditCard ||
                              method == PaymentMethod.telecomBill
                        ? null
                        : accountId,
                    cardId:
                        method == PaymentMethod.creditCard ||
                            method == PaymentMethod.debitCard
                        ? cardId
                        : null,
                    billId: existing?.billId,
                    merchant: merchant.text.trim(),
                    note: note.text.trim(),
                    isNecessary: necessary,
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
}
