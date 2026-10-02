import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/app_store.dart';
import '../../application/providers.dart';
import '../../domain/models.dart';
import '../design_tokens.dart';
import '../widgets/common.dart';

/// Accounts not confirmed against the bank for this many days are flagged
/// as due for 對帳.
const _staleAfterDays = 30;

/// 對帳: check each account balance and credit-card bill against the real
/// bank/statement figure, book any difference as an adjustment, and keep a
/// history of every check and the difference it booked.
class ReconciliationPage extends ConsumerWidget {
  const ReconciliationPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final store = ref.watch(appStoreProvider);
    final mask = store.data.settings.maskBalances;
    final now = DateTime.now();
    final accounts = store.data.accounts
        .where(
          (item) => item.kind == FinancialAccountKind.asset && item.isActive,
        )
        .toList();
    final bills = _creditBills(store);
    final telecomPayments = _telecomPayments(store);
    final products = _heldProducts(store);
    final history = store.reconciliationHistory;

    bool isStaleTarget(ReconciliationTargetType type, String id) {
      final last = store.lastReconciliation(type, id);
      return last == null || now.difference(last.date).inDays > _staleAfterDays;
    }

    bool isStale(Account account) =>
        isStaleTarget(ReconciliationTargetType.account, account.id);
    bool isStaleProduct(InvestmentProduct product) =>
        isStaleTarget(ReconciliationTargetType.investment, product.id);

    final staleCount =
        accounts.where(isStale).length +
        products.where(isStaleProduct).length;
    final uncheckedBills =
        bills
            .where(
              (bill) =>
                  store.lastReconciliation(
                    ReconciliationTargetType.cardBill,
                    bill.id,
                  ) ==
                  null,
            )
            .length +
        telecomPayments
            .where(
              (payment) =>
                  store.lastReconciliation(
                    ReconciliationTargetType.telecomBill,
                    payment.id,
                  ) ==
                  null,
            )
            .length;
    final monthAdjustments = history
        .where(
          (item) =>
              item.date.year == now.year &&
              item.date.month == now.month &&
              item.currency == store.data.settings.defaultCurrency,
        )
        .fold(0, (sum, item) => sum + item.differenceMinor);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const PageHeader(title: '對帳', subtitle: '核對銀行與信用卡的實際金額，差額自動調整並留下紀錄'),
        const SizedBox(height: 24),
        ResponsiveGrid(
          minWidth: 210,
          children: [
            SummaryCard(
              label: '待對帳項目',
              value: '$staleCount 個',
              caption: '帳戶與投資超過 $_staleAfterDays 天未確認',
              icon: Icons.account_balance_outlined,
              tone: staleCount > 0 ? context.colors.liability : null,
            ),
            SummaryCard(
              label: '待核對帳單',
              value: '$uncheckedBills 張',
              caption: '信用卡與電信帳單尚未核對',
              icon: Icons.credit_card_outlined,
              tone: uncheckedBills > 0 ? context.colors.liability : null,
            ),
            SummaryCard(
              label: '本月調整差額',
              value: _signedMoney(
                monthAdjustments,
                currency: store.data.settings.defaultCurrency,
                mask: mask,
              ),
              caption: '實際 − 帳面',
              icon: Icons.difference_outlined,
            ),
            SummaryCard(
              label: '最近對帳',
              value: history.isEmpty ? '尚未對帳' : dateText(history.first.date),
              caption: '共 ${history.length} 筆紀錄',
              icon: Icons.fact_check_outlined,
              tone: context.colors.asset,
            ),
          ],
        ),
        const SizedBox(height: 28),
        const _SectionTitle(
          title: '帳戶餘額',
          subtitle: '輸入網銀或錢包顯示的餘額，系統會計算差額並自動補登調整',
        ),
        const SizedBox(height: 12),
        if (accounts.isEmpty)
          const EmptyState(
            icon: Icons.account_balance_wallet_outlined,
            title: '還沒有帳戶',
            message: '先到「帳戶」新增帳戶，再回來對帳。',
          )
        else
          Card(
            child: Column(
              children: [
                for (var index = 0; index < accounts.length; index++) ...[
                  _AccountReconcileRow(
                    account: accounts[index],
                    store: store,
                    stale: isStale(accounts[index]),
                    mask: mask,
                    onReconcile: () =>
                        _showAccountDialog(context, ref, accounts[index]),
                  ),
                  if (index < accounts.length - 1) const Divider(height: 1),
                ],
              ],
            ),
          ),
        const SizedBox(height: 28),
        const _SectionTitle(
          title: '投資部位',
          subtitle: '輸入券商顯示的持有數量（必要時含平均成本），差異會補一筆持倉快照',
        ),
        const SizedBox(height: 12),
        if (products.isEmpty)
          const EmptyState(
            icon: Icons.trending_up_outlined,
            title: '沒有持有中的投資',
            message: '在「投資」新增持倉後，就能在這裡和券商對帳。',
          )
        else
          Card(
            child: Column(
              children: [
                for (var index = 0; index < products.length; index++) ...[
                  _InvestmentReconcileRow(
                    product: products[index],
                    store: store,
                    stale: isStaleProduct(products[index]),
                    mask: mask,
                    onReconcile: () =>
                        _showInvestmentDialog(context, ref, products[index]),
                  ),
                  if (index < products.length - 1) const Divider(height: 1),
                ],
              ],
            ),
          ),
        const SizedBox(height: 28),
        const _SectionTitle(
          title: '帳單核對',
          subtitle: '信用卡與電信帳單都會自動產生，拿到實際帳單後在這裡逐筆核對',
        ),
        const SizedBox(height: 12),
        _BillsSection(
          store: store,
          bills: bills,
          telecomPayments: telecomPayments,
          mask: mask,
          onReconcileBill: (bill) => _showBillDialog(context, ref, bill),
          onReconcileTelecom: (payment) =>
              _showTelecomDialog(context, ref, payment),
        ),
        const SizedBox(height: 28),
        const _SectionTitle(title: '對帳紀錄', subtitle: '撤銷帳戶、電信或投資對帳會一併移除它補登的調整'),
        const SizedBox(height: 12),
        if (history.isEmpty)
          const EmptyState(
            icon: Icons.fact_check_outlined,
            title: '還沒有對帳紀錄',
            message: '完成第一次對帳後，帳面與實際金額的差異會記錄在這裡。',
          )
        else
          Card(
            child: Column(
              children: [
                for (var index = 0; index < history.length; index++) ...[
                  _HistoryRow(
                    record: history[index],
                    store: store,
                    mask: mask,
                    onDelete: () async {
                      final record = history[index];
                      final label =
                          record.targetType == ReconciliationTargetType.cardBill
                          ? '這筆對帳紀錄'
                          : '這筆對帳紀錄與其調整';
                      if (await confirmDelete(context, label)) {
                        await store.deleteReconciliation(record.id);
                      }
                    },
                  ),
                  if (index < history.length - 1) const Divider(height: 1),
                ],
              ],
            ),
          ),
      ],
    );
  }

  /// Every credit-card bill, newest due date first.
  static List<CardBill> _creditBills(AppStore store) {
    final result = store.data.bills
        .where((bill) => store.cardById(bill.cardId)?.isCredit == true)
        .toList();
    result.sort((a, b) {
      final byDue = b.dueDate.compareTo(a.dueDate);
      return byDue != 0 ? byDue : a.cardId.compareTo(b.cardId);
    });
    return result;
  }

  /// Products currently held, plus any that were reconciled before (so a
  /// position the broker shows but the books zeroed out can still be
  /// corrected), sorted by name.
  static List<InvestmentProduct> _heldProducts(AppStore store) =>
      store.data.products
          .where(
            (product) =>
                (store.holdings[product.id]?.quantityMicros ?? 0) > 0 ||
                store.lastReconciliation(
                      ReconciliationTargetType.investment,
                      product.id,
                    ) !=
                    null,
          )
          .toList()
        ..sort((a, b) => a.name.compareTo(b.name));

  Future<void> _showInvestmentDialog(
    BuildContext context,
    WidgetRef ref,
    InvestmentProduct product,
  ) async {
    final store = ref.read(appStoreProvider);
    final quantity = TextEditingController();
    final averageCost = TextEditingController();
    final note = TextEditingController();
    var date = DateTime.now();
    var error = '';
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) {
          final book = store.holdingAt(product.id, date);
          final quantityText = quantity.text.trim().replaceAll(',', '');
          final enteredQuantity = double.tryParse(quantityText);
          final enteredMicros = enteredQuantity == null
              ? null
              : (enteredQuantity * 1000000).round();
          final costText = averageCost.text.trim();
          final enteredCost = costText.isEmpty ? null : parseMoney(costText);
          final quantityDiff = enteredMicros == null
              ? null
              : enteredMicros - book.quantityMicros;
          final costChanged =
              enteredCost != null &&
              enteredMicros != 0 &&
              enteredCost != book.averageCostMinor;
          int valueOf(int micros) =>
              (micros * product.currentPriceMinor / 1000000).round();
          return AlertDialog(
            title: Text('對帳：${product.name}'),
            content: SizedBox(
              width: 420,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    InkWell(
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: date,
                          firstDate: DateTime(2000),
                          lastDate: DateTime.now(),
                        );
                        if (picked != null) setState(() => date = picked);
                      },
                      child: InputDecorator(
                        decoration: const InputDecoration(
                          labelText: '對帳日期',
                          helperText: '以該日收盤後的帳面持倉比較',
                        ),
                        child: Text(dateText(date)),
                      ),
                    ),
                    const SizedBox(height: 16),
                    _AmountLine(
                      label: '帳面持有',
                      value: '${_quantityText(book.quantityMicros)} 單位',
                    ),
                    const SizedBox(height: 6),
                    _AmountLine(
                      label: '帳面平均成本',
                      value: moneyText(
                        book.averageCostMinor,
                        currency: product.currency,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: quantity,
                      autofocus: true,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: '實際持有數量',
                        helperText: '券商 App 或對帳單上的股數／單位數',
                      ),
                      onChanged: (_) => setState(() => error = ''),
                    ),
                    const SizedBox(height: 12),
                    MoneyField(
                      controller: averageCost,
                      decoration: InputDecoration(
                        labelText: '實際平均成本（${product.currency}，選填）',
                        helperText: '留空則沿用帳面平均成本',
                      ),
                      onChanged: (_) => setState(() => error = ''),
                    ),
                    const SizedBox(height: 12),
                    if (quantityDiff != null)
                      _InvestmentDifferenceBanner(
                        quantityDiffMicros: quantityDiff,
                        valueDiffMinor:
                            valueOf(enteredMicros!) -
                            valueOf(book.quantityMicros),
                        costChanged: costChanged,
                        currency: product.currency,
                      ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: note,
                      decoration: const InputDecoration(
                        labelText: '差異說明',
                        helperText: '選填，例如：股票股利、零股、漏記交易',
                      ),
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
                onPressed: () async {
                  if (enteredMicros == null || enteredMicros < 0) {
                    setState(() => error = '請輸入實際持有數量');
                    return;
                  }
                  if (enteredCost != null && enteredCost < 0) {
                    setState(() => error = '平均成本不可為負數');
                    return;
                  }
                  await store.reconcileInvestment(
                    productId: product.id,
                    actualQuantityMicros: enteredMicros,
                    actualAverageCostMinor: enteredCost,
                    date: date,
                    note: note.text,
                  );
                  if (store.lastSyncError != null) {
                    setState(() => error = store.lastSyncError!);
                    return;
                  }
                  if (dialogContext.mounted) Navigator.pop(dialogContext);
                  if (context.mounted) showSaved(context, '已完成投資對帳');
                },
                child: Text(
                  quantityDiff == 0 && !costChanged ? '確認無差異' : '確認並調整',
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// Every 電信帳單 the server has generated, newest first.
  static List<TelecomBillPayment> _telecomPayments(AppStore store) =>
      [...store.data.telecomBillPayments]
        ..sort((a, b) => b.paidAt.compareTo(a.paidAt));

  Future<void> _showTelecomDialog(
    BuildContext context,
    WidgetRef ref,
    TelecomBillPayment payment,
  ) async {
    final store = ref.read(appStoreProvider);
    final account = store.accountById(payment.debitAccountId);
    final currency = account?.currency ?? 'TWD';
    final actual = TextEditingController();
    final note = TextEditingController();
    var error = '';
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) {
          final text = actual.text.trim();
          final entered = text.isEmpty ? null : parseMoney(text);
          final difference = entered == null
              ? null
              : entered - payment.amountMinor;
          return AlertDialog(
            title: Text('核對：電信帳單 ${payment.month}'),
            content: SizedBox(
              width: 420,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _AmountLine(
                      label: '系統明細合計',
                      value: moneyText(payment.amountMinor, currency: currency),
                    ),
                    const SizedBox(height: 6),
                    _AmountLine(
                      label: '扣款帳戶',
                      value: account?.name ?? '指定帳戶',
                    ),
                    const SizedBox(height: 12),
                    MoneyField(
                      controller: actual,
                      autofocus: true,
                      decoration: const InputDecoration(
                        labelText: '電信帳單應繳總額',
                        helperText: '依電信公司寄來的帳單填寫',
                      ),
                      onChanged: (_) => setState(() => error = ''),
                    ),
                    const SizedBox(height: 12),
                    if (difference != null)
                      _DifferenceBanner(
                        differenceMinor: difference,
                        currency: currency,
                        zeroText: '帳單與明細相符',
                        nonZeroText: '差額會調整扣款帳戶的餘額',
                      ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: note,
                      decoration: const InputDecoration(
                        labelText: '差異說明',
                        helperText: '選填，例如：漏記小額付款、月租費調整',
                      ),
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
                onPressed: () async {
                  if (entered == null || entered < 0) {
                    setState(() => error = '請輸入電信帳單應繳總額');
                    return;
                  }
                  await store.reconcileTelecomBill(
                    paymentId: payment.id,
                    actualAmountMinor: entered,
                    date: DateTime.now(),
                    note: note.text,
                  );
                  if (store.lastSyncError != null) {
                    setState(() => error = store.lastSyncError!);
                    return;
                  }
                  if (dialogContext.mounted) Navigator.pop(dialogContext);
                  if (context.mounted) showSaved(context, '已完成帳單核對');
                },
                child: Text(difference == 0 ? '確認無差異' : '確認並調整'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _showAccountDialog(
    BuildContext context,
    WidgetRef ref,
    Account account,
  ) async {
    final store = ref.read(appStoreProvider);
    final actual = TextEditingController();
    final note = TextEditingController();
    var date = DateTime.now();
    var error = '';
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) {
          final book = store.accountBalanceAt(account.id, date);
          final entered = actual.text.trim().isEmpty
              ? null
              : parseMoney(actual.text.trim());
          final difference = entered == null ? null : entered - book;
          return AlertDialog(
            title: Text('對帳：${account.name}'),
            content: SizedBox(
              width: 420,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    InkWell(
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: date,
                          firstDate: DateTime(2000),
                          lastDate: DateTime.now(),
                        );
                        if (picked != null) setState(() => date = picked);
                      },
                      child: InputDecorator(
                        decoration: const InputDecoration(
                          labelText: '對帳日期',
                          helperText: '以該日結束時的帳面餘額比較',
                        ),
                        child: Text(dateText(date)),
                      ),
                    ),
                    const SizedBox(height: 16),
                    _AmountLine(
                      label: '帳面餘額',
                      value: moneyText(book, currency: account.currency),
                    ),
                    const SizedBox(height: 12),
                    MoneyField(
                      controller: actual,
                      autofocus: true,
                      decoration: InputDecoration(
                        labelText: '實際餘額（${account.currency}）',
                        helperText: '網銀、存摺或錢包上看到的金額',
                      ),
                      onChanged: (_) => setState(() => error = ''),
                    ),
                    const SizedBox(height: 12),
                    if (difference != null)
                      _DifferenceBanner(
                        differenceMinor: difference,
                        currency: account.currency,
                        zeroText: '帳面與實際相符，將記錄為已確認',
                        nonZeroText: '確認後會新增一筆餘額調整',
                      ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: note,
                      decoration: const InputDecoration(
                        labelText: '差異說明',
                        helperText: '選填，例如：利息、手續費、漏記消費',
                      ),
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
                onPressed: () async {
                  final value = actual.text.trim().replaceAll(',', '');
                  if (double.tryParse(value) == null) {
                    setState(() => error = '請輸入實際餘額');
                    return;
                  }
                  await store.reconcileAccount(
                    accountId: account.id,
                    actualBalanceMinor: parseMoney(value),
                    date: date,
                    note: note.text,
                  );
                  if (store.lastSyncError != null) {
                    setState(() => error = store.lastSyncError!);
                    return;
                  }
                  if (dialogContext.mounted) Navigator.pop(dialogContext);
                  if (context.mounted) showSaved(context, '已完成對帳');
                },
                child: Text(difference == 0 ? '確認無差異' : '確認並調整'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _showBillDialog(
    BuildContext context,
    WidgetRef ref,
    CardBill bill,
  ) async {
    final store = ref.read(appStoreProvider);
    final calculated = store.calculatedBillAmount(bill);
    final paid = store.paidBillMinor(bill);
    final current = store.billAmount(bill);
    final actual = TextEditingController(
      text: (current / 100).toStringAsFixed(current % 100 == 0 ? 0 : 2),
    );
    final note = TextEditingController(text: bill.reconciliationNote);
    var reason = bill.reconciliationReason;
    var error = '';
    final cardName = store.cardById(bill.cardId)?.name ?? '信用卡';
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) {
          final text = actual.text.trim();
          final entered = text.isEmpty ? null : parseMoney(text);
          final difference = entered == null ? null : entered - calculated;
          return AlertDialog(
            title: Text('核對：$cardName ${bill.month} 帳單'),
            content: SizedBox(
              width: 420,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _AmountLine(label: '系統明細合計', value: moneyText(calculated)),
                    const SizedBox(height: 6),
                    _AmountLine(label: '已繳金額', value: moneyText(paid)),
                    const SizedBox(height: 12),
                    MoneyField(
                      controller: actual,
                      autofocus: true,
                      decoration: const InputDecoration(
                        labelText: '銀行帳單應繳總額',
                        helperText: '依銀行寄來的帳單填寫',
                      ),
                      onChanged: (_) => setState(() => error = ''),
                    ),
                    const SizedBox(height: 12),
                    if (difference != null)
                      _DifferenceBanner(
                        differenceMinor: difference,
                        currency: 'TWD',
                        zeroText: '帳單與明細相符',
                        nonZeroText: '差額會記入信用卡負債並列為帳單核對差額',
                      ),
                    if (difference != null && difference != 0) ...[
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
                            if (item != CardBillReconciliationReason.none &&
                                item !=
                                    CardBillReconciliationReason
                                        .legacyAdjustment)
                              DropdownMenuItem(
                                value: item,
                                child: Text(item.label),
                              ),
                        ],
                        onChanged: (value) => setState(() {
                          reason = value!;
                          error = '';
                        }),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: note,
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
                onPressed: () async {
                  if (entered == null || entered < 0 || difference == null) {
                    setState(() => error = '請輸入銀行帳單應繳總額');
                    return;
                  }
                  if (difference != 0 &&
                      (reason == CardBillReconciliationReason.none ||
                          reason ==
                              CardBillReconciliationReason.legacyAdjustment)) {
                    setState(() => error = '請選擇差異原因');
                    return;
                  }
                  if (difference != 0 &&
                      reason == CardBillReconciliationReason.missingOrOther &&
                      note.text.trim().isEmpty) {
                    setState(() => error = '請填寫差異說明');
                    return;
                  }
                  await store.upsertBill(
                    bill.copyWith(
                      statementAmountMinor: entered,
                      reconciliationReason: difference == 0
                          ? CardBillReconciliationReason.none
                          : reason,
                      reconciliationNote: difference == 0
                          ? ''
                          : note.text.trim(),
                    ),
                    reconciliationDate: DateTime.now(),
                  );
                  if (store.lastSyncError != null) {
                    setState(() => error = store.lastSyncError!);
                    return;
                  }
                  if (dialogContext.mounted) Navigator.pop(dialogContext);
                  if (context.mounted) showSaved(context, '已完成帳單核對');
                },
                child: Text(difference == 0 ? '確認無差異' : '確認並調整'),
              ),
            ],
          );
        },
      ),
    );
  }
}

String _signedMoney(int minor, {String currency = 'TWD', bool mask = false}) {
  if (mask) return moneyText(minor, currency: currency, mask: true);
  final text = moneyText(minor.abs(), currency: currency);
  return minor > 0
      ? '+$text'
      : minor < 0
      ? '−$text'
      : text;
}

/// Units held, with up to four decimals and no trailing zeros
/// (e.g. 1000, 12.5, 0.1234).
String _quantityText(int micros) {
  var text = (micros / 1000000).toStringAsFixed(4);
  text = text.replaceFirst(RegExp(r'0+$'), '');
  return text.replaceFirst(RegExp(r'\.$'), '');
}

String _signedQuantity(int micros) {
  final text = _quantityText(micros.abs());
  return micros > 0
      ? '+$text'
      : micros < 0
      ? '−$text'
      : text;
}

class _InvestmentDifferenceBanner extends StatelessWidget {
  const _InvestmentDifferenceBanner({
    required this.quantityDiffMicros,
    required this.valueDiffMinor,
    required this.costChanged,
    required this.currency,
  });

  final int quantityDiffMicros;
  final int valueDiffMinor;
  final bool costChanged;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final balanced = quantityDiffMicros == 0 && !costChanged;
    final color = balanced ? context.colors.asset : context.colors.liability;
    final pale = balanced
        ? context.colors.assetPale
        : context.colors.liabilityPale;
    final title = balanced
        ? '持倉相符'
        : quantityDiffMicros == 0
        ? '數量相符，平均成本不同'
        : '數量差 ${_signedQuantity(quantityDiffMicros)} 單位'
              '（市值 ${_signedMoney(valueDiffMinor, currency: currency)}）';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: pale,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            balanced ? Icons.check_circle_outline : Icons.difference_outlined,
            color: color,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(color: color, fontWeight: FontWeight.w800),
                ),
                Text(
                  balanced
                      ? '將記錄為已確認'
                      : '確認後會在對帳日補一筆持倉快照，之後的交易照常計算',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InvestmentReconcileRow extends StatelessWidget {
  const _InvestmentReconcileRow({
    required this.product,
    required this.store,
    required this.stale,
    required this.mask,
    required this.onReconcile,
  });

  final InvestmentProduct product;
  final AppStore store;
  final bool stale;
  final bool mask;
  final VoidCallback onReconcile;

  @override
  Widget build(BuildContext context) {
    final holding = store.holdings[product.id];
    final quantity = holding?.quantityMicros ?? 0;
    final value = (quantity * product.currentPriceMinor / 1000000).round();
    final last = store.lastReconciliation(
      ReconciliationTargetType.investment,
      product.id,
    );
    final lastText = last == null
        ? '尚未對帳'
        : '上次對帳 ${dateText(last.date)}'
              '${last.isBalanced
                  ? '・相符'
                  : last.quantityDifferenceMicros != 0
                  ? '・調整 ${_signedQuantity(last.quantityDifferenceMicros)} 單位'
                  : '・調整平均成本'}';
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      leading: Icon(
        stale ? Icons.schedule : Icons.verified_outlined,
        color: stale ? context.colors.liability : context.colors.asset,
      ),
      title: Text(
        product.symbol.isEmpty
            ? product.name
            : '${product.name}（${product.symbol}）',
      ),
      subtitle: Text(
        '帳面 ${_quantityText(quantity)} 單位'
        '・市值 ${moneyText(value, currency: product.currency, mask: mask)}'
        '\n$lastText',
      ),
      isThreeLine: true,
      trailing: FilledButton.tonal(
        onPressed: onReconcile,
        child: const Text('對帳'),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, required this.subtitle});

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
        ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
      ),
      const SizedBox(height: 4),
      Text(subtitle, style: TextStyle(color: context.colors.textMuted)),
    ],
  );
}

class _AmountLine extends StatelessWidget {
  const _AmountLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Text(label, style: TextStyle(color: context.colors.textMuted)),
      ),
      Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
    ],
  );
}

class _DifferenceBanner extends StatelessWidget {
  const _DifferenceBanner({
    required this.differenceMinor,
    required this.currency,
    required this.zeroText,
    required this.nonZeroText,
  });

  final int differenceMinor;
  final String currency;
  final String zeroText;
  final String nonZeroText;

  @override
  Widget build(BuildContext context) {
    final balanced = differenceMinor == 0;
    final color = balanced ? context.colors.asset : context.colors.liability;
    final pale = balanced
        ? context.colors.assetPale
        : context.colors.liabilityPale;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: pale,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            balanced ? Icons.check_circle_outline : Icons.difference_outlined,
            color: color,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  balanced
                      ? '無差額'
                      : '差額 ${_signedMoney(differenceMinor, currency: currency)}',
                  style: TextStyle(color: color, fontWeight: FontWeight.w800),
                ),
                Text(balanced ? zeroText : nonZeroText),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AccountReconcileRow extends StatelessWidget {
  const _AccountReconcileRow({
    required this.account,
    required this.store,
    required this.stale,
    required this.mask,
    required this.onReconcile,
  });

  final Account account;
  final AppStore store;
  final bool stale;
  final bool mask;
  final VoidCallback onReconcile;

  @override
  Widget build(BuildContext context) {
    final last = store.lastReconciliation(
      ReconciliationTargetType.account,
      account.id,
    );
    final lastText = last == null
        ? '尚未對帳'
        : '上次對帳 ${dateText(last.date)}'
              '${last.isBalanced ? '・相符' : '・調整 ${_signedMoney(last.differenceMinor, currency: last.currency, mask: mask)}'}';
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      leading: Icon(
        stale ? Icons.schedule : Icons.verified_outlined,
        color: stale ? context.colors.liability : context.colors.asset,
      ),
      title: Text(account.name),
      subtitle: Text(
        '帳面 ${moneyText(store.accountBalance(account.id), currency: account.currency, mask: mask)}\n$lastText',
      ),
      isThreeLine: true,
      trailing: FilledButton.tonal(
        onPressed: onReconcile,
        child: const Text('對帳'),
      ),
    );
  }
}

class _BillReconcileRow extends StatelessWidget {
  const _BillReconcileRow({
    required this.bill,
    required this.store,
    required this.mask,
    required this.onReconcile,
  });

  final CardBill bill;
  final AppStore store;
  final bool mask;
  final VoidCallback onReconcile;

  @override
  Widget build(BuildContext context) {
    final last = store.lastReconciliation(
      ReconciliationTargetType.cardBill,
      bill.id,
    );
    final difference = store.reconciliationDifference(bill);
    final checkedText = last == null
        ? '尚未核對'
        : '已核對 ${dateText(last.date)}'
              '${difference == 0 ? '・相符' : '・差額 ${_signedMoney(difference, mask: mask)}'}';
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      leading: Icon(
        last == null ? Icons.pending_outlined : Icons.verified_outlined,
        color: last == null ? context.colors.liability : context.colors.asset,
      ),
      title: Text(
        '${store.cardById(bill.cardId)?.name ?? '信用卡'} ${bill.month}',
      ),
      subtitle: Text(
        '明細 ${moneyText(store.calculatedBillAmount(bill), mask: mask)}'
        '・帳單 ${moneyText(store.billAmount(bill), mask: mask)}'
        '・${store.billStatus(bill).label}\n$checkedText',
      ),
      isThreeLine: true,
      trailing: FilledButton.tonal(
        onPressed: onReconcile,
        child: const Text('核對'),
      ),
    );
  }
}

/// Credit-card and 電信 bills in one list, newest first, filterable to just
/// the ones still waiting for a check against the real statement.
class _BillsSection extends StatefulWidget {
  const _BillsSection({
    required this.store,
    required this.bills,
    required this.telecomPayments,
    required this.mask,
    required this.onReconcileBill,
    required this.onReconcileTelecom,
  });

  final AppStore store;
  final List<CardBill> bills;
  final List<TelecomBillPayment> telecomPayments;
  final bool mask;
  final ValueChanged<CardBill> onReconcileBill;
  final ValueChanged<TelecomBillPayment> onReconcileTelecom;

  @override
  State<_BillsSection> createState() => _BillsSectionState();
}

class _BillsSectionState extends State<_BillsSection> {
  var _pendingOnly = true;

  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    final entries = <(DateTime, Widget)>[
      for (final bill in widget.bills)
        if (!_pendingOnly ||
            store.outstandingBillMinor(bill) > 0 ||
            store.lastReconciliation(
                  ReconciliationTargetType.cardBill,
                  bill.id,
                ) ==
                null)
          (
            bill.dueDate,
            _BillReconcileRow(
              bill: bill,
              store: store,
              mask: widget.mask,
              onReconcile: () => widget.onReconcileBill(bill),
            ),
          ),
      for (final payment in widget.telecomPayments)
        if (!_pendingOnly ||
            store.lastReconciliation(
                  ReconciliationTargetType.telecomBill,
                  payment.id,
                ) ==
                null)
          (
            payment.paidAt,
            _TelecomReconcileRow(
              payment: payment,
              store: store,
              mask: widget.mask,
              onReconcile: () => widget.onReconcileTelecom(payment),
            ),
          ),
    ]..sort((a, b) => b.$1.compareTo(a.$1));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment(value: true, label: Text('待核對')),
            ButtonSegment(value: false, label: Text('全部')),
          ],
          selected: {_pendingOnly},
          onSelectionChanged: (value) =>
              setState(() => _pendingOnly = value.first),
        ),
        const SizedBox(height: 12),
        if (entries.isEmpty)
          EmptyState(
            icon: Icons.receipt_long_outlined,
            title: _pendingOnly ? '帳單都核對完了' : '還沒有帳單',
            message: '信用卡結帳後、電信帳單扣款後，自動產生的帳單會出現在這裡。',
          )
        else
          Card(
            child: Column(
              children: [
                for (var index = 0; index < entries.length; index++) ...[
                  entries[index].$2,
                  if (index < entries.length - 1) const Divider(height: 1),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

class _TelecomReconcileRow extends StatelessWidget {
  const _TelecomReconcileRow({
    required this.payment,
    required this.store,
    required this.mask,
    required this.onReconcile,
  });

  final TelecomBillPayment payment;
  final AppStore store;
  final bool mask;
  final VoidCallback onReconcile;

  @override
  Widget build(BuildContext context) {
    final last = store.lastReconciliation(
      ReconciliationTargetType.telecomBill,
      payment.id,
    );
    final account = store.accountById(payment.debitAccountId);
    final currency = account?.currency ?? 'TWD';
    final checkedText = last == null
        ? '尚未核對'
        : '已核對 ${dateText(last.date)}'
              '${last.isBalanced ? '・相符' : '・差額 ${_signedMoney(last.differenceMinor, currency: last.currency, mask: mask)}'}';
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      leading: Icon(
        last == null ? Icons.pending_outlined : Icons.verified_outlined,
        color: last == null ? context.colors.liability : context.colors.asset,
      ),
      title: Text('電信帳單 ${payment.month}'),
      subtitle: Text(
        '明細 ${moneyText(payment.amountMinor, currency: currency, mask: mask)}'
        '・${account?.name ?? '指定帳戶'} 扣款 ${dateText(payment.paidAt)}'
        '\n$checkedText',
      ),
      isThreeLine: true,
      trailing: FilledButton.tonal(
        onPressed: onReconcile,
        child: const Text('核對'),
      ),
    );
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({
    required this.record,
    required this.store,
    required this.mask,
    required this.onDelete,
  });

  final ReconciliationRecord record;
  final AppStore store;
  final bool mask;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final color = record.isBalanced
        ? context.colors.asset
        : context.colors.liability;
    final isInvestment =
        record.targetType == ReconciliationTargetType.investment;
    final summary = isInvestment
        ? '${dateText(record.date)}・${record.targetType.label}'
              '・帳面 ${_quantityText(record.bookQuantityMicros ?? 0)}'
              ' → 實際 ${_quantityText(record.actualQuantityMicros ?? 0)} 單位'
        : '${dateText(record.date)}・${record.targetType.label}'
              '・帳面 ${moneyText(record.bookBalanceMinor, currency: record.currency, mask: mask)}'
              ' → 實際 ${moneyText(record.actualBalanceMinor, currency: record.currency, mask: mask)}';
    final differenceText = record.isBalanced
        ? '相符'
        : isInvestment && record.quantityDifferenceMicros == 0
        ? '成本調整'
        : isInvestment
        ? '${_signedQuantity(record.quantityDifferenceMicros)} 單位'
        : _signedMoney(
            record.differenceMinor,
            currency: record.currency,
            mask: mask,
          );
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      title: Text(store.reconciliationTargetName(record)),
      subtitle: Text(
        record.note.isEmpty ? summary : '$summary\n${record.note}',
      ),
      isThreeLine: record.note.isNotEmpty,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            differenceText,
            style: TextStyle(color: color, fontWeight: FontWeight.w800),
          ),
          IconButton(
            tooltip: record.targetType == ReconciliationTargetType.cardBill
                ? '刪除紀錄'
                : '撤銷對帳',
            onPressed: onDelete,
            icon: const Icon(Icons.undo),
          ),
        ],
      ),
    );
  }
}
