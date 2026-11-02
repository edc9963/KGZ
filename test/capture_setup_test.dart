import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quick_ledger/application/app_store.dart';
import 'package:quick_ledger/application/providers.dart';
import 'package:quick_ledger/application/theme_mode_controller.dart';
import 'package:quick_ledger/data/repositories.dart';
import 'package:quick_ledger/domain/models.dart';
import 'package:quick_ledger/presentation/pages/settings_page.dart';
import 'package:quick_ledger/presentation/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('settings issues a capture token and copies a filled script', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    String? clipboard;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          clipboard = (call.arguments as Map)['text'] as String;
        }
        return null;
      },
    );
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final capture = _CaptureSetup();
    final store = AppStore(
      authRepository: _SignedOutAuth(),
      financeRepository: _UnusedFinance(),
      csvExportService: _Csv(),
      captureSetupRepository: capture,
    );
    await store.initialize();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appStoreProvider.overrideWith((ref) => store),
          themeModeControllerProvider.overrideWith(
            (ref) => ThemeModeController(preferences),
          ),
        ],
        child: MaterialApp(
          theme: buildAppTheme(Brightness.light),
          home: const Scaffold(
            body: SingleChildScrollView(child: SettingsPage()),
          ),
        ),
      ),
    );
    await tester.tap(find.text('同步'));
    await tester.pumpAndSettle();

    expect(find.text('自動記帳'), findsOneWidget);
    expect(find.text('尚未連結 LINE 官方帳號'), findsOneWidget);
    expect(find.text('2 筆待確認'), findsOneWidget);

    await tester.tap(find.text('產生金鑰'));
    await tester.pumpAndSettle();
    expect(capture.issued, 1);
    expect(find.text('kgz_test-token'), findsOneWidget);
    expect(find.text('重新產生'), findsOneWidget);

    await tester.tap(find.text('銀行通知信（Gmail）'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('複製 Apps Script'));
    await tester.pumpAndSettle();
    expect(clipboard, contains('function runOnce()'));
    expect(
      clipboard,
      contains(
        "KGZ_URL: 'https://example.invalid/functions/v1/card-email-ingest'",
      ),
    );
    expect(clipboard, contains("KGZ_TOKEN: 'kgz_test-token'"));

    // Re-issuing asks first, because the old token stops working.
    await tester.tap(find.text('重新產生'));
    await tester.pumpAndSettle();
    expect(find.text('重新產生金鑰？'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(capture.issued, 1);
  });
}

class _CaptureSetup implements CaptureSetupRepository {
  var issued = 0;

  @override
  CaptureEndpoints get endpoints =>
      const CaptureEndpoints('https://example.invalid/functions/v1');

  @override
  Future<CaptureSetupStatus> loadStatus() async => CaptureSetupStatus(
    hasToken: issued > 0,
    lineLinked: false,
    pendingCount: 2,
    tokenCreatedAt: issued > 0 ? DateTime(2026, 11, 2, 9, 30) : null,
  );

  @override
  Future<String> issueToken() async {
    issued += 1;
    return 'kgz_test-token';
  }
}

class _SignedOutAuth implements AuthRepository {
  @override
  Stream<bool> get authStateChanges => const Stream.empty();
  @override
  String? get currentUserId => null;
  @override
  String? get currentUserDisplayName => null;
  @override
  bool get isSignedIn => false;
  @override
  Future<void> signInWithLine({String? returnPath}) async {}
  @override
  Future<void> signOut() async {}
}

class _UnusedFinance implements FinanceRepository {
  @override
  Future<FinanceSnapshot> load() async =>
      const FinanceSnapshot(data: AppData());
  @override
  Future<SaveResult> save(AppData data) => throw UnimplementedError();
  @override
  Future<SaveResult> clear() => throw UnimplementedError();
  @override
  Future<FinanceSnapshot> resolveInitialMigration(
    InitialMigrationAction action,
  ) => throw UnimplementedError();
}

class _Csv implements CsvExportService {
  @override
  Future<void> export(String fileName, List<List<Object?>> rows) async {}
}
