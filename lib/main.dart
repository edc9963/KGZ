import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'application/app_store.dart';
import 'application/providers.dart';
import 'application/theme_mode_controller.dart';
import 'data/download_service.dart';
import 'data/local_repositories.dart';
import 'data/local_ocr_import_repository.dart';
import 'data/oauth_navigation.dart';
import 'data/supabase_finance_repository.dart';
import 'data/supabase_market_data_repository.dart';
import 'data/supabase_public_collection_repository.dart';
import 'presentation/app_shell.dart';
import 'presentation/pages/accounts_page.dart';
import 'presentation/pages/cards_page.dart';
import 'presentation/pages/collection_page.dart';
import 'presentation/pages/dashboard_page.dart';
import 'presentation/pages/expenses_page.dart';
import 'presentation/pages/investments_page.dart';
import 'presentation/pages/login_page.dart';
import 'presentation/pages/orders_page.dart';
import 'presentation/pages/reports_page.dart';
import 'presentation/pages/settings_page.dart';
import 'presentation/design_tokens.dart';
import 'presentation/theme.dart';
import 'presentation/widgets/brand_icon.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Read local preferences first (fast, no network) so even the splash
  // screen's first frame already knows the user's light/dark/system choice
  // instead of flashing light and then flipping to dark.
  final preferences = await SharedPreferences.getInstance();
  final themeModeController = ThemeModeController(
    preferences,
    initialMode: ThemeModeController.readStored(preferences),
  );
  // Get pixels on screen before doing any network/storage work below, so the
  // user sees a branded splash immediately instead of a blank page while
  // Supabase, auth and the initial cloud sync are still loading.
  runApp(_SplashApp(themeMode: themeModeController.mode));
  final bootstrap = await _bootstrapApp(preferences);
  runApp(
    ProviderScope(
      overrides: [
        appStoreProvider.overrideWith((ref) => bootstrap.store),
        themeModeControllerProvider.overrideWith((ref) => themeModeController),
      ],
      child: QuickLedgerApp(
        store: bootstrap.store,
        themeModeController: themeModeController,
        startupAuthError: bootstrap.startupAuthError,
        startupAuthNotice: bootstrap.startupAuthNotice,
      ),
    ),
  );
}

class _SplashApp extends StatelessWidget {
  const _SplashApp({required this.themeMode});

  final ThemeMode themeMode;

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: buildAppTheme(Brightness.light),
    darkTheme: buildAppTheme(Brightness.dark),
    themeMode: themeMode,
    home: Builder(
      builder: (context) => Scaffold(
        backgroundColor: context.colors.mobileBackground,
        body: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              BrandIcon(size: 72, borderRadius: 18),
              SizedBox(height: 24),
              SizedBox(
                width: 26,
                height: 26,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _BootstrapResult {
  const _BootstrapResult({
    required this.store,
    this.startupAuthError,
    this.startupAuthNotice,
  });

  final AppStore store;
  final String? startupAuthError;
  final String? startupAuthNotice;
}

Future<_BootstrapResult> _bootstrapApp(SharedPreferences preferences) async {
  final initialBrowserUri = kIsWeb ? currentBrowserUri() : null;
  final returningFromOAuth =
      initialBrowserUri?.queryParameters['auth_return'] == '1';
  final oauthStartedInPwa =
      initialBrowserUri?.queryParameters['auth_source'] == 'pwa';
  // Keep OAuth fragments (for example #access_token=...) separate from app
  // routing so Supabase can restore the session before clearing the fragment.
  usePathUrlStrategy();
  const supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://lxmxtbcrflmflpffaswc.supabase.co',
  );
  const supabaseKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
    defaultValue: 'sb_publishable_0JUi99_rguokVIrhdfsiQA_1K3O5XfS',
  );
  final supabaseConfigured = supabaseUrl.isNotEmpty && supabaseKey.isNotEmpty;
  String? startupAuthError;
  String? startupAuthNotice;
  if (supabaseConfigured) {
    await Supabase.initialize(
      url: supabaseUrl,
      publishableKey: supabaseKey,
      // LINE's iOS in-app browser may discard the PKCE verifier while it
      // leaves the app for LINE authorization. The implicit web callback is
      // self-contained, and Supabase removes its fragment after restoring the
      // session. Native builds keep the recommended PKCE flow.
      authOptions: FlutterAuthClientOptions(
        authFlowType: kIsWeb ? AuthFlowType.implicit : AuthFlowType.pkce,
        // Web callbacks are handled explicitly below before GoRouter starts.
        // This avoids a race between Flutter's URL strategy and app_links.
        detectSessionInUri: !kIsWeb,
      ),
    );
    if (initialBrowserUri case final uri? when _isOAuthCallbackUri(uri)) {
      try {
        await Supabase.instance.client.auth.getSessionFromUrl(uri);
      } on Object catch (error) {
        startupAuthError = 'LINE 登入回呼處理失敗：$error';
      } finally {
        clearOAuthCallbackUrl();
      }
      if (returningFromOAuth &&
          oauthStartedInPwa &&
          Supabase.instance.client.auth.currentSession != null &&
          !isStandaloneDisplayMode()) {
        startupAuthNotice =
            'LINE 登入已完成。若你是從已安裝的快記帳開始登入，'
            '可以關閉這個瀏覽器頁面並回到快記帳；若安裝版仍顯示未登入，'
            '請先在此瀏覽器繼續使用。';
      }
    }
  }
  final auth = supabaseConfigured
      ? SupabaseAuthRepository(Supabase.instance.client)
      : const UnconfiguredAuthRepository();
  final persistence = UserScopedSharedPreferencesPersistence(
    preferences,
    () => auth.currentUserId,
  );
  final store = AppStore(
    authRepository: auth,
    financeRepository: supabaseConfigured
        ? SupabaseFinanceRepository(
            client: Supabase.instance.client,
            cache: persistence,
            preferences: preferences,
            userIdProvider: () => auth.currentUserId,
          )
        : LocalFinanceRepository(persistence),
    csvExportService: BrowserCsvExportService(),
    orderImportRepository: const LocalUberEatsOrderImportRepository(),
    publicCollectionRepository: supabaseConfigured
        ? SupabasePublicCollectionRepository(Supabase.instance.client)
        : null,
    marketDataRepository: supabaseConfigured
        ? SupabaseMarketDataRepository(Supabase.instance.client, preferences)
        : null,
  );
  await store.initialize();
  return _BootstrapResult(
    store: store,
    startupAuthError: startupAuthError,
    startupAuthNotice: startupAuthNotice,
  );
}

class QuickLedgerApp extends StatefulWidget {
  const QuickLedgerApp({
    required this.store,
    required this.themeModeController,
    this.startupAuthError,
    this.startupAuthNotice,
    super.key,
  });
  final AppStore store;
  final ThemeModeController themeModeController;
  final String? startupAuthError;
  final String? startupAuthNotice;

  @override
  State<QuickLedgerApp> createState() => _QuickLedgerAppState();
}

class _QuickLedgerAppState extends State<QuickLedgerApp> {
  bool _showStartupAuthNotice = true;

  late final GoRouter _router = GoRouter(
    initialLocation: '/dashboard',
    refreshListenable: widget.store,
    redirect: (context, state) {
      final publicCollection = state.uri.path.startsWith('/collect/');
      final login = state.uri.path == '/login';
      if (publicCollection) return null;
      if (!widget.store.isSignedIn && !login) {
        final next = Uri.encodeQueryComponent(state.uri.toString());
        return '/login?next=$next';
      }
      if (widget.store.isSignedIn && login) {
        return safeAuthReturnPath(state.uri.queryParameters['next']);
      }
      return null;
    },
    routes: [
      GoRoute(
        path: '/login',
        builder: (context, state) => LoginPage(
          returnPath: safeAuthReturnPath(state.uri.queryParameters['next']),
          autoSignIn: state.uri.queryParameters['source'] == 'line_oa',
          startupError: widget.startupAuthError,
          standaloneMode: isStandaloneDisplayMode(),
        ),
      ),
      GoRoute(
        path: '/collect/:token',
        builder: (context, state) =>
            CollectionPage(token: state.pathParameters['token']!),
      ),
      GoRoute(path: '/line-import/:token', redirect: (_, __) => '/orders'),
      // Each branch below gets its own Navigator that `StatefulShellRoute`
      // keeps alive (as an IndexedStack) once built. Switching between the
      // bottom-nav/sidebar destinations therefore just swaps which branch is
      // on screen instead of disposing and rebuilding the destination page
      // from scratch on every tap — that full rebuild (on top of an already
      // expensive one, see `LedgerQueries`) racing the page-switch animation
      // was what caused the visible stutter/ghosting when switching tabs.
      // Branches are grouped to match `AppShell`'s `_destinations` /
      // `_workspaceTabs`: each top-level destination plus the secondary
      // workspace tab (報表/卡片/投資) that lives under it share a branch, so
      // switching between those two still preserves the *other* branches'
      // state even though it's a normal push within this branch's stack.
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            AppShell(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/dashboard',
                builder: (context, state) => const DashboardPage(),
              ),
              GoRoute(
                path: '/reports',
                builder: (context, state) => const ReportsPage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/expenses',
                builder: (context, state) => ExpensesPage(
                  createOnOpen: const {
                    '1',
                    'expense',
                  }.contains(state.uri.queryParameters['create']),
                  createIncomeOnOpen:
                      state.uri.queryParameters['create'] == 'income',
                  editExpenseId: state.uri.queryParameters['edit'],
                ),
              ),
              GoRoute(
                path: '/cards',
                builder: (context, state) => const CardsPage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/accounts',
                builder: (context, state) => const AccountsPage(),
              ),
              GoRoute(
                path: '/investments',
                builder: (context, state) => const InvestmentsPage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/orders',
                builder: (context, state) => const OrdersPage(),
                routes: [
                  GoRoute(
                    path: ':id',
                    builder: (context, state) =>
                        OrderDetailPage(orderId: state.pathParameters['id']!),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/settings',
                builder: (context, state) => const SettingsPage(),
              ),
            ],
          ),
        ],
      ),
    ],
  );

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.themeModeController,
    builder: (context, _) => MaterialApp.router(
      title: '快記帳',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(Brightness.light),
      darkTheme: buildAppTheme(Brightness.dark),
      themeMode: widget.themeModeController.mode,
      locale: const Locale('zh', 'TW'),
      supportedLocales: const [Locale('zh', 'TW')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      builder: (context, child) => Column(
        children: [
          if (_showStartupAuthNotice && widget.startupAuthNotice != null)
            MaterialBanner(
              content: Text(widget.startupAuthNotice!),
              leading: const Icon(Icons.open_in_browser),
              actions: [
                TextButton(
                  onPressed: () =>
                      setState(() => _showStartupAuthNotice = false),
                  child: const Text('知道了'),
                ),
              ],
            ),
          Expanded(child: child ?? const SizedBox.shrink()),
        ],
      ),
      routerConfig: _router,
    ),
  );
}

bool _isOAuthCallbackUri(Uri uri) {
  final parameters = <String, String>{...uri.queryParameters};
  if (uri.fragment.isNotEmpty) {
    try {
      parameters.addAll(Uri.splitQueryString(uri.fragment));
    } on FormatException {
      return false;
    }
  }
  return const {
    'access_token',
    'code',
    'error',
    'error_code',
    'error_description',
  }.any(parameters.containsKey);
}
