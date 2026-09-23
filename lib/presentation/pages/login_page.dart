import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/providers.dart';
import '../design_tokens.dart';
import '../widgets/brand_icon.dart';

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({
    this.returnPath,
    this.autoSignIn = false,
    this.startupError,
    this.standaloneMode = false,
    super.key,
  });

  final String? returnPath;
  final bool autoSignIn;
  final String? startupError;
  final bool standaloneMode;

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  bool _loading = false;
  bool _autoSignInStarted = false;

  @override
  void initState() {
    super.initState();
    if (widget.autoSignIn) {
      _autoSignInStarted = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !ref.read(appStoreProvider).isSignedIn) _login();
      });
    }
  }

  Future<void> _login() async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      await ref.read(appStoreProvider).signIn(returnPath: widget.returnPath);
    } on Object catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('LINE 登入失敗：$error')));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
    body: DecoratedBox(
      decoration: BoxDecoration(
        // A quiet wash of the app icon's own two colors: pale icon-cyan
        // fading into warm wool-cream in light mode, a cyan-tinted charcoal
        // settling into the app's true dark background at night — the same
        // "comet cyan meets warm gold" story the icon itself tells, instead
        // of the previous unrelated mint-green.
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? const [Color(0xFF102A2E), Color(0xFF14181A)]
              : const [Color(0xFFE7F6F7), Color(0xFFFBF3E4)],
        ),
      ),
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1000),
            child: Row(
              children: [
                if (MediaQuery.sizeOf(context).width >= 800)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(right: 72),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const BrandIcon(size: 60, borderRadius: 15),
                          const SizedBox(height: 28),
                          Text(
                            '每一筆都清楚，\n每一天都安心。',
                            style: Theme.of(context).textTheme.displaySmall
                                ?.copyWith(
                                  fontWeight: FontWeight.w900,
                                  height: 1.25,
                                ),
                          ),
                          const SizedBox(height: 18),
                          const Text(
                            '整合帳戶、信用卡、投資與代訂收款，'
                            '用一個清楚的總覽掌握自己的財務。',
                            style: TextStyle(fontSize: 17, height: 1.7),
                          ),
                        ],
                      ),
                    ),
                  ),
                SizedBox(
                  width: MediaQuery.sizeOf(context).width >= 800
                      ? 410
                      : MediaQuery.sizeOf(context).width - 48,
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            '歡迎使用快記帳',
                            style: Theme.of(context).textTheme.headlineMedium
                                ?.copyWith(fontWeight: FontWeight.w900),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            '登入後查看你的財務總覽',
                            style: TextStyle(color: context.colors.textMuted),
                          ),
                          if (widget.startupError case final error?) ...[
                            const SizedBox(height: 12),
                            Text(
                              error,
                              style: const TextStyle(
                                color: Colors.redAccent,
                                fontSize: 13,
                                height: 1.45,
                              ),
                            ),
                          ],
                          if (widget.autoSignIn && _autoSignInStarted) ...[
                            const SizedBox(height: 12),
                            Text(
                              '正在從 LINE 官方帳號安全登入；若授權未完成，可使用下方按鈕重試。',
                              style: TextStyle(
                                color: context.colors.textMuted,
                                fontSize: 13,
                                height: 1.45,
                              ),
                            ),
                          ],
                          if (widget.standaloneMode) ...[
                            const SizedBox(height: 12),
                            Text(
                              'LINE 授權完成後，系統可能改用一般瀏覽器開啟。'
                              '看到登入完成提示後，可回到已安裝的快記帳；'
                              '若安裝版未同步登入，請在該瀏覽器繼續使用。',
                              style: TextStyle(
                                color: context.colors.textMuted,
                                fontSize: 13,
                                height: 1.45,
                              ),
                            ),
                          ],
                          const SizedBox(height: 32),
                          FilledButton(
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFF06C755),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 17),
                            ),
                            onPressed: _loading ? null : _login,
                            child: _loading
                                ? const SizedBox.square(
                                    dimension: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.chat_bubble_rounded),
                                      SizedBox(width: 10),
                                      Text(
                                        '使用 LINE 登入',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ],
                                  ),
                          ),
                          const SizedBox(height: 20),
                          DecoratedBox(
                            decoration: BoxDecoration(
                              color: context.colors.background,
                              borderRadius: const BorderRadius.all(
                                Radius.circular(12),
                              ),
                            ),
                            child: const Padding(
                              padding: EdgeInsets.all(14),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(Icons.science_outlined, size: 20),
                                  SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      '登入由 Supabase Custom OIDC 與 LINE '
                                      'Login 保護；財務資料儲存在 Supabase 並以'
                                      '帳號權限隔離，此裝置只保留最後同步快取。',
                                      style: TextStyle(
                                        fontSize: 13,
                                        height: 1.45,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  }
}
