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
import 'presentation/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
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
  final preferences = await SharedPreferences.getInstance();
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
  runApp(
    ProviderScope(
      overrides: [appStoreProvider.overrideWith((ref) => store)],
      child: QuickLedgerApp(
        store: store,
        startupAuthError: startupAuthError,
        startupAuthNotice: startupAuthNotice,
      ),
    ),
  );
}

class QuickLedgerApp extends StatefulWidget {
  const QuickLedgerApp({
    required this.store,
    this.startupAuthError,
    this.startupAuthNotice,
    super.key,
  });
  final AppStore store;
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
      ShellRoute(
        builder: (context, state, child) => AppShell(child: child),
        routes: [
          GoRoute(
            path: '/dashboard',
            builder: (context, state) => const DashboardPage(),
          ),
          GoRoute(
            path: '/reports',
            builder: (context, state) => const ReportsPage(),
          ),
          GoRoute(
            path: '/accounts',
            builder: (context, state) => const AccountsPage(),
          ),
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
            path: '/investments',
            builder: (context, state) => const InvestmentsPage(),
          ),
          GoRoute(
            path: '/cards',
            builder: (context, state) => const CardsPage(),
          ),
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
          GoRoute(
            path: '/settings',
            builder: (context, state) => const SettingsPage(),
          ),
        ],
      ),
    ],
  );

  @override
  Widget build(BuildContext context) => MaterialApp.router(
    title: '快記帳',
    debugShowCheckedModeBanner: false,
    theme: buildAppTheme(),
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
                onPressed: () => setState(() => _showStartupAuthNotice = false),
                child: const Text('知道了'),
              ),
            ],
          ),
        Expanded(child: child ?? const SizedBox.shrink()),
      ],
    ),
    routerConfig: _router,
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
