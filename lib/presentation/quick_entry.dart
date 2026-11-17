import 'package:flutter/material.dart';
import 'package:forui/forui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/app_store.dart';
import '../application/providers.dart';
import '../domain/models.dart';
import 'design_tokens.dart';
import 'widgets/common.dart';

enum QuickEntryKind { expense, income }

Future<void> showQuickEntry(
  BuildContext context, {
  QuickEntryKind initialKind = QuickEntryKind.expense,
}) async {
  final compact = MediaQuery.sizeOf(context).width < 600;
  if (compact) {
    await showFSheet<void>(
      useRootNavigator: true,
      context: context,
      side: FLayout.btt,
      mainAxisMaxRatio: .9,
      builder: (context) => DecoratedBox(
        decoration: BoxDecoration(
          color: context.colors.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: FractionallySizedBox(
          heightFactor: 1,
          child: _QuickEntryEditor(initialKind: initialKind),
        ),
      ),
    );
  } else {
    await showFDialog<void>(
      useRootNavigator: true,
      context: context,
      builder: (context, style, animation) => FDialog(
        animation: animation,
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 720),
        builder: (context, style) =>
            _QuickEntryEditor(initialKind: initialKind),
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
    if (!_payment.isSelectable) _payment = PaymentMethod.cash;
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
                  FTooltip(
                    tipBuilder: (context, _) => Text('關閉'),
                    child: FButton.icon(
                      variant: FButtonVariant.ghost,
                      onPress: _submitting
                          ? null
                          : () => Navigator.pop(context),
                      semanticsLabel: '關閉',
                      child: const Icon(Icons.close),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              // Figma quick-entry sheet: rose (light) / orange (dark)
              // segmented control for the entry kind.
              KgzTabBar<QuickEntryKind>(
                tabs: const [
                  (QuickEntryKind.expense, '支出', null),
                  (QuickEntryKind.income, '收入', null),
                ],
                selected: _kind,
                onSelected: (value) {
                  if (_submitting || value == _kind) return;
                  setState(() {
                    HapticFeedback.selectionClick();
                    _kind = value;
                    _category = null;
                    _error = null;
                  });
                },
              ),
              const SizedBox(height: 18),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      MoneyField(
                        controller: _amount,
                        autofocus: true,
                        contentTextStyle: Theme.of(context)
                            .textTheme
                            .headlineMedium
                            ?.copyWith(fontWeight: FontWeight.w900),
                        label: Text('輸入金額'),
                        prefixText: r'NT$ ',
                        validator: (value) =>
                            parseMoney(value ?? '') <= 0 ? '請輸入大於 0 的金額' : null,
                      ),
                      const SizedBox(height: 12),
                      ItemNameField(
                        controller: _item,
                        suggestions: store.itemNamesFor(
                          _kind == QuickEntryKind.expense
                              ? BookkeepingCategoryKind.expense
                              : BookkeepingCategoryKind.income,
                          _category,
                        ),
                        textInputAction: TextInputAction.next,
                        label: Text(
                          _kind == QuickEntryKind.expense ? '項目' : '收入項目',
                        ),
                        validator: (value) =>
                            value == null || value.trim().isEmpty
                            ? '請輸入項目'
                            : null,
                      ),
                      const SizedBox(height: 12),
                      FormField<String>(
                        initialValue: _category,
                        validator: (_) => _category == null ? '請選擇分類' : null,
                        builder: (field) => Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '分類',
                              style: TextStyle(
                                color: context.colors.textMuted,
                                fontSize: 12.5,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                for (final category in categories)
                                  FButton(
                                    variant: category == _category
                                        ? FButtonVariant.primary
                                        : FButtonVariant.outline,
                                    size: FButtonSizeVariant.sm,
                                    mainAxisSize: MainAxisSize.min,
                                    selected: category == _category,
                                    onPress: () {
                                      HapticFeedback.selectionClick();
                                      setState(() => _category = category);
                                      field.didChange(category);
                                    },
                                    child: Text(category),
                                  ),
                              ],
                            ),
                            if (field.errorText != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Text(
                                  field.errorText!,
                                  style: TextStyle(
                                    color: context.colors.expense,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (_kind == QuickEntryKind.expense) ...[
                        KgzSelect<PaymentMethod>(
                          value: _payment,
                          label: Text('付款方式'),
                          items: [
                            for (final method in PaymentMethod.selectableWith())
                              KgzSelectItem(method, method.label),
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
                          KgzSelect<String>(
                            value:
                                store.data.cards.any(
                                  (card) => card.id == _cardId,
                                )
                                ? _cardId
                                : null,
                            label: Text(
                              _payment == PaymentMethod.creditCard
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
                                KgzSelectItem(
                                  card.id,
                                  '${card.name} •${card.lastFour}',
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
                      FAccordion(
                        control: FAccordionControl.managed(
                          onChange: (expanded) =>
                              _advanced = expanded.isNotEmpty,
                        ),
                        children: [
                          FAccordionItem(
                            initiallyExpanded: _advanced,
                            title: const Text('更多選項'),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                FItem(
                                  title: const Text('日期'),
                                  subtitle: Text(dateText(_date)),
                                  suffix: const Icon(
                                    Icons.calendar_today_outlined,
                                  ),
                                  onPress: _pickDate,
                                ),
                                if (_kind == QuickEntryKind.expense) ...[
                                  FTextFormField(
                                    control: FTextFieldControl.managed(
                                      controller: _merchant,
                                    ),
                                    label: Text('商家（選填）'),
                                  ),
                                  FItem(
                                    title: const Text('必要支出'),
                                    suffix: FSwitch(
                                      value: _necessary,
                                      onChange: (value) =>
                                          setState(() => _necessary = value),
                                    ),
                                    onPress: () => ((value) => setState(
                                      () => _necessary = value,
                                    ))(!(_necessary)),
                                  ),
                                ],
                                FTextFormField(
                                  control: FTextFieldControl.managed(
                                    controller: _note,
                                  ),
                                  label: Text('備註（選填）'),
                                ),
                              ],
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
              FButton(
                size: FButtonSizeVariant.lg,
                onPress: _submitting || !store.canWrite ? null : _save,
                prefix: _submitting
                    ? const SizedBox.square(
                        dimension: 18,
                        child: FCircularProgress(),
                      )
                    : const Icon(Icons.check),
                child: Text(_submitting ? '同步中' : '儲存記錄'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _accountField(AppStore store) => KgzSelect<String>(
    value: store.activeAssetAccounts.any((account) => account.id == _accountId)
        ? _accountId
        : null,
    label: Text(_kind == QuickEntryKind.income ? '入帳帳戶' : '扣款帳戶'),
    items: [
      for (final account in store.activeAssetAccounts)
        KgzSelectItem<String>(account.id, account.name),
    ],
    validator: (value) => value == null ? '請選擇帳戶' : null,
    onChanged: (value) => setState(() => _accountId = value),
  );

  Future<void> _pickDate() async {
    final value = await showKgzDatePicker(
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
      HapticFeedback.lightImpact();
      // The navigator outlives this sheet, so its context can still show
      // the toast after the pop.
      final noticeContext = Navigator.of(context).context;
      Navigator.pop(context);
      if (noticeContext.mounted) {
        showSaved(
          noticeContext,
          _kind == QuickEntryKind.expense ? '支出已儲存' : '收入已儲存',
        );
      }
    } else {
      setState(() {
        _submitting = false;
        _error = store.lastSyncError ?? '無法儲存，請稍後再試';
      });
    }
  }
}
