void navigateToOAuth(String url) {
  throw UnsupportedError('Browser OAuth navigation is only available on web');
}

Uri? currentBrowserUri() => null;

void clearOAuthCallbackUrl() {}

bool isStandaloneDisplayMode() => false;
