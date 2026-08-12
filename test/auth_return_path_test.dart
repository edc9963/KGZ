import 'package:flutter_test/flutter_test.dart';
import 'package:quick_ledger/data/local_repositories.dart';

void main() {
  test('accepts same-origin relative auth return paths', () {
    expect(
      safeAuthReturnPath('/line-import/token-1?from=line'),
      '/line-import/token-1?from=line',
    );
    expect(safeAuthReturnPath('/expenses?create=1'), '/expenses?create=1');
  });

  test('rejects external and protocol-relative auth return paths', () {
    expect(safeAuthReturnPath('https://evil.example/path'), '/dashboard');
    expect(safeAuthReturnPath('//evil.example/path'), '/dashboard');
    expect(safeAuthReturnPath('/login'), '/dashboard');
    expect(safeAuthReturnPath(null), '/dashboard');
  });
}
