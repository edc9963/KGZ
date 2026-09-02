import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../application/app_store.dart';
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
    return LayoutBuilder(
      builder: (context, constraints) {
        final tabView = TabBarView(
          controller: _tabs,
          children: [
            _CardsList(onEdit: (card) => _showCardDialog(context, card)),
            _BillsList(onEdit: (bill) => _showBillDialog(context, bill)),
          ],
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            PageHeader(
              title: '卡片',
              subtitle: '管理信用卡帳單，以及直接扣款的金融卡',
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
                  Tab(text: '卡片'),
                  Tab(text: '信用卡帳單'),
                ],
              ),
            ),
            const SizedBox(height: 16),
            if (constraints.hasBoundedHeight)
              Expanded(child: tabView)
            else
              SizedBox(height: 620, child: tabView),
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
      },
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
        existing?.debitAccountId ?? store.activeAssetAccounts.firstOrNull?.id;
    var active = existing?.isActive ?? true;
    var cardType = existing?.cardType ?? PaymentCardType.credit;
    final formKey = GlobalKey<FormState>();
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(
            existing == null ? '新增卡片' : '編輯${existing.cardType.label}',
          ),
          content: SizedBox(
            width: 500,
            child: Form(
              key: formKey,
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    DropdownButtonFormField<PaymentCardType>(
                      initialValue: cardType,
                      decoration: const InputDecoration(labelText: '卡片類別'),
                      items: PaymentCardType.values
                          .map(
                            (type) => DropdownMenuItem(
                              value: type,
                              child: Text(type.label),
                            ),
                          )
                          .toList(),
                      onChanged: existing == null
                          ? (value) => setState(() => cardType = value!)
                          : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: name,
                      decoration: InputDecoration(
                        labelText: '${cardType.label}名稱',
                      ),
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
                    if (cardType == PaymentCardType.credit)
                      const SizedBox(height: 12),
                    if (cardType == PaymentCardType.credit)
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
                    if (cardType == PaymentCardType.credit)
                      const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue:
                          store.activeAssetAccounts.any(
                            (item) => item.id == accountId,
                          )
                          ? accountId
                          : null,
                      decoration: InputDecoration(
                        labelText: cardType == PaymentCardType.debit
                            ? '直接扣款帳戶'
                            : '自動扣款帳戶',
                        helperText: cardType == PaymentCardType.debit
                            ? '使用此金融卡消費時，金額會立即從這個帳戶扣除'
                            : null,
                      ),
                      items: store.activeAssetAccounts
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
                      title: Text('啟用${cardType.label}'),
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
                    cardType: cardType,
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

  // Kept temporarily so older deep-link editor behavior remains source
  // compatible while v9 data migrates; all UI entry points use the v9 editor.
  // ignore: unused_element
  Future<void> _showLegacyBillDialog(
    BuildContext context, [
    CardBill? existing,
  ]) async {
    final store = ref.read(appStoreProvider);
    var cardId =
        existing?.cardId ??
        store.data.cards.where((card) => card.isCredit).firstOrNull?.id;
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
                          store.data.cards.any(
                            (item) => item.id == cardId && item.isCredit,
                          )
                          ? cardId
                          : null,
                      decoration: const InputDecoration(labelText: '信用卡'),
                      items: store.data.cards
                          .where((card) => card.isCredit)
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

  Future<void> _showBillDialog(
    BuildContext context, [
    CardBill? existing,
  ]) async {
    final store = ref.read(appStoreProvider);
    var cardId =
        existing?.cardId ??
        store.data.cards.where((card) => card.isCredit).firstOrNull?.id;
    final now = DateTime.now();
    var billMonth =
        existing?.month ??
        '${now.year}-${now.month.toString().padLeft(2, '0')}';
    final selected = <String>{...?existing?.chargeIds};
    final actualAmount = TextEditingController(
      text: existing == null
          ? ''
          : (store.billAmount(existing) / 100).toString(),
    );
    final search = TextEditingController();
    final note = TextEditingController(text: existing?.note);
    final reconciliationNote = TextEditingController(
      text: existing?.reconciliationNote,
    );
    var reason =
        existing?.reconciliationReason ?? CardBillReconciliationReason.none;
    var error = '';
    var initializedCycle = existing != null;

    ({DateTime closingDate, DateTime dueDate, DateTime autoDebitDate}) dates() {
      final card = store.cardById(cardId);
      final parts = billMonth.split('-');
      if (card == null || parts.length != 2) {
        return (
          closingDate: now,
          dueDate: now.add(const Duration(days: 20)),
          autoDebitDate: now.add(const Duration(days: 21)),
        );
      }
      return store.cardBillingDates(
        card,
        int.tryParse(parts[0]) ?? now.year,
        int.tryParse(parts[1]) ?? now.month,
      );
    }

    var dueDate = existing?.dueDate ?? dates().dueDate;
    var debitDate = existing?.autoDebitDate ?? dates().autoDebitDate;

    List<_BillCandidate> candidates() {
      final result = <_BillCandidate>[
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
          _BillCandidate(
            id: 'expense:${expense.id}',
            date: expense.date,
            label:
                '${expense.item}${expense.merchant.isEmpty ? '' : '・${expense.merchant}'}',
            detail: expense.category,
            amountMinor: expense.amountMinor,
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
          _BillCandidate(
            id: 'order:${order.id}',
            date: order.date,
            label: order.name,
            detail:
                '代訂・本人 ${moneyText(order.selfExpenseMinor)}／代墊 ${moneyText(order.advanceCardMinor)}',
            amountMinor: order.totalMinor,
          ),
      ];
      result.sort((a, b) => b.date.compareTo(a.date));
      return result;
    }

    bool inCycle(_BillCandidate item) {
      final current = dates().closingDate;
      final previousMonth = DateTime(current.year, current.month - 1);
      final card = store.cardById(cardId);
      if (card == null) return false;
      final previous = store
          .cardBillingDates(card, previousMonth.year, previousMonth.month)
          .closingDate;
      return item.date.isAfter(previous) && !item.date.isAfter(current);
    }

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) {
          final all = candidates();
          selected.retainAll(all.map((item) => item.id).toSet());
          if (!initializedCycle) {
            selected.addAll(all.where(inCycle).map((item) => item.id));
            initializedCycle = true;
          }
          final query = search.text.trim().toLowerCase();
          final visible = all
              .where(
                (item) =>
                    query.isEmpty ||
                    item.label.toLowerCase().contains(query) ||
                    item.detail.toLowerCase().contains(query),
              )
              .toList();
          final calculated = all
              .where((item) => selected.contains(item.id))
              .fold(0, (sum, item) => sum + item.amountMinor);
          final actual = actualAmount.text.trim().isEmpty
              ? null
              : parseMoney(actualAmount.text);
          final difference = actual == null ? 0 : actual - calculated;
          final paid = existing == null ? 0 : store.paidBillMinor(existing);
          final remaining = actual == null
              ? 0
              : (actual - paid).clamp(0, actual).toInt();
          return AlertDialog(
            title: Text(existing == null ? '新增信用卡帳單' : '編輯信用卡帳單'),
            content: SizedBox(
              width: 680,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    DropdownButtonFormField<String>(
                      initialValue: cardId,
                      decoration: const InputDecoration(labelText: '信用卡'),
                      items: [
                        for (final card in store.data.cards.where(
                          (item) => item.isCredit,
                        ))
                          DropdownMenuItem(
                            value: card.id,
                            child: Text('${card.name} •${card.lastFour}'),
                          ),
                      ],
                      onChanged: existing == null
                          ? (value) => setState(() {
                              cardId = value;
                              selected.clear();
                              initializedCycle = false;
                              dueDate = dates().dueDate;
                              debitDate = dates().autoDebitDate;
                            })
                          : null,
                    ),
                    const SizedBox(height: 12),
                    InkWell(
                      onTap: () async {
                        final parts = billMonth.split('-');
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: DateTime(
                            int.tryParse(parts.first) ?? now.year,
                            int.tryParse(parts.last) ?? now.month,
                          ),
                          firstDate: DateTime(2000),
                          lastDate: DateTime(now.year + 5, 12, 31),
                          helpText: '選擇帳單月份（日期可任選）',
                        );
                        if (picked != null) {
                          setState(() {
                            billMonth =
                                '${picked.year}-${picked.month.toString().padLeft(2, '0')}';
                            initializedCycle = false;
                            dueDate = dates().dueDate;
                            debitDate = dates().autoDebitDate;
                          });
                        }
                      },
                      child: InputDecorator(
                        decoration: const InputDecoration(labelText: '帳單月份'),
                        child: Text(billMonth),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: search,
                            decoration: const InputDecoration(
                              labelText: '搜尋刷卡紀錄',
                              prefixIcon: Icon(Icons.search),
                            ),
                            onChanged: (_) => setState(() {}),
                          ),
                        ),
                        const SizedBox(width: 8),
                        TextButton(
                          onPressed: visible.isEmpty
                              ? null
                              : () => setState(
                                  () => selected.addAll(
                                    visible.map((item) => item.id),
                                  ),
                                ),
                          child: const Text('全選'),
                        ),
                        TextButton(
                          onPressed: visible.isEmpty
                              ? null
                              : () => setState(
                                  () => selected.removeAll(
                                    visible.map((item) => item.id),
                                  ),
                                ),
                          child: const Text('取消全選'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text('本期結帳日 ${dateText(dates().closingDate)}；已自動預選結帳週期內紀錄'),
                    if (visible.isEmpty)
                      const ListTile(title: Text('沒有符合條件的未入帳紀錄'))
                    else
                      for (final item in visible)
                        CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          value: selected.contains(item.id),
                          title: Text(item.label),
                          subtitle: Text(
                            '${dateText(item.date)}・${item.detail}${inCycle(item) ? '' : '・週期外'}',
                          ),
                          secondary: Text(moneyText(item.amountMinor)),
                          onChanged: (value) => setState(() {
                            value == true
                                ? selected.add(item.id)
                                : selected.remove(item.id);
                          }),
                        ),
                    const Divider(height: 24),
                    TextField(
                      controller: actualAmount,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: '銀行實際帳單總額',
                        helperText: '此金額是待繳金額的唯一依據',
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                    if (difference != 0) ...[
                      const SizedBox(height: 12),
                      DropdownButtonFormField<CardBillReconciliationReason>(
                        initialValue:
                            reason == CardBillReconciliationReason.none
                            ? null
                            : reason,
                        decoration: const InputDecoration(labelText: '差異原因'),
                        items: [
                          for (final item
                              in CardBillReconciliationReason.values)
                            if (item != CardBillReconciliationReason.none)
                              DropdownMenuItem(
                                value: item,
                                child: Text(item.label),
                              ),
                        ],
                        onChanged: (value) => setState(() => reason = value!),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: reconciliationNote,
                        decoration: InputDecoration(
                          labelText: '差異說明',
                          helperText:
                              reason ==
                                  CardBillReconciliationReason.missingOrOther
                              ? '漏登／其他時必填'
                              : '選填',
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 12,
                      runSpacing: 8,
                      children: [
                        _BillMetric(label: '明細合計', amountMinor: calculated),
                        _BillMetric(label: '核對差額', amountMinor: difference),
                        _BillMetric(label: '已繳', amountMinor: paid),
                        _BillMetric(label: '剩餘待繳', amountMinor: remaining),
                      ],
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
                      decoration: const InputDecoration(labelText: '帳單備註'),
                    ),
                    if (error.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(
                          error,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
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
                        if (actual == null || actual < 0) {
                          setState(() => error = '請輸入銀行實際帳單總額');
                          return;
                        }
                        if (difference != 0 &&
                            reason == CardBillReconciliationReason.none) {
                          setState(() => error = '請選擇帳單差異原因');
                          return;
                        }
                        if (difference != 0 &&
                            reason ==
                                CardBillReconciliationReason.missingOrOther &&
                            reconciliationNote.text.trim().isEmpty) {
                          setState(() => error = '請填寫差異說明');
                          return;
                        }
                        await store.upsertBill(
                          CardBill(
                            id: existing?.id ?? store.newId(),
                            userId: store.userId,
                            cardId: cardId!,
                            month: billMonth,
                            chargeIds: selected.toList(),
                            manualAdjustmentMinor: 0,
                            paidMinor: paid,
                            dueDate: dueDate,
                            autoDebitDate: debitDate,
                            note: note.text.trim(),
                            statementAmountMinor: actual,
                            reconciliationReason: difference == 0
                                ? CardBillReconciliationReason.none
                                : reason,
                            reconciliationNote: reconciliationNote.text.trim(),
                            autoDebitState:
                                existing?.autoDebitState ??
                                CardBillAutoDebitState.pending,
                            paidAt: existing?.paidAt,
                            origin: existing?.origin ?? DataOrigin.user,
                          ),
                        );
                        if (store.lastSyncError != null) {
                          setState(() => error = store.lastSyncError!);
                          return;
                        }
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

class _BillMetric extends StatelessWidget {
  const _BillMetric({required this.label, required this.amountMinor});
  final String label;
  final int amountMinor;

  @override
  Widget build(BuildContext context) =>
      Chip(label: Text('$label ${moneyText(amountMinor)}'));
}

class _BillCandidate {
  const _BillCandidate({
    required this.id,
    required this.date,
    required this.label,
    required this.detail,
    required this.amountMinor,
  });

  final String id;
  final DateTime date;
  final String label;
  final String detail;
  final int amountMinor;
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
        title: '還沒有卡片',
        message: '新增信用卡管理帳單，或新增金融卡直接扣指定帳戶。',
      );
    }
    return ListView.separated(
      itemCount: store.data.cards.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final card = store.data.cards[index];
        final records = <_CardChargeRecord>[
          for (final expense in store.data.expenses.where(
            (item) => item.cardId == card.id,
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
        final unbilled = card.isCredit ? store.unbilledCardMinor(card.id) : 0;
        return Card(
          clipBehavior: Clip.antiAlias,
          child: ExpansionTile(
            key: PageStorageKey('card-${card.id}'),
            tilePadding: const EdgeInsets.symmetric(
              horizontal: 18,
              vertical: 8,
            ),
            childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            leading: CircleAvatar(
              child: Icon(
                card.isDebit ? Icons.account_balance_wallet : Icons.credit_card,
              ),
            ),
            title: Row(
              children: [
                Expanded(
                  child: Text(
                    card.name,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                PopupMenuButton<String>(
                  tooltip: '卡片操作',
                  onSelected: (value) async {
                    if (value == 'edit') {
                      WidgetsBinding.instance.addPostFrameCallback(
                        (_) => onEdit(card),
                      );
                      return;
                    }
                    if (value == 'delete' &&
                        await confirmDelete(context, '卡片')) {
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
                '${card.cardType.label}・${card.bank} •${card.lastFour}\n'
                '${card.isDebit ? '直接扣款' : '${card.closingDay} 日結帳・${card.autoDebitDay} 日自動扣款'}・'
                '${accountName(store, card.debitAccountId)}'
                '${card.isCredit ? '\n未入帳 ${moneyText(unbilled, mask: store.data.settings.maskBalances)}' : ''}',
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
                      final status = card.isDebit
                          ? '已從 ${accountName(store, card.debitAccountId)} 直接扣款'
                          : bill == null
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

class _BillsList extends ConsumerStatefulWidget {
  const _BillsList({required this.onEdit});
  final ValueChanged<CardBill> onEdit;

  @override
  ConsumerState<_BillsList> createState() => _BillsListState();
}

class _BillsListState extends ConsumerState<_BillsList> {
  String? cardFilter;
  int? yearFilter;
  CardBillStatus? statusFilter;

  @override
  Widget build(BuildContext context) {
    final store = ref.watch(appStoreProvider);
    if (store.data.bills.isEmpty) {
      return const EmptyState(
        icon: Icons.calendar_month_outlined,
        title: '還沒有帳單',
        message: '將未入帳單刷卡紀錄組成本期帳單。',
      );
    }
    final years =
        store.data.bills
            .map((item) => int.tryParse(item.month.split('-').first))
            .whereType<int>()
            .toSet()
            .toList()
          ..sort((a, b) => b.compareTo(a));
    final bills =
        store.data.bills
            .where(
              (bill) =>
                  (cardFilter == null || bill.cardId == cardFilter) &&
                  (yearFilter == null ||
                      bill.month.startsWith('$yearFilter-')) &&
                  (statusFilter == null ||
                      store.billStatus(bill) == statusFilter),
            )
            .toList()
          ..sort((a, b) => b.dueDate.compareTo(a.dueDate));
    return Column(
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 8,
          children: [
            DropdownButton<String?>(
              value: cardFilter,
              hint: const Text('所有信用卡'),
              items: [
                const DropdownMenuItem(value: null, child: Text('所有信用卡')),
                for (final card in store.data.cards.where(
                  (item) => item.isCredit,
                ))
                  DropdownMenuItem(value: card.id, child: Text(card.name)),
              ],
              onChanged: (value) => setState(() => cardFilter = value),
            ),
            DropdownButton<int?>(
              value: yearFilter,
              hint: const Text('所有年份'),
              items: [
                const DropdownMenuItem(value: null, child: Text('所有年份')),
                for (final year in years)
                  DropdownMenuItem(value: year, child: Text('$year 年')),
              ],
              onChanged: (value) => setState(() => yearFilter = value),
            ),
            DropdownButton<CardBillStatus?>(
              value: statusFilter,
              hint: const Text('所有狀態'),
              items: [
                const DropdownMenuItem(value: null, child: Text('所有狀態')),
                for (final status in CardBillStatus.values)
                  DropdownMenuItem(value: status, child: Text(status.label)),
              ],
              onChanged: (value) => setState(() => statusFilter = value),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Expanded(
          child: bills.isEmpty
              ? const Center(child: Text('沒有符合篩選條件的帳單'))
              : ListView.separated(
                  itemCount: bills.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final bill = bills[index];
                    final amount = store.billAmount(bill);
                    final outstanding = store.outstandingBillMinor(bill);
                    final status = store.billStatus(bill);
                    final paid = status == CardBillStatus.paid;
                    final card = store.cardById(bill.cardId);
                    final balance = card == null
                        ? 0
                        : store.accountBalance(card.debitAccountId);
                    final insufficient = outstanding > balance;
                    final now = DateTime.now();
                    final dueDays = DateTime(
                      bill.dueDate.year,
                      bill.dueDate.month,
                      bill.dueDate.day,
                    ).difference(DateTime(now.year, now.month, now.day)).inDays;
                    return Card(
                      child: InkWell(
                        onTap: () => _showDetails(context, store, bill),
                        child: Padding(
                          padding: const EdgeInsets.all(18),
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              final summary = Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${card?.name ?? '信用卡'} ${bill.month}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  Text(
                                    '截止 ${dateText(bill.dueDate)}・自動扣款 ${dateText(bill.autoDebitDate)}',
                                  ),
                                  Text(
                                    dueDays < 0
                                        ? '已逾期 ${-dueDays} 天'
                                        : dueDays == 0
                                        ? '今天截止'
                                        : '距截止 $dueDays 天',
                                  ),
                                  if (insufficient && !paid)
                                    Text(
                                      '扣款帳戶餘額可能不足',
                                      style: TextStyle(
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.error,
                                      ),
                                    ),
                                ],
                              );
                              final trailing = Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
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
                                      Text(
                                        '${status.label}・未繳 ${moneyText(outstanding)}',
                                      ),
                                    ],
                                  ),
                                  PopupMenuButton<String>(
                                    onSelected: (value) async {
                                      if (value == 'edit') {
                                        WidgetsBinding.instance
                                            .addPostFrameCallback(
                                              (_) => widget.onEdit(bill),
                                            );
                                      } else if (value == 'payment') {
                                        await _showPayment(
                                          context,
                                          store,
                                          bill,
                                        );
                                      } else if (value == 'pay') {
                                        await store.payBill(bill.id);
                                      } else if (value == 'failed') {
                                        await store.markBillAutoDebitFailed(
                                          bill.id,
                                        );
                                      } else if (value == 'delete') {
                                        final confirmed = await confirmDelete(
                                          context,
                                          '帳單',
                                        );
                                        if (confirmed) {
                                          await store.deleteBill(bill.id);
                                        }
                                      }
                                    },
                                    itemBuilder: (context) => [
                                      const PopupMenuItem(
                                        value: 'edit',
                                        child: Text('編輯帳單'),
                                      ),
                                      if (!paid)
                                        const PopupMenuItem(
                                          value: 'payment',
                                          child: Text('新增繳款'),
                                        ),
                                      if (!paid)
                                        const PopupMenuItem(
                                          value: 'pay',
                                          child: Text('確認自動扣款成功'),
                                        ),
                                      if (!paid)
                                        const PopupMenuItem(
                                          value: 'failed',
                                          child: Text('標記扣款失敗'),
                                        ),
                                      const PopupMenuItem(
                                        value: 'delete',
                                        child: Text('刪除'),
                                      ),
                                    ],
                                  ),
                                ],
                              );
                              return Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  CircleAvatar(
                                    backgroundColor: paid
                                        ? const Color(0xFFDFF4EA)
                                        : const Color(0xFFFFE9DD),
                                    child: Icon(
                                      paid
                                          ? Icons.check
                                          : Icons.notifications_none,
                                      color: paid
                                          ? const Color(0xFF0E7C66)
                                          : const Color(0xFFD35D2A),
                                    ),
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: constraints.maxWidth < 620
                                        ? Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              summary,
                                              const SizedBox(height: 8),
                                              trailing,
                                            ],
                                          )
                                        : Row(
                                            children: [
                                              Expanded(child: summary),
                                              trailing,
                                            ],
                                          ),
                                  ),
                                ],
                              );
                            },
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Future<void> _showPayment(
    BuildContext context,
    AppStore store,
    CardBill bill, [
    FinancialTransaction? existing,
  ]) async {
    final amount = TextEditingController(
      text: ((existing?.amountMinor ?? store.outstandingBillMinor(bill)) / 100)
          .toString(),
    );
    final note = TextEditingController(text: existing?.note);
    var date = existing?.date ?? DateTime.now();
    var accountId = existing?.impacts
        .where((item) => item.amountMinor < 0)
        .map((item) => item.accountId)
        .where((id) => store.activeAssetAccounts.any((item) => item.id == id))
        .firstOrNull;
    accountId ??= store.cardById(bill.cardId)?.debitAccountId;
    var error = '';
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(existing == null ? '新增繳款' : '編輯繳款'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: amount,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: '繳款金額',
                    helperText:
                        '剩餘 ${moneyText(store.outstandingBillMinor(bill))}',
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: accountId,
                  decoration: const InputDecoration(labelText: '扣款帳戶'),
                  items: [
                    for (final account in store.activeAssetAccounts)
                      DropdownMenuItem(
                        value: account.id,
                        child: Text(account.name),
                      ),
                  ],
                  onChanged: (value) => setState(() => accountId = value),
                ),
                const SizedBox(height: 12),
                _DateField(
                  label: '繳款日期',
                  date: date,
                  onChanged: (value) => setState(() => date = value),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: note,
                  decoration: const InputDecoration(labelText: '備註'),
                ),
                if (error.isNotEmpty)
                  Text(
                    error,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: accountId == null
                  ? null
                  : () async {
                      await store.upsertBillPayment(
                        billId: bill.id,
                        paymentId: existing?.id ?? store.newId(),
                        amountMinor: parseMoney(amount.text),
                        date: date,
                        accountId: accountId!,
                        note: note.text,
                      );
                      if (store.lastSyncError != null) {
                        setState(() => error = store.lastSyncError!);
                        return;
                      }
                      if (dialogContext.mounted) Navigator.pop(dialogContext);
                    },
              child: const Text('儲存'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showDetails(
    BuildContext context,
    AppStore store,
    CardBill bill,
  ) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        final payments = store.billPayments(bill.id);
        return AlertDialog(
          title: Text(
            '${store.cardById(bill.cardId)?.name ?? '信用卡'} ${bill.month}',
          ),
          content: SizedBox(
            width: 620,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('銀行實際總額 ${moneyText(store.billAmount(bill))}'),
                  Text('明細合計 ${moneyText(store.calculatedBillAmount(bill))}'),
                  Text(
                    '核對差額 ${moneyText(store.reconciliationDifference(bill))}・${bill.reconciliationReason.label}',
                  ),
                  if (bill.reconciliationNote.isNotEmpty)
                    Text(bill.reconciliationNote),
                  const Divider(),
                  Text('帳單明細', style: Theme.of(context).textTheme.titleSmall),
                  for (final id in bill.chargeIds)
                    ListTile(
                      dense: true,
                      title: Text(_chargeLabel(store, id)),
                      trailing: Text(moneyText(_chargeAmount(store, id))),
                    ),
                  const Divider(),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '繳款紀錄',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                      ),
                      TextButton.icon(
                        onPressed: store.outstandingBillMinor(bill) == 0
                            ? null
                            : () async {
                                Navigator.pop(dialogContext);
                                await _showPayment(context, store, bill);
                              },
                        icon: const Icon(Icons.add),
                        label: const Text('新增繳款'),
                      ),
                    ],
                  ),
                  if (payments.isEmpty)
                    const ListTile(title: Text('尚無繳款紀錄'))
                  else
                    for (final payment in payments)
                      ListTile(
                        title: Text(moneyText(payment.amountMinor)),
                        subtitle: Text(
                          '${dateText(payment.date)}${payment.note.isEmpty ? '' : '・${payment.note}'}',
                        ),
                        trailing: PopupMenuButton<String>(
                          onSelected: (value) async {
                            Navigator.pop(dialogContext);
                            if (value == 'edit') {
                              await _showPayment(context, store, bill, payment);
                            } else if (value == 'delete') {
                              await store.deleteBillPayment(
                                bill.id,
                                payment.id,
                              );
                            }
                          },
                          itemBuilder: (_) => const [
                            PopupMenuItem(value: 'edit', child: Text('編輯')),
                            PopupMenuItem(value: 'delete', child: Text('刪除')),
                          ],
                        ),
                      ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('關閉'),
            ),
          ],
        );
      },
    );
  }

  String _chargeLabel(AppStore store, String id) {
    if (id.startsWith('expense:')) {
      final sourceId = id.substring('expense:'.length);
      return store.data.expenses
              .where((item) => item.id == sourceId)
              .map((item) => '${dateText(item.date)} ${item.item}')
              .firstOrNull ??
          '已刪除的支出';
    }
    final sourceId = id.substring('order:'.length);
    return store.data.orders
            .where((item) => item.id == sourceId)
            .map((item) => '${dateText(item.date)} ${item.name}')
            .firstOrNull ??
        '已刪除的代訂';
  }

  int _chargeAmount(AppStore store, String id) {
    if (id.startsWith('expense:')) {
      final sourceId = id.substring('expense:'.length);
      return store.data.expenses
              .where((item) => item.id == sourceId)
              .map((item) => item.amountMinor)
              .firstOrNull ??
          0;
    }
    final sourceId = id.substring('order:'.length);
    return store.data.orders
            .where((item) => item.id == sourceId)
            .map((item) => item.totalMinor)
            .firstOrNull ??
        0;
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
