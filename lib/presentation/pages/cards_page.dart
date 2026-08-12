import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../application/providers.dart';
import '../../domain/models.dart';
import '../widgets/common.dart';

class CardsPage extends ConsumerStatefulWidget {
  const CardsPage({
    this.editBillId,
    this.returnOnEditorClose = false,
    super.key,
  });

  final String? editBillId;
  final bool returnOnEditorClose;

  @override
  ConsumerState<CardsPage> createState() => _CardsPageState();
}

class _CardsPageState extends ConsumerState<CardsPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this);
  bool _editorOpened = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (widget.editBillId == null || _editorOpened) return;
    _editorOpened = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final bill = ref
          .read(appStoreProvider)
          .data
          .bills
          .where((item) => item.id == widget.editBillId)
          .firstOrNull;
      if (bill != null) await _showBillDialog(context, bill);
      if (widget.returnOnEditorClose && mounted) Navigator.pop(context);
    });
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final store = ref.watch(appStoreProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PageHeader(
          title: '信用卡',
          subtitle: '管理卡片、帳單與自動扣款提醒',
          action: FilledButton.icon(
            onPressed: () => _tabs.index == 0
                ? _showCardDialog(context)
                : _showBillDialog(context),
            icon: const Icon(Icons.add),
            label: const Text('新增'),
          ),
        ),
        const SizedBox(height: 20),
        Card(
          child: TabBar(
            controller: _tabs,
            tabs: const [
              Tab(text: '信用卡'),
              Tab(text: '帳單與扣款'),
            ],
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 620,
          child: TabBarView(
            controller: _tabs,
            children: [
              _CardsList(onEdit: (card) => _showCardDialog(context, card)),
              _BillsList(onEdit: (bill) => _showBillDialog(context, bill)),
            ],
          ),
        ),
        Card(
          color: const Color(0xFFFFF8E8),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Icon(Icons.info_outline, color: Color(0xFF9A6A00)),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '目前待扣款 ${moneyText(store.pendingCardMinor)}，'
                    '包含未入帳單刷卡與帳單未繳餘額。',
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _showCardDialog(
    BuildContext context, [
    CreditCard? existing,
  ]) async {
    final store = ref.read(appStoreProvider);
    final name = TextEditingController(text: existing?.name);
    final bank = TextEditingController(text: existing?.bank);
    final lastFour = TextEditingController(text: existing?.lastFour);
    final note = TextEditingController(text: existing?.note);
    var closingDay = existing?.closingDay ?? 15;
    var dueDay = existing?.dueDay ?? 28;
    var debitDay = existing?.autoDebitDay ?? 28;
    var accountId =
        existing?.debitAccountId ??
        (store.data.accounts.isEmpty ? null : store.data.accounts.first.id);
    var active = existing?.isActive ?? true;
    final formKey = GlobalKey<FormState>();
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(existing == null ? '新增信用卡' : '編輯信用卡'),
          content: SizedBox(
            width: 500,
            child: Form(
              key: formKey,
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    TextFormField(
                      controller: name,
                      decoration: const InputDecoration(labelText: '信用卡名稱'),
                      validator: (value) =>
                          value == null || value.trim().isEmpty
                          ? '請輸入名稱'
                          : null,
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: bank,
                            decoration: const InputDecoration(
                              labelText: '發卡銀行',
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextFormField(
                            controller: lastFour,
                            maxLength: 4,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: '卡號末四碼',
                            ),
                            validator: (value) =>
                                value?.length == 4 ? null : '請輸入四碼',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        for (final entry in [
                          ('結帳日', closingDay),
                          ('繳款截止日', dueDay),
                          ('自動扣款日', debitDay),
                        ])
                          Expanded(
                            child: Padding(
                              padding: EdgeInsets.only(
                                right: entry.$1 == '自動扣款日' ? 0 : 8,
                              ),
                              child: DropdownButtonFormField<int>(
                                initialValue: entry.$2,
                                decoration: InputDecoration(
                                  labelText: entry.$1,
                                ),
                                items: List.generate(
                                  31,
                                  (index) => DropdownMenuItem(
                                    value: index + 1,
                                    child: Text('${index + 1} 日'),
                                  ),
                                ),
                                onChanged: (value) => setState(() {
                                  if (entry.$1 == '結帳日') closingDay = value!;
                                  if (entry.$1 == '繳款截止日') dueDay = value!;
                                  if (entry.$1 == '自動扣款日') debitDay = value!;
                                }),
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue:
                          store.data.accounts.any(
                            (item) => item.id == accountId,
                          )
                          ? accountId
                          : null,
                      decoration: const InputDecoration(labelText: '自動扣款帳戶'),
                      items: store.data.accounts
                          .map(
                            (account) => DropdownMenuItem(
                              value: account.id,
                              child: Text(account.name),
                            ),
                          )
                          .toList(),
                      validator: (value) => value == null ? '請選擇帳戶' : null,
                      onChanged: (value) => setState(() => accountId = value),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: note,
                      decoration: const InputDecoration(labelText: '備註'),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('啟用信用卡'),
                      value: active,
                      onChanged: (value) => setState(() => active = value),
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
                await store.upsertCard(
                  CreditCard(
                    id: existing?.id ?? store.newId(),
                    userId: store.userId,
                    name: name.text.trim(),
                    bank: bank.text.trim(),
                    lastFour: lastFour.text.trim(),
                    closingDay: closingDay,
                    dueDay: dueDay,
                    autoDebitDay: debitDay,
                    debitAccountId: accountId!,
                    isActive: active,
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

  Future<void> _showBillDialog(
    BuildContext context, [
    CardBill? existing,
  ]) async {
    final store = ref.read(appStoreProvider);
    var cardId =
        existing?.cardId ??
        (store.data.cards.isEmpty ? null : store.data.cards.first.id);
    final now = DateTime.now();
    final month = TextEditingController(
      text:
          existing?.month ??
          '${now.year}-${now.month.toString().padLeft(2, '0')}',
    );
    final adjustment = TextEditingController(
      text: existing == null
          ? '0'
          : (existing.manualAdjustmentMinor / 100).toString(),
    );
    final paid = TextEditingController(
      text: existing == null ? '0' : (existing.paidMinor / 100).toString(),
    );
    final note = TextEditingController(text: existing?.note);
    var dueDate = existing?.dueDate ?? now.add(const Duration(days: 20));
    var debitDate =
        existing?.autoDebitDate ?? now.add(const Duration(days: 21));
    final selected = <String>{...?existing?.chargeIds};
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) {
          final candidates = <({String id, String label, int amount})>[
            for (final expense in store.data.expenses.where(
              (item) =>
                  item.isCreditCard &&
                  item.cardId == cardId &&
                  store.canAssignChargeToBill(
                    'expense:${item.id}',
                    cardId ?? '',
                    billId: existing?.id,
                  ),
            ))
              (
                id: 'expense:${expense.id}',
                label: '${dateText(expense.date)} ${expense.item}',
                amount: expense.amountMinor,
              ),
            for (final order in store.data.orders.where(
              (item) =>
                  item.cardId == cardId &&
                  store.canAssignChargeToBill(
                    'order:${item.id}',
                    cardId ?? '',
                    billId: existing?.id,
                  ),
            ))
              (
                id: 'order:${order.id}',
                label:
                    '${dateText(order.date)} ${order.name} '
                    '（本人 ${moneyText(order.selfExpenseMinor)}／'
                    '代墊 ${moneyText(order.advanceCardMinor)}）',
                amount: order.totalMinor,
              ),
          ];
          selected.retainAll(candidates.map((item) => item.id).toSet());
          final preview =
              candidates
                  .where((item) => selected.contains(item.id))
                  .fold(0, (sum, item) => sum + item.amount) +
              parseMoney(adjustment.text);
          return AlertDialog(
            title: Text(existing == null ? '新增信用卡帳單' : '編輯信用卡帳單'),
            content: SizedBox(
              width: 560,
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    DropdownButtonFormField<String>(
                      initialValue:
                          store.data.cards.any((item) => item.id == cardId)
                          ? cardId
                          : null,
                      decoration: const InputDecoration(labelText: '信用卡'),
                      items: store.data.cards
                          .map(
                            (card) => DropdownMenuItem(
                              value: card.id,
                              child: Text(card.name),
                            ),
                          )
                          .toList(),
                      onChanged: (value) => setState(() {
                        cardId = value;
                        selected.removeWhere(
                          (id) =>
                              value == null ||
                              !store.canAssignChargeToBill(
                                id,
                                value,
                                billId: existing?.id,
                              ),
                        );
                      }),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: month,
                      decoration: const InputDecoration(
                        labelText: '帳單月份',
                        hintText: '2026-07',
                      ),
                    ),
                    const SizedBox(height: 16),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        '選擇納入本期的刷卡紀錄',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    if (candidates.isEmpty)
                      const ListTile(title: Text('此卡目前沒有刷卡紀錄'))
                    else
                      for (final item in candidates)
                        CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          value: selected.contains(item.id),
                          title: Text(item.label),
                          secondary: Text(moneyText(item.amount)),
                          onChanged: (value) => setState(() {
                            value == true
                                ? selected.add(item.id)
                                : selected.remove(item.id);
                          }),
                        ),
                    TextField(
                      controller: adjustment,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                        signed: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: '帳單人工調整',
                        helperText: '回饋或折抵可填負數',
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: paid,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: '已繳金額',
                        helperText: '可記錄部分繳款；繳款會扣除自動扣款帳戶',
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _DateField(
                            label: '繳款截止日',
                            date: dueDate,
                            onChanged: (value) =>
                                setState(() => dueDate = value),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _DateField(
                            label: '自動扣款日',
                            date: debitDate,
                            onChanged: (value) =>
                                setState(() => debitDate = value),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: note,
                      decoration: const InputDecoration(labelText: '備註'),
                    ),
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Text(
                        '預計帳單金額 ${moneyText(preview)}',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: cardId == null
                    ? null
                    : () async {
                        await store.upsertBill(
                          CardBill(
                            id: existing?.id ?? store.newId(),
                            userId: store.userId,
                            cardId: cardId!,
                            month: month.text.trim(),
                            chargeIds: selected.toList(),
                            manualAdjustmentMinor: parseMoney(adjustment.text),
                            paidMinor: parseMoney(
                              paid.text,
                            ).clamp(0, preview < 0 ? 0 : preview).toInt(),
                            dueDate: dueDate,
                            autoDebitDate: debitDate,
                            note: note.text.trim(),
                            origin: existing?.origin ?? DataOrigin.user,
                          ),
                        );
                        if (dialogContext.mounted) Navigator.pop(dialogContext);
                      },
                child: const Text('儲存'),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _CardsList extends ConsumerWidget {
  const _CardsList({required this.onEdit});
  final ValueChanged<CreditCard> onEdit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final store = ref.watch(appStoreProvider);
    if (store.data.cards.isEmpty) {
      return const EmptyState(
        icon: Icons.credit_card_outlined,
        title: '還沒有信用卡',
        message: '先新增信用卡，再記錄刷卡消費與帳單。',
      );
    }
    return ListView.separated(
      itemCount: store.data.cards.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final card = store.data.cards[index];
        final records = <_CardChargeRecord>[
          for (final expense in store.data.expenses.where(
            (item) => item.isCreditCard && item.cardId == card.id,
          ))
            _CardChargeRecord(
              id: 'expense:${expense.id}',
              sourceId: expense.id,
              date: expense.date,
              item: expense.item,
              detail: expense.merchant.isEmpty
                  ? '一般消費'
                  : '一般消費・${expense.merchant}',
              amountMinor: expense.amountMinor,
              isOrder: false,
            ),
          for (final order in store.data.orders.where(
            (item) => item.cardId == card.id,
          ))
            _CardChargeRecord(
              id: 'order:${order.id}',
              sourceId: order.id,
              date: order.date,
              item: order.name,
              detail: '代訂刷卡・${order.platform}',
              amountMinor: order.totalMinor,
              isOrder: true,
            ),
        ]..sort((a, b) => b.date.compareTo(a.date));
        final unbilled = store.unbilledCardMinor(card.id);
        return Card(
          clipBehavior: Clip.antiAlias,
          child: ExpansionTile(
            key: PageStorageKey('card-${card.id}'),
            tilePadding: const EdgeInsets.symmetric(
              horizontal: 18,
              vertical: 8,
            ),
            childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            leading: const CircleAvatar(child: Icon(Icons.credit_card)),
            title: Row(
              children: [
                Expanded(
                  child: Text(
                    card.name,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                PopupMenuButton<String>(
                  tooltip: '信用卡操作',
                  onSelected: (value) async {
                    if (value == 'edit') {
                      WidgetsBinding.instance.addPostFrameCallback(
                        (_) => onEdit(card),
                      );
                      return;
                    }
                    if (value == 'delete' &&
                        await confirmDelete(context, '信用卡')) {
                      await store.deleteCard(card.id);
                    }
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem(value: 'edit', child: Text('編輯')),
                    PopupMenuItem(value: 'delete', child: Text('刪除')),
                  ],
                ),
              ],
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '${card.bank} •${card.lastFour}\n'
                '${card.closingDay} 日結帳・${card.autoDebitDay} 日自動扣款・'
                '${accountName(store, card.debitAccountId)}\n'
                '未入帳 ${moneyText(unbilled, mask: store.data.settings.maskBalances)}',
              ),
            ),
            children: [
              const Divider(height: 1),
              if (records.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.receipt_long_outlined),
                      SizedBox(width: 10),
                      Text('目前沒有刷卡紀錄'),
                    ],
                  ),
                )
              else
                for (final record in records)
                  Builder(
                    builder: (context) {
                      final bill = store.cardBillForCharge(record.id);
                      final status = bill == null
                          ? '未入帳'
                          : '已列入 ${bill.month} 帳單';
                      return ListTile(
                        leading: Icon(
                          record.isOrder
                              ? Icons.groups_outlined
                              : Icons.receipt_long_outlined,
                        ),
                        title: Text(record.item),
                        subtitle: Text(
                          '${dateText(record.date)}・${record.detail}\n$status',
                        ),
                        isThreeLine: true,
                        trailing: Text(
                          moneyText(
                            record.amountMinor,
                            mask: store.data.settings.maskBalances,
                          ),
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        onTap: () => context.go(
                          record.isOrder
                              ? '/orders/${record.sourceId}'
                              : '/expenses?edit=${record.sourceId}',
                        ),
                      );
                    },
                  ),
            ],
          ),
        );
      },
    );
  }
}

class _CardChargeRecord {
  const _CardChargeRecord({
    required this.id,
    required this.sourceId,
    required this.date,
    required this.item,
    required this.detail,
    required this.amountMinor,
    required this.isOrder,
  });

  final String id;
  final String sourceId;
  final DateTime date;
  final String item;
  final String detail;
  final int amountMinor;
  final bool isOrder;
}

class _BillsList extends ConsumerWidget {
  const _BillsList({required this.onEdit});
  final ValueChanged<CardBill> onEdit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final store = ref.watch(appStoreProvider);
    if (store.data.bills.isEmpty) {
      return const EmptyState(
        icon: Icons.calendar_month_outlined,
        title: '還沒有帳單',
        message: '將未入帳單刷卡紀錄組成本期帳單。',
      );
    }
    return ListView.separated(
      itemCount: store.data.bills.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final bill = store.data.bills[index];
        final amount = store.billAmount(bill);
        final outstanding = (amount - bill.paidMinor).clamp(0, amount).toInt();
        final paid = outstanding == 0;
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor: paid
                      ? const Color(0xFFDFF4EA)
                      : const Color(0xFFFFE9DD),
                  child: Icon(
                    paid ? Icons.check : Icons.notifications_none,
                    color: paid
                        ? const Color(0xFF0E7C66)
                        : const Color(0xFFD35D2A),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${store.cardById(bill.cardId)?.name ?? '信用卡'} ${bill.month}',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      Text(
                        '截止 ${dateText(bill.dueDate)}・'
                        '自動扣款 ${dateText(bill.autoDebitDate)}',
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      moneyText(amount),
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(paid ? '已繳清' : '未繳 ${moneyText(outstanding)}'),
                  ],
                ),
                PopupMenuButton<String>(
                  onSelected: (value) async {
                    if (value == 'edit') {
                      WidgetsBinding.instance.addPostFrameCallback(
                        (_) => onEdit(bill),
                      );
                    } else if (value == 'pay') {
                      await store.payBill(bill.id);
                    } else if (value == 'delete') {
                      final confirmed = await confirmDelete(context, '帳單');
                      if (confirmed) await store.deleteBill(bill.id);
                    }
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(value: 'edit', child: Text('編輯')),
                    if (!paid)
                      const PopupMenuItem(value: 'pay', child: Text('標記已繳清')),
                    const PopupMenuItem(value: 'delete', child: Text('刪除')),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _DateField extends StatelessWidget {
  const _DateField({
    required this.label,
    required this.date,
    required this.onChanged,
  });
  final String label;
  final DateTime date;
  final ValueChanged<DateTime> onChanged;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: () async {
      final value = await showDatePicker(
        context: context,
        initialDate: date,
        firstDate: DateTime(2000),
        lastDate: DateTime.now().add(const Duration(days: 730)),
      );
      if (value != null) onChanged(value);
    },
    child: InputDecorator(
      decoration: InputDecoration(labelText: label),
      child: Text(dateText(date)),
    ),
  );
}
