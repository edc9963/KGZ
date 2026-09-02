import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../application/app_store.dart';
import '../application/providers.dart';
import '../data/repositories.dart';
import '../data/supabase_finance_repository.dart';
import 'design_tokens.dart';
import 'quick_entry.dart';
import 'widgets/brand_icon.dart';

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
  ],
};

class AppShell extends ConsumerWidget {
  const AppShell({required this.child, super.key});
  final Widget child;

  int _indexFor(String path) {
    final index = switch (path) {
      _ when path.startsWith('/reports') => 0,
      _ when path.startsWith('/cards') => 1,
      _ when path.startsWith('/investments') => 2,
      _ => _destinations.indexWhere((item) => path.startsWith(item.path)),
    };
    return index < 0 ? 0 : index;
  }

  Widget _withSyncState(BuildContext context, AppStore store, Widget content) {
    final message = store.lastSyncError;
    return Stack(
      children: [
        Column(
          children: [
            if (message != null)
              Material(
                color: store.isOffline || store.hasConflict
                    ? Theme.of(context).colorScheme.errorContainer
                    : Theme.of(context).colorScheme.secondaryContainer,
                child: SafeArea(
                  bottom: false,
                  child: ListTile(
                    dense: true,
                    leading: Icon(
                      store.isOffline ? Icons.cloud_off : Icons.info_outline,
                    ),
                    title: Text(message),
                    trailing: store.isOffline || store.hasConflict
                        ? TextButton(
                            onPressed: store.reloadCloud,
                            child: const Text('重新載入'),
                          )
                        : null,
                  ),
                ),
              ),
            if (store.isSaving) const LinearProgressIndicator(minHeight: 2),
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
  Widget build(BuildContext context, WidgetRef ref) {
    final path = GoRouterState.of(context).uri.path;
    final selected = _indexFor(path);
    final width = MediaQuery.sizeOf(context).width;
    final desktop = width >= 1024;
    final tablet = width >= 600 && !desktop;
    final store = ref.watch(appStoreProvider);

    final content = SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          desktop
              ? 32
              : tablet
              ? 24
              : 16,
          tablet || desktop ? 24 : 16,
          desktop
              ? 32
              : tablet
              ? 24
              : 16,
          desktop || tablet ? 32 : 110,
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1440),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_workspaceTabs.containsKey(selected)) ...[
                _WorkspaceNavigation(
                  destinations: _workspaceTabs[selected]!,
                  currentPath: path,
                ),
                const SizedBox(height: 20),
              ],
              child,
            ],
          ),
        ),
      ),
    );

    if (desktop) {
      return Scaffold(
        body: _withSyncState(
          context,
          store,
          Row(
            children: [
              _DesktopSidebar(
                selectedIndex: selected,
                store: store,
                onSelected: (index) => context.go(_destinations[index].path),
              ),
              Expanded(child: content),
            ],
          ),
        ),
      );
    }

    if (tablet) {
      return Scaffold(
        body: _withSyncState(
          context,
          store,
          Row(
            children: [
              NavigationRail(
                selectedIndex: selected,
                labelType: NavigationRailLabelType.all,
                onDestinationSelected: (index) =>
                    context.go(_destinations[index].path),
                leading: const Padding(
                  padding: EdgeInsets.only(bottom: 12),
                  child: BrandIcon(size: 40, borderRadius: 10),
                ),
                destinations: [
                  for (final destination in _destinations)
                    NavigationRailDestination(
                      icon: Icon(destination.icon),
                      label: Text(destination.label),
                    ),
                ],
              ),
              const VerticalDivider(width: 1),
              Expanded(child: content),
            ],
          ),
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: store.canWrite ? () => showQuickEntry(context) : null,
          icon: const Icon(Icons.add),
          label: const Text('快速新增'),
        ),
      );
    }

    const mobileDestinations = [0, 1, 2, 3];
    final mobileIndex = mobileDestinations.indexOf(selected);
    return Scaffold(
      drawer: _MobileDrawer(
        selectedIndex: selected,
        store: store,
        onSelected: (path) {
          Navigator.pop(context);
          context.go(path);
        },
      ),
      appBar: AppBar(
        title: Text(
          _destinations[selected].label,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        actions: [
          Tooltip(
            message: _syncLabel(store),
            child: Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Icon(_syncIcon(store), size: 20),
            ),
          ),
        ],
      ),
      body: _withSyncState(context, store, content),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: store.canWrite ? () => showQuickEntry(context) : null,
        icon: const Icon(Icons.add),
        label: const Text('快速記帳'),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: mobileIndex < 0 ? 0 : mobileIndex,
        onDestinationSelected: (index) =>
            context.go(_destinations[mobileDestinations[index]].path),
        destinations: [
          for (final index in mobileDestinations)
            NavigationDestination(
              icon: Icon(_destinations[index].icon),
              label: _destinations[index].label,
            ),
        ],
      ),
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
  Widget build(BuildContext context) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: SegmentedButton<String>(
      showSelectedIcon: false,
      style: const ButtonStyle(
        minimumSize: WidgetStatePropertyAll(Size(116, 48)),
        padding: WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 16)),
      ),
      segments: [
        for (final destination in destinations)
          ButtonSegment(
            value: destination.path,
            icon: Icon(destination.icon),
            label: Text(
              destination.label,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.visible,
            ),
          ),
      ],
      selected: {
        destinations
                .where((item) => currentPath.startsWith(item.path))
                .firstOrNull
                ?.path ??
            destinations.first.path,
      },
      onSelectionChanged: (value) => context.go(value.single),
    ),
  );
}

class _MobileDrawer extends StatelessWidget {
  const _MobileDrawer({
    required this.selectedIndex,
    required this.store,
    required this.onSelected,
  });

  final int selectedIndex;
  final AppStore store;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) => Drawer(
    child: SafeArea(
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: 12),
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 8, 20, 20),
            child: Row(
              children: [
                BrandIcon(size: 42, borderRadius: 11),
                SizedBox(width: 12),
                Text(
                  '快記帳',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
                ),
              ],
            ),
          ),
          for (var index = 0; index < _destinations.length; index++) ...[
            ListTile(
              selected: selectedIndex == index,
              leading: Icon(_destinations[index].icon),
              title: Text(_destinations[index].label),
              onTap: () => onSelected(_destinations[index].path),
            ),
            if (_workspaceTabs[index] case final tabs?)
              for (final tab in tabs)
                Padding(
                  padding: const EdgeInsets.only(left: 24),
                  child: ListTile(
                    dense: true,
                    leading: Icon(tab.icon, size: 20),
                    title: Text(tab.label),
                    onTap: () => onSelected(tab.path),
                  ),
                ),
          ],
          const Divider(),
          SwitchListTile(
            secondary: Icon(
              store.data.settings.maskBalances
                  ? Icons.visibility_off_outlined
                  : Icons.visibility_outlined,
            ),
            title: Text(store.data.settings.maskBalances ? '顯示金額' : '隱藏金額'),
            value: store.data.settings.maskBalances,
            onChanged: store.canWrite
                ? (value) => store.updateSettings(
                    store.data.settings.copyWith(maskBalances: value),
                  )
                : null,
          ),
        ],
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
    return Material(
      color: AppColors.graphite,
      child: SizedBox(
        width: 236,
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(24, 24, 20, 20),
                child: Row(
                  children: [
                    BrandIcon(size: 40, borderRadius: 10),
                    SizedBox(width: 12),
                    Text(
                      '快記帳',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  children: [
                    const Padding(
                      padding: EdgeInsets.fromLTRB(12, 6, 12, 10),
                      child: Text(
                        '工作區',
                        style: TextStyle(
                          color: Color(0xFF93A4AB),
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          letterSpacing: .6,
                        ),
                      ),
                    ),
                    for (var index = 0; index < _destinations.length; index++)
                      _SidebarItem(
                        destination: _destinations[index],
                        selected: selectedIndex == index,
                        onTap: () => onSelected(index),
                      ),
                  ],
                ),
              ),
              const Divider(
                color: Color(0xFF43535A),
                indent: 20,
                endIndent: 20,
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                child: Row(
                  children: [
                    Icon(
                      _syncIcon(store),
                      size: 16,
                      color: const Color(0xFFDCE5E8),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _syncLabel(store),
                        style: const TextStyle(
                          color: Color(0xFFDCE5E8),
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 6, 12, 18),
                child: ListTile(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  leading: Icon(
                    store.data.settings.maskBalances
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                    color: const Color(0xFFDCE5E8),
                  ),
                  title: Text(
                    store.data.settings.maskBalances ? '顯示金額' : '隱藏金額',
                    style: const TextStyle(color: Color(0xFFDCE5E8)),
                  ),
                  onTap: store.canWrite
                      ? () => store.updateSettings(
                          store.data.settings.copyWith(
                            maskBalances: !store.data.settings.maskBalances,
                          ),
                        )
                      : null,
                ),
              ),
            ],
          ),
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

class _SidebarItem extends StatelessWidget {
  const _SidebarItem({
    required this.destination,
    required this.selected,
    required this.onTap,
  });

  final _Destination destination;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: ListTile(
      dense: true,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      tileColor: selected ? AppColors.primary : Colors.transparent,
      leading: Icon(
        destination.icon,
        color: selected ? Colors.white : const Color(0xFFDCE5E8),
      ),
      title: Text(
        destination.label,
        style: TextStyle(
          color: selected ? Colors.white : const Color(0xFFDCE5E8),
          fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
        ),
      ),
      onTap: onTap,
    ),
  );
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
      child: Card(
        margin: const EdgeInsets.all(24),
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
                          child: CircularProgressIndicator(strokeWidth: 2.5),
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
                        color: Theme.of(context).colorScheme.errorContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.error_outline,
                            color: Theme.of(
                              context,
                            ).colorScheme.onErrorContainer,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              message,
                              style: TextStyle(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onErrorContainer,
                              ),
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
                    FilledButton.icon(
                      onPressed: store.isSaving
                          ? null
                          : () => store.resolveInitialMigration(
                              bothExist
                                  ? InitialMigrationAction.merge
                                  : InitialMigrationAction.uploadLocal,
                            ),
                      icon: const Icon(Icons.cloud_upload_outlined),
                      label: Text(bothExist ? '安全合併' : '上傳資料'),
                    ),
                    OutlinedButton(
                      onPressed: store.isSaving
                          ? null
                          : () => store.resolveInitialMigration(
                              InitialMigrationAction.useCloud,
                            ),
                      child: Text(bothExist ? '使用雲端' : '略過本機資料'),
                    ),
                    if (bothExist)
                      TextButton(
                        onPressed: store.isSaving
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
    );
  }

  Future<void> _confirmReplace(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('取代雲端資料？'),
        content: const Text('雲端現有資料會被本機版本取代。這個動作無法自動復原。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
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
