import 'package:web/web.dart' as web;

void navigateToOAuth(String url) => web.window.location.assign(url);

Uri currentBrowserUri() => Uri.parse(web.window.location.href);

void clearOAuthCallbackUrl() {
  final uri = currentBrowserUri();
  final query = Map<String, String>.from(uri.queryParameters)
    ..removeWhere(
      (key, _) => const {
        'code',
        'error',
        'error_code',
        'error_description',
        'auth_return',
        'auth_source',
      }.contains(key),
    );
  final clean = uri.replace(
    queryParameters: query.isEmpty ? null : query,
    fragment: '',
  );
  web.window.history.replaceState(null, '', clean.toString());
}

bool isStandaloneDisplayMode() =>
    web.window.matchMedia('(display-mode: standalone)').matches;
