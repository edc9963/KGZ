import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:quick_ledger/application/app_store.dart';
import 'package:quick_ledger/application/providers.dart';
import 'package:quick_ledger/data/repositories.dart';
import 'package:quick_ledger/domain/models.dart';
import 'package:quick_ledger/presentation/app_shell.dart';
import 'package:quick_ledger/presentation/pages/cards_page.dart';
import 'package:quick_ledger/presentation/theme.dart';
import 'package:quick_ledger/presentation/widgets/common.dart';

void main() {
  testWidgets('mobile actions stay docked and follow the active route', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);
    final store = AppStore(
      authRepository: _Auth(),
      financeRepository: _Finance(),
      csvExportService: _Csv(),
    );
    await store.initialize();
    String? lastAction;
    final router = GoRouter(
      initialLocation: '/accounts',
      routes: [
        StatefulShellRoute.indexedStack(
          builder: (context, state, navigationShell) =>
              AppShell(navigationShell: navigationShell),
          branches: [
            for (final path in ['/accounts', '/expenses', '/settings'])
              StatefulShellBranch(
                routes: [
                  GoRoute(
                    path: path,
                    builder: (context, state) => Column(
                      children: [
                        PageHeader(
                          title: path,
                          action: path == '/settings'
                              ? null
                              : FilledButton(
                                  onPressed: () => lastAction = path,
                                  child: Text('新增 $path'),
                                ),
                        ),
                        const SizedBox(height: 1600),
                        const Text('清單底部'),
                      ],
                    ),
                  ),
                ],
              ),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appStoreProvider.overrideWith((ref) => store)],
        child: MaterialApp.router(
          theme: buildAppTheme(Brightness.light),
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final action = find.widgetWithText(FilledButton, '新增 /accounts');
    expect(action, findsOneWidget);
    final original = tester.getTopLeft(action);
    expect(
      tester.getBottomLeft(action).dy,
      lessThan(tester.getTopLeft(find.byType(NavigationBar)).dy),
    );
    await tester.drag(
      find.byType(SingleChildScrollView).first,
      const Offset(0, -500),
    );
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(action), original);
    await tester.tap(action);
    expect(lastAction, '/accounts');
    router.go('/expenses');
    await tester.pumpAndSettle();
    expect(action, findsNothing);
    await tester.tap(find.text('新增 /expenses'));
    expect(lastAction, '/expenses');
    await tester.tap(find.text('設定').last);
    await tester.pumpAndSettle();
    final nav = tester.widget<NavigationBar>(find.byType(NavigationBar));
    expect(nav.destinations, hasLength(5));
    expect(nav.selectedIndex, 4);
    expect(find.text('新增 /expenses'), findsNothing);
    router.go('/accounts');
    await tester.pumpAndSettle();
    expect(action, findsOneWidget);
    tester.view.viewInsets = const FakeViewPadding(bottom: 320);
    await tester.pumpAndSettle();
    expect(action, findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('cards page renders inside the scrollable workspace shell', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = AppStore(
      authRepository: _Auth(),
      financeRepository: _Finance(),
      csvExportService: _Csv(),
    );
    await store.initialize();
    final router = GoRouter(
      initialLocation: '/cards',
      routes: [
        StatefulShellRoute.indexedStack(
          builder: (context, state, navigationShell) =>
              AppShell(navigationShell: navigationShell),
          branches: [
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: '/cards',
                  builder: (context, state) => const CardsPage(),
                ),
              ],
            ),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appStoreProvider.overrideWith((ref) => store)],
        child: MaterialApp.router(
          theme: buildAppTheme(Brightness.light),
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('還沒有卡片'), findsOneWidget);
    expect(find.textContaining('目前待扣款'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final size in [
    const Size(360, 800),
    const Size(768, 1024),
    const Size(1440, 900),
  ]) {
    testWidgets('workspace shell adapts at ${size.width.toInt()}px', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = AppStore(
        authRepository: _Auth(),
        financeRepository: _Finance(),
        csvExportService: _Csv(),
      );
      await store.initialize();
      final router = GoRouter(
        initialLocation: '/reports',
        routes: [
          StatefulShellRoute.indexedStack(
            builder: (context, state, navigationShell) =>
                AppShell(navigationShell: navigationShell),
            branches: [
              for (final path in const [
                '/dashboard',
                '/reports',
                '/expenses',
                '/cards',
                '/accounts',
                '/investments',
                '/orders',
                '/settings',
              ])
                StatefulShellBranch(
                  routes: [
                    GoRoute(
                      path: path,
                      builder: (context, state) =>
                          PageHeader(title: path, subtitle: ''),
                    ),
                  ],
                ),
            ],
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [appStoreProvider.overrideWith((ref) => store)],
          child: MaterialApp.router(
            theme: buildAppTheme(Brightness.light),
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('報表'), findsOneWidget);
      final workspaceLabel = tester.widget<Text>(find.text('報表'));
      expect(workspaceLabel.maxLines, 1);
      expect(workspaceLabel.softWrap, isFalse);
      expect(find.byType(KgzTabBar<String>), findsOneWidget);
      expect(
        tester.getSize(find.byType(KgzTabBar<String>)).height,
        greaterThanOrEqualTo(48),
      );
      expect(tester.takeException(), isNull);
      if (size.width < 600) {
        expect(find.byType(NavigationBar), findsOneWidget);
        expect(find.byIcon(Icons.menu), findsNothing);
        expect(find.text('KGZ  /  總覽'), findsNothing);
      } else if (size.width < 1024) {
        expect(find.byType(NavigationRail), findsOneWidget);
        expect(find.byType(NavigationBar), findsNothing);
      } else {
        expect(find.text('工作區'), findsOneWidget);
        expect(find.byType(NavigationRail), findsNothing);
      }
    });
  }

  testWidgets('quick entry opens from the global action button', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = AppStore(
      authRepository: _Auth(),
      financeRepository: _Finance(),
      csvExportService: _Csv(),
    );
    await store.initialize();
    final router = GoRouter(
      initialLocation: '/dashboard',
      routes: [
        StatefulShellRoute.indexedStack(
          builder: (context, state, navigationShell) =>
              AppShell(navigationShell: navigationShell),
          branches: [
            for (final path in const [
              '/dashboard',
              '/reports',
              '/expenses',
              '/cards',
              '/accounts',
              '/investments',
              '/orders',
              '/settings',
            ])
              StatefulShellBranch(
                routes: [
                  GoRoute(path: path, builder: (context, state) => Text(path)),
                ],
              ),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appStoreProvider.overrideWith((ref) => store)],
        child: MaterialApp.router(
          theme: buildAppTheme(Brightness.light),
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('快速記帳'));
    await tester.pumpAndSettle();

    expect(find.text('快速記帳'), findsNWidgets(2));
    expect(find.text('支出'), findsWidgets);
    expect(find.text('收入'), findsOneWidget);
    expect(find.text('更多選項'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class _Auth implements AuthRepository {
  final _controller = StreamController<bool>.broadcast();
  @override
  Stream<bool> get authStateChanges => _controller.stream;
  @override
  String? get currentUserId => 'user';
  @override
  String? get currentUserDisplayName => '測試使用者';
  @override
  bool get isSignedIn => true;
  @override
  Future<void> signInWithLine({String? returnPath}) async {}
  @override
  Future<void> signOut() async {}
}

class _Finance implements FinanceRepository {
  AppData data = const AppData();
  var revision = 0;
  @override
  Future<SaveResult> clear() async {
    data = const AppData();
    return SaveResult(revision: ++revision, updatedAt: DateTime.now());
  }

  @override
  Future<FinanceSnapshot> load() async =>
      FinanceSnapshot(data: data, revision: revision, cloudExists: true);

  @override
  Future<FinanceSnapshot> resolveInitialMigration(
    InitialMigrationAction action,
  ) => load();

  @override
  Future<SaveResult> save(AppData data) async {
    this.data = data;
    return SaveResult(revision: ++revision, updatedAt: DateTime.now());
  }
}

class _Csv implements CsvExportService {
  @override
  Future<void> export(String fileName, List<List<Object?>> rows) async {}
}
