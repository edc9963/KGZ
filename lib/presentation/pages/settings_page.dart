import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/app_store.dart';
import '../../application/providers.dart';
import '../../domain/models.dart';
import '../design_tokens.dart';
import '../widgets/common.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final store = ref.watch(appStoreProvider);
    final settings = store.data.settings;
    final latestRatesByPair = <String, FxRate>{};
    for (final rate in settings.fxRates) {
      final key = '${rate.from}/${rate.to}';
      final current = latestRatesByPair[key];
      if (current == null || rate.updatedAt.isAfter(current.updatedAt)) {
        latestRatesByPair[key] = rate;
      }
    }
    final latestRates = latestRatesByPair.values.toList()
      ..sort((a, b) => a.from.compareTo(b.from));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const PageHeader(title: '設定', subtitle: '預設值、匯率、收款資訊、提醒與本機資料管理'),
        const SizedBox(height: 22),
        _Section(
          title: '一般偏好',
          icon: Icons.tune,
          children: [
            ListTile(
              title: const Text('預設幣別'),
              subtitle: Text(settings.defaultCurrency),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _showPreferences(context, ref),
            ),
            ListTile(
              title: const Text('預設付款方式'),
              subtitle: Text(settings.defaultPaymentMethod.label),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _showPreferences(context, ref),
            ),
            ListTile(
              title: const Text('預設消費分類'),
              subtitle: Text(settings.defaultCategory),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _showPreferences(context, ref),
            ),
            SwitchListTile(
              title: const Text('遮罩財務金額'),
              subtitle: const Text('在首頁與清單隱藏敏感金額'),
              value: settings.maskBalances,
              onChanged: (value) =>
                  store.updateSettings(settings.copyWith(maskBalances: value)),
            ),
          ],
        ),
        const SizedBox(height: 16),
        const _Section(
          title: '記帳分類',
          icon: Icons.category_outlined,
          children: [_CategoryManager()],
        ),
        const SizedBox(height: 16),
        _Section(
          title: '匯率',
          icon: Icons.currency_exchange,
          trailing: TextButton.icon(
            onPressed: () => _showFxRate(context, ref),
            icon: const Icon(Icons.add),
            label: const Text('新增／更新'),
          ),
          children: [
            if (latestRates.isEmpty)
              const ListTile(
                title: Text('尚未設定外幣匯率'),
                subtitle: Text('沒有匯率的外幣不會併入首頁總額'),
              )
            else
              for (final rate in latestRates)
                ListTile(
                  leading: CircleAvatar(child: Text(rate.from)),
                  title: Text('1 ${rate.from} = ${rate.rate} ${rate.to}'),
                  subtitle: Text('更新 ${dateText(rate.updatedAt)}'),
                  trailing: IconButton(
                    tooltip: '刪除匯率',
                    onPressed: () => store.updateSettings(
                      settings.copyWith(
                        fxRates: settings.fxRates
                            .where(
                              (item) =>
                                  item.from != rate.from || item.to != rate.to,
                            )
                            .toList(),
                      ),
                    ),
                    icon: const Icon(Icons.delete_outline),
                  ),
                ),
          ],
        ),
        const SizedBox(height: 16),
        _Section(
          title: '收款資訊',
          icon: Icons.qr_code_2,
          trailing: TextButton(
            onPressed: () => _showCollectionSettings(context, ref),
            child: const Text('編輯'),
          ),
          children: [
            ListTile(
              title: const Text('預設銀行轉入帳戶'),
              subtitle: Text(
                accountName(store, store.defaultBankTransferAccountId),
              ),
            ),
            ListTile(
              title: const Text('銀行帳號資訊'),
              subtitle: Text(
                settings.bankAccountInfo.isEmpty
                    ? '尚未設定'
                    : settings.bankAccountInfo,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _Section(
          title: '提醒',
          icon: Icons.notifications_none,
          children: [
            SwitchListTile(
              title: const Text('帳單扣款提醒'),
              subtitle: const Text('信用卡扣款日與固定支出餘額不足提醒'),
              value: settings.remindersEnabled,
              onChanged: (value) => store.updateSettings(
                settings.copyWith(remindersEnabled: value),
              ),
            ),
            SwitchListTile(
              title: const Text('LINE 提醒'),
              subtitle: const Text('預留設定；本機原型不會發送 LINE 訊息'),
              value: settings.lineRemindersEnabled,
              onChanged: (value) => store.updateSettings(
                settings.copyWith(lineRemindersEnabled: value),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _Section(
          title: 'CSV 匯出',
          icon: Icons.download_outlined,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  OutlinedButton.icon(
                    onPressed: store.exportAccounts,
                    icon: const Icon(Icons.account_balance_wallet_outlined),
                    label: const Text('帳戶'),
                  ),
                  OutlinedButton.icon(
                    onPressed: store.exportExpenses,
                    icon: const Icon(Icons.receipt_long_outlined),
                    label: const Text('支出'),
                  ),
                  OutlinedButton.icon(
                    onPressed: store.exportIncomes,
                    icon: const Icon(Icons.savings_outlined),
                    label: const Text('收入'),
                  ),
                  OutlinedButton.icon(
                    onPressed: store.exportInvestments,
                    icon: const Icon(Icons.trending_up),
                    label: const Text('投資'),
                  ),
                  OutlinedButton.icon(
                    onPressed: store.exportBills,
                    icon: const Icon(Icons.credit_card),
                    label: const Text('信用卡帳單'),
                  ),
                  OutlinedButton.icon(
                    onPressed: store.exportOrders,
                    icon: const Icon(Icons.groups_outlined),
                    label: const Text('代訂收款'),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _Section(
          title: '原型資料',
          icon: Icons.science_outlined,
          children: [
            ListTile(
              title: const Text('產生完整測試資料'),
              subtitle: const Text('重建帳戶、消費、投資、帳單與代訂示範情境'),
              trailing: FilledButton.tonal(
                onPressed: () async {
                  await store.generateDemoData();
                  if (context.mounted) showSaved(context, '測試資料已產生');
                },
                child: const Text('產生'),
              ),
            ),
            ListTile(
              title: const Text('清除測試資料'),
              subtitle: const Text('只移除 demo 標記資料，保留自行建立的內容'),
              trailing: OutlinedButton(
                onPressed: () async {
                  final confirmed =
                      await showDialog<bool>(
                        context: context,
                        builder: (dialogContext) => AlertDialog(
                          title: const Text('清除測試資料？'),
                          content: const Text('自行建立的資料與設定不會被刪除。'),
                          actions: [
                            TextButton(
                              onPressed: () =>
                                  Navigator.pop(dialogContext, false),
                              child: const Text('取消'),
                            ),
                            FilledButton(
                              onPressed: () =>
                                  Navigator.pop(dialogContext, true),
                              child: const Text('清除'),
                            ),
                          ],
                        ),
                      ) ??
                      false;
                  if (confirmed) {
                    await store.clearDemoData();
                    if (context.mounted) showSaved(context, '測試資料已清除');
                  }
                },
                child: const Text('清除'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Card(
          child: ListTile(
            leading: const CircleAvatar(
              backgroundColor: Color(0xFFDFF4EA),
              child: Icon(Icons.chat_bubble_outline, color: Color(0xFF0E7C66)),
            ),
            title: const Text('Demo LINE 使用者'),
            subtitle: const Text('所有資料只保存在這個瀏覽器'),
            trailing: TextButton.icon(
              onPressed: store.signOut,
              icon: const Icon(Icons.logout),
              label: const Text('登出'),
            ),
          ),
        ),
        const SizedBox(height: 24),
        const Center(
          child: Text(
            '快記帳互動原型 v0.1.0｜尚未連線 Supabase',
            style: TextStyle(color: Colors.black45, fontSize: 12),
          ),
        ),
      ],
    );
  }

  Future<void> _showPreferences(BuildContext context, WidgetRef ref) async {
    final store = ref.read(appStoreProvider);
    final current = store.data.settings;
    var currency = current.defaultCurrency;
    var payment = current.defaultPaymentMethod;
    var categoryId = current.defaultExpenseCategoryId;
    final expenseCategories = store.categoriesFor(
      BookkeepingCategoryKind.expense,
      activeOnly: true,
    );
    if (!expenseCategories.any((item) => item.id == categoryId)) {
      categoryId = expenseCategories.first.id;
    }
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('一般偏好'),
          content: SizedBox(
            width: 440,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: currency,
                  decoration: const InputDecoration(labelText: '預設幣別'),
                  items: const ['TWD', 'USD', 'JPY', 'EUR']
                      .map(
                        (value) =>
                            DropdownMenuItem(value: value, child: Text(value)),
                      )
                      .toList(),
                  onChanged: (value) => setState(() => currency = value!),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<PaymentMethod>(
                  initialValue: payment,
                  decoration: const InputDecoration(labelText: '預設付款方式'),
                  items: PaymentMethod.values
                      .map(
                        (value) => DropdownMenuItem(
                          value: value,
                          child: Text(value.label),
                        ),
                      )
                      .toList(),
                  onChanged: (value) => setState(() => payment = value!),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: categoryId,
                  decoration: const InputDecoration(labelText: '預設消費分類'),
                  items: expenseCategories
                      .map(
                        (value) => DropdownMenuItem(
                          value: value.id,
                          child: Text(value.name),
                        ),
                      )
                      .toList(),
                  onChanged: (value) => setState(() => categoryId = value!),
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
              onPressed: () async {
                await store.updateSettings(
                  current.copyWith(
                    defaultCurrency: currency,
                    defaultPaymentMethod: payment,
                    defaultCategory: store.categoryName(categoryId),
                    defaultExpenseCategoryId: categoryId,
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

  Future<void> _showFxRate(BuildContext context, WidgetRef ref) async {
    final store = ref.read(appStoreProvider);
    final current = store.data.settings;
    var from = const [
      'TWD',
      'USD',
      'JPY',
      'EUR',
    ].firstWhere((value) => value != current.defaultCurrency);
    final rate = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('新增／更新匯率'),
          content: SizedBox(
            width: 420,
            child: Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: from,
                    decoration: const InputDecoration(labelText: '外幣'),
                    items: const ['TWD', 'USD', 'JPY', 'EUR']
                        .where((value) => value != current.defaultCurrency)
                        .map(
                          (value) => DropdownMenuItem(
                            value: value,
                            child: Text(value),
                          ),
                        )
                        .toList(),
                    onChanged: (value) => setState(() => from = value!),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 10),
                  child: Text('→'),
                ),
                Expanded(
                  child: TextField(
                    controller: rate,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText: '${current.defaultCurrency} 匯率',
                    ),
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
              onPressed: () async {
                final value = double.tryParse(rate.text) ?? 0;
                if (value <= 0) return;
                final now = DateTime.now();
                final rates = [...current.fxRates]
                  ..removeWhere(
                    (item) =>
                        item.from == from &&
                        item.to == current.defaultCurrency &&
                        item.updatedAt.year == now.year &&
                        item.updatedAt.month == now.month &&
                        item.updatedAt.day == now.day,
                  )
                  ..add(
                    FxRate(
                      from: from,
                      to: current.defaultCurrency,
                      rateMicros: (value * 1000000).round(),
                      updatedAt: now,
                    ),
                  );
                await store.updateSettings(current.copyWith(fxRates: rates));
                if (dialogContext.mounted) Navigator.pop(dialogContext);
              },
              child: const Text('儲存'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showCollectionSettings(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final store = ref.read(appStoreProvider);
    final current = store.data.settings;
    var accountId = store.defaultBankTransferAccountId;
    final bankQr = TextEditingController(text: current.bankQrData);
    final bankInfo = TextEditingController(text: current.bankAccountInfo);
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('收款資訊'),
          content: SizedBox(
            width: 500,
            child: SingleChildScrollView(
              child: Column(
                children: [
                  DropdownButtonFormField<String>(
                    initialValue:
                        store.bankTransferAccounts.any(
                          (item) => item.id == accountId,
                        )
                        ? accountId
                        : null,
                    decoration: const InputDecoration(labelText: '預設銀行轉入帳戶'),
                    items: store.bankTransferAccounts
                        .map(
                          (account) => DropdownMenuItem(
                            value: account.id,
                            child: Text(account.name),
                          ),
                        )
                        .toList(),
                    onChanged: (value) => setState(() => accountId = value),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: bankQr,
                    decoration: const InputDecoration(labelText: '銀行轉帳 QR 內容'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: bankInfo,
                    maxLines: 2,
                    decoration: const InputDecoration(labelText: '銀行帳號與備註資訊'),
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
                await store.updateSettings(
                  current.copyWith(
                    defaultCollectionAccountId: accountId,
                    bankQrData: bankQr.text.trim(),
                    bankAccountInfo: bankInfo.text.trim(),
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

class _CategoryManager extends ConsumerStatefulWidget {
  const _CategoryManager();

  @override
  ConsumerState<_CategoryManager> createState() => _CategoryManagerState();
}

class _CategoryManagerState extends ConsumerState<_CategoryManager> {
  var _kind = BookkeepingCategoryKind.expense;

  @override
  Widget build(BuildContext context) {
    final store = ref.watch(appStoreProvider);
    final categories = store.categoriesFor(_kind);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 12,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SegmentedButton<BookkeepingCategoryKind>(
                segments: const [
                  ButtonSegment(
                    value: BookkeepingCategoryKind.expense,
                    label: Text('支出'),
                    icon: Icon(Icons.north_east_rounded),
                  ),
                  ButtonSegment(
                    value: BookkeepingCategoryKind.income,
                    label: Text('收入'),
                    icon: Icon(Icons.south_west_rounded),
                  ),
                ],
                selected: {_kind},
                onSelectionChanged: (value) => setState(() {
                  _kind = value.single;
                }),
              ),
              FilledButton.icon(
                onPressed: store.canWrite
                    ? () => _showEditor(context, store)
                    : null,
                icon: const Icon(Icons.add),
                label: const Text('新增分類'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            '拖曳調整選單順序；已使用的分類可停用或合併，但不會直接刪除。',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: AppColors.textMuted),
          ),
          const SizedBox(height: 8),
          ReorderableListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            itemCount: categories.length,
            onReorderItem: store.canWrite
                ? (oldIndex, newIndex) {
                    final ids = categories.map((item) => item.id).toList();
                    final moved = ids.removeAt(oldIndex);
                    ids.insert(newIndex, moved);
                    store.reorderCategories(_kind, ids);
                  }
                : (_, _) {},
            itemBuilder: (context, index) {
              final category = categories[index];
              final visual = bookkeepingCategoryVisual(category);
              final mergedInto = store.categoryById(
                category.mergedIntoCategoryId,
              );
              return ListTile(
                key: ValueKey(category.id),
                contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                leading: CircleAvatar(
                  backgroundColor: visual.pale,
                  foregroundColor: visual.color,
                  child: Icon(visual.icon),
                ),
                title: Text(
                  category.name,
                  style: TextStyle(
                    color: category.isActive ? null : AppColors.textMuted,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                subtitle: Text(
                  category.isActive
                      ? category.isBuiltIn
                            ? '內建分類'
                            : '自訂分類'
                      : mergedInto == null
                      ? '已停用'
                      : '已合併至 ${mergedInto.name}',
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ReorderableDragStartListener(
                      index: index,
                      child: const Padding(
                        padding: EdgeInsets.all(12),
                        child: Icon(Icons.drag_handle),
                      ),
                    ),
                    PopupMenuButton<String>(
                      tooltip: '分類操作',
                      enabled: store.canWrite,
                      onSelected: (action) =>
                          _handleAction(context, store, category, action),
                      itemBuilder: (context) => [
                        const PopupMenuItem(
                          value: 'edit',
                          child: ListTile(
                            leading: Icon(Icons.edit_outlined),
                            title: Text('編輯'),
                          ),
                        ),
                        PopupMenuItem(
                          value: 'toggle',
                          child: ListTile(
                            leading: Icon(
                              category.isActive
                                  ? Icons.pause_circle_outline
                                  : Icons.play_circle_outline,
                            ),
                            title: Text(category.isActive ? '停用' : '重新啟用'),
                          ),
                        ),
                        if (category.isActive)
                          const PopupMenuItem(
                            value: 'merge',
                            child: ListTile(
                              leading: Icon(Icons.merge_type),
                              title: Text('合併到其他分類'),
                            ),
                          ),
                        if (!category.isBuiltIn &&
                            !store.isCategoryUsed(category))
                          const PopupMenuItem(
                            value: 'delete',
                            child: ListTile(
                              leading: Icon(Icons.delete_outline),
                              title: Text('永久刪除'),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Future<void> _handleAction(
    BuildContext context,
    AppStore store,
    BookkeepingCategory category,
    String action,
  ) async {
    switch (action) {
      case 'edit':
        await _showEditor(context, store, existing: category);
      case 'toggle':
        await store.setCategoryActive(category.id, !category.isActive);
      case 'merge':
        await _showMerge(context, store, category);
      case 'delete':
        await store.deleteCategory(category.id);
    }
  }

  Future<void> _showEditor(
    BuildContext context,
    AppStore store, {
    BookkeepingCategory? existing,
  }) async {
    final controller = TextEditingController(text: existing?.name ?? '');
    var iconKey = existing?.iconKey ?? 'other';
    var colorKey = existing?.colorKey ?? 'blue';
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(existing == null ? '新增分類' : '編輯分類'),
          content: SizedBox(
            width: 440,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: controller,
                  autofocus: true,
                  maxLength: 20,
                  decoration: const InputDecoration(labelText: '分類名稱'),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: iconKey,
                  decoration: const InputDecoration(labelText: '圖示'),
                  items: categoryIconOptions.entries
                      .map(
                        (entry) => DropdownMenuItem(
                          value: entry.key,
                          child: Row(
                            children: [
                              Icon(entry.value),
                              const SizedBox(width: 10),
                              Text(entry.key),
                            ],
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (value) => setDialogState(() => iconKey = value!),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: colorKey,
                  decoration: const InputDecoration(labelText: '色彩'),
                  items: categoryColorOptions.entries
                      .map(
                        (entry) => DropdownMenuItem(
                          value: entry.key,
                          child: Row(
                            children: [
                              CircleAvatar(
                                radius: 8,
                                backgroundColor: entry.value,
                              ),
                              const SizedBox(width: 10),
                              Text(entry.key),
                            ],
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (value) => setDialogState(() => colorKey = value!),
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
              onPressed: () async {
                if (existing == null) {
                  await store.addCategory(
                    kind: _kind,
                    name: controller.text,
                    iconKey: iconKey,
                    colorKey: colorKey,
                  );
                } else {
                  await store.updateCategory(
                    existing.copyWith(
                      name: controller.text,
                      iconKey: iconKey,
                      colorKey: colorKey,
                    ),
                  );
                }
                if (dialogContext.mounted && store.lastSyncError == null) {
                  Navigator.pop(dialogContext);
                }
              },
              child: const Text('儲存'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
  }

  Future<void> _showMerge(
    BuildContext context,
    AppStore store,
    BookkeepingCategory source,
  ) async {
    final targets = store
        .categoriesFor(source.kind, activeOnly: true)
        .where((item) => item.id != source.id)
        .toList();
    if (targets.isEmpty) {
      showSaved(context, '沒有可合併的目標分類');
      return;
    }
    var targetId = targets.first.id;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('合併「${source.name}」'),
          content: DropdownButtonFormField<String>(
            initialValue: targetId,
            decoration: const InputDecoration(labelText: '目標分類'),
            items: targets
                .map(
                  (item) =>
                      DropdownMenuItem(value: item.id, child: Text(item.name)),
                )
                .toList(),
            onChanged: (value) => setDialogState(() => targetId = value!),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () async {
                await store.mergeCategory(source.id, targetId);
                if (dialogContext.mounted) Navigator.pop(dialogContext);
              },
              child: const Text('確認合併'),
            ),
          ],
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.icon,
    required this.children,
    this.trailing,
  });
  final String title;
  final IconData icon;
  final List<Widget> children;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Card(
    child: Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 12, 8),
          child: Row(
            children: [
              Icon(icon, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 10),
              Text(
                title,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
              ),
              const Spacer(),
              if (trailing != null) trailing!,
            ],
          ),
        ),
        const Divider(height: 1),
        ...children,
      ],
    ),
  );
}
