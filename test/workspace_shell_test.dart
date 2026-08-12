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
import 'package:quick_ledger/presentation/theme.dart';

void main() {
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

      expect(find.text('趨勢與財務報表'), findsOneWidget);
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
}

class _Auth implements AuthRepository {
  final _controller = StreamController<bool>.broadcast();
  @override
  Stream<bool> get authStateChanges => _controller.stream;
  @override
  String? get currentUserId => 'user';
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
