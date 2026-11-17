import 'package:flutter/material.dart';
import 'package:forui/forui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../application/app_store.dart';
import '../application/providers.dart';
import '../data/repositories.dart';
import '../data/supabase_finance_repository.dart';
import 'design_tokens.dart';
import 'quick_entry.dart';
import 'widgets/brand_icon.dart';
import 'widgets/kgz_layout.dart';

class _Destination {
  const _Destination(this.path, this.label, this.icon);
  final String path;
  final String label;
  final IconData icon;
}

const _destinations = [
  _Destination('/dashboard', '總覽', Icons.space_dashboard_outlined),
  _Destination('/expenses', '帳務', Icons.receipt_long_outlined),
  _Destination('/accounts', '資產', Icons.account_balance_wallet_outlined),
  _Destination('/orders', '代訂', Icons.groups_outlined),
  _Destination('/settings', '設定', Icons.settings_outlined),
];

const _workspaceTabs = <int, List<_Destination>>{
  0: [
    _Destination('/dashboard', '總覽', Icons.dashboard_outlined),
    _Destination('/reports', '報表', Icons.assessment_outlined),
  ],
  1: [
    _Destination('/expenses', '交易', Icons.receipt_long_outlined),
    _Destination('/cards', '卡片', Icons.credit_card_outlined),
  ],
  2: [
    _Destination('/accounts', '帳戶', Icons.account_balance_outlined),
    _Destination('/investments', '投資', Icons.trending_up_outlined),
    _Destination('/reconciliation', '對帳', Icons.fact_check_outlined),
  ],
};

class AppShell extends ConsumerStatefulWidget {
  const AppShell({required this.navigationShell, super.key});

  // The branches configured in `main.dart`'s `StatefulShellRoute
  // .indexedStack` keep one Navigator alive per top-level destination, so
  // rendering `navigationShell` here (in place of the plain `child` a
  // regular `ShellRoute` would hand us) is what makes switching bottom-nav/
  // sidebar tabs preserve each destination's state and widget tree instead
  // of tearing it down and rebuilding it on every tap.
  final StatefulNavigationShell navigationShell;

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  final _mobileActions = ValueNotifier<Map<String, Widget?>>({});

  @override
  void dispose() {
    _mobileActions.dispose();
    super.dispose();
  }

  int _indexFor(String path) {
    final index = switch (path) {
      _ when path.startsWith('/reports') => 0,
      _ when path.startsWith('/cards') => 1,
      _ when path.startsWith('/investments') => 2,
      _ when path.startsWith('/reconciliation') => 2,
      _ => _destinations.indexWhere((item) => path.startsWith(item.path)),
    };
    return index < 0 ? 0 : index;
  }

  Widget _withSyncState(BuildContext context, AppStore store, Widget content) {
    final message = store.lastSyncError;
    // Offline/conflict are real connectivity states that clear themselves
    // once the cause does; everything else routed through lastSyncError is
    // a one-off failure (most often a form validation a dialog didn't catch
    // before calling into the store) that only ever gets cleared by the
    // *next unrelated successful save* — with nothing to trigger that, the
    // banner otherwise sits here indefinitely. Give those a dismiss button.
    final isConnectivityStatus = store.isOffline || store.hasConflict;
    return Stack(
      children: [
        Column(
          children: [
            if (message != null)
              ColoredBox(
                color: isConnectivityStatus
                    ? context.colors.expensePale
                    : context.colors.accentPale,
                child: SafeArea(
                  bottom: false,
                  child: FItem(
                    prefix: Icon(
                      store.isOffline ? Icons.cloud_off : Icons.info_outline,
                    ),
                    title: Text(message),
                    suffix: isConnectivityStatus
                        ? FButton(
                            variant: FButtonVariant.ghost,
                            mainAxisSize: MainAxisSize.min,
                            onPress: store.reloadCloud,
                            child: const Text('重新載入'),
                          )
                        : FTooltip(
                            tipBuilder: (context, _) => Text('關閉'),
                            child: FButton.icon(
                              variant: FButtonVariant.ghost,
                              onPress: () {
                                store.lastSyncError = null;
                                store.notify();
                              },
                              semanticsLabel: '關閉',
                              child: const Icon(Icons.close, size: 18),
                            ),
                          ),
                  ),
                ),
              ),
            if (store.isSaving) FProgress(),
            Expanded(child: content),
          ],
        ),
        if (store.needsInitialMigration)
          Positioned.fill(
            child: ColoredBox(
              color: Colors.black54,
              child: Center(child: _MigrationCard(store: store)),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final path = GoRouterState.of(context).uri.path;
    final selected = _indexFor(path);
    final width = MediaQuery.sizeOf(context).width;
    final desktop = width >= 1024;
    final tablet = width >= 600 && !desktop;
    final store = ref.watch(appStoreProvider);

    final content = SafeArea(
      child: RefreshIndicator(
        onRefresh: store.reloadCloud,
        color: context.colors.accent,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.fromLTRB(
            desktop
                ? 32
                : tablet
                ? 24
                : 24,
            tablet || desktop ? 24 : 16,
            desktop
                ? 32
                : tablet
                ? 24
                : 24,
            desktop || tablet ? 32 : 24,
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1440),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // The workspace tabs render inside the page, under its
                // PageHeader (see WorkspaceScope), matching the Figma layout.
                WorkspaceScope(
                  mobileActions: desktop || tablet ? null : _mobileActions,
                  path: path,
                  label: _destinations[selected].label,
                  tabs: _workspaceTabs.containsKey(selected)
                      ? _WorkspaceNavigation(
                          destinations: _workspaceTabs[selected]!,
                          currentPath: path,
                        )
                      : null,
                  child: widget.navigationShell,
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (desktop) {
      return FScaffold(
        childPad: false,
        sidebar: _DesktopSidebar(
          selectedIndex: selected,
          store: store,
          onSelected: (index) {
            HapticFeedback.selectionClick();
            context.go(_destinations[index].path);
          },
        ),
        child: _withSyncState(context, store, content),
      );
    }

    if (tablet) {
      return FScaffold(
        childPad: false,
        child: _withSyncState(
          context,
          store,
          Stack(
            children: [
              Row(
                children: [
                  _TabletRail(
                    selectedIndex: selected,
                    onSelected: (index) {
                      HapticFeedback.selectionClick();
                      context.go(_destinations[index].path);
                    },
                  ),
                  const FDivider(axis: Axis.vertical),
                  Expanded(child: content),
                ],
              ),
              Positioned(
                right: 24,
                bottom: 24,
                child: SafeArea(
                  child: FButton(
                    size: FButtonSizeVariant.lg,
                    mainAxisSize: MainAxisSize.min,
                    onPress: store.canWrite
                        ? () => showQuickEntry(context)
                        : null,
                    prefix: const Icon(FLucideIcons.plus),
                    child: const Text('快速新增'),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    const mobileDestinations = [0, 1, 2, 3, 4];
    final mobileIndex = mobileDestinations.indexOf(selected);
    // No drawer on phones: the bottom bar already reaches every workspace and
    // each page shows its own sub-tabs, so a hamburger menu only duplicated
    // them. The one thing it added — the balance mask — lives in the bar.
    final mask = store.data.settings.maskBalances;
    return FScaffold(
      childPad: false,
      header: SafeArea(
        bottom: false,
        child: FHeader(
          title: const Row(
            children: [
              BrandIcon(size: 28, borderRadius: 8),
              SizedBox(width: 10),
              Text(
                '快記帳',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
              ),
            ],
          ),
          suffixes: [
            FTooltip(
              tipBuilder: (context, _) => Text(mask ? '顯示金額' : '隱藏金額'),
              child: FHeaderAction(
                icon: Icon(
                  mask ? FLucideIcons.eyeOff : FLucideIcons.eye,
                  semanticLabel: mask ? '顯示金額' : '隱藏金額',
                ),
                onPress: store.canWrite
                    ? () => store.updateSettings(
                        store.data.settings.copyWith(maskBalances: !mask),
                      )
                    : null,
              ),
            ),
            FTooltip(
              tipBuilder: (context, _) => Text(_syncLabel(store)),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Icon(_syncIcon(store), size: 20),
              ),
            ),
          ],
        ),
      ),
      footer: ValueListenableBuilder<Map<String, Widget?>>(
        valueListenable: _mobileActions,
        builder: (context, actions, _) {
          final action =
              actions[path] ??
              (path == '/dashboard'
                  ? FButton(
                      mainAxisSize: MainAxisSize.min,
                      onPress: store.canWrite
                          ? () => showQuickEntry(context)
                          : null,
                      prefix: const Icon(FLucideIcons.plus),
                      child: const Text('快速記帳'),
                    )
                  : null);
          final children = action is Wrap
              ? action.children
              : action is Row
              ? action.children
              : <Widget>[if (action != null) action];
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (action != null &&
                  MediaQuery.viewInsetsOf(context).bottom == 0)
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 10, 24, 10),
                  child: Row(
                    children: [
                      for (var i = 0; i < children.length; i++) ...[
                        if (i > 0) const SizedBox(width: 8),
                        if (children[i] is FButton)
                          Expanded(child: children[i])
                        else
                          children[i],
                      ],
                    ],
                  ),
                ),
              FBottomNavigationBar(
                safeAreaBottom: true,
                index: mobileIndex < 0 ? 0 : mobileIndex,
                onChange: (index) {
                  HapticFeedback.selectionClick();
                  context.go(_destinations[mobileDestinations[index]].path);
                },
                children: [
                  for (final index in mobileDestinations)
                    FBottomNavigationBarItem(
                      icon: Icon(_destinations[index].icon),
                      label: Text(_destinations[index].label),
                    ),
                ],
              ),
            ],
          );
        },
      ),
      child: _withSyncState(context, store, content),
    );
  }
}

class _WorkspaceNavigation extends StatelessWidget {
  const _WorkspaceNavigation({
    required this.destinations,
    required this.currentPath,
  });

  final List<_Destination> destinations;
  final String currentPath;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerLeft,
    child: ConstrainedBox(
      constraints: BoxConstraints(maxWidth: 160.0 * destinations.length),
      child: KgzTabBar<String>(
        tabs: [
          for (final destination in destinations)
            (
              destination.path,
              destination.label,
              MediaQuery.sizeOf(context).width < 600 ? null : destination.icon,
            ),
        ],
        selected:
            destinations
                .where((item) => currentPath.startsWith(item.path))
                .firstOrNull
                ?.path ??
            destinations.first.path,
        onSelected: (path) {
          HapticFeedback.selectionClick();
          context.go(path);
        },
      ),
    ),
  );
}

class _DesktopSidebar extends StatelessWidget {
  const _DesktopSidebar({
    required this.selectedIndex,
    required this.store,
    required this.onSelected,
  });

  final int selectedIndex;
  final AppStore store;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final mask = store.data.settings.maskBalances;
    return SizedBox(
      width: 236,
      child: FSidebar(
        header: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 24, 16, 12),
            child: Row(
              children: [
                const BrandIcon(size: 40, borderRadius: 10),
                const SizedBox(width: 12),
                Text(
                  '快記帳',
                  style: TextStyle(
                    color: colors.text,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
        ),
        footer: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                  child: Row(
                    children: [
                      Icon(_syncIcon(store), size: 16, color: colors.textMuted),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _syncLabel(store),
                          style: TextStyle(
                            color: colors.textMuted,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                FSidebarItem(
                  icon: Icon(mask ? FLucideIcons.eyeOff : FLucideIcons.eye),
                  label: Text(mask ? '顯示金額' : '隱藏金額'),
                  onPress: store.canWrite
                      ? () => store.updateSettings(
                          store.data.settings.copyWith(maskBalances: !mask),
                        )
                      : null,
                ),
              ],
            ),
          ),
        ),
        children: [
          FSidebarGroup(
            label: const Text('工作區'),
            children: [
              for (var index = 0; index < _destinations.length; index++)
                FSidebarItem(
                  icon: Icon(_destinations[index].icon),
                  label: Text(_destinations[index].label),
                  selected: selectedIndex == index,
                  onPress: () => onSelected(index),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Compact icon-over-label rail for tablets (600–1024 px), in the spirit of
/// Material's NavigationRail but drawn with forui's [FTappable].
class _TabletRail extends StatelessWidget {
  const _TabletRail({required this.selectedIndex, required this.onSelected});

  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SizedBox(
      key: const ValueKey('tablet-rail'),
      width: 88,
      child: SafeArea(
        right: false,
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(0, 16, 0, 12),
              child: BrandIcon(size: 40, borderRadius: 10),
            ),
            for (var index = 0; index < _destinations.length; index++)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: FTappable(
                  selected: selectedIndex == index,
                  semanticsLabel: _destinations[index].label,
                  onPress: () => onSelected(index),
                  builder: (context, variants, child) => DecoratedBox(
                    decoration: BoxDecoration(
                      color: selectedIndex == index
                          ? colors.accentPale
                          : variants.contains(FTappableVariant.hovered)
                          ? colors.subtle
                          : null,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: child,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Column(
                      children: [
                        Icon(
                          _destinations[index].icon,
                          color: selectedIndex == index
                              ? colors.accent
                              : colors.textMuted,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _destinations[index].label,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: selectedIndex == index
                                ? FontWeight.w800
                                : FontWeight.w500,
                            color: selectedIndex == index
                                ? colors.text
                                : colors.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

IconData _syncIcon(AppStore store) {
  if (store.isSaving) return Icons.sync;
  if (store.isOffline) return Icons.cloud_off_outlined;
  if (store.hasConflict) return Icons.sync_problem_outlined;
  if (store.lastSyncError != null) return Icons.error_outline;
  return Icons.cloud_done_outlined;
}

String _syncLabel(AppStore store) {
  if (store.isSaving) return '同步中';
  if (store.isOffline) return '離線・僅可查看';
  if (store.hasConflict) return '資料衝突・請重新載入';
  if (store.lastSyncError != null) return '同步失敗';
  final updated = store.cloudUpdatedAt;
  if (updated == null) return '已連線';
  final difference = DateTime.now().difference(updated.toLocal());
  if (difference.inMinutes < 1) return '已同步・剛剛';
  if (difference.inHours < 1) return '已同步・${difference.inMinutes} 分鐘前';
  return '已同步・${updated.toLocal().hour.toString().padLeft(2, '0')}:${updated.toLocal().minute.toString().padLeft(2, '0')}';
}

class _MigrationCard extends StatelessWidget {
  const _MigrationCard({required this.store});
  final AppStore store;

  @override
  Widget build(BuildContext context) {
    final local = store.localMigrationCandidate!;
    final localCount = financeItemCount(local);
    final cloudCount = financeItemCount(store.data);
    final bothExist = store.cloudExists && cloudCount > 0;
    return PopScope(
      canPop: false,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: KgzCard(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    bothExist ? '選擇資料合併方式' : '上傳本機資料',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    bothExist
                        ? '本機有 $localCount 筆、雲端有 $cloudCount 筆資料。'
                        : '這個瀏覽器有 $localCount 筆既有資料，可以安全地上傳到你的雲端帳號。',
                  ),
                  if (bothExist) ...[
                    const SizedBox(height: 8),
                    const Text('合併時，相同 ID 會保留雲端版本，本機獨有資料會加入。'),
                  ],
                  if (store.isSaving) ...[
                    const SizedBox(height: 20),
                    Semantics(
                      liveRegion: true,
                      child: const Row(
                        children: [
                          SizedBox.square(
                            dimension: 20,
                            child: FCircularProgress(),
                          ),
                          SizedBox(width: 12),
                          Expanded(child: Text('正在處理資料，請稍候…')),
                        ],
                      ),
                    ),
                  ],
                  if (store.lastSyncError case final message?) ...[
                    const SizedBox(height: 16),
                    Semantics(
                      liveRegion: true,
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: context.colors.expensePale,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.error_outline,
                              color: context.colors.expense,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                message,
                                style: TextStyle(color: context.colors.expense),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      FButton(
                        mainAxisSize: MainAxisSize.min,
                        onPress: store.isSaving
                            ? null
                            : () => store.resolveInitialMigration(
                                bothExist
                                    ? InitialMigrationAction.merge
                                    : InitialMigrationAction.uploadLocal,
                              ),
                        prefix: const Icon(Icons.cloud_upload_outlined),
                        child: Text(bothExist ? '安全合併' : '上傳資料'),
                      ),
                      FButton(
                        variant: FButtonVariant.outline,
                        mainAxisSize: MainAxisSize.min,
                        onPress: store.isSaving
                            ? null
                            : () => store.resolveInitialMigration(
                                InitialMigrationAction.useCloud,
                              ),
                        child: Text(bothExist ? '使用雲端' : '略過本機資料'),
                      ),
                      if (bothExist)
                        FButton(
                          variant: FButtonVariant.ghost,
                          mainAxisSize: MainAxisSize.min,
                          onPress: store.isSaving
                              ? null
                              : () => _confirmReplace(context),
                          child: const Text('以本機取代雲端'),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _confirmReplace(BuildContext context) async {
    final confirmed = await showFDialog<bool>(
      useRootNavigator: true,
      context: context,
      builder: (context, _, _) => KgzDialog(
        title: const Text('取代雲端資料？'),
        content: const Text('雲端現有資料會被本機版本取代。這個動作無法自動復原。'),
        actions: [
          FButton(
            variant: FButtonVariant.ghost,
            mainAxisSize: MainAxisSize.min,
            onPress: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FButton(
            mainAxisSize: MainAxisSize.min,
            variant: FButtonVariant.destructive,
            onPress: () => Navigator.pop(context, true),
            child: const Text('確認取代'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await store.resolveInitialMigration(InitialMigrationAction.replaceCloud);
    }
  }
}
