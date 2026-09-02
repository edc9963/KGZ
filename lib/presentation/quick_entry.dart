import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/app_store.dart';
import '../application/providers.dart';
import '../domain/models.dart';
import 'widgets/common.dart';

enum QuickEntryKind { expense, income }

Future<void> showQuickEntry(
  BuildContext context, {
  QuickEntryKind initialKind = QuickEntryKind.expense,
}) async {
  final compact = MediaQuery.sizeOf(context).width < 600;
  if (compact) {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => FractionallySizedBox(
        heightFactor: .9,
        child: _QuickEntryEditor(initialKind: initialKind),
      ),
    );
  } else {
    await showDialog<void>(
      context: context,
      builder: (_) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560, maxHeight: 720),
          child: _QuickEntryEditor(initialKind: initialKind),
        ),
      ),
    );
  }
}

class _QuickEntryEditor extends ConsumerStatefulWidget {
  const _QuickEntryEditor({required this.initialKind});

  final QuickEntryKind initialKind;

  @override
  ConsumerState<_QuickEntryEditor> createState() => _QuickEntryEditorState();
}

class _QuickEntryEditorState extends ConsumerState<_QuickEntryEditor> {
  final _formKey = GlobalKey<FormState>();
  final _amount = TextEditingController();
  final _item = TextEditingController();
  final _merchant = TextEditingController();
  final _note = TextEditingController();
  late QuickEntryKind _kind;
  late PaymentMethod _payment;
  String? _category;
  String? _accountId;
  String? _cardId;
  DateTime _date = DateTime.now();
  bool _necessary = false;
  bool _advanced = false;
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _kind = widget.initialKind;
    final store = ref.read(appStoreProvider);
    _payment = store.data.settings.defaultPaymentMethod;
    _category = store.data.settings.defaultCategory;
    _accountId = store.activeAssetAccounts.firstOrNull?.id;
    _cardId = store.data.cards
        .where((card) => card.isActive && card.isCredit)
        .firstOrNull
        ?.id;
    if (_payment == PaymentMethod.creditCard && _cardId == null) {
      _payment = PaymentMethod.cash;
    }
  }

  @override
  void dispose() {
    _amount.dispose();
    _item.dispose();
    _merchant.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final store = ref.watch(appStoreProvider);
    final expenseCategories = store.categoryNamesFor(
      BookkeepingCategoryKind.expense,
    );
    final incomeCategories = store.categoryNamesFor(
      BookkeepingCategoryKind.income,
    );
    final categories = _kind == QuickEntryKind.expense
        ? expenseCategories
        : incomeCategories;
    if (!categories.contains(_category)) _category = categories.firstOrNull;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          24,
          12,
          24,
          24 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Text(
                    '快速記帳',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: '關閉',
                    onPressed: _submitting
                        ? null
                        : () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              SegmentedButton<QuickEntryKind>(
                segments: const [
                  ButtonSegment(
                    value: QuickEntryKind.expense,
                    label: Text('支出'),
                  ),
                  ButtonSegment(
                    value: QuickEntryKind.income,
                    label: Text('收入'),
                  ),
                ],
                selected: {_kind},
                onSelectionChanged: _submitting
                    ? null
                    : (value) => setState(() {
                        _kind = value.single;
                        _category = null;
                        _error = null;
                      }),
              ),
              const SizedBox(height: 18),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      TextFormField(
                        controller: _amount,
                        autofocus: true,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        textInputAction: TextInputAction.next,
                        style: Theme.of(context).textTheme.headlineMedium
                            ?.copyWith(fontWeight: FontWeight.w900),
                        decoration: const InputDecoration(
                          labelText: '金額',
                          prefixText: r'NT$ ',
                        ),
                        validator: (value) =>
                            parseMoney(value ?? '') <= 0 ? '請輸入大於 0 的金額' : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _item,
                        textInputAction: TextInputAction.next,
                        decoration: InputDecoration(
                          labelText: _kind == QuickEntryKind.expense
                              ? '項目'
                              : '收入項目',
                        ),
                        validator: (value) =>
                            value == null || value.trim().isEmpty
                            ? '請輸入項目'
                            : null,
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: _category,
                        isExpanded: true,
                        decoration: const InputDecoration(labelText: '分類'),
                        items: [
                          for (final category in categories)
                            DropdownMenuItem(
                              value: category,
                              child: Text(category),
                            ),
                        ],
                        validator: (value) => value == null ? '請選擇分類' : null,
                        onChanged: (value) => setState(() => _category = value),
                      ),
                      const SizedBox(height: 12),
                      if (_kind == QuickEntryKind.expense) ...[
                        DropdownButtonFormField<PaymentMethod>(
                          initialValue: _payment,
                          isExpanded: true,
                          decoration: const InputDecoration(labelText: '付款方式'),
                          items: [
                            for (final method in PaymentMethod.values)
                              DropdownMenuItem(
                                value: method,
                                child: Text(method.label),
                              ),
                          ],
                          onChanged: (value) => setState(() {
                            _payment = value!;
                            _error = null;
                            if (_payment == PaymentMethod.creditCard) {
                              _cardId = store.data.cards
                                  .where(
                                    (card) => card.isActive && card.isCredit,
                                  )
                                  .firstOrNull
                                  ?.id;
                            } else if (_payment == PaymentMethod.debitCard) {
                              _cardId = store.data.cards
                                  .where(
                                    (card) => card.isActive && card.isDebit,
                                  )
                                  .firstOrNull
                                  ?.id;
                            }
                          }),
                        ),
                        if (_payment == PaymentMethod.creditCard ||
                            _payment == PaymentMethod.debitCard) ...[
                          const SizedBox(height: 12),
                          DropdownButtonFormField<String>(
                            initialValue:
                                store.data.cards.any(
                                  (card) => card.id == _cardId,
                                )
                                ? _cardId
                                : null,
                            decoration: InputDecoration(
                              labelText: _payment == PaymentMethod.creditCard
                                  ? '信用卡'
                                  : '金融卡',
                            ),
                            items: [
                              for (final card in store.data.cards.where(
                                (card) =>
                                    card.isActive &&
                                    (_payment == PaymentMethod.creditCard
                                        ? card.isCredit
                                        : card.isDebit),
                              ))
                                DropdownMenuItem(
                                  value: card.id,
                                  child: Text('${card.name} •${card.lastFour}'),
                                ),
                            ],
                            validator: (value) =>
                                value == null ? '請先建立可用卡片' : null,
                            onChanged: (value) =>
                                setState(() => _cardId = value),
                          ),
                        ] else if (_payment != PaymentMethod.telecomBill) ...[
                          const SizedBox(height: 12),
                          _accountField(store),
                        ],
                      ] else
                        _accountField(store),
                      const SizedBox(height: 8),
                      ExpansionTile(
                        tilePadding: EdgeInsets.zero,
                        title: const Text('更多選項'),
                        initiallyExpanded: _advanced,
                        onExpansionChanged: (value) => _advanced = value,
                        children: [
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('日期'),
                            subtitle: Text(dateText(_date)),
                            trailing: const Icon(Icons.calendar_today_outlined),
                            onTap: _pickDate,
                          ),
                          if (_kind == QuickEntryKind.expense) ...[
                            TextFormField(
                              controller: _merchant,
                              decoration: const InputDecoration(
                                labelText: '商家（選填）',
                              ),
                            ),
                            SwitchListTile(
                              contentPadding: EdgeInsets.zero,
                              title: const Text('必要支出'),
                              value: _necessary,
                              onChanged: (value) =>
                                  setState(() => _necessary = value),
                            ),
                          ],
                          TextFormField(
                            controller: _note,
                            decoration: const InputDecoration(
                              labelText: '備註（選填）',
                            ),
                          ),
                        ],
                      ),
                      if (_error != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Text(
                            _error!,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _submitting || !store.canWrite ? null : _save,
                icon: _submitting
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.check),
                label: Text(_submitting ? '同步中' : '儲存'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _accountField(AppStore store) => DropdownButtonFormField<String>(
    initialValue:
        store.activeAssetAccounts.any((account) => account.id == _accountId)
        ? _accountId
        : null,
    isExpanded: true,
    decoration: InputDecoration(
      labelText: _kind == QuickEntryKind.income ? '入帳帳戶' : '扣款帳戶',
    ),
    items: [
      for (final account in store.activeAssetAccounts)
        DropdownMenuItem<String>(value: account.id, child: Text(account.name)),
    ],
    validator: (value) => value == null ? '請選擇帳戶' : null,
    onChanged: (value) => setState(() => _accountId = value),
  );

  Future<void> _pickDate() async {
    final value = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (value != null) setState(() => _date = value);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final store = ref.read(appStoreProvider);
    setState(() {
      _submitting = true;
      _error = null;
    });
    if (_kind == QuickEntryKind.expense) {
      final card = store.cardById(_cardId);
      await store.upsertExpense(
        Expense(
          id: store.newId(),
          userId: store.userId,
          date: _date,
          amountMinor: parseMoney(_amount.text),
          paymentMethod: _payment,
          item: _item.text.trim(),
          category: _category!,
          accountId: _payment == PaymentMethod.debitCard
              ? card?.debitAccountId
              : _payment == PaymentMethod.creditCard ||
                    _payment == PaymentMethod.telecomBill
              ? null
              : _accountId,
          cardId:
              _payment == PaymentMethod.creditCard ||
                  _payment == PaymentMethod.debitCard
              ? _cardId
              : null,
          merchant: _merchant.text.trim(),
          note: _note.text.trim(),
          isNecessary: _necessary,
        ),
      );
    } else {
      await store.upsertIncome(
        IncomeEntry(
          id: store.newId(),
          userId: store.userId,
          date: _date,
          amountMinor: parseMoney(_amount.text),
          item: _item.text.trim(),
          category: _category!,
          accountId: _accountId!,
          note: _note.text.trim(),
        ),
      );
    }
    if (!mounted) return;
    if (store.lastSyncError == null && !store.hasConflict) {
      final messenger = ScaffoldMessenger.of(context);
      Navigator.pop(context);
      messenger.showSnackBar(
        SnackBar(
          content: Text(_kind == QuickEntryKind.expense ? '支出已儲存' : '收入已儲存'),
        ),
      );
    } else {
      setState(() {
        _submitting = false;
        _error = store.lastSyncError ?? '無法儲存，請稍後再試';
      });
    }
  }
}
