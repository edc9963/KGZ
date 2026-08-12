import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../application/providers.dart';
import '../../data/repositories.dart';
import '../../domain/models.dart';
import '../widgets/brand_icon.dart';
import '../widgets/common.dart';

class CollectionPage extends ConsumerStatefulWidget {
  const CollectionPage({required this.token, super.key});

  final String token;

  @override
  ConsumerState<CollectionPage> createState() => _CollectionPageState();
}

class _CollectionPageState extends ConsumerState<CollectionPage> {
  late Future<PublicCollectionDetails?> _details;
  bool _submitting = false;
  String? _submitError;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _details = ref.read(appStoreProvider).loadPublicCollection(widget.token);
  }

  Future<void> _markPending() async {
    if (_submitting) return;
    setState(() {
      _submitting = true;
      _submitError = null;
    });
    try {
      await ref
          .read(appStoreProvider)
          .markPublicCollectionPending(widget.token);
      if (!mounted) return;
      setState(_reload);
    } on Object {
      if (mounted) setState(() => _submitError = '通知失敗，請稍後再試。');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          BrandIcon(size: 28, borderRadius: 7),
          SizedBox(width: 8),
          Text('快記帳收款'),
        ],
      ),
      centerTitle: true,
    ),
    body: FutureBuilder<PublicCollectionDetails?>(
      future: _details,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return EmptyState(
            icon: Icons.cloud_off_outlined,
            title: '暫時無法載入收款資料',
            message: '請確認網路連線後再試一次。',
            action: FilledButton(
              onPressed: () => setState(_reload),
              child: const Text('重新載入'),
            ),
          );
        }
        final details = snapshot.data;
        if (details == null) {
          return const EmptyState(
            icon: Icons.link_off,
            title: '收款連結不存在',
            message: '連結可能已失效，請向收款人索取新的連結。',
          );
        }
        return _CollectionDetailsCard(
          details: details,
          submitting: _submitting,
          submitError: _submitError,
          onMarkPending: _markPending,
        );
      },
    ),
  );
}

class _CollectionDetailsCard extends StatelessWidget {
  const _CollectionDetailsCard({
    required this.details,
    required this.submitting,
    required this.submitError,
    required this.onMarkPending,
  });

  final PublicCollectionDetails details;
  final bool submitting;
  final String? submitError;
  final VoidCallback onMarkPending;

  @override
  Widget build(BuildContext context) {
    final isBankTransfer =
        details.collectionMethod == collectionMethodBankTransfer;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    details.orderName,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    dateText(details.orderDate),
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.black54),
                  ),
                  const SizedBox(height: 26),
                  _InfoRow(label: '付款人', value: details.participantName),
                  _InfoRow(label: '品項', value: details.itemName),
                  _InfoRow(
                    label: '餐點',
                    value: moneyText(details.itemAmountMinor),
                  ),
                  _InfoRow(
                    label: '費用分攤',
                    value: moneyText(details.sharedFeeMinor),
                  ),
                  _InfoRow(
                    label: '折扣分攤',
                    value: '-${moneyText(details.discountMinor)}',
                  ),
                  const Divider(height: 32),
                  Text(
                    '應付 ${moneyText(details.dueMinor)}',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    details.collectionMethod,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.black54),
                  ),
                  const SizedBox(height: 18),
                  if (isBankTransfer) ...[
                    if (details.bankQrData.isNotEmpty)
                      Center(
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: QrImageView(
                            data: details.bankQrData,
                            size: 180,
                          ),
                        ),
                      )
                    else
                      const _Notice(text: '收款人尚未設定 QR Code 內容'),
                    if (details.bankAccountInfo.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      SelectableText(
                        details.bankAccountInfo,
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ] else
                    const _Notice(text: '請以現金付款'),
                  if (details.orderNote.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Text(
                      details.orderNote,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.black54),
                    ),
                  ],
                  if (submitError case final error?) ...[
                    const SizedBox(height: 16),
                    Text(
                      error,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed:
                        details.status == CollectionStatus.unpaid && !submitting
                        ? onMarkPending
                        : null,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: submitting
                          ? const SizedBox.square(
                              dimension: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(switch (details.status) {
                              CollectionStatus.unpaid => '我已付款',
                              CollectionStatus.pending => '已通知收款人，等待確認',
                              CollectionStatus.paid => '收款人已確認',
                              CollectionStatus.cancelled => '此收款已取消',
                            }),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    '此頁不會自動確認付款結果，收款人確認後才會入帳。',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: Colors.black54),
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

class _Notice extends StatelessWidget {
  const _Notice({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: const BoxDecoration(
      color: Color(0xFFF0F7F4),
      borderRadius: BorderRadius.all(Radius.circular(12)),
    ),
    child: Padding(padding: const EdgeInsets.all(14), child: Text(text)),
  );
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      children: [
        Text(label, style: const TextStyle(color: Colors.black54)),
        const Spacer(),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
      ],
    ),
  );
}
