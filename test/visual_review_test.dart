// Opt-in visual-review harness: renders every workspace
// page with demo data at phone and desktop widths in both themes, using the
// real Noto Sans TC font, and writes PNGs to CAPTURE_DIR.
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:quick_ledger/application/app_store.dart';
import 'package:quick_ledger/application/providers.dart';
import 'package:quick_ledger/application/theme_mode_controller.dart';
import 'package:quick_ledger/data/repositories.dart';
import 'package:quick_ledger/domain/models.dart';
import 'package:quick_ledger/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _out = String.fromEnvironment('CAPTURE_DIR');
const _only = String.fromEnvironment('CAPTURE_ONLY');
const _fontPath = String.fromEnvironment(
  'CJK_FONT',
  defaultValue: 'C:/Windows/Fonts/NotoSansTC-VF.ttf',
);

Future<void> _loadFont(String family, List<String> paths) async {
  final loader = FontLoader(family);
  for (final path in paths) {
    final bytes = File(path).readAsBytesSync();
    loader.addFont(Future.value(ByteData.view(bytes.buffer)));
  }
  await loader.load();
}

Future<void> _capture(WidgetTester tester, String name) async {
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull, reason: name);
  final element = tester.element(find.byType(QuickLedgerApp));
  await tester.runAsync(() async {
    final image = await captureImage(element);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    File('$_out/$name.png').writeAsBytesSync(data!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  const routes = [
    '/dashboard',
    '/reports',
    '/expenses',
    '/cards',
    '/accounts',
    '/investments',
    '/reconciliation',
    '/orders',
    '/settings',
  ];
  const sizes = {'phone': Size(390, 844), 'desktop': Size(1280, 900)};

  testWidgets('capture screens', (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.runAsync(() async {
      await _loadFont('Noto Sans TC', [_fontPath]);
      await _loadFont('MaterialIcons', [
        'C:/sdk/flutter/bin/cache/artifacts/material_fonts/materialicons-regular.otf',
      ]);
    });
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    Directory(_out).createSync(recursive: true);

    for (final theme in [ThemeMode.light, ThemeMode.dark]) {
      for (final MapEntry(key: sizeName, value: size) in sizes.entries) {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        final store = AppStore(
          authRepository: _Auth(),
          financeRepository: _Finance(),
          csvExportService: _Csv(),
        );
        await store.initialize();
        await store.generateDemoData();
        final controller = ThemeModeController(preferences, initialMode: theme);
        await tester.pumpWidget(
          ProviderScope(
            key: UniqueKey(),
            overrides: [
              appStoreProvider.overrideWith((ref) => store),
              themeModeControllerProvider.overrideWith((ref) => controller),
            ],
            child: QuickLedgerApp(
              store: store,
              themeModeController: controller,
            ),
          ),
        );
        await tester.pump(const Duration(seconds: 1));
        for (final route in routes) {
          final name = '${route.substring(1)}_${sizeName}_${theme.name}';
          if (_only.isNotEmpty && !name.contains(_only)) continue;
          GoRouter.of(tester.element(find.byType(Scaffold).first)).go(route);
          await tester.pump();
          await tester.pump(const Duration(seconds: 2));
          await _capture(tester, name);
          if (sizeName == 'phone') {
            final label = switch (route) {
              '/accounts' => '新增帳戶',
              '/expenses' => '新增支出',
              '/cards' => '新增',
              '/investments' => '建立庫存',
              '/orders' => '新增代訂',
              '/dashboard' => '快速記帳',
              _ => null,
            };
            if (label != null) {
              await tester.tap(find.widgetWithText(FilledButton, label).last);
              await tester.pumpAndSettle();
              if (route == '/orders') {
                await tester.tap(find.text('手動輸入'));
                await tester.pumpAndSettle();
              }
              await _capture(tester, '${name}_form');
              tester.view.viewInsets = const FakeViewPadding(bottom: 300);
              await _capture(tester, '${name}_keyboard');
              tester.view.resetViewInsets();
              final dialogContext = tester.element(find.byType(Scaffold).first);
              Navigator.of(dialogContext, rootNavigator: true).pop();
              await tester.pumpAndSettle();
            }
          }
        }
      }
    }
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  }, skip: _out.isEmpty);
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
