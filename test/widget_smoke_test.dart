import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:quick_ledger/application/app_store.dart';
import 'package:quick_ledger/application/providers.dart';
import 'package:quick_ledger/data/ocr_models.dart';
import 'package:quick_ledger/data/repositories.dart';
import 'package:quick_ledger/domain/models.dart';
import 'package:quick_ledger/main.dart';
import 'package:quick_ledger/presentation/pages/dashboard_page.dart';
import 'package:quick_ledger/presentation/pages/accounts_page.dart';
import 'package:quick_ledger/presentation/pages/cards_page.dart';
import 'package:quick_ledger/presentation/pages/expenses_page.dart';
import 'package:quick_ledger/presentation/pages/login_page.dart';
import 'package:quick_ledger/presentation/pages/investments_page.dart';
import 'package:quick_ledger/presentation/pages/orders_page.dart';
import 'package:quick_ledger/presentation/import_image_picker_models.dart';
import 'package:quick_ledger/presentation/pages/reports_page.dart';
import 'package:quick_ledger/presentation/theme.dart';

void main() {
  test(
    'order editor restores the saved collection fee instead of card cost',
    () {
      const participant = OrderParticipant(
        id: 'friend',
        name: '朋友',
        isSelf: false,
        itemName: '餐點',
        itemAmountMinor: 10000,
        sharedFeeMinor: 300,
        discountMinor: 0,
        suggestedDueMinor: 10400,
        status: CollectionStatus.unpaid,
        collectionMethod: collectionMethodCash,
        collectionAccountId: systemCashAccountId,
        token: 'token',
        note: '',
      );

      expect(collectionFeeMinorForEditing(participant), 400);
    },
  );

  test('order editor keeps the self participant first after cloud reload', () {
    OrderParticipant participant(String id, {bool isSelf = false}) =>
        OrderParticipant(
          id: id,
          name: id,
          isSelf: isSelf,
          itemName: '餐點',
          itemAmountMinor: 10000,
          sharedFeeMinor: 0,
          discountMinor: 0,
          status: isSelf ? CollectionStatus.paid : CollectionStatus.unpaid,
          collectionMethod: isSelf ? '' : collectionMethodCash,
          collectionAccountId: isSelf ? null : systemCashAccountId,
          token: '$id-token',
          note: '',
        );

    final sorted = participantsWithSelfFirst([
      participant('friend-a'),
      participant('self', isSelf: true),
      participant('friend-b'),
    ]);

    expect(sorted.map((item) => item.id), ['self', 'friend-a', 'friend-b']);
  });

  test('self fee does not increase the collection overage', () {
    expect(
      nonSelfFeeDifferenceMinor(
        isSelf: const [true, false, false],
        targetSharesMinor: const [100, 200, 200],
        assignedSharesMinor: const [100, 300, 300],
      ),
      -200,
    );
  });

  test('Uber Eats screenshot selection validates cancel, type, and limits', () {
    PickedImportImage image(String name, int size, {bool withData = true}) =>
        PickedImportImage(
          name: name,
          size: size,
          bytes: withData ? base64Decode('AA==') : null,
        );

    expect(validateUberEatsImportFiles(null), isNull);
    expect(validateUberEatsImportFiles([image('receipt.png', 1024)]), isNull);
    expect(
      validateUberEatsImportFiles([
        for (var index = 0; index < 7; index++) image('$index.png', 1),
      ]),
      contains('最多'),
    );
    expect(
      validateUberEatsImportFiles([image('large.jpg', 6 * 1024 * 1024 + 1)]),
      contains('6 MB'),
    );
    expect(
      validateUberEatsImportFiles([
        image('one.webp', 6 * 1024 * 1024),
        image('two.webp', 6 * 1024 * 1024),
        image('three.webp', 6 * 1024 * 1024),
        image('four.webp', 3 * 1024 * 1024),
      ]),
      contains('20 MB'),
    );
    expect(
      validateUberEatsImportFiles([image('receipt.heic', 1024)]),
      contains('PNG'),
    );
    expect(
      validateUberEatsImportFiles([
        image('receipt.png', 1024, withData: false),
      ]),
      contains('PNG'),
    );
  });

  testWidgets('screenshot import clearly explains when a card is required', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final auth = _WidgetAuth()..signedIn = true;
    final store = await _makeStore(auth: auth);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appStoreProvider.overrideWith((ref) => store)],
        child: MaterialApp(
          theme: buildAppTheme(),
          home: const Scaffold(
            body: SingleChildScrollView(
              padding: EdgeInsets.all(18),
              child: OrdersPage(),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('從截圖匯入'));
    await tester.pumpAndSettle();
    expect(find.text('請先建立信用卡'), findsOneWidget);
    expect(find.text('前往信用卡'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'mobile create flow chooses a source and opens full-width editor',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final auth = _WidgetAuth()..signedIn = true;
      final store = await _makeStore(auth: auth, finance: _importFinance());
      await tester.pumpWidget(
        ProviderScope(
          overrides: [appStoreProvider.overrideWith((ref) => store)],
          child: MaterialApp(
            theme: buildAppTheme(),
            home: const Scaffold(
              body: SingleChildScrollView(
                padding: EdgeInsets.all(18),
                child: OrdersPage(),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('新增代訂').first);
      await tester.pumpAndSettle();
      expect(find.text('手動輸入'), findsOneWidget);
      expect(find.text('截圖辨識'), findsOneWidget);
      await tester.tap(find.text('手動輸入'));
      await tester.pumpAndSettle();

      expect(find.text('訂單資訊'), findsOneWidget);
      expect(find.text('下一步'), findsOneWidget);
      expect(tester.getSize(find.byType(AlertDialog)).width, 390);
      expect(tester.takeException(), isNull);
    },
  );

  for (final width in [390.0, 430.0, 900.0]) {
    testWidgets('Uber Eats import is responsive at ${width.toInt()}px', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final auth = _WidgetAuth()..signedIn = true;
      final store = await _makeStore(
        auth: auth,
        finance: _importFinance(),
        orderImport: const _WidgetOrderImport(),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [appStoreProvider.overrideWith((ref) => store)],
          child: MaterialApp(
            theme: buildAppTheme(),
            home: buildUberEatsImportDialogForTest(
              images: [
                _testImportImage('ue-1.png'),
                _testImportImage('ue-2.png'),
              ],
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.textContaining('不會上傳或保存'), findsOneWidget);
      expect(find.text('ue-1.png'), findsOneWidget);
      expect(find.text('ue-2.png'), findsOneWidget);
      expect(find.text('開始辨識'), findsOneWidget);
      expect(tester.takeException(), isNull);

      if (width < 600) {
        await tester.tap(find.byTooltip('往後移').first);
        await tester.pump();
        expect(
          tester.getTopLeft(find.text('ue-2.png')).dy,
          lessThan(tester.getTopLeft(find.text('ue-1.png')).dy),
        );
        await tester.tap(find.byTooltip('移除截圖').first);
        await tester.pump();
        expect(find.text('ue-2.png'), findsNothing);
        expect(tester.takeException(), isNull);
      }

      await tester.tap(find.text('開始辨識'));
      await tester.pumpAndSettle();
      expect(find.text('平台'), findsOneWidget);
      expect(find.text('付款信用卡'), findsOneWidget);
      expect(find.text('確認匯入'), findsOneWidget);
      expect(find.text('本人負擔費用'), findsOneWidget);
      expect(find.text('收款附加費'), findsOneWidget);
      expect(find.text('統一調整收款附加費'), findsOneWidget);
      expect(find.text('預計收款'), findsOneWidget);
      expect(find.text('總共收款'), findsOneWidget);
      expect(find.text('預計多收'), findsOneWidget);
      expect(find.text('分攤設定'), findsOneWidget);
      expect(find.text('本人分攤附加費'), findsOneWidget);
      expect(find.text('訂單折扣'), findsOneWidget);
      expect(find.text('手動固定'), findsOneWidget);
      expect(find.text('自動分配'), findsOneWidget);
      expect(find.text('已分配'), findsOneWidget);
      expect(find.text('重設費用分攤'), findsNothing);

      final deliverySwitch = find.byKey(
        const ValueKey('include-self-delivery'),
      );
      final serviceSwitch = find.byKey(const ValueKey('include-self-service'));
      final totalMetric = find.byKey(const ValueKey('discount-total'));
      final fixedMetric = find.byKey(const ValueKey('discount-fixed'));
      final automaticMetric = find.byKey(const ValueKey('discount-automatic'));
      final assignedMetric = find.byKey(const ValueKey('discount-assigned'));
      if (width < 600) {
        expect(
          tester.getTopLeft(serviceSwitch).dy,
          greaterThan(tester.getTopLeft(deliverySwitch).dy),
        );
        expect(
          tester.getTopLeft(fixedMetric).dy,
          tester.getTopLeft(totalMetric).dy,
        );
        expect(
          tester.getTopLeft(automaticMetric).dy,
          greaterThan(tester.getTopLeft(totalMetric).dy),
        );
      } else {
        expect(
          tester.getTopLeft(serviceSwitch).dy,
          tester.getTopLeft(deliverySwitch).dy,
        );
        expect({
          tester.getTopLeft(totalMetric).dy,
          tester.getTopLeft(fixedMetric).dy,
          tester.getTopLeft(automaticMetric).dy,
          tester.getTopLeft(assignedMetric).dy,
        }, hasLength(1));
      }
      expect(tester.takeException(), isNull);
      if (width == 430) {
        await tester.ensureVisible(deliverySwitch);
        await tester.pumpAndSettle();
        expect(tester.widget<Switch>(deliverySwitch).value, isFalse);
        await tester.tap(deliverySwitch);
        await tester.pump();
        expect(tester.widget<Switch>(deliverySwitch).value, isTrue);
        await tester.tap(deliverySwitch);
        await tester.pump();
      }
      if (width == 390) {
        await tester.ensureVisible(
          find.byKey(const ValueKey('fee-plus-收款附加費')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('fee-plus-收款附加費')));
        await tester.pump();
        expect(find.byTooltip('已固定，點擊恢復自動'), findsOneWidget);
        expect(find.textContaining('目前多收'), findsOneWidget);
        await tester.tap(find.text('確認匯入'));
        await tester.pumpAndSettle();
        expect(store.data.orders, hasLength(1));
        expect(store.data.orders.single.name, '測試代訂');
        expect(store.data.orders.single.expectedCollectionResultMinor, 100);
      }
    });
  }

  testWidgets('mobile import highlights low-confidence OCR fields', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final auth = _WidgetAuth()..signedIn = true;
    final store = await _makeStore(
      auth: auth,
      finance: _importFinance(),
      orderImport: const _WidgetOrderImport(lowConfidence: true),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appStoreProvider.overrideWith((ref) => store)],
        child: MaterialApp(
          theme: buildAppTheme(),
          home: buildUberEatsImportDialogForTest(
            images: [_testImportImage('ue.png')],
          ),
        ),
      ),
    );

    await tester.tap(find.text('開始辨識'));
    await tester.pumpAndSettle();
    expect(find.text('總額（元）・待確認'), findsOneWidget);
    expect(find.text('姓名（自己）・待確認'), findsOneWidget);
    expect(find.text('請確認：請確認本人・黃色欄位需核對'), findsOneWidget);
    expect(find.textContaining('使用瀏覽器本機 OCR'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('mobile OCR shows progress and allows retry after failure', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = _PendingWidgetOrderImport();
    final auth = _WidgetAuth()..signedIn = true;
    final store = await _makeStore(
      auth: auth,
      finance: _importFinance(),
      orderImport: repository,
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appStoreProvider.overrideWith((ref) => store)],
        child: MaterialApp(
          theme: buildAppTheme(),
          home: buildUberEatsImportDialogForTest(
            images: [_testImportImage('ue.png')],
          ),
        ),
      ),
    );

    await tester.tap(find.text('開始辨識'));
    await tester.pump();
    expect(find.text('正在下載測試模型'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);

    repository.completer.completeError(StateError('測試辨識失敗'));
    await tester.pumpAndSettle();
    expect(find.text('重新辨識'), findsOneWidget);
    expect(find.textContaining('測試辨識失敗'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('mobile OCR review returns to the top after recognition', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final auth = _WidgetAuth()..signedIn = true;
    final store = await _makeStore(
      auth: auth,
      finance: _importFinance(),
      orderImport: const _WidgetOrderImport(),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appStoreProvider.overrideWith((ref) => store)],
        child: MaterialApp(
          theme: buildAppTheme(),
          home: buildUberEatsImportDialogForTest(
            images: [
              for (var index = 0; index < 8; index++)
                _testImportImage('ue-$index.png'),
            ],
          ),
        ),
      ),
    );

    final importScroll = find.byKey(const ValueKey('uber-eats-import-scroll'));
    await tester.drag(importScroll, const Offset(0, -500));
    await tester.pumpAndSettle();
    final scrollable = find
        .descendant(of: importScroll, matching: find.byType(Scrollable))
        .first;
    expect(
      tester.state<ScrollableState>(scrollable).position.pixels,
      greaterThan(0),
    );

    await tester.tap(find.text('開始辨識'));
    await tester.pumpAndSettle();

    expect(tester.state<ScrollableState>(scrollable).position.pixels, 0);
    expect(find.text('查看原始截圖'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('login identifies the protected LINE flow', (tester) async {
    final auth = _WidgetAuth();
    final store = await _makeStore(auth: auth);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appStoreProvider.overrideWith((ref) => store)],
        child: MaterialApp(theme: buildAppTheme(), home: const LoginPage()),
      ),
    );
    expect(find.text('歡迎使用快記帳'), findsOneWidget);
    expect(find.text('使用 LINE 登入'), findsOneWidget);
    expect(find.textContaining('Supabase Custom OIDC'), findsOneWidget);
    expect(auth.signInCalls, 0);
  });

  testWidgets('LINE official account login starts automatically once', (
    tester,
  ) async {
    final auth = _WidgetAuth();
    final store = await _makeStore(auth: auth);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appStoreProvider.overrideWith((ref) => store)],
        child: MaterialApp(
          theme: buildAppTheme(),
          home: const LoginPage(autoSignIn: true, returnPath: '/dashboard'),
        ),
      ),
    );

    await tester.pump();
    await tester.pump();

    expect(auth.signInCalls, 1);
    expect(auth.lastReturnPath, '/dashboard');
    expect(find.textContaining('正在從 LINE 官方帳號安全登入'), findsOneWidget);
  });

  testWidgets('failed automatic LINE login waits for a manual retry', (
    tester,
  ) async {
    final auth = _WidgetAuth(signInError: StateError('cancelled'));
    final store = await _makeStore(auth: auth);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appStoreProvider.overrideWith((ref) => store)],
        child: MaterialApp(
          theme: buildAppTheme(),
          home: const LoginPage(autoSignIn: true),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(auth.signInCalls, 1);
    expect(find.textContaining('LINE 登入失敗'), findsOneWidget);

    await tester.tap(find.text('使用 LINE 登入'));
    await tester.pump();
    expect(auth.signInCalls, 2);
  });

  testWidgets('LINE official account login skips an existing session', (
    tester,
  ) async {
    final auth = _WidgetAuth()..signedIn = true;
    final store = await _makeStore(auth: auth);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appStoreProvider.overrideWith((ref) => store)],
        child: MaterialApp(
          theme: buildAppTheme(),
          home: const LoginPage(autoSignIn: true),
        ),
      ),
    );

    await tester.pump();
    expect(auth.signInCalls, 0);
  });

  testWidgets('first cloud login shows local migration choices', (
    tester,
  ) async {
    final auth = _WidgetAuth()..signedIn = true;
    final now = DateTime.utc(2026, 7, 30);
    final finance = _WidgetFinance(
      cloudExists: false,
      localCandidate: AppData(
        accounts: [
          Account(
            id: 'local-account',
            userId: 'user',
            name: '本機帳戶',
            institution: '',
            type: '銀行帳戶',
            currency: 'TWD',
            openingBalanceMinor: 0,
            isActive: true,
            note: '',
            createdAt: now,
            updatedAt: now,
          ),
        ],
      ),
    );
    final store = await _makeStore(auth: auth, finance: finance);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appStoreProvider.overrideWith((ref) => store)],
        child: QuickLedgerApp(store: store),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('上傳本機資料'), findsOneWidget);
    expect(find.textContaining('1 筆既有資料'), findsOneWidget);
    expect(find.text('略過本機資料'), findsOneWidget);
  });

  testWidgets('merge action immediately shows progress feedback', (
    tester,
  ) async {
    final auth = _WidgetAuth()..signedIn = true;
    final migrationCompleter = Completer<void>();
    final finance = _WidgetFinance(
      data: const AppData(settings: UserSettings(defaultCategory: '雲端')),
      localCandidate: const AppData(
        settings: UserSettings(defaultCategory: '本機'),
      ),
      migrationCompleter: migrationCompleter,
    );
    final store = await _makeStore(auth: auth, finance: finance);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appStoreProvider.overrideWith((ref) => store)],
        child: QuickLedgerApp(store: store),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('安全合併'));
    await tester.pump();

    expect(find.text('正在處理資料，請稍候…'), findsOneWidget);
    expect(finance.lastMigrationAction, InitialMigrationAction.merge);

    migrationCompleter.complete();
    await tester.pumpAndSettle();
    expect(find.text('選擇資料合併方式'), findsNothing);
  });

  testWidgets('use-cloud failure is visible inside migration card', (
    tester,
  ) async {
    final auth = _WidgetAuth()..signedIn = true;
    final finance = _WidgetFinance(
      data: const AppData(settings: UserSettings(defaultCategory: '雲端')),
      localCandidate: const AppData(
        settings: UserSettings(defaultCategory: '本機'),
      ),
      migrationError: const FinanceConnectionException(),
    );
    final store = await _makeStore(auth: auth, finance: finance);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appStoreProvider.overrideWith((ref) => store)],
        child: QuickLedgerApp(store: store),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('使用雲端'));
    await tester.pumpAndSettle();

    expect(finance.lastMigrationAction, InitialMigrationAction.useCloud);
    expect(find.text('資料處理失敗，請稍後再試'), findsWidgets);
  });

  testWidgets('offline cloud cache is visible but read only', (tester) async {
    final auth = _WidgetAuth()..signedIn = true;
    final store = await _makeStore(
      auth: auth,
      finance: _WidgetFinance(
        data: const AppData(settings: UserSettings(defaultCategory: '離線快取')),
        offline: true,
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appStoreProvider.overrideWith((ref) => store)],
        child: QuickLedgerApp(store: store),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('目前離線，資料僅供查看'), findsOneWidget);
    expect(find.text('重新載入'), findsOneWidget);
    expect(store.canWrite, isFalse);
  });

  testWidgets('group-order self cost appears once in expense records', (
    tester,
  ) async {
    final auth = _WidgetAuth()..signedIn = true;
    final store = await _makeStore(
      auth: auth,
      finance: _WidgetFinance(
        data: AppData(
          orders: [
            GroupOrder(
              id: 'order-1',
              userId: 'user',
              name: 'Uber Eats 代訂',
              date: DateTime.now(),
              platform: 'Uber Eats',
              cardId: 'card-1',
              totalMinor: 68300,
              deliveryFeeMinor: 0,
              serviceFeeMinor: 3000,
              discountMinor: 700,
              splitMethod: SplitMethod.equal,
              note: '',
              participants: const [
                OrderParticipant(
                  id: 'self',
                  name: '均維',
                  isSelf: true,
                  itemName: '綠咖哩雞飯',
                  itemAmountMinor: 18000,
                  sharedFeeMinor: 800,
                  discountMinor: 700,
                  status: CollectionStatus.paid,
                  collectionMethod: '本人',
                  collectionAccountId: null,
                  token: 'self-token',
                  note: '',
                ),
              ],
            ),
          ],
        ),
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appStoreProvider.overrideWith((ref) => store)],
        child: MaterialApp(
          theme: buildAppTheme(),
          home: const Scaffold(
            body: SingleChildScrollView(child: ExpensesPage()),
          ),
        ),
      ),
    );

    expect(find.text('綠咖哩雞飯（代訂本人）'), findsOneWidget);
    expect(find.text(r'NT$181'), findsOneWidget);
    expect(find.textContaining('代訂本人消費'), findsOneWidget);
    expect(find.text('沒有符合條件的消費'), findsNothing);
  });

  testWidgets('import preview can remove self and last person then add again', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final auth = _WidgetAuth()..signedIn = true;
    final store = await _makeStore(
      auth: auth,
      finance: _WidgetFinance(
        data: AppData(
          cards: [
            CreditCard(
              id: 'card-1',
              userId: 'user',
              name: '測試卡',
              bank: '銀行',
              lastFour: '4936',
              closingDay: 1,
              dueDay: 15,
              autoDebitDay: 15,
              debitAccountId: 'account-1',
              isActive: true,
              note: '',
            ),
          ],
        ),
      ),
      orderImport: const _WidgetOrderImport(),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appStoreProvider.overrideWith((ref) => store)],
        child: MaterialApp(
          theme: buildAppTheme(),
          home: Scaffold(body: buildUberEatsImportDialogForTest()),
        ),
      ),
    );
    await tester.tap(find.text('開始辨識'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('import-remove-person-0')),
      findsOneWidget,
    );
    expect(find.text('姓名（自己）'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('import-remove-person-0')));
    await tester.pump();
    expect(find.text('姓名（自己）'), findsNothing);
    expect(find.text('目前沒有本人參與者'), findsOneWidget);
    expect(
      tester
          .widget<Switch>(find.byKey(const ValueKey('include-self-delivery')))
          .onChanged,
      isNull,
    );

    await tester.tap(find.byKey(const ValueKey('import-remove-person-0')));
    await tester.pump();
    expect(find.text('目前沒有人員，請新增至少一位才能匯入。'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('import-add-person')));
    await tester.pump();
    expect(
      find.byKey(const ValueKey('import-remove-person-0')),
      findsOneWidget,
    );
    expect(find.text('姓名'), findsOneWidget);
    expect(find.text('姓名（自己）'), findsNothing);
  });

  testWidgets('credit card with month-end dates can be edited', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final now = DateTime.utc(2026, 8, 6);
    final account = Account(
      id: 'account-1',
      userId: 'user',
      name: '扣款帳戶',
      institution: '銀行',
      type: '銀行帳戶',
      currency: 'TWD',
      openingBalanceMinor: 0,
      isActive: true,
      note: '',
      createdAt: now,
      updatedAt: now,
    );
    final deletedAccount = Account(
      id: 'deleted-account',
      userId: 'user',
      name: '已刪除舊帳戶',
      institution: '舊銀行',
      type: '銀行帳戶',
      currency: 'TWD',
      openingBalanceMinor: 0,
      isActive: false,
      note: '',
      createdAt: now,
      updatedAt: now,
    );
    final auth = _WidgetAuth()..signedIn = true;
    final store = await _makeStore(
      auth: auth,
      finance: _WidgetFinance(
        data: AppData(
          accounts: [account, deletedAccount],
          cards: [
            CreditCard(
              id: 'card-1',
              userId: 'user',
              name: '月底結帳卡',
              bank: '銀行',
              lastFour: '1234',
              closingDay: 29,
              dueDay: 30,
              autoDebitDay: 31,
              debitAccountId: account.id,
              isActive: true,
              note: '',
            ),
          ],
        ),
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appStoreProvider.overrideWith((ref) => store)],
        child: MaterialApp(
          theme: buildAppTheme(),
          home: const Scaffold(body: CardsPage()),
        ),
      ),
    );

    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('編輯'));
    await tester.pumpAndSettle();

    expect(find.text('編輯信用卡'), findsOneWidget);
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    expect(find.text('已刪除舊帳戶'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'credit card expands charges with bill status and unbilled total',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final now = DateTime.utc(2026, 8, 11);
      const card = CreditCard(
        id: 'card',
        userId: 'user',
        name: '明細測試卡',
        bank: '銀行',
        lastFour: '5678',
        closingDay: 15,
        dueDay: 28,
        autoDebitDay: 28,
        debitAccountId: 'bank',
        isActive: true,
        note: '',
      );
      Expense expense(String id, String item, int amount) => Expense(
        id: id,
        userId: 'user',
        date: now,
        amountMinor: amount,
        paymentMethod: PaymentMethod.creditCard,
        item: item,
        category: '餐飲',
        cardId: card.id,
        merchant: '',
        note: '',
        isNecessary: true,
      );
      final store = await _makeStore(
        auth: _WidgetAuth()..signedIn = true,
        finance: _WidgetFinance(
          data: AppData(
            cards: const [card],
            expenses: [
              expense('billed', '已入帳午餐', 10000),
              expense('unbilled', '未入帳晚餐', 25000),
            ],
            bills: [
              CardBill(
                id: 'bill',
                userId: 'user',
                cardId: card.id,
                month: '2026-08',
                chargeIds: const ['expense:billed'],
                manualAdjustmentMinor: 0,
                paidMinor: 0,
                dueDate: now,
                autoDebitDate: now,
                note: '',
              ),
            ],
          ),
        ),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [appStoreProvider.overrideWith((ref) => store)],
          child: MaterialApp(
            theme: buildAppTheme(),
            home: const Scaffold(body: CardsPage()),
          ),
        ),
      );

      expect(find.textContaining('未入帳 NT\$250'), findsOneWidget);
      await tester.tap(find.text('明細測試卡'));
      await tester.pumpAndSettle();
      expect(find.text('已入帳午餐'), findsOneWidget);
      expect(find.text('未入帳晚餐'), findsOneWidget);
      expect(find.textContaining('已列入 2026-08 帳單'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('statement reconciliation and payment history render at 390px', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final now = DateTime.now();
    final account = Account(
      id: 'bill-bank',
      userId: 'user',
      name: '帳單扣款帳戶',
      institution: '銀行',
      type: '活存',
      currency: 'TWD',
      openingBalanceMinor: 100000,
      isActive: true,
      note: '',
      createdAt: now,
      updatedAt: now,
    );
    const card = CreditCard(
      id: 'bill-card',
      userId: 'user',
      name: '帳單核對卡',
      bank: '銀行',
      lastFour: '7788',
      closingDay: 15,
      dueDay: 28,
      autoDebitDay: 28,
      debitAccountId: 'bill-bank',
      isActive: true,
      note: '',
    );
    final expense = Expense(
      id: 'bill-charge',
      userId: 'user',
      date: now,
      amountMinor: 10000,
      paymentMethod: PaymentMethod.creditCard,
      item: '核對消費',
      category: '購物',
      cardId: card.id,
      merchant: '商店',
      note: '',
      isNecessary: false,
    );
    final bill = CardBill(
      id: 'bill-detail',
      userId: 'user',
      cardId: card.id,
      month: '${now.year}-${now.month.toString().padLeft(2, '0')}',
      chargeIds: const ['expense:bill-charge'],
      manualAdjustmentMinor: 0,
      paidMinor: 4000,
      dueDate: now.add(const Duration(days: 10)),
      autoDebitDate: now.add(const Duration(days: 8)),
      note: '',
      statementAmountMinor: 12000,
      reconciliationReason: CardBillReconciliationReason.feeOrInterest,
    );
    final payment = FinancialTransaction(
      id: 'card-payment:bill-detail:first',
      userId: 'user',
      date: now,
      type: FinancialTransactionType.cardPayment,
      label: '部分繳款',
      amountMinor: 4000,
      currency: 'TWD',
      relatedEntityType: 'cardBill',
      relatedEntityId: bill.id,
      impacts: const [
        AccountImpact(
          accountId: 'bill-bank',
          amountMinor: -4000,
          currency: 'TWD',
        ),
      ],
    );
    final store = await _makeStore(
      auth: _WidgetAuth()..signedIn = true,
      finance: _WidgetFinance(
        data: AppData(
          accounts: [account],
          cards: const [card],
          expenses: [expense],
          bills: [bill],
          transactions: [payment],
        ),
      ),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appStoreProvider.overrideWith((ref) => store)],
        child: MaterialApp(
          theme: buildAppTheme(),
          home: const Scaffold(body: CardsPage()),
        ),
      ),
    );
    await tester.tap(find.text('信用卡帳單'));
    await tester.pumpAndSettle();
    expect(find.textContaining('部分繳款'), findsOneWidget);
    expect(find.text('所有狀態'), findsOneWidget);
    await tester.tap(find.textContaining('帳單核對卡').first);
    await tester.pumpAndSettle();
    expect(find.textContaining('銀行實際總額'), findsOneWidget);
    expect(find.textContaining('核對差額'), findsOneWidget);
    expect(find.text('繳款紀錄'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('account ledger opens and reuses the expense editor', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final created = DateTime.utc(2026, 8, 1);
    final store = await _makeStore(
      auth: _WidgetAuth()..signedIn = true,
      finance: _WidgetFinance(
        data: AppData(
          accounts: [
            Account(
              id: 'account',
              userId: 'user',
              name: '日常帳戶',
              institution: '測試銀行',
              type: '銀行帳戶',
              currency: 'TWD',
              openingBalanceMinor: 100000,
              isActive: true,
              note: '',
              createdAt: created,
              updatedAt: created,
            ),
          ],
          expenses: [
            Expense(
              id: 'lunch',
              userId: 'user',
              date: DateTime.utc(2026, 8, 2),
              amountMinor: 12000,
              paymentMethod: PaymentMethod.cash,
              item: '午餐',
              category: '餐飲',
              accountId: 'account',
              merchant: '',
              note: '',
              isNecessary: true,
            ),
          ],
        ),
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appStoreProvider.overrideWith((ref) => store)],
        child: MaterialApp(
          theme: buildAppTheme(),
          home: const Scaffold(
            body: SingleChildScrollView(child: AccountsPage()),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);

    await tester.ensureVisible(find.text('日常帳戶'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('日常帳戶'));
    await tester.pumpAndSettle();
    expect(find.text('日常帳戶 扣／入帳明細'), findsOneWidget);
    expect(find.text('午餐'), findsOneWidget);
    expect(find.text('期初餘額'), findsWidgets);
    await tester.tap(find.byTooltip('明細操作').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('編輯'));
    await tester.pumpAndSettle();
    expect(find.text('編輯消費'), findsOneWidget);

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(find.text('日常帳戶 扣／入帳明細'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byTooltip('明細操作').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('刪除'));
    await tester.pumpAndSettle();
    expect(find.text('刪除消費？'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, '刪除'));
    await tester.pumpAndSettle();
    expect(store.data.expenses, isEmpty);
    expect(store.accountBalance('account'), 100000);
    expect(find.text('午餐'), findsNothing);
    expect(find.text('日常帳戶 扣／入帳明細'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('balance adjustment can set a new total directly', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final now = DateTime.utc(2026, 8, 1);
    final store = await _makeStore(
      auth: _WidgetAuth()..signedIn = true,
      finance: _WidgetFinance(
        data: AppData(
          accounts: [
            Account(
              id: 'bank',
              userId: 'user',
              name: '彰銀',
              institution: '彰化銀行',
              type: '銀行帳戶',
              currency: 'TWD',
              openingBalanceMinor: 800000,
              isActive: true,
              note: '',
              createdAt: now,
              updatedAt: now,
            ),
          ],
        ),
      ),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appStoreProvider.overrideWith((ref) => store)],
        child: MaterialApp(
          theme: buildAppTheme(),
          home: const Scaffold(
            body: SingleChildScrollView(child: AccountsPage()),
          ),
        ),
      ),
    );

    final row = find.ancestor(
      of: find.text('彰銀'),
      matching: find.byType(ListTile),
    );
    await tester.tap(
      find.descendant(of: row, matching: find.byType(PopupMenuButton<String>)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('餘額調整'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('直接改總額'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '10000');
    await tester.tap(find.text('套用調整'));
    await tester.pumpAndSettle();

    expect(store.accountBalance('bank'), 1000000);
    expect(store.data.balanceAdjustments.single.amountMinor, 200000);
    expect(tester.takeException(), isNull);
  });

  test(
    'current month income and balance totals are exposed by the store',
    () async {
      final now = DateTime.now();
      final account = Account(
        id: 'bank',
        userId: 'user',
        name: '薪轉帳戶',
        institution: '',
        type: '銀行帳戶',
        currency: 'TWD',
        openingBalanceMinor: 0,
        isActive: true,
        note: '',
        createdAt: now,
        updatedAt: now,
      );
      final store = await _makeStore(
        auth: _WidgetAuth()..signedIn = true,
        finance: _WidgetFinance(
          data: AppData(
            accounts: [account],
            incomes: [
              IncomeEntry(
                id: 'income',
                userId: 'user',
                date: now,
                amountMinor: 5000000,
                item: '薪資',
                category: '薪資',
                accountId: account.id,
                note: '',
              ),
            ],
            expenses: [
              Expense(
                id: 'expense',
                userId: 'user',
                date: now,
                amountMinor: 1200000,
                paymentMethod: PaymentMethod.transfer,
                item: '房租',
                category: '房租',
                accountId: account.id,
                merchant: '',
                note: '',
                isNecessary: true,
              ),
            ],
          ),
        ),
      );

      expect(store.currentMonthIncomeDefaultMinor, 5000000);
      expect(store.currentMonthBalanceDefaultMinor, 3800000);
    },
  );

  for (final size in [
    const Size(390, 844),
    const Size(768, 1024),
    const Size(1440, 900),
  ]) {
    testWidgets('dashboard renders at ${size.width.toInt()}px', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = await _makeStore();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [appStoreProvider.overrideWith((ref) => store)],
          child: MaterialApp(
            theme: buildAppTheme(),
            home: const Scaffold(
              body: SingleChildScrollView(
                padding: EdgeInsets.all(16),
                child: DashboardPage(),
              ),
            ),
          ),
        ),
      );
      expect(find.text('財務總覽'), findsOneWidget);
      expect(find.text('本月收入'), findsOneWidget);
      expect(find.text('信用卡待繳'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('dashboard summary cards navigate to their destination pages', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = await _makeStore();
    final routes = <String, String>{
      '淨資產': '/reports',
      '本月收入': '/expenses',
      '本月支出': '/expenses',
      '信用卡待繳': '/cards',
      '存款合計': '/accounts',
      '投資現值': '/investments',
      '代墊應收款': '/orders',
      '本月代收收益': '/orders',
    };
    final router = GoRouter(
      initialLocation: '/dashboard',
      routes: [
        GoRoute(
          path: '/dashboard',
          builder: (context, state) => const Scaffold(
            body: SingleChildScrollView(
              padding: EdgeInsets.all(16),
              child: DashboardPage(),
            ),
          ),
        ),
        for (final path in routes.values.toSet())
          GoRoute(
            path: path,
            builder: (context, state) => Scaffold(body: Text(path)),
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

    for (final entry in routes.entries) {
      router.go('/dashboard');
      await tester.pumpAndSettle();
      if (find.text(entry.key).evaluate().isEmpty) {
        await tester.tap(find.text('其他財務摘要'));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.text(entry.key));
      await tester.pumpAndSettle();
      expect(router.routeInformationProvider.value.uri.path, entry.value);
    }
  });

  testWidgets('recurring expense tab shows telecom billing settings', (
    tester,
  ) async {
    final now = DateTime(2026, 8, 1);
    final store = await _makeStore(
      auth: _WidgetAuth()..signedIn = true,
      finance: _WidgetFinance(
        data: AppData(
          accounts: [
            Account(
              id: 'bank',
              userId: 'user',
              name: '電信扣款帳戶',
              institution: '銀行',
              type: '銀行帳戶',
              currency: 'TWD',
              openingBalanceMinor: 100000,
              isActive: true,
              note: '',
              createdAt: now,
              updatedAt: now,
            ),
          ],
          recurringExpenses: const [
            RecurringExpense(
              id: 'phone',
              userId: 'user',
              item: '手機月租',
              category: '訂閱',
              amountMinor: 59900,
              paymentMethod: PaymentMethod.telecomBill,
              dayOfMonth: 31,
              startMonth: '2026-08',
              telecomDebitAccountId: 'bank',
              isActive: true,
              isNecessary: true,
              note: '',
            ),
          ],
        ),
      ),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appStoreProvider.overrideWith((ref) => store)],
        child: MaterialApp(
          theme: buildAppTheme(),
          home: const Scaffold(
            body: SingleChildScrollView(child: ExpensesPage()),
          ),
        ),
      ),
    );

    await tester.tap(find.text('固定支出'));
    await tester.pumpAndSettle();
    expect(find.text('手機月租'), findsOneWidget);
    expect(find.textContaining('每月 31 日・電信帳單繳費'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('telecom payment requires an active recurring bill', (
    tester,
  ) async {
    final store = await _makeStore(
      auth: _WidgetAuth()..signedIn = true,
      finance: _WidgetFinance(
        data: const AppData(
          settings: UserSettings(
            defaultPaymentMethod: PaymentMethod.telecomBill,
          ),
        ),
      ),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appStoreProvider.overrideWith((ref) => store)],
        child: MaterialApp(
          theme: buildAppTheme(),
          home: const Scaffold(
            body: SingleChildScrollView(
              child: ExpensesPage(createOnOpen: true),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('新增消費'), findsWidgets);
    expect(find.text('請先到固定支出設定電信月租與扣款帳號'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('income editor saves into the selected account', (tester) async {
    final auth = _WidgetAuth()..signedIn = true;
    final now = DateTime(2026, 8, 7);
    final finance = _WidgetFinance(
      data: AppData(
        accounts: [
          Account(
            id: 'bank',
            userId: 'user',
            name: '薪轉帳戶',
            institution: '',
            type: '銀行帳戶',
            currency: 'TWD',
            openingBalanceMinor: 0,
            isActive: true,
            note: '',
            createdAt: now,
            updatedAt: now,
          ),
        ],
      ),
    );
    final store = await _makeStore(auth: auth, finance: finance);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appStoreProvider.overrideWith((ref) => store)],
        child: MaterialApp(
          theme: buildAppTheme(),
          home: const Scaffold(
            body: SingleChildScrollView(
              child: ExpensesPage(createIncomeOnOpen: true),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextFormField, '收入項目'), '八月薪資');
    await tester.enterText(find.widgetWithText(TextFormField, '金額'), '50000');
    await tester.tap(find.widgetWithText(FilledButton, '儲存'));
    await tester.pumpAndSettle();

    expect(store.data.incomes.single.item, '八月薪資');
    expect(store.accountBalance('bank'), 5000000);
    expect(find.text('八月薪資'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('investment page creates an unpriced snapshot in one dialog', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = await _makeStore(auth: _WidgetAuth()..signedIn = true);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appStoreProvider.overrideWith((ref) => store)],
        child: MaterialApp(
          theme: buildAppTheme(),
          home: const Scaffold(
            body: SingleChildScrollView(
              padding: EdgeInsets.all(16),
              child: InvestmentsPage(),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('create-holding')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('holding-product-symbol')),
      '0050',
    );
    await tester.enterText(
      find.byKey(const ValueKey('holding-product-name')),
      '元大台灣50',
    );
    await tester.enterText(
      find.byKey(const ValueKey('holding-quantity')),
      '10',
    );
    await tester.enterText(
      find.byKey(const ValueKey('holding-unit-cost')),
      '150',
    );
    await tester.pump();
    expect(
      tester
          .widget<FilledButton>(find.byKey(const ValueKey('save-holding')))
          .onPressed,
      isNotNull,
    );
    await tester.ensureVisible(find.byKey(const ValueKey('save-holding')));
    await tester.tap(find.byKey(const ValueKey('save-holding')));
    await tester.pumpAndSettle();

    expect(store.data.products.single.name, '元大台灣50');
    expect(store.data.products.single.currentPriceMinor, 0);
    expect(store.data.investmentAdjustments, hasLength(1));
    expect(store.data.investmentTransactions, isEmpty);
    expect(store.holdings.values.single.quantity, 10);
    expect(find.text('尚未設定目前價格'), findsOneWidget);
    expect(find.text('尚未定價'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('investment purchase previews and debits the selected account', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(768, 1024);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final now = DateTime.utc(2026, 8, 11);
    final account = Account(
      id: 'bank',
      userId: 'user',
      name: '證券交割戶',
      institution: '',
      type: '銀行帳戶',
      currency: 'TWD',
      openingBalanceMinor: 10000000,
      isActive: true,
      note: '',
      createdAt: now,
      updatedAt: now,
    );
    final store = await _makeStore(
      auth: _WidgetAuth()..signedIn = true,
      finance: _WidgetFinance(data: AppData(accounts: [account])),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appStoreProvider.overrideWith((ref) => store)],
        child: MaterialApp(
          theme: buildAppTheme(),
          home: const Scaffold(
            body: SingleChildScrollView(child: InvestmentsPage()),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('create-holding')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('新買入'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('holding-product-name')),
      '測試 ETF',
    );
    await tester.enterText(find.byKey(const ValueKey('holding-quantity')), '2');
    await tester.enterText(
      find.byKey(const ValueKey('holding-unit-cost')),
      '1000',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('holding-debit-account')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('證券交割戶').last);
    await tester.pumpAndSettle();
    expect(find.text('預計扣款 NT\$2,000'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const ValueKey('save-holding')));
    await tester.tap(find.byKey(const ValueKey('save-holding')));
    await tester.pumpAndSettle();

    expect(store.data.investmentTransactions, hasLength(1));
    expect(store.data.investmentTransactions.single.debitAccountId, 'bank');
    expect(store.accountBalance('bank'), 9800000);
    expect(tester.takeException(), isNull);
  });

  testWidgets('existing investment snapshot is prefilled and updated', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final now = DateTime.utc(2026, 8, 11);
    final product = InvestmentProduct(
      id: 'fund',
      userId: 'user',
      symbol: 'FUND',
      name: '既有基金',
      type: '基金',
      currency: 'TWD',
      currentPriceMinor: 12000,
      priceUpdatedAt: now,
      note: '',
    );
    final store = await _makeStore(
      auth: _WidgetAuth()..signedIn = true,
      finance: _WidgetFinance(
        data: AppData(
          products: [product],
          investmentAdjustments: [
            InvestmentAdjustment(
              id: 'initial',
              userId: 'user',
              productId: product.id,
              date: now.subtract(const Duration(days: 1)),
              quantityMicros: 3000000,
              averageCostMinor: 10000,
              reason: '初始',
            ),
          ],
        ),
      ),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appStoreProvider.overrideWith((ref) => store)],
        child: MaterialApp(
          theme: buildAppTheme(),
          home: const Scaffold(
            body: SingleChildScrollView(child: InvestmentsPage()),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('create-holding')));
    await tester.pumpAndSettle();
    expect(find.text('尚未設定目前價格'), findsNothing);
    expect(find.text('NT\$360'), findsWidgets);
    expect(find.text('更新庫存'), findsWidgets);
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('holding-quantity')))
          .controller
          ?.text,
      '3.0',
    );
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('holding-unit-cost')))
          .controller
          ?.text,
      '100.0',
    );
    await tester.enterText(find.byKey(const ValueKey('holding-quantity')), '4');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('save-holding')));
    await tester.pumpAndSettle();

    expect(store.data.investmentAdjustments, hasLength(2));
    expect(store.holdings['fund']?.quantity, 4);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reports render charts and statements responsively', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final auth = _WidgetAuth()..signedIn = true;
    final now = DateTime.now();
    final finance = _WidgetFinance(
      data: AppData(
        accounts: [
          Account(
            id: 'bank',
            userId: 'user',
            name: '銀行',
            institution: '',
            type: '銀行帳戶',
            currency: 'TWD',
            openingBalanceMinor: 100000,
            isActive: true,
            note: '',
            createdAt: DateTime(now.year, now.month, 1),
            updatedAt: now,
          ),
        ],
        expenses: [
          Expense(
            id: 'food',
            userId: 'user',
            date: now,
            amountMinor: 10000,
            paymentMethod: PaymentMethod.transfer,
            item: '餐飲',
            category: '餐飲',
            accountId: 'bank',
            merchant: '',
            note: '',
            isNecessary: true,
          ),
        ],
      ),
    );
    final store = await _makeStore(auth: auth, finance: finance);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appStoreProvider.overrideWith((ref) => store)],
        child: MaterialApp(
          theme: buildAppTheme(),
          home: const Scaffold(
            body: SingleChildScrollView(
              padding: EdgeInsets.all(16),
              child: ReportsPage(),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('財務報表'), findsOneWidget);
    expect(find.text('淨資產趨勢'), findsOneWidget);
    expect(find.text('近 6 個月收入／支出'), findsOneWidget);
    expect(find.text('現金流摘要'), findsOneWidget);
    final netWorthTop = tester.getTopLeft(find.text('淨資產'));
    final incomeTop = tester.getTopLeft(find.text('本期收入'));
    final expenseTop = tester.getTopLeft(find.text('本期支出'));
    expect(incomeTop.dy, netWorthTop.dy);
    expect(expenseTop.dy, greaterThan(netWorthTop.dy));
    final reportTabs = find.byWidgetPredicate(
      (widget) => widget is SegmentedButton,
    );
    expect(tester.getSize(reportTabs).width, lessThanOrEqualTo(358));
    expect(tester.takeException(), isNull);
  });
}

ImportImage _testImportImage(String name) => ImportImage(
  name: name,
  mimeType: 'image/png',
  bytes: base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
  ),
);

_WidgetFinance _importFinance() => _WidgetFinance(
  data: AppData(
    cards: [
      CreditCard(
        id: 'card-1',
        userId: 'user',
        name: '測試卡',
        bank: '銀行',
        lastFour: '4936',
        closingDay: 1,
        dueDay: 15,
        autoDebitDay: 15,
        debitAccountId: 'account-1',
        isActive: true,
        note: '',
      ),
    ],
  ),
);

Future<AppStore> _makeStore({
  _WidgetAuth? auth,
  _WidgetFinance? finance,
  OrderImportRepository? orderImport,
}) async {
  final store = AppStore(
    authRepository: auth ?? _WidgetAuth(),
    financeRepository: finance ?? _WidgetFinance(),
    csvExportService: _WidgetCsv(),
    orderImportRepository: orderImport,
  );
  await store.initialize();
  return store;
}

class _WidgetOrderImport implements OrderImportRepository {
  const _WidgetOrderImport({this.lowConfidence = false});

  final bool lowConfidence;

  @override
  Future<ImportedOrder> importUberEats(
    List<ImportImage> images, {
    OcrProgressCallback? onProgress,
  }) async => ImportedOrder(
    name: '測試代訂',
    platform: 'Uber Eats',
    date: DateTime(2026, 8, 6),
    totalMinor: 30000,
    deliveryFeeMinor: 0,
    serviceFeeMinor: 0,
    discountMinor: 0,
    paymentLastFour: '4936',
    participants: [
      ImportedParticipant(
        name: '本人',
        isSelf: true,
        itemName: '餐點一',
        itemAmountMinor: 12000,
        nameConfidence: lowConfidence ? 0.5 : 1,
      ),
      const ImportedParticipant(
        name: '同事',
        isSelf: false,
        itemName: '餐點二',
        itemAmountMinor: 18000,
      ),
    ],
    warnings: lowConfidence
        ? const ['使用瀏覽器本機 OCR，請逐項確認辨識結果', '未辨識到「您」']
        : const [],
    reconciliationDifferenceMinor: 0,
    fieldConfidence: {if (lowConfidence) 'total': 0.5},
  );
}

class _PendingWidgetOrderImport implements OrderImportRepository {
  final completer = Completer<ImportedOrder>();

  @override
  Future<ImportedOrder> importUberEats(
    List<ImportImage> images, {
    OcrProgressCallback? onProgress,
  }) {
    onProgress?.call(
      const OcrProgress(
        stage: 'model',
        progress: 0.35,
        message: '正在下載測試模型',
        engine: 'PP-OCRv5',
      ),
    );
    return completer.future;
  }
}

class _WidgetAuth implements AuthRepository {
  _WidgetAuth({this.signInError});

  final controller = StreamController<bool>.broadcast();
  final Object? signInError;
  bool signedIn = false;
  int signInCalls = 0;
  String? lastReturnPath;
  @override
  Stream<bool> get authStateChanges => controller.stream;
  @override
  String? get currentUserId => signedIn ? 'user' : null;
  @override
  String? get currentUserDisplayName => signedIn ? '測試使用者' : null;
  @override
  bool get isSignedIn => signedIn;
  @override
  Future<void> signInWithLine({String? returnPath}) async {
    signInCalls += 1;
    lastReturnPath = returnPath;
    if (signInError != null) throw signInError!;
    signedIn = true;
    controller.add(true);
  }

  @override
  Future<void> signOut() async {
    signedIn = false;
    controller.add(false);
  }
}

class _WidgetFinance implements FinanceRepository {
  _WidgetFinance({
    this.data = const AppData(),
    this.cloudExists = true,
    this.localCandidate,
    this.offline = false,
    this.migrationCompleter,
    this.migrationError,
  });

  AppData data;
  final bool cloudExists;
  AppData? localCandidate;
  final bool offline;
  final Completer<void>? migrationCompleter;
  final Object? migrationError;
  InitialMigrationAction? lastMigrationAction;
  int revision = 0;
  @override
  Future<SaveResult> clear() async {
    data = const AppData();
    return SaveResult(revision: ++revision, updatedAt: DateTime.now());
  }

  @override
  Future<FinanceSnapshot> load() async => FinanceSnapshot(
    data: data,
    revision: revision,
    cloudExists: cloudExists,
    localCandidate: localCandidate,
    isOffline: offline,
  );
  @override
  Future<SaveResult> save(AppData data) async {
    this.data = data;
    return SaveResult(revision: ++revision, updatedAt: DateTime.now());
  }

  @override
  Future<FinanceSnapshot> resolveInitialMigration(
    InitialMigrationAction action,
  ) async {
    lastMigrationAction = action;
    await migrationCompleter?.future;
    if (migrationError case final error?) throw error;
    if (action == InitialMigrationAction.uploadLocal ||
        action == InitialMigrationAction.replaceCloud) {
      data = localCandidate ?? data;
    }
    localCandidate = null;
    return load();
  }
}

class _WidgetCsv implements CsvExportService {
  @override
  Future<void> export(String fileName, List<List<Object?>> rows) async {}
}
