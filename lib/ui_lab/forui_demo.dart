import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

import '../presentation/forui_theme.dart';
import '../presentation/theme.dart';
import 'demo_data.dart';

/// The "支出分類" screen built with forui (duobaseio/forui, formerly
/// forus-labs/forui). Unlike shadcn_ui it keeps a regular [MaterialApp] and
/// only slips an [FTheme] in through `builder`.
///
/// Defaults to the KGZ palette via [buildForuiTheme]; the header's palette
/// button flips to forui's stock Neutral theme for comparison.
class ForuiDemoApp extends StatefulWidget {
  const ForuiDemoApp({
    required this.dark,
    required this.onToggleTheme,
    required this.onSwitchLibrary,
    super.key,
  });

  final bool dark;
  final VoidCallback onToggleTheme;
  final VoidCallback onSwitchLibrary;

  @override
  State<ForuiDemoApp> createState() => _ForuiDemoAppState();
}

class _ForuiDemoAppState extends State<ForuiDemoApp> {
  bool kgzPalette = true;

  @override
  Widget build(BuildContext context) {
    final brightness = widget.dark ? Brightness.dark : Brightness.light;
    final theme = kgzPalette
        ? buildForuiTheme(brightness)
        : (widget.dark ? FTheme.neutral.dark : FTheme.neutral.light).desktop;
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'UI Lab — forui',
      locale: const Locale('zh', 'TW'),
      localizationsDelegates: FLocalizations.localizationsDelegates,
      supportedLocales: FLocalizations.supportedLocales,
      // Material side keeps the real KGZ theme, so `context.colors` and any
      // leftover Material widgets still match.
      theme: kgzPalette ? buildAppTheme(brightness) : theme.toApproximateMaterialTheme(),
      builder: (context, child) => FTheme(
        data: theme,
        child: FToaster(child: child!),
      ),
      home: _ForuiCategoriesPage(
        dark: widget.dark,
        kgzPalette: kgzPalette,
        onToggleTheme: widget.onToggleTheme,
        onTogglePalette: () => setState(() => kgzPalette = !kgzPalette),
        onSwitchLibrary: widget.onSwitchLibrary,
      ),
    );
  }
}

class _ForuiCategoriesPage extends StatefulWidget {
  const _ForuiCategoriesPage({
    required this.dark,
    required this.kgzPalette,
    required this.onToggleTheme,
    required this.onTogglePalette,
    required this.onSwitchLibrary,
  });

  final bool dark;
  final bool kgzPalette;
  final VoidCallback onToggleTheme;
  final VoidCallback onTogglePalette;
  final VoidCallback onSwitchLibrary;

  @override
  State<_ForuiCategoriesPage> createState() => _ForuiCategoriesPageState();
}

class _ForuiCategoriesPageState extends State<_ForuiCategoriesPage> {
  final categories = buildDemoCategories();

  Future<void> _addCategory() async {
    final created = await showFDialog<DemoCategory>(
      context: context,
      builder: (context, style, animation) => _ForuiAddCategoryDialog(animation: animation),
    );
    if (created == null || !mounted) return;
    setState(() => categories.add(created));
    showFToast(
      context: context,
      icon: const Icon(FLucideIcons.circleCheck),
      title: const Text('已新增分類'),
      description: Text(created.name),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final active = categories.where((c) => c.isActive).toList();
    final spent = active.fold<int>(0, (sum, c) => sum + c.spent);
    final budget = active.fold<int>(0, (sum, c) => sum + c.budget);
    final overCount = active.where((c) => c.isOverBudget).length;

    return FScaffold(
      header: FHeader(
        title: const Text('支出分類'),
        suffixes: [
          FBadge(variant: FBadgeVariant.outline, child: const Text('forui 0.25')),
          FButton(
            variant: FButtonVariant.ghost,
            size: FButtonSizeVariant.sm,
            mainAxisSize: MainAxisSize.min,
            prefix: const Icon(FLucideIcons.palette),
            onPress: widget.onTogglePalette,
            child: Text(widget.kgzPalette ? 'KGZ 配色' : 'Neutral 配色'),
          ),
          FHeaderAction(
            icon: Icon(widget.dark ? FLucideIcons.sun : FLucideIcons.moon),
            onPress: widget.onToggleTheme,
          ),
          FButton(
            variant: FButtonVariant.outline,
            size: FButtonSizeVariant.sm,
            mainAxisSize: MainAxisSize.min,
            prefix: const Icon(FLucideIcons.arrowLeftRight),
            onPress: widget.onSwitchLibrary,
            child: const Text('換 shadcn'),
          ),
        ],
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: ListView(
            padding: const EdgeInsets.symmetric(vertical: 16),
            children: [
              FCard(
                child: Padding(
                  padding: theme.cardStyle.padding,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('本月支出', style: theme.cardStyle.titleTextStyle),
                                const SizedBox(height: 2),
                                Text(
                                  '${active.length} 個啟用中的分類',
                                  style: theme.cardStyle.subtitleTextStyle,
                                ),
                              ],
                            ),
                          ),
                          if (overCount > 0)
                            RelayoutOnFontChange(
                              child: FBadge(
                                variant: FBadgeVariant.destructive,
                                child: Text('$overCount 類超支'),
                              ),
                            )
                          else
                            RelayoutOnFontChange(
                              child: FBadge(
                                variant: FBadgeVariant.secondary,
                                child: const Text('預算內'),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        formatMoney(spent),
                        style: theme.typography.display.xl3.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '預算 ${formatMoney(budget)}',
                        style: theme.typography.body.sm.copyWith(color: theme.colors.mutedForeground),
                      ),
                      const SizedBox(height: 12),
                      FDeterminateProgress(
                        value: budget == 0 ? 0 : (spent / budget).clamp(0, 1).toDouble(),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              FTileGroup(
                label: const Text('分類'),
                description: const Text('關閉的分類不會出現在記帳選單中'),
                children: [
                  for (final category in categories)
                    FTile(
                      prefix: CircleAvatar(
                        radius: 16,
                        backgroundColor: category.color.withValues(alpha: 0.15),
                        child: Icon(category.icon, size: 16, color: category.color),
                      ),
                      title: Row(
                        children: [
                          Text(category.name),
                          if (category.isBuiltIn) ...[
                            const SizedBox(width: 6),
                            RelayoutOnFontChange(
                              child: FBadge(
                                variant: FBadgeVariant.secondary,
                                child: const Text('內建'),
                              ),
                            ),
                          ],
                        ],
                      ),
                      subtitle: Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            FDeterminateProgress(
                              value: category.ratio,
                              style: FDeterminateProgressStyleDelta.delta(
                                fillDecoration: DecorationDelta.boxDelta(
                                  color: category.isOverBudget
                                      ? theme.colors.destructive
                                      : category.color,
                                ),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${formatMoney(category.spent)} / ${formatMoney(category.budget)}',
                              style: TextStyle(
                                color: category.isOverBudget ? theme.colors.destructive : null,
                              ),
                            ),
                          ],
                        ),
                      ),
                      suffix: FSwitch(
                        value: category.isActive,
                        onChange: (value) => setState(() => category.isActive = value),
                      ),
                      onPress: () => setState(() => category.isActive = !category.isActive),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              FButton(
                prefix: const Icon(FLucideIcons.plus),
                onPress: _addCategory,
                child: const Text('新增分類'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ForuiAddCategoryDialog extends StatefulWidget {
  const _ForuiAddCategoryDialog({required this.animation});

  final Animation<double> animation;

  @override
  State<_ForuiAddCategoryDialog> createState() => _ForuiAddCategoryDialogState();
}

class _ForuiAddCategoryDialogState extends State<_ForuiAddCategoryDialog> {
  final formKey = GlobalKey<FormState>();
  // `.managed(onChange:)` still means no TextEditingController to create or
  // dispose. `.lifted(value:, onChange:)` would be the fully declarative
  // option, but in forui 0.25 combining it with FTextFormField inside a Form
  // throws "setState() called during build" on every keystroke (the lifted
  // control writes the controller in didUpdateWidget, which notifies the
  // Form). FSelect's lifted control below works fine.
  TextEditingValue name = TextEditingValue.empty;
  TextEditingValue budget = TextEditingValue.empty;
  String? colorKey = 'coral';

  void _submit() {
    if (!formKey.currentState!.validate()) return;
    Navigator.of(context).pop(
      DemoCategory(
        name: name.text.trim(),
        iconKey: 'other',
        colorKey: colorKey ?? 'slate',
        spent: 0,
        budget: int.tryParse(budget.text) ?? 0,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => FDialog(
    animation: widget.animation,
    constraints: const BoxConstraints(minWidth: 280, maxWidth: 420),
    // forui 0.25 ships FDialog as a bare container; the title/body/actions
    // layout comes from `dart run forui snippet create vertical-title-dialog`
    // and is adapted here.
    builder: (context, style) => Padding(
      padding: const EdgeInsets.all(20),
      child: Form(
        key: formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DefaultTextStyle.merge(style: style.titleTextStyle, child: const Text('新增分類')),
            const SizedBox(height: 4),
            DefaultTextStyle.merge(
              style: style.bodyTextStyle,
              child: const Text('建立一個新的支出分類'),
            ),
            const SizedBox(height: 16),
            FTextFormField(
              label: const Text('名稱'),
              hint: '例如：寵物',
              control: FTextFieldControl.managed(onChange: (v) => name = v),
              validator: (v) => (v ?? '').trim().isEmpty ? '請輸入名稱' : null,
            ),
            const SizedBox(height: 12),
            FTextFormField(
              label: const Text('每月預算'),
              hint: '0',
              keyboardType: TextInputType.number,
              control: FTextFieldControl.managed(onChange: (v) => budget = v),
            ),
            const SizedBox(height: 12),
            FSelect<String>(
              label: const Text('色彩'),
              hint: '選擇色彩',
              items: demoColorChoices,
              control: FSelectControl.lifted(
                value: colorKey,
                onChange: (v) => setState(() => colorKey = v),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              spacing: 8,
              children: [
                FButton(
                  variant: FButtonVariant.outline,
                  mainAxisSize: MainAxisSize.min,
                  onPress: () => Navigator.of(context).pop(),
                  child: const Text('取消'),
                ),
                FButton(
                  mainAxisSize: MainAxisSize.min,
                  onPress: _submit,
                  child: const Text('建立'),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}
