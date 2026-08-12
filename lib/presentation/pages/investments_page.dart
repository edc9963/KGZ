import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/providers.dart';
import '../../domain/models.dart';
import '../widgets/common.dart';

enum _HoldingCreationMode { snapshot, purchase }

class InvestmentsPage extends ConsumerStatefulWidget {
  const InvestmentsPage({
    this.editTransactionId,
    this.returnOnEditorClose = false,
    super.key,
  });

  final String? editTransactionId;
  final bool returnOnEditorClose;

  @override
  ConsumerState<InvestmentsPage> createState() => _InvestmentsPageState();
}

class _InvestmentsPageState extends ConsumerState<InvestmentsPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 3, vsync: this);
  bool _editorOpened = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (widget.editTransactionId == null || _editorOpened) return;
    _editorOpened = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final item = ref
          .read(appStoreProvider)
          .data
          .investmentTransactions
          .where((item) => item.id == widget.editTransactionId)
          .firstOrNull;
      if (item != null) await _showTransactionDialog(context, item);
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
    final heldProducts = store.data.products.where(
      (product) => (store.holdings[product.id]?.quantityMicros ?? 0) > 0,
    );
    final unpricedHoldingCount = heldProducts
        .where((product) => product.currentPriceMinor <= 0)
        .length;
    final pricedHoldingCount = heldProducts.length - unpricedHoldingCount;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PageHeader(
          title: '投資管理',
          subtitle: '交易自動推導庫存，也可透過盤點調整校正',
          action: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              FilledButton.icon(
                key: const ValueKey('create-holding'),
                onPressed: () => _showCreateHoldingDialog(context),
                icon: const Icon(Icons.add),
                label: const Text('建立庫存'),
              ),
              PopupMenuButton<String>(
                tooltip: '其他投資操作',
                onSelected: (value) {
                  if (value == 'product') _showProductDialog(context);
                  if (value == 'transaction') _showTransactionDialog(context);
                  if (value == 'adjustment') _showAdjustmentDialog(context);
                },
                itemBuilder: (context) => const [
                  PopupMenuItem(value: 'transaction', child: Text('新增交易')),
                  PopupMenuItem(value: 'product', child: Text('新增商品')),
                  PopupMenuItem(value: 'adjustment', child: Text('庫存盤點調整')),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        ResponsiveGrid(
          children: [
            SummaryCard(
              label: '投資現值',
              value: pricedHoldingCount == 0 && unpricedHoldingCount > 0
                  ? '尚未定價'
                  : moneyText(
                      store.investmentValueMinor,
                      mask: store.data.settings.maskBalances,
                    ),
              icon: Icons.trending_up,
              tone: const Color(0xFF3578E5),
              caption: unpricedHoldingCount == 0
                  ? null
                  : '$unpricedHoldingCount 項持倉尚待補目前價格',
            ),
            SummaryCard(
              label: '持有商品',
              value:
                  '${store.holdings.values.where((item) => item.quantityMicros > 0).length} 項',
              icon: Icons.inventory_2_outlined,
            ),
            SummaryCard(
              label: '交易紀錄',
              value: '${store.data.investmentTransactions.length} 筆',
              icon: Icons.swap_horiz_rounded,
            ),
          ],
        ),
        const SizedBox(height: 18),
        Card(
          child: TabBar(
            controller: _tabs,
            tabs: const [
              Tab(text: '庫存'),
              Tab(text: '交易紀錄'),
              Tab(text: '商品'),
            ],
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 620,
          child: TabBarView(
            controller: _tabs,
            children: [
              _HoldingsList(
                onCreate: () => _showCreateHoldingDialog(context),
                onAdjust: (id) => _showAdjustmentDialog(context, id),
              ),
              _TransactionsList(
                onEdit: (item) => _showTransactionDialog(context, item),
              ),
              _ProductsList(
                onEdit: (item) => _showProductDialog(context, item),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _showCreateHoldingDialog(BuildContext context) async {
    final store = ref.read(appStoreProvider);
    var mode = _HoldingCreationMode.snapshot;
    var createProduct = store.data.products.isEmpty;
    String? productId = store.data.products.firstOrNull?.id;
    String? accountId = store.data.accounts
        .where((item) => item.isActive)
        .firstOrNull
        ?.id;
    var productType = 'ETF';
    var currency = 'TWD';
    var date = DateTime.now();
    var showCosts = false;
    final symbol = TextEditingController();
    final name = TextEditingController();
    final quantity = TextEditingController();
    final unitCost = TextEditingController();
    final fee = TextEditingController(text: '0');
    final tax = TextEditingController(text: '0');

    void loadExistingProduct(String? id) {
      productId = id;
      final holding = id == null ? null : store.holdings[id];
      quantity.text = holding == null ? '' : holding.quantity.toString();
      unitCost.text = holding == null
          ? ''
          : (holding.averageCostMinor / 100).toString();
    }

    if (!createProduct) loadExistingProduct(productId);

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) {
          final selectedHolding = createProduct || productId == null
              ? null
              : store.holdings[productId];
          final isUpdating =
              mode == _HoldingCreationMode.snapshot &&
              (selectedHolding?.quantityMicros ?? 0) > 0;
          final parsedQuantity = parseQuantity(quantity.text);
          final parsedUnitCost = parseMoney(unitCost.text);
          final parsedFee = parseMoney(fee.text);
          final parsedTax = parseMoney(tax.text);
          final totalMinor =
              (parsedQuantity * parsedUnitCost).round() + parsedFee + parsedTax;
          final productValid = createProduct
              ? name.text.trim().isNotEmpty
              : productId != null;
          final canSave =
              productValid &&
              parsedQuantity > 0 &&
              parsedUnitCost > 0 &&
              (mode == _HoldingCreationMode.snapshot || accountId != null);
          final activeAccounts = store.data.accounts
              .where((item) => item.isActive)
              .toList();

          return AlertDialog(
            title: Text(isUpdating ? '更新庫存' : '建立庫存'),
            content: SizedBox(
              width: 560,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SegmentedButton<_HoldingCreationMode>(
                      segments: const [
                        ButtonSegment(
                          value: _HoldingCreationMode.snapshot,
                          icon: Icon(Icons.inventory_2_outlined),
                          label: Text('既有持倉'),
                        ),
                        ButtonSegment(
                          value: _HoldingCreationMode.purchase,
                          icon: Icon(Icons.shopping_cart_outlined),
                          label: Text('新買入'),
                        ),
                      ],
                      selected: {mode},
                      onSelectionChanged: (value) => setState(() {
                        mode = value.first;
                        if (mode == _HoldingCreationMode.snapshot &&
                            !createProduct) {
                          loadExistingProduct(productId);
                        } else {
                          quantity.clear();
                          unitCost.clear();
                        }
                      }),
                    ),
                    const SizedBox(height: 16),
                    SegmentedButton<bool>(
                      segments: const [
                        ButtonSegment(
                          value: true,
                          icon: Icon(Icons.add_chart),
                          label: Text('新增商品'),
                        ),
                        ButtonSegment(
                          value: false,
                          icon: Icon(Icons.search),
                          label: Text('既有商品'),
                        ),
                      ],
                      selected: {createProduct},
                      onSelectionChanged: store.data.products.isEmpty
                          ? null
                          : (value) => setState(() {
                              createProduct = value.first;
                              if (!createProduct) {
                                loadExistingProduct(productId);
                              } else {
                                quantity.clear();
                                unitCost.clear();
                              }
                            }),
                    ),
                    const SizedBox(height: 16),
                    if (createProduct) ...[
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              key: const ValueKey('holding-product-symbol'),
                              controller: symbol,
                              decoration: const InputDecoration(
                                labelText: '商品代號',
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 2,
                            child: TextField(
                              key: const ValueKey('holding-product-name'),
                              controller: name,
                              decoration: const InputDecoration(
                                labelText: '商品名稱',
                              ),
                              onChanged: (_) => setState(() {}),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              initialValue: productType,
                              decoration: const InputDecoration(
                                labelText: '商品類型',
                              ),
                              items: const ['股票', 'ETF', '基金', '外幣', '虛擬資產']
                                  .map(
                                    (value) => DropdownMenuItem(
                                      value: value,
                                      child: Text(value),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (value) =>
                                  setState(() => productType = value!),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              initialValue: currency,
                              decoration: const InputDecoration(
                                labelText: '幣別',
                              ),
                              items: const ['TWD', 'USD', 'JPY', 'EUR']
                                  .map(
                                    (value) => DropdownMenuItem(
                                      value: value,
                                      child: Text(value),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (value) =>
                                  setState(() => currency = value!),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        '目前價格可稍後到商品資料補上；未設定前不顯示市值與損益。',
                        style: TextStyle(color: Colors.black54),
                      ),
                    ] else
                      DropdownButtonFormField<String>(
                        key: const ValueKey('holding-existing-product'),
                        initialValue: productId,
                        decoration: const InputDecoration(labelText: '投資商品'),
                        items: store.data.products
                            .map(
                              (product) => DropdownMenuItem(
                                value: product.id,
                                child: Text(
                                  '${product.symbol} ${product.name}',
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: (value) => setState(() {
                          loadExistingProduct(value);
                        }),
                      ),
                    const SizedBox(height: 12),
                    InkWell(
                      onTap: () async {
                        final value = await showDatePicker(
                          context: context,
                          initialDate: date,
                          firstDate: DateTime(2000),
                          lastDate: DateTime.now().add(
                            const Duration(days: 365),
                          ),
                        );
                        if (value != null) setState(() => date = value);
                      },
                      child: InputDecorator(
                        decoration: InputDecoration(
                          labelText: mode == _HoldingCreationMode.snapshot
                              ? '盤點日期'
                              : '交易日期',
                        ),
                        child: Text(dateText(date)),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            key: const ValueKey('holding-quantity'),
                            controller: quantity,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: const InputDecoration(labelText: '單位數'),
                            onChanged: (_) => setState(() {}),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            key: const ValueKey('holding-unit-cost'),
                            controller: unitCost,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: InputDecoration(
                              labelText: mode == _HoldingCreationMode.snapshot
                                  ? '平均成本'
                                  : '買入單價',
                            ),
                            onChanged: (_) => setState(() {}),
                          ),
                        ),
                      ],
                    ),
                    if (mode == _HoldingCreationMode.purchase) ...[
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        key: const ValueKey('holding-debit-account'),
                        initialValue:
                            activeAccounts.any((item) => item.id == accountId)
                            ? accountId
                            : null,
                        decoration: const InputDecoration(labelText: '扣款帳戶'),
                        items: activeAccounts
                            .map(
                              (account) => DropdownMenuItem(
                                value: account.id,
                                child: Text(account.name),
                              ),
                            )
                            .toList(),
                        onChanged: (value) => setState(() => accountId = value),
                      ),
                      TextButton.icon(
                        onPressed: () => setState(() => showCosts = !showCosts),
                        icon: Icon(
                          showCosts ? Icons.expand_less : Icons.expand_more,
                        ),
                        label: Text(showCosts ? '收起費用' : '加入手續費與稅費'),
                      ),
                      if (showCosts)
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                key: const ValueKey('holding-fee'),
                                controller: fee,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                decoration: const InputDecoration(
                                  labelText: '手續費',
                                ),
                                onChanged: (_) => setState(() {}),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextField(
                                key: const ValueKey('holding-tax'),
                                controller: tax,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                decoration: const InputDecoration(
                                  labelText: '稅費',
                                ),
                                onChanged: (_) => setState(() {}),
                              ),
                            ),
                          ],
                        ),
                      const SizedBox(height: 8),
                      Text(
                        '預計扣款 ${moneyText(totalMinor, currency: currency)}',
                        key: const ValueKey('holding-total'),
                        textAlign: TextAlign.end,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ] else if (isUpdating) ...[
                      const SizedBox(height: 10),
                      const Text(
                        '這會以所選日期校正持倉，且不影響任何現金帳戶。',
                        style: TextStyle(color: Colors.black54),
                      ),
                    ],
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
                key: const ValueKey('save-holding'),
                onPressed: canSave
                    ? () async {
                        final product = createProduct
                            ? InvestmentProduct(
                                id: store.newId(),
                                userId: store.userId,
                                symbol: symbol.text.trim(),
                                name: name.text.trim(),
                                type: productType,
                                currency: currency,
                                currentPriceMinor: 0,
                                priceUpdatedAt: date,
                                note: '',
                              )
                            : store.productById(productId!)!;
                        final quantityMicros = (parsedQuantity * 1000000)
                            .round();
                        await store.createInvestmentHolding(
                          product: product,
                          adjustment: mode == _HoldingCreationMode.snapshot
                              ? InvestmentAdjustment(
                                  id: store.newId(),
                                  userId: store.userId,
                                  productId: product.id,
                                  date: date,
                                  quantityMicros: quantityMicros,
                                  averageCostMinor: parsedUnitCost,
                                  reason: isUpdating ? '庫存校正' : '建立既有持倉',
                                )
                              : null,
                          transaction: mode == _HoldingCreationMode.purchase
                              ? InvestmentTransaction(
                                  id: store.newId(),
                                  userId: store.userId,
                                  date: date,
                                  type: InvestmentTransactionType.buy,
                                  productId: product.id,
                                  quantityMicros: quantityMicros,
                                  priceMinor: parsedUnitCost,
                                  feeMinor: parsedFee,
                                  taxMinor: parsedTax,
                                  debitAccountId: accountId,
                                  note: '建立庫存',
                                )
                              : null,
                        );
                        _tabs.animateTo(0);
                        if (dialogContext.mounted) {
                          Navigator.pop(dialogContext);
                        }
                      }
                    : null,
                child: Text(isUpdating ? '更新庫存' : '建立庫存'),
              ),
            ],
          );
        },
      ),
    );

    // The dialog route completes before its reverse animation has detached the
    // text fields. Keep their controllers alive until that transition finishes.
    await Future<void>.delayed(const Duration(milliseconds: 250));
    symbol.dispose();
    name.dispose();
    quantity.dispose();
    unitCost.dispose();
    fee.dispose();
    tax.dispose();
  }

  Future<void> _showProductDialog(
    BuildContext context, [
    InvestmentProduct? existing,
  ]) async {
    final store = ref.read(appStoreProvider);
    final symbol = TextEditingController(text: existing?.symbol);
    final name = TextEditingController(text: existing?.name);
    final price = TextEditingController(
      text: existing == null
          ? ''
          : (existing.currentPriceMinor / 100).toString(),
    );
    final note = TextEditingController(text: existing?.note);
    var type = existing?.type ?? 'ETF';
    var currency = existing?.currency ?? 'TWD';
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(existing == null ? '新增投資商品' : '編輯投資商品'),
          content: SizedBox(
            width: 480,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: symbol,
                        decoration: const InputDecoration(labelText: '商品代號'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: TextField(
                        controller: name,
                        decoration: const InputDecoration(labelText: '商品名稱'),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: type,
                        decoration: const InputDecoration(labelText: '商品類型'),
                        items: const ['股票', 'ETF', '基金', '外幣', '虛擬資產']
                            .map(
                              (value) => DropdownMenuItem(
                                value: value,
                                child: Text(value),
                              ),
                            )
                            .toList(),
                        onChanged: (value) => setState(() => type = value!),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: currency,
                        decoration: const InputDecoration(labelText: '幣別'),
                        items: const ['TWD', 'USD', 'JPY', 'EUR']
                            .map(
                              (value) => DropdownMenuItem(
                                value: value,
                                child: Text(value),
                              ),
                            )
                            .toList(),
                        onChanged: (value) => setState(() => currency = value!),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: price,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(labelText: '目前價格'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: note,
                  decoration: const InputDecoration(labelText: '備註'),
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
              onPressed: name.text.trim().isEmpty
                  ? null
                  : () async {
                      await store.upsertProduct(
                        InvestmentProduct(
                          id: existing?.id ?? store.newId(),
                          userId: store.userId,
                          symbol: symbol.text.trim(),
                          name: name.text.trim(),
                          type: type,
                          currency: currency,
                          currentPriceMinor: parseMoney(price.text),
                          priceUpdatedAt: DateTime.now(),
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

  Future<void> _showTransactionDialog(
    BuildContext context, [
    InvestmentTransaction? existing,
  ]) async {
    final store = ref.read(appStoreProvider);
    var productId =
        existing?.productId ??
        (store.data.products.isEmpty ? null : store.data.products.first.id);
    var type = existing?.type ?? InvestmentTransactionType.buy;
    var date = existing?.date ?? DateTime.now();
    var debitId =
        existing?.debitAccountId ??
        (store.data.accounts.isEmpty ? null : store.data.accounts.first.id);
    var creditId =
        existing?.creditAccountId ??
        (store.data.accounts.isEmpty ? null : store.data.accounts.first.id);
    final quantity = TextEditingController(
      text: existing == null ? '' : existing.quantity.toString(),
    );
    final price = TextEditingController(
      text: existing == null ? '' : (existing.priceMinor / 100).toString(),
    );
    final fee = TextEditingController(
      text: existing == null ? '0' : (existing.feeMinor / 100).toString(),
    );
    final tax = TextEditingController(
      text: existing == null ? '0' : (existing.taxMinor / 100).toString(),
    );
    final note = TextEditingController(text: existing?.note);
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) {
          final needsDebit =
              type == InvestmentTransactionType.buy ||
              type == InvestmentTransactionType.subscribe;
          final needsCredit =
              type == InvestmentTransactionType.sell ||
              type == InvestmentTransactionType.redeem ||
              type == InvestmentTransactionType.dividend;
          return AlertDialog(
            title: Text(existing == null ? '新增投資交易' : '編輯投資交易'),
            content: SizedBox(
              width: 540,
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    DropdownButtonFormField<String>(
                      initialValue:
                          store.data.products.any(
                            (item) => item.id == productId,
                          )
                          ? productId
                          : null,
                      decoration: const InputDecoration(labelText: '投資商品'),
                      items: store.data.products
                          .map(
                            (product) => DropdownMenuItem(
                              value: product.id,
                              child: Text('${product.symbol} ${product.name}'),
                            ),
                          )
                          .toList(),
                      onChanged: (value) => setState(() => productId = value),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<InvestmentTransactionType>(
                      initialValue: type,
                      decoration: const InputDecoration(labelText: '交易類型'),
                      items: InvestmentTransactionType.values
                          .map(
                            (value) => DropdownMenuItem(
                              value: value,
                              child: Text(value.label),
                            ),
                          )
                          .toList(),
                      onChanged: (value) => setState(() => type = value!),
                    ),
                    const SizedBox(height: 12),
                    InkWell(
                      onTap: () async {
                        final value = await showDatePicker(
                          context: context,
                          initialDate: date,
                          firstDate: DateTime(2000),
                          lastDate: DateTime.now().add(
                            const Duration(days: 365),
                          ),
                        );
                        if (value != null) setState(() => date = value);
                      },
                      child: InputDecorator(
                        decoration: const InputDecoration(labelText: '交易日期'),
                        child: Text(dateText(date)),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: quantity,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: const InputDecoration(labelText: '數量'),
                            onChanged: (_) => setState(() {}),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: price,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: const InputDecoration(
                              labelText: '價格／每單位配息',
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: fee,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: const InputDecoration(labelText: '手續費'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: tax,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: const InputDecoration(labelText: '稅費'),
                          ),
                        ),
                      ],
                    ),
                    if (needsDebit || needsCredit) ...[
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue:
                            store.data.accounts.any(
                              (item) =>
                                  item.id == (needsDebit ? debitId : creditId),
                            )
                            ? (needsDebit ? debitId : creditId)
                            : null,
                        decoration: InputDecoration(
                          labelText: needsDebit ? '扣款帳戶' : '入款帳戶',
                        ),
                        items: store.data.accounts
                            .map(
                              (account) => DropdownMenuItem(
                                value: account.id,
                                child: Text(account.name),
                              ),
                            )
                            .toList(),
                        onChanged: (value) => setState(() {
                          needsDebit ? debitId = value : creditId = value;
                        }),
                      ),
                    ],
                    const SizedBox(height: 12),
                    TextField(
                      controller: note,
                      decoration: const InputDecoration(labelText: '備註'),
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
                onPressed:
                    productId == null || parseQuantity(quantity.text) <= 0
                    ? null
                    : () async {
                        await store.upsertInvestmentTransaction(
                          InvestmentTransaction(
                            id: existing?.id ?? store.newId(),
                            userId: store.userId,
                            date: date,
                            type: type,
                            productId: productId!,
                            quantityMicros:
                                (parseQuantity(quantity.text) * 1000000)
                                    .round(),
                            priceMinor: parseMoney(price.text),
                            feeMinor: parseMoney(fee.text),
                            taxMinor: parseMoney(tax.text),
                            debitAccountId: needsDebit ? debitId : null,
                            creditAccountId: needsCredit ? creditId : null,
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

  Future<void> _showAdjustmentDialog(
    BuildContext context, [
    String? initialProductId,
  ]) async {
    final store = ref.read(appStoreProvider);
    var productId =
        initialProductId ??
        (store.data.products.isEmpty ? null : store.data.products.first.id);
    final initialHolding = store.holdings[productId];
    final quantity = TextEditingController(
      text: initialHolding?.quantity.toString() ?? '',
    );
    final cost = TextEditingController(
      text: initialHolding == null
          ? ''
          : (initialHolding.averageCostMinor / 100).toString(),
    );
    final reason = TextEditingController(text: '券商庫存盤點');
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('庫存盤點調整'),
          content: SizedBox(
            width: 460,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: productId,
                  decoration: const InputDecoration(labelText: '投資商品'),
                  items: store.data.products
                      .map(
                        (product) => DropdownMenuItem(
                          value: product.id,
                          child: Text('${product.symbol} ${product.name}'),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    setState(() => productId = value);
                    final holding = store.holdings[value];
                    quantity.text = holding?.quantity.toString() ?? '';
                    cost.text = holding == null
                        ? ''
                        : (holding.averageCostMinor / 100).toString();
                  },
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: quantity,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(labelText: '校正後數量'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: cost,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(labelText: '校正後平均成本'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: reason,
                  decoration: const InputDecoration(labelText: '調整原因'),
                ),
                const SizedBox(height: 10),
                const Text(
                  '盤點調整不產生帳戶扣入款，後續交易將以校正後庫存繼續計算。',
                  style: TextStyle(color: Colors.black54),
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
              onPressed: productId == null
                  ? null
                  : () async {
                      await store.upsertInvestmentAdjustment(
                        InvestmentAdjustment(
                          id: store.newId(),
                          userId: store.userId,
                          productId: productId!,
                          date: DateTime.now(),
                          quantityMicros:
                              (parseQuantity(quantity.text) * 1000000).round(),
                          averageCostMinor: parseMoney(cost.text),
                          reason: reason.text.trim(),
                        ),
                      );
                      if (dialogContext.mounted) Navigator.pop(dialogContext);
                    },
              child: const Text('套用校正'),
            ),
          ],
        ),
      ),
    );
  }
}

class _HoldingsList extends ConsumerWidget {
  const _HoldingsList({required this.onCreate, required this.onAdjust});
  final VoidCallback onCreate;
  final ValueChanged<String> onAdjust;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final store = ref.watch(appStoreProvider);
    final products = store.data.products
        .where(
          (product) => (store.holdings[product.id]?.quantityMicros ?? 0) > 0,
        )
        .toList();
    if (products.isEmpty) {
      return EmptyState(
        icon: Icons.inventory_2_outlined,
        title: '目前沒有投資庫存',
        message: '直接填入商品、單位數與平均成本即可開始。',
        action: FilledButton.icon(
          key: const ValueKey('empty-create-holding'),
          onPressed: onCreate,
          icon: const Icon(Icons.add),
          label: const Text('建立庫存'),
        ),
      );
    }
    return ListView.separated(
      itemCount: products.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final product = products[index];
        final holding = store.holdings[product.id]!;
        final isPriced = product.currentPriceMinor > 0;
        final value = isPriced
            ? (holding.quantityMicros * product.currentPriceMinor / 1000000)
                  .round()
            : 0;
        final cost =
            (holding.quantityMicros * holding.averageCostMinor / 1000000)
                .round();
        final profit = value - cost;
        final rate = cost == 0 ? 0 : profit / cost * 100;
        final identity = Row(
          children: [
            CircleAvatar(
              child: Text(
                product.symbol.isEmpty
                    ? product.name.characters.take(2).toString()
                    : product.symbol.characters.take(2).toString(),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${product.symbol} ${product.name}'.trim(),
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  Text(
                    '${holding.quantity.toStringAsFixed(4)} 單位・'
                    '均價 ${moneyText(holding.averageCostMinor, currency: product.currency)}',
                  ),
                ],
              ),
            ),
          ],
        );
        final valuation = isPriced
            ? Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    moneyText(value, currency: product.currency),
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                  Text(
                    '${profit >= 0 ? '+' : ''}${moneyText(profit, currency: product.currency)} '
                    '(${rate.toStringAsFixed(2)}%)',
                    style: TextStyle(
                      color: profit >= 0
                          ? const Color(0xFFB84B3E)
                          : const Color(0xFF1680A8),
                    ),
                  ),
                ],
              )
            : const Text(
                '尚未設定目前價格',
                key: ValueKey('holding-unpriced'),
                style: TextStyle(color: Colors.black54),
              );
        return Card(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final action = IconButton(
                tooltip: '盤點調整',
                onPressed: () => onAdjust(product.id),
                icon: const Icon(Icons.tune),
              );
              if (constraints.maxWidth < 600) {
                return Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 8, 10),
                  child: Column(
                    children: [
                      identity,
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          const SizedBox(width: 52),
                          Expanded(child: valuation),
                          action,
                        ],
                      ),
                    ],
                  ),
                );
              }
              return Padding(
                padding: const EdgeInsets.fromLTRB(18, 14, 8, 14),
                child: Row(
                  children: [
                    Expanded(child: identity),
                    const SizedBox(width: 16),
                    valuation,
                    action,
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }
}

class _TransactionsList extends ConsumerWidget {
  const _TransactionsList({required this.onEdit});
  final ValueChanged<InvestmentTransaction> onEdit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final store = ref.watch(appStoreProvider);
    final items = [...store.data.investmentTransactions]
      ..sort((a, b) => b.date.compareTo(a.date));
    if (items.isEmpty) {
      return const EmptyState(
        icon: Icons.swap_horiz,
        title: '沒有投資交易',
        message: '買入、賣出、申贖與配息都會顯示在這裡。',
      );
    }
    return ListView.separated(
      itemCount: items.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final item = items[index];
        final product = store.productById(item.productId);
        return ListTile(
          leading: CircleAvatar(child: Text(item.type.label.characters.first)),
          title: Text('${product?.symbol ?? ''} ${product?.name ?? ''}'),
          subtitle: Text(
            '${dateText(item.date)}・${item.type.label}・'
            '${item.quantity.toStringAsFixed(4)} 單位',
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                moneyText(
                  item.grossMinor,
                  currency: product?.currency ?? 'TWD',
                ),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              PopupMenuButton<String>(
                onSelected: (value) async {
                  if (value == 'edit') onEdit(item);
                  if (value == 'delete' &&
                      await confirmDelete(context, '投資交易')) {
                    await store.deleteInvestmentTransaction(item.id);
                  }
                },
                itemBuilder: (context) => const [
                  PopupMenuItem(value: 'edit', child: Text('編輯')),
                  PopupMenuItem(value: 'delete', child: Text('刪除')),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ProductsList extends ConsumerWidget {
  const _ProductsList({required this.onEdit});
  final ValueChanged<InvestmentProduct> onEdit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final store = ref.watch(appStoreProvider);
    if (store.data.products.isEmpty) {
      return const EmptyState(
        icon: Icons.add_chart,
        title: '還沒有投資商品',
        message: '先建立股票、ETF、基金、外幣或虛擬資產。',
      );
    }
    return ListView.separated(
      itemCount: store.data.products.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final item = store.data.products[index];
        return ListTile(
          leading: const CircleAvatar(child: Icon(Icons.show_chart)),
          title: Text('${item.symbol} ${item.name}'),
          subtitle: Text(
            '${item.type}・${item.currency}・更新 ${dateText(item.priceUpdatedAt)}',
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                moneyText(item.currentPriceMinor, currency: item.currency),
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              PopupMenuButton<String>(
                onSelected: (value) async {
                  if (value == 'edit') onEdit(item);
                  if (value == 'delete' &&
                      await confirmDelete(context, '投資商品及其交易')) {
                    await store.deleteProduct(item.id);
                  }
                },
                itemBuilder: (context) => const [
                  PopupMenuItem(value: 'edit', child: Text('編輯')),
                  PopupMenuItem(value: 'delete', child: Text('刪除')),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
