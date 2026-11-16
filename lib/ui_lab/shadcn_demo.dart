import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../presentation/design_tokens.dart';
import 'demo_data.dart';

/// The "支出分類" screen built with shadcn_ui (nank1ro/flutter-shadcn-ui).
class ShadcnDemoApp extends StatelessWidget {
  const ShadcnDemoApp({
    required this.dark,
    required this.onToggleTheme,
    required this.onSwitchLibrary,
    super.key,
  });

  final bool dark;
  final VoidCallback onToggleTheme;
  final VoidCallback onSwitchLibrary;

  @override
  Widget build(BuildContext context) => ShadApp(
    debugShowCheckedModeBanner: false,
    title: 'UI Lab — shadcn_ui',
    locale: const Locale('zh', 'TW'),
    supportedLocales: const [Locale('zh', 'TW'), Locale('en')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    theme: ShadThemeData(
      brightness: Brightness.light,
      colorScheme: const ShadZincColorScheme.light(),
    ),
    darkTheme: ShadThemeData(
      brightness: Brightness.dark,
      colorScheme: const ShadZincColorScheme.dark(),
    ),
    themeMode: dark ? ThemeMode.dark : ThemeMode.light,
    home: _ShadcnCategoriesPage(
      dark: dark,
      onToggleTheme: onToggleTheme,
      onSwitchLibrary: onSwitchLibrary,
    ),
  );
}

class _ShadcnCategoriesPage extends StatefulWidget {
  const _ShadcnCategoriesPage({
    required this.dark,
    required this.onToggleTheme,
    required this.onSwitchLibrary,
  });

  final bool dark;
  final VoidCallback onToggleTheme;
  final VoidCallback onSwitchLibrary;

  @override
  State<_ShadcnCategoriesPage> createState() => _ShadcnCategoriesPageState();
}

class _ShadcnCategoriesPageState extends State<_ShadcnCategoriesPage> {
  final categories = buildDemoCategories();

  Future<void> _addCategory() async {
    final created = await showShadDialog<DemoCategory>(
      context: context,
      builder: (context) => const _ShadcnAddCategoryDialog(),
    );
    if (created == null || !mounted) return;
    setState(() => categories.add(created));
    ShadToaster.of(context).show(
      ShadToast(
        title: const Text('已新增分類'),
        description: Text(created.name),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final active = categories.where((c) => c.isActive).toList();
    final spent = active.fold<int>(0, (sum, c) => sum + c.spent);
    final budget = active.fold<int>(0, (sum, c) => sum + c.budget);
    final overCount = active.where((c) => c.isOverBudget).length;

    return Scaffold(
      backgroundColor: theme.colorScheme.background,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Row(
                  children: [
                    Expanded(child: Text('支出分類', style: theme.textTheme.h3)),
                    const ShadBadge.outline(child: Text('shadcn_ui 0.59')),
                    const SizedBox(width: 8),
                    ShadIconButton.ghost(
                      icon: Icon(widget.dark ? LucideIcons.sun : LucideIcons.moon),
                      onPressed: widget.onToggleTheme,
                    ),
                    ShadButton.outline(
                      size: ShadButtonSize.sm,
                      leading: const Icon(LucideIcons.arrowLeftRight, size: 16),
                      onPressed: widget.onSwitchLibrary,
                      child: const Text('換 forui'),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                ShadCard(
                  title: const Text('本月支出'),
                  description: Text('${active.length} 個啟用中的分類'),
                  trailing: overCount > 0
                      ? ShadBadge.destructive(child: Text('$overCount 類超支'))
                      : const ShadBadge.secondary(child: Text('預算內')),
                  child: Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(formatMoney(spent), style: theme.textTheme.h2),
                        const SizedBox(height: 4),
                        Text('預算 ${formatMoney(budget)}', style: theme.textTheme.muted),
                        const SizedBox(height: 12),
                        ShadProgress(value: budget == 0 ? 0 : (spent / budget).clamp(0, 1)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                ShadCard(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(
                    children: [
                      for (final (index, category) in categories.indexed) ...[
                        if (index > 0) const ShadSeparator.horizontal(margin: EdgeInsets.zero),
                        _ShadcnCategoryRow(
                          category: category,
                          onActiveChanged: (value) => setState(() => category.isActive = value),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                ShadButton(
                  width: double.infinity,
                  leading: const Icon(LucideIcons.plus, size: 16),
                  onPressed: _addCategory,
                  child: const Text('新增分類'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ShadcnCategoryRow extends StatelessWidget {
  const _ShadcnCategoryRow({required this.category, required this.onActiveChanged});

  final DemoCategory category;
  final ValueChanged<bool> onActiveChanged;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final muted = !category.isActive;
    return Opacity(
      opacity: muted ? 0.5 : 1,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: category.color.withValues(alpha: 0.15),
              child: Icon(category.icon, size: 18, color: category.color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(category.name, style: theme.textTheme.large),
                      if (category.isBuiltIn) ...[
                        const SizedBox(width: 6),
                        const ShadBadge.secondary(child: Text('內建')),
                      ],
                    ],
                  ),
                  const SizedBox(height: 6),
                  ShadProgress(
                    value: category.ratio,
                    minHeight: 6,
                    color: category.isOverBudget ? theme.colorScheme.destructive : category.color,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${formatMoney(category.spent)} / ${formatMoney(category.budget)}',
                    style: theme.textTheme.muted.copyWith(
                      color: category.isOverBudget ? theme.colorScheme.destructive : null,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            ShadSwitch(value: category.isActive, onChanged: onActiveChanged),
          ],
        ),
      ),
    );
  }
}

class _ShadcnAddCategoryDialog extends StatefulWidget {
  const _ShadcnAddCategoryDialog();

  @override
  State<_ShadcnAddCategoryDialog> createState() => _ShadcnAddCategoryDialogState();
}

class _ShadcnAddCategoryDialogState extends State<_ShadcnAddCategoryDialog> {
  final formKey = GlobalKey<ShadFormState>();

  void _submit() {
    if (!formKey.currentState!.saveAndValidate()) return;
    final values = formKey.currentState!.value;
    Navigator.of(context).pop(
      DemoCategory(
        name: (values['name'] as String).trim(),
        iconKey: 'other',
        colorKey: values['color'] as String,
        spent: 0,
        budget: int.tryParse(values['budget'] as String? ?? '') ?? 0,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ShadDialog(
    title: const Text('新增分類'),
    description: const Text('建立一個新的支出分類'),
    constraints: const BoxConstraints(maxWidth: 420),
    actions: [
      ShadButton.outline(child: const Text('取消'), onPressed: () => Navigator.of(context).pop()),
      ShadButton(onPressed: _submit, child: const Text('建立')),
    ],
    child: ShadForm(
      key: formKey,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ShadInputFormField(
              id: 'name',
              label: const Text('名稱'),
              placeholder: const Text('例如：寵物'),
              validator: (v) => v.trim().isEmpty ? '請輸入名稱' : null,
            ),
            const SizedBox(height: 12),
            ShadInputFormField(
              id: 'budget',
              label: const Text('每月預算'),
              placeholder: const Text('0'),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 12),
            ShadSelectFormField<String>(
              id: 'color',
              label: const Text('色彩'),
              initialValue: 'coral',
              minWidth: 360,
              options: [
                for (final MapEntry(key: label, value: key) in demoColorChoices.entries)
                  ShadOption(value: key, child: _ColorLabel(colorKey: key, label: label)),
              ],
              selectedOptionBuilder: (context, value) => _ColorLabel(
                colorKey: value,
                label: demoColorChoices.entries.firstWhere((e) => e.value == value).key,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _ColorLabel extends StatelessWidget {
  const _ColorLabel({required this.colorKey, required this.label});

  final String colorKey;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 12,
        height: 12,
        decoration: BoxDecoration(
          color: categoryColorOptions[colorKey],
          shape: BoxShape.circle,
        ),
      ),
      const SizedBox(width: 8),
      Text(label),
    ],
  );
}
