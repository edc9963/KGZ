import 'package:flutter/material.dart';

/// Phase-two route reserved for the server OCR review flow.
///
/// The Bot does not issue review URLs while OCR_ENABLED=false, so a guessed or
/// stale URL cannot create finance data. The authenticated review repository
/// and confirm RPC are intentionally activated together with the Cloud Run
/// deployment.
class LineImportReviewPage extends StatelessWidget {
  const LineImportReviewPage({required this.token, super.key});

  final String token;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('確認訂單辨識結果')),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Card(
          margin: const EdgeInsets.all(24),
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.document_scanner_outlined,
                  size: 52,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(height: 20),
                Text(
                  '雲端圖片辨識尚未啟用',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 12),
                const Text(
                  '目前 LINE 官方帳號不會下載或保存圖片。'
                  'Cloud Run 與 Firebase 部署完成後，這裡才會顯示'
                  '逐項可修改的辨識草稿，確認前不會寫入財務資料。',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                  child: const Text('返回'),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
