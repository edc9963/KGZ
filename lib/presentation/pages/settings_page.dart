import 'package:flutter/material.dart';
import 'package:forui/forui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/app_store.dart';
import '../../application/providers.dart';
import '../../data/repositories.dart';
import '../../domain/models.dart';
import '../design_tokens.dart';
import '../widgets/common.dart';

String _syncSettingsText(AppStore store) {
  if (store.isOffline) return '目前離線，資料僅供查看';
  if (store.hasConflict) return '雲端資料有更新，請重新載入';
  if (store.isSaving) return '正在同步資料';
  final updated = store.cloudUpdatedAt?.toLocal();
  if (updated == null) return '已連線至雲端';
  return '最後同步 ${dateText(updated)} '
      '${updated.hour.toString().padLeft(2, '0')}:${updated.minute.toString().padLeft(2, '0')}';
}

enum _SettingsTab { preferences, categories, sync, data }

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  _SettingsTab _tab = _SettingsTab.preferences;

  @override
  Widget build(BuildContext context) {
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
        const PageHeader(title: '設定'),
        const SizedBox(height: 14),
        KgzTabBar<_SettingsTab>(
          tabs: const [
            (_SettingsTab.preferences, '偏好', null),
            (_SettingsTab.categories, '分類', null),
            (_SettingsTab.sync, '同步', null),
            (_SettingsTab.data, '資料', null),
          ],
          selected: _tab,
          onSelected: (value) => setState(() => _tab = value),
        ),
        const SizedBox(height: 22),
        if (_tab == _SettingsTab.preferences)
          _Section(
            title: '外觀',
            icon: Icons.dark_mode_outlined,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                child: _ThemeModeSelector(
                  mode: ref.watch(themeModeControllerProvider).mode,
                  onChanged: (mode) =>
                      ref.read(themeModeControllerProvider).setMode(mode),
                ),
              ),
            ],
          ),
        if (_tab == _SettingsTab.preferences) const SizedBox(height: 16),
        if (_tab == _SettingsTab.preferences)
          _Section(
            title: '一般偏好',
            icon: Icons.tune,
            children: [
              FItem(
                title: const Text('預設幣別'),
                subtitle: Text(settings.defaultCurrency),
                suffix: const Icon(Icons.chevron_right),
                onPress: () => _showPreferences(context, ref),
              ),
              FItem(
                title: const Text('預設付款方式'),
                subtitle: Text(settings.defaultPaymentMethod.label),
                suffix: const Icon(Icons.chevron_right),
                onPress: () => _showPreferences(context, ref),
              ),
              FItem(
                title: const Text('預設消費分類'),
                subtitle: Text(settings.defaultCategory),
                suffix: const Icon(Icons.chevron_right),
                onPress: () => _showPreferences(context, ref),
              ),
              FItem(
                title: const Text('遮罩財務金額'),
                suffix: FSwitch(
                  value: settings.maskBalances,
                  onChange: (value) => store.updateSettings(
                    settings.copyWith(maskBalances: value),
                  ),
                ),
                onPress: () => ((value) => store.updateSettings(
                  settings.copyWith(maskBalances: value),
                ))(!(settings.maskBalances)),
              ),
            ],
          ),
        if (_tab == _SettingsTab.preferences) const SizedBox(height: 16),
        if (_tab == _SettingsTab.categories)
          const _Section(
            title: '記帳分類',
            icon: Icons.category_outlined,
            children: [_CategoryManager()],
          ),
        if (_tab == _SettingsTab.preferences || _tab == _SettingsTab.categories)
          const SizedBox(height: 16),
        if (_tab == _SettingsTab.preferences)
          _Section(
            title: '匯率',
            icon: Icons.currency_exchange,
            trailing: FButton(
              variant: FButtonVariant.ghost,
              mainAxisSize: MainAxisSize.min,
              onPress: () => _showFxRate(context, ref),
              prefix: const Icon(Icons.add),
              child: const Text('新增／更新'),
            ),
            children: [
              if (latestRates.isEmpty)
                FItem(
                  title: Text('尚未設定外幣匯率'),
                  subtitle: Text('沒有匯率的外幣不會併入首頁總額'),
                )
              else
                for (final rate in latestRates)
                  FItem(
                    prefix: FAvatar.raw(child: Text(rate.from)),
                    title: Text('1 ${rate.from} = ${rate.rate} ${rate.to}'),
                    subtitle: Text('更新 ${dateText(rate.updatedAt)}'),
                    suffix: FTooltip(
                      tipBuilder: (context, _) => Text('刪除匯率'),
                      child: FButton.icon(
                        variant: FButtonVariant.ghost,
                        onPress: () => store.updateSettings(
                          settings.copyWith(
                            fxRates: settings.fxRates
                                .where(
                                  (item) =>
                                      item.from != rate.from ||
                                      item.to != rate.to,
                                )
                                .toList(),
                          ),
                        ),
                        semanticsLabel: '刪除匯率',
                        child: const Icon(Icons.delete_outline),
                      ),
                    ),
                  ),
            ],
          ),
        if (_tab == _SettingsTab.preferences) const SizedBox(height: 16),
        if (_tab == _SettingsTab.sync)
          _Section(
            title: '提醒',
            icon: Icons.notifications_none,
            children: [
              FItem(
                title: const Text('帳單扣款提醒'),
                subtitle: const Text('信用卡扣款日與固定支出餘額不足提醒'),
                suffix: FSwitch(
                  value: settings.remindersEnabled,
                  onChange: (value) => store.updateSettings(
                    settings.copyWith(remindersEnabled: value),
                  ),
                ),
                onPress: () => ((value) => store.updateSettings(
                  settings.copyWith(remindersEnabled: value),
                ))(!(settings.remindersEnabled)),
              ),
            ],
          ),
        if (_tab == _SettingsTab.sync) const SizedBox(height: 16),
        if (_tab == _SettingsTab.sync) _CaptureSetup(store.captureSetup),
        if (_tab == _SettingsTab.sync) const SizedBox(height: 16),
        if (_tab == _SettingsTab.data)
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
                    FButton(
                      variant: FButtonVariant.outline,
                      mainAxisSize: MainAxisSize.min,
                      onPress: store.exportAccounts,
                      prefix: const Icon(Icons.account_balance_wallet_outlined),
                      child: const Text('帳戶'),
                    ),
                    FButton(
                      variant: FButtonVariant.outline,
                      mainAxisSize: MainAxisSize.min,
                      onPress: store.exportExpenses,
                      prefix: const Icon(Icons.receipt_long_outlined),
                      child: const Text('支出'),
                    ),
                    FButton(
                      variant: FButtonVariant.outline,
                      mainAxisSize: MainAxisSize.min,
                      onPress: store.exportIncomes,
                      prefix: const Icon(Icons.savings_outlined),
                      child: const Text('收入'),
                    ),
                    FButton(
                      variant: FButtonVariant.outline,
                      mainAxisSize: MainAxisSize.min,
                      onPress: store.exportInvestments,
                      prefix: const Icon(Icons.trending_up),
                      child: const Text('投資'),
                    ),
                    FButton(
                      variant: FButtonVariant.outline,
                      mainAxisSize: MainAxisSize.min,
                      onPress: store.exportBills,
                      prefix: const Icon(Icons.credit_card),
                      child: const Text('信用卡帳單'),
                    ),
                    FButton(
                      variant: FButtonVariant.outline,
                      mainAxisSize: MainAxisSize.min,
                      onPress: store.exportOrders,
                      prefix: const Icon(Icons.groups_outlined),
                      child: const Text('代訂收款'),
                    ),
                    FButton(
                      variant: FButtonVariant.outline,
                      mainAxisSize: MainAxisSize.min,
                      onPress: store.exportReconciliations,
                      prefix: const Icon(Icons.fact_check_outlined),
                      child: const Text('對帳紀錄'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        if (_tab == _SettingsTab.data) const SizedBox(height: 16),
        if (_tab == _SettingsTab.data)
          _Section(
            title: '原型資料',
            icon: Icons.science_outlined,
            children: [
              FItem(
                title: const Text('產生完整測試資料'),
                subtitle: const Text('重建帳戶、消費、投資、帳單與代訂示範情境'),
                suffix: FButton(
                  variant: FButtonVariant.secondary,
                  mainAxisSize: MainAxisSize.min,
                  onPress: () async {
                    await store.generateDemoData();
                    if (context.mounted) showSaved(context, '測試資料已產生');
                  },
                  child: const Text('產生'),
                ),
              ),
              FItem(
                title: const Text('清除測試資料'),
                subtitle: const Text('只移除 demo 標記資料，保留自行建立的內容'),
                suffix: FButton(
                  variant: FButtonVariant.outline,
                  mainAxisSize: MainAxisSize.min,
                  onPress: () async {
                    final confirmed =
                        await showFDialog<bool>(
                          useRootNavigator: true,
                          context: context,
                          builder: (dialogContext, _, _) => KgzDialog(
                            title: const Text('清除測試資料？'),
                            content: const Text('自行建立的資料與設定不會被刪除。'),
                            actions: [
                              FButton(
                                variant: FButtonVariant.ghost,
                                mainAxisSize: MainAxisSize.min,
                                onPress: () =>
                                    Navigator.pop(dialogContext, false),
                                child: const Text('取消'),
                              ),
                              FButton(
                                mainAxisSize: MainAxisSize.min,
                                onPress: () =>
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
        if (_tab == _SettingsTab.data) const SizedBox(height: 16),
        if (_tab == _SettingsTab.data)
          KgzCard(
            child: FItem(
              prefix: FAvatar.raw(
                style: FAvatarStyleDelta.delta(
                  backgroundColor: Color.alphaBlend(
                    context.colors.income.withValues(alpha: .16),
                    context.colors.surface,
                  ),
                ),
                child: Icon(
                  Icons.chat_bubble_outline,
                  color: context.colors.income,
                ),
              ),
              title: Text(store.userDisplayName ?? 'LINE 帳號已登入'),
              subtitle: Text(_syncSettingsText(store)),
              suffix: FButton(
                variant: FButtonVariant.ghost,
                mainAxisSize: MainAxisSize.min,
                onPress: store.signOut,
                prefix: const Icon(Icons.logout),
                child: const Text('登出'),
              ),
            ),
          ),
        if (_tab == _SettingsTab.data) const SizedBox(height: 24),
        if (_tab == _SettingsTab.data)
          Center(
            child: Text(
              '快記帳｜個人財務管理',
              style: TextStyle(color: context.colors.textMuted, fontSize: 12),
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
    await showFDialog<void>(
      useRootNavigator: true,
      context: context,
      builder: (dialogContext, _, _) => StatefulBuilder(
        builder: (context, setState) => KgzDialog(
          title: const Text('一般偏好'),
          content: SizedBox(
            width: 440,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                KgzSelect<String>(
                  value: currency,
                  label: Text('預設幣別'),
                  items: const [
                    'TWD',
                    'USD',
                    'JPY',
                    'EUR',
                  ].map((value) => KgzSelectItem(value, value)).toList(),
                  onChanged: (value) => setState(() => currency = value!),
                ),
                const SizedBox(height: 12),
                KgzSelect<PaymentMethod>(
                  value: payment,
                  label: Text('預設付款方式'),
                  items: PaymentMethod.selectableWith(
                    current.defaultPaymentMethod,
                  ).map((value) => KgzSelectItem(value, value.label)).toList(),
                  onChanged: (value) => setState(() => payment = value!),
                ),
                const SizedBox(height: 12),
                KgzSelect<String>(
                  value: categoryId,
                  label: Text('預設消費分類'),
                  items: expenseCategories
                      .map((value) => KgzSelectItem(value.id, value.name))
                      .toList(),
                  onChanged: (value) => setState(() => categoryId = value!),
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
    await showFDialog<void>(
      useRootNavigator: true,
      context: context,
      builder: (dialogContext, _, _) => StatefulBuilder(
        builder: (context, setState) => KgzDialog(
          title: const Text('新增／更新匯率'),
          content: SizedBox(
            width: 420,
            child: Row(
              children: [
                Expanded(
                  child: KgzSelect<String>(
                    value: from,
                    label: Text('外幣'),
                    items: const ['TWD', 'USD', 'JPY', 'EUR']
                        .where((value) => value != current.defaultCurrency)
                        .map((value) => KgzSelectItem(value, value))
                        .toList(),
                    onChanged: (value) => setState(() => from = value!),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 10),
                  child: Text('→'),
                ),
                Expanded(
                  child: FTextField(
                    control: FTextFieldControl.managed(controller: rate),
                    label: Text('${current.defaultCurrency} 匯率'),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                  ),
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
              KgzTabBar<BookkeepingCategoryKind>(
                tabs: const [
                  (
                    BookkeepingCategoryKind.expense,
                    '支出',
                    Icons.north_east_rounded,
                  ),
                  (
                    BookkeepingCategoryKind.income,
                    '收入',
                    Icons.south_west_rounded,
                  ),
                ],
                selected: _kind,
                onSelected: (value) => setState(() {
                  _kind = value;
                }),
              ),
              FButton(
                mainAxisSize: MainAxisSize.min,
                onPress: store.canWrite
                    ? () => _showEditor(context, store)
                    : null,
                prefix: const Icon(Icons.add),
                child: const Text('新增分類'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            '拖曳調整選單順序；已使用的分類可停用或合併，但不會直接刪除。',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: context.colors.textMuted),
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
              final visual = bookkeepingCategoryVisual(
                category,
                context.colors,
              );
              final mergedInto = store.categoryById(
                category.mergedIntoCategoryId,
              );
              return FItem(
                key: ValueKey(category.id),
                prefix: FAvatar.raw(
                  style: FAvatarStyleDelta.delta(
                    backgroundColor: visual.pale,
                    foregroundColor: visual.color,
                  ),
                  child: IconTheme.merge(
                    data: IconThemeData(color: visual.color),
                    child: Icon(visual.icon),
                  ),
                ),
                title: Text(
                  category.name,
                  style: TextStyle(
                    color: category.isActive ? null : context.colors.textMuted,
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
                suffix: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ReorderableDragStartListener(
                      index: index,
                      child: const Padding(
                        padding: EdgeInsets.all(12),
                        child: Icon(Icons.drag_handle),
                      ),
                    ),
                    KgzPopoverMenu<String>(
                      semanticsLabel: '分類操作',
                      enabled: store.canWrite,
                      entries: [
                        KgzMenuEntry('edit', '編輯', icon: Icons.edit_outlined),
                        KgzMenuEntry(
                          'toggle',
                          category.isActive ? '停用' : '重新啟用',
                          icon: category.isActive
                              ? Icons.pause_circle_outline
                              : Icons.play_circle_outline,
                        ),
                        if (category.isActive)
                          KgzMenuEntry(
                            'merge',
                            '合併到其他分類',
                            icon: Icons.merge_type,
                          ),
                        if (!category.isBuiltIn &&
                            !store.isCategoryUsed(category))
                          KgzMenuEntry(
                            'delete',
                            '永久刪除',
                            icon: Icons.delete_outline,
                            destructive: true,
                          ),
                      ],
                      onSelected: (action) =>
                          _handleAction(context, store, category, action),
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
    await showFDialog<void>(
      useRootNavigator: true,
      context: context,
      builder: (dialogContext, _, _) => StatefulBuilder(
        builder: (context, setDialogState) => KgzDialog(
          title: Text(existing == null ? '新增分類' : '編輯分類'),
          content: SizedBox(
            width: 440,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FTextField(
                  control: FTextFieldControl.managed(controller: controller),
                  label: Text('分類名稱'),
                  autofocus: true,
                  maxLength: 20,
                ),
                const SizedBox(height: 12),
                KgzSelect<String>(
                  value: iconKey,
                  label: const Text('圖示'),
                  prefixIcon: Icon(categoryIconOptions[iconKey]),
                  items: [
                    for (final entry in categoryIconOptions.entries)
                      KgzSelectItem(
                        entry.key,
                        entry.key,
                        prefix: Icon(entry.value),
                      ),
                  ],
                  onChanged: (value) => setDialogState(() => iconKey = value!),
                ),
                const SizedBox(height: 16),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '色彩',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: context.colors.textMuted,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                CategoryColorPicker(
                  value: colorKey,
                  onChanged: (value) => setDialogState(() => colorKey = value),
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
    await showFDialog<void>(
      useRootNavigator: true,
      context: context,
      builder: (dialogContext, _, _) => StatefulBuilder(
        builder: (context, setDialogState) => KgzDialog(
          title: Text('合併「${source.name}」'),
          content: KgzSelect<String>(
            value: targetId,
            label: Text('目標分類'),
            items: targets
                .map((item) => KgzSelectItem(item.id, item.name))
                .toList(),
            onChanged: (value) => setDialogState(() => targetId = value!),
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

String _dateTimeText(DateTime value) {
  final local = value.toLocal();
  return '${dateText(local)} '
      '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
}

Future<void> _copy(BuildContext context, String text, String label) async {
  await Clipboard.setData(ClipboardData(text: text));
  if (context.mounted) showSaved(context, '已複製$label');
}

/// 自動記帳: issue the shared capture token and copy what each shortcut or
/// the Gmail Apps Script needs. iOS does not let a web page create the
/// Transaction/Message automations themselves, so those stay as short steps.
class _CaptureSetup extends StatefulWidget {
  const _CaptureSetup(this.repository);

  final CaptureSetupRepository? repository;

  @override
  State<_CaptureSetup> createState() => _CaptureSetupState();
}

class _CaptureSetupState extends State<_CaptureSetup> {
  CaptureSetupStatus? _status;
  Object? _error;
  bool _issuing = false;

  /// The plaintext token from this visit, if one was issued. The server only
  /// keeps its hash, so it is gone once the page is left.
  String? _token;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final repository = widget.repository;
    if (repository == null) return;
    try {
      final status = await repository.loadStatus();
      if (mounted) {
        setState(() {
          _status = status;
          _error = null;
        });
      }
    } on Object catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  Future<void> _issue() async {
    final repository = widget.repository!;
    if (_status?.hasToken ?? false) {
      final confirmed =
          await showFDialog<bool>(
            useRootNavigator: true,
            context: context,
            builder: (dialogContext, _, _) => KgzDialog(
              title: const Text('重新產生金鑰？'),
              content: const Text('舊金鑰會立即失效，已設定的捷徑與 Apps Script 都要換成新金鑰。'),
              actions: [
                FButton(
                  variant: FButtonVariant.ghost,
                  mainAxisSize: MainAxisSize.min,
                  onPress: () => Navigator.pop(dialogContext, false),
                  child: const Text('取消'),
                ),
                FButton(
                  mainAxisSize: MainAxisSize.min,
                  onPress: () => Navigator.pop(dialogContext, true),
                  child: const Text('重新產生'),
                ),
              ],
            ),
          ) ??
          false;
      if (!confirmed) return;
    }
    setState(() => _issuing = true);
    try {
      final token = await repository.issueToken();
      if (!mounted) return;
      setState(() => _token = token);
      await _load();
    } on Object catch (error) {
      if (mounted) showSaved(context, '產生金鑰失敗：$error');
    } finally {
      if (mounted) setState(() => _issuing = false);
    }
  }

  Future<void> _copyAppsScript() async {
    final endpoints = widget.repository!.endpoints;
    final script = await rootBundle.loadString(
      'tool/line-pay-gmail-forwarder.gs',
    );
    if (!mounted) return;
    await _copy(
      context,
      '$script\n'
          '// 由快記帳網頁產生：選取 kgzSetup 執行一次即完成設定（會要求 Gmail 授權）。\n'
          'function kgzSetup() {\n'
          '  PropertiesService.getScriptProperties().setProperties({\n'
          "    KGZ_URL: '${endpoints.cardEmail}',\n"
          "    KGZ_TOKEN: '$_token'\n"
          '  });\n'
          '  runOnce();\n'
          '  install();\n'
          '}\n',
      ' Apps Script',
    );
  }

  @override
  Widget build(BuildContext context) {
    final repository = widget.repository;
    final status = _status;
    final token = _token;
    final muted = TextStyle(color: context.colors.textMuted);
    return _Section(
      title: '自動記帳',
      icon: Icons.bolt_outlined,
      children: [
        if (repository == null)
          FItem(
            title: Text('需要雲端帳號'),
            subtitle: Text('登入 LINE 帳號後才能使用 Apple Pay／LINE Pay 自動記帳'),
          )
        else if (_error != null)
          FItem(
            title: const Text('無法讀取自動記帳狀態'),
            subtitle: Text('$_error'),
            suffix: FButton(
              variant: FButtonVariant.ghost,
              mainAxisSize: MainAxisSize.min,
              onPress: _load,
              child: const Text('重試'),
            ),
          )
        else if (status == null)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: FCircularProgress()),
          )
        else ...[
          FItem(
            title: const Text('捷徑金鑰'),
            subtitle: Text(
              !status.hasToken
                  ? '尚未產生；捷徑與 Apps Script 共用同一把金鑰'
                  : '產生於 ${_dateTimeText(status.tokenCreatedAt!)}・'
                        '${status.tokenLastUsedAt == null ? '尚未收到資料' : '最近收到 ${_dateTimeText(status.tokenLastUsedAt!)}'}',
            ),
            suffix: FButton(
              variant: FButtonVariant.secondary,
              mainAxisSize: MainAxisSize.min,
              onPress: _issuing ? null : _issue,
              child: Text(status.hasToken ? '重新產生' : '產生金鑰'),
            ),
          ),
          if (token != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SelectableText(
                    token,
                    style: const TextStyle(fontFamily: 'monospace'),
                  ),
                  const SizedBox(height: 4),
                  Text('金鑰只會在這次顯示，離開頁面後請重新產生。', style: muted),
                  const SizedBox(height: 8),
                  FButton(
                    variant: FButtonVariant.outline,
                    mainAxisSize: MainAxisSize.min,
                    onPress: () => _copy(context, token, '金鑰'),
                    prefix: const Icon(Icons.copy),
                    child: const Text('複製金鑰'),
                  ),
                ],
              ),
            ),
          if (!status.lineLinked)
            FItem(
              prefix: Icon(Icons.info_outline, color: context.colors.warn),
              title: const Text('尚未連結 LINE 官方帳號'),
              subtitle: const Text('收到的消費要在 LINE 點分類入帳，請先加入官方帳號完成連結'),
            ),
          if (status.pendingCount > 0)
            FItem(
              prefix: const Icon(Icons.inbox_outlined),
              title: Text('${status.pendingCount} 筆待確認'),
              subtitle: const Text('在 LINE 官方帳號輸入「待確認」處理'),
            ),
          FDivider(),
          _CaptureGuide(
            title: 'Apple Pay',
            subtitle: '每次感應後自動送出',
            url: repository.endpoints.applePay,
            steps: const [
              '「捷徑」→「自動化」→「＋」→「交易」，選要記錄的卡片，勾「立即執行」。',
              '動作「取得 URL 內容」：方法 POST，標頭 x-capture-token ＝ 金鑰。',
              '要求本文 JSON：amount ＝ 金額、merchant ＝ 商家、card ＝ 卡片或票卡。',
            ],
            token: token,
          ),
          _CaptureGuide(
            title: 'LINE Pay／電信帳單截圖',
            subtitle: '截圖後執行捷徑，文字在手機上辨識',
            url: repository.endpoints.screenshot,
            steps: const [
              '新增捷徑：「取得最新的螢幕快照」→「從影像擷取文字」。',
              '「取得 URL 內容」：POST，標頭 x-capture-token ＝ 金鑰，JSON 本文 text ＝ 擷取的文字。',
              '「取得字典值」message →「顯示通知」。可在「輔助使用 → 觸控 → 背面輕點」指定這個捷徑。',
            ],
            token: token,
          ),
          _CaptureGuide(
            title: '電信代收簡訊',
            subtitle: '收到遠傳「交易成功通知」就記錄',
            url: repository.endpoints.screenshot,
            steps: const [
              '「捷徑」→「自動化」→「＋」→「訊息」：「訊息包含」填「交易成功通知」，勾「立即執行」。',
              '動作「取得 URL 內容」：POST，標頭 x-capture-token ＝ 金鑰，JSON 本文 text ＝「捷徑輸入」。',
            ],
            token: token,
          ),
          _CaptureGuide(
            title: '銀行通知信（Gmail）',
            subtitle: 'LINE Pay 刷卡、彰銀 TWPAY／金融卡扣帳',
            url: repository.endpoints.cardEmail,
            steps: const [
              '到 script.google.com 新增專案，刪掉預設內容後貼上複製的腳本。',
              '上方選 kgzSetup 按「執行」並允許 Gmail 授權，之後每 10 分鐘自動轉送。',
            ],
            token: token,
            extra: token == null
                ? Text('先產生金鑰，就能複製已填好網址與金鑰的腳本。', style: muted)
                : FilledButton.tonalIcon(
                    onPressed: _copyAppsScript,
                    icon: const Icon(Icons.code),
                    label: const Text('複製 Apps Script'),
                  ),
          ),
        ],
      ],
    );
  }
}

class _CaptureGuide extends StatelessWidget {
  const _CaptureGuide({
    required this.title,
    required this.subtitle,
    required this.url,
    required this.steps,
    required this.token,
    this.extra,
  });

  final String title;
  final String subtitle;
  final String url;
  final List<String> steps;
  final String? token;
  final Widget? extra;

  @override
  Widget build(BuildContext context) => FAccordion(
    children: [
      FAccordionItem(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title),
            DefaultTextStyle.merge(
              style: TextStyle(fontSize: 12.5, color: context.colors.textMuted),
              child: Text(subtitle),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final (index, step) in steps.indexed)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text('${index + 1}. $step'),
                ),
              const SizedBox(height: 4),
              SelectableText(
                url,
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                  color: context.colors.textMuted,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  FButton(
                    variant: FButtonVariant.outline,
                    mainAxisSize: MainAxisSize.min,
                    onPress: () => _copy(context, url, '網址'),
                    prefix: const Icon(Icons.link),
                    child: const Text('複製網址'),
                  ),
                  if (token != null)
                    FButton(
                      variant: FButtonVariant.outline,
                      mainAxisSize: MainAxisSize.min,
                      onPress: () => _copy(context, token!, '金鑰'),
                      prefix: const Icon(Icons.key_outlined),
                      child: const Text('複製金鑰'),
                    ),
                  ?extra,
                ],
              ),
            ],
          ),
        ),
      ),
    ],
  );
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
  Widget build(BuildContext context) => KgzCard(
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
        FDivider(),
        ...children,
      ],
    ),
  );
}

class _ThemeModeSelector extends StatelessWidget {
  const _ThemeModeSelector({required this.mode, required this.onChanged});

  final ThemeMode mode;
  final ValueChanged<ThemeMode> onChanged;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      // Figma theme previews: each card is painted in its own theme's
      // colors, whatever the app is currently showing.
      Row(
        children: [
          Expanded(
            child: _ThemePreviewCard(
              palette: AppSemanticColors.light,
              caption: '淺色',
              name: 'Warm Meadow',
              selected: mode == ThemeMode.light,
              onTap: () => onChanged(ThemeMode.light),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _ThemePreviewCard(
              palette: AppSemanticColors.dark,
              caption: '深色',
              name: 'Stellar Night',
              selected: mode == ThemeMode.dark,
              onTap: () => onChanged(ThemeMode.dark),
            ),
          ),
        ],
      ),
      const SizedBox(height: 10),
      Align(
        alignment: Alignment.centerLeft,
        child: FButton(
          variant: mode == ThemeMode.system
              ? FButtonVariant.primary
              : FButtonVariant.outline,
          size: FButtonSizeVariant.sm,
          mainAxisSize: MainAxisSize.min,
          selected: mode == ThemeMode.system,
          prefix: const Icon(Icons.brightness_auto_outlined, size: 18),
          onPress: () => onChanged(ThemeMode.system),
          child: const Text('跟隨系統'),
        ),
      ),
    ],
  );
}

class _ThemePreviewCard extends StatelessWidget {
  const _ThemePreviewCard({
    required this.palette,
    required this.caption,
    required this.name,
    required this.selected,
    required this.onTap,
  });

  final AppSemanticColors palette;
  final String caption;
  final String name;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    label: '$caption主題 $name',
    excludeSemantics: true,
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: palette.background,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: selected ? context.colors.accent : context.colors.border,
          width: selected ? 2 : 1,
        ),
      ),
      child: FTappable(
        onPress: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                caption,
                style: TextStyle(color: palette.textMuted, fontSize: 12),
              ),
              Text(
                name,
                style: TextStyle(
                  color: palette.text,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                r'NT$ 28,460',
                style: TextStyle(
                  color: palette.asset,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 10),
              Container(
                height: 10,
                decoration: BoxDecoration(
                  color: palette.primary,
                  borderRadius: BorderRadius.circular(5),
                ),
              ),
              const SizedBox(height: 6),
              FractionallySizedBox(
                widthFactor: .6,
                child: Container(
                  height: 10,
                  decoration: BoxDecoration(
                    color: palette.selection,
                    borderRadius: BorderRadius.circular(5),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
