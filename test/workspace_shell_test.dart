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

void main() {
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
        ShellRoute(
          builder: (context, state, child) => AppShell(child: child),
          routes: [
            GoRoute(
              path: '/cards',
              builder: (context, state) => const CardsPage(),
            ),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appStoreProvider.overrideWith((ref) => store)],
        child: MaterialApp.router(theme: buildAppTheme(), routerConfig: router),
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
          ShellRoute(
            builder: (context, state, child) => AppShell(child: child),
            routes: [
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
                GoRoute(path: path, builder: (context, state) => Text(path)),
            ],
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [appStoreProvider.overrideWith((ref) => store)],
          child: MaterialApp.router(
            theme: buildAppTheme(),
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('報表'), findsOneWidget);
      final workspaceLabel = tester.widget<Text>(find.text('報表'));
      expect(workspaceLabel.maxLines, 1);
      expect(workspaceLabel.softWrap, isFalse);
      final workspaceTabs = tester.widget<SegmentedButton<String>>(
        find.byType(SegmentedButton<String>),
      );
      expect(
        workspaceTabs.style?.minimumSize?.resolve(<WidgetState>{}),
        const Size(116, 48),
      );
      expect(tester.takeException(), isNull);
      if (size.width < 600) {
        expect(find.byType(NavigationBar), findsOneWidget);
        expect(find.byIcon(Icons.menu), findsOneWidget);
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
        ShellRoute(
          builder: (context, state, child) => AppShell(child: child),
          routes: [
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
              GoRoute(path: path, builder: (context, state) => Text(path)),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appStoreProvider.overrideWith((ref) => store)],
        child: MaterialApp.router(theme: buildAppTheme(), routerConfig: router),
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
