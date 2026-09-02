import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../application/providers.dart';
import '../../data/ocr_models.dart';
import '../../data/repositories.dart';
import '../../domain/models.dart';
import '../../domain/order_allocation.dart';
import '../import_image_picker.dart';
import '../import_image_picker_models.dart';
import '../widgets/common.dart';

const _maxImportImageCount = 6;
const _maxImportImageBytes = 6 * 1024 * 1024;
const _maxImportTotalBytes = 20 * 1024 * 1024;
const _allowedImportExtensions = {'png', 'jpg', 'jpeg', 'webp'};

@visibleForTesting
String? validateUberEatsImportFiles(List<PickedImportImage>? files) {
  if (files == null) return null;
  if (files.isEmpty) return '請至少選擇一張截圖。';
  if (files.length > _maxImportImageCount) {
    return '一次最多只能選擇 6 張截圖。';
  }
  if (files.any(
    (file) =>
        file.bytes == null ||
        file.size > _maxImportImageBytes ||
        !_allowedImportExtensions.contains(file.extension?.toLowerCase()),
  )) {
    return '僅支援 PNG、JPEG、WebP，且單張不可超過 6 MB。';
  }
  if (files.fold<int>(0, (sum, file) => sum + file.size) >
      _maxImportTotalBytes) {
    return '截圖合計不可超過 20 MB。';
  }
  return null;
}

@visibleForTesting
int collectionFeeMinorForEditing(OrderParticipant participant) {
  if (participant.isSelf) return participant.sharedFeeMinor;
  return (participant.dueMinor -
          participant.itemAmountMinor +
          participant.discountMinor)
      .clamp(0, 999999999);
}

@visibleForTesting
List<OrderParticipant> participantsWithSelfFirst(
  Iterable<OrderParticipant> participants,
) => [
  ...participants.where((participant) => participant.isSelf),
  ...participants.where((participant) => !participant.isSelf),
];

@visibleForTesting
int nonSelfFeeDifferenceMinor({
  required List<bool> isSelf,
  required List<int> targetSharesMinor,
  required List<int> assignedSharesMinor,
}) {
  if (isSelf.length != targetSharesMinor.length ||
      isSelf.length != assignedSharesMinor.length) {
    throw ArgumentError('Fee share lengths must match');
  }
  var target = 0;
  var assigned = 0;
  for (var index = 0; index < isSelf.length; index++) {
    if (isSelf[index]) continue;
    target += targetSharesMinor[index];
    assigned += assignedSharesMinor[index];
  }
  return target - assigned;
}

class OrdersPage extends ConsumerWidget {
  const OrdersPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final store = ref.watch(appStoreProvider);
    final orders = [...store.data.orders]
      ..sort((a, b) => b.date.compareTo(a.date));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PageHeader(
          title: '代訂收款',
          subtitle: '刷整筆、只算自己的支出；同事款項逐筆追蹤',
          action: Wrap(
            spacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: () => _showImportDialog(context, ref),
                icon: const Icon(Icons.document_scanner_outlined),
                label: const Text('從截圖匯入'),
              ),
              FilledButton.icon(
                onPressed: () => _showCreateMethodDialog(context, ref),
                icon: const Icon(Icons.add),
                label: const Text('新增代訂'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 22),
        ResponsiveGrid(
          children: [
            SummaryCard(
              label: '代墊應收款',
              value: moneyText(
                store.receivablesMinor,
                mask: store.data.settings.maskBalances,
              ),
              compactValue: compactMoneyText(
                store.receivablesMinor,
                mask: store.data.settings.maskBalances,
              ),
              icon: Icons.handshake_outlined,
            ),
            SummaryCard(
              label: '待確認',
              value:
                  '${orders.expand((item) => item.participants).where((item) => item.status == CollectionStatus.pending).length} 人',
              icon: Icons.hourglass_top_rounded,
              tone: const Color(0xFFE27848),
            ),
            SummaryCard(
              label: '代訂筆數',
              value: '${orders.length} 筆',
              icon: Icons.receipt_long_outlined,
            ),
          ],
        ),
        const SizedBox(height: 18),
        if (orders.isEmpty)
          EmptyState(
            icon: Icons.groups_outlined,
            title: '還沒有代訂',
            message: '建立餐點或團購代訂，系統會分開計算個人支出與應收款。',
            action: FilledButton(
              onPressed: () => _showCreateMethodDialog(context, ref),
              child: const Text('新增代訂'),
            ),
          )
        else
          for (final order in orders)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Card(
                child: InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: () => context.go('/orders/${order.id}'),
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 24,
                          child: Text('${order.participants.length}'),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                order.name,
                                style: Theme.of(context).textTheme.titleMedium
                                    ?.copyWith(fontWeight: FontWeight.w900),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${dateText(order.date)}・${order.platform}・'
                                '${store.cardById(order.cardId)?.name ?? '信用卡'}',
                              ),
                            ],
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              moneyText(order.totalMinor),
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            Text(
                              '未收 ${moneyText(order.outstandingMinor)}',
                              style: const TextStyle(color: Color(0xFFD35D2A)),
                            ),
                          ],
                        ),
                        PopupMenuButton<String>(
                          onSelected: (value) async {
                            if (value == 'edit') {
                              await _showOrderDialog(context, ref, order);
                            } else if (value == 'delete') {
                              final confirmed = await confirmDelete(
                                context,
                                '代訂',
                              );
                              if (confirmed) await store.deleteOrder(order.id);
                            }
                          },
                          itemBuilder: (context) => const [
                            PopupMenuItem(value: 'edit', child: Text('編輯')),
                            PopupMenuItem(value: 'delete', child: Text('刪除')),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
      ],
    );
  }

  Future<void> _showCreateMethodDialog(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final method = await showDialog<_OrderEntryMethod>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('新增代訂'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_note_outlined),
              title: const Text('手動輸入'),
              subtitle: const Text('自行填寫訂單、人員與分攤'),
              onTap: () =>
                  Navigator.pop(dialogContext, _OrderEntryMethod.manual),
            ),
            ListTile(
              leading: const Icon(Icons.document_scanner_outlined),
              title: const Text('截圖辨識'),
              subtitle: const Text('從 Uber Eats 截圖帶入後再確認'),
              onTap: () => Navigator.pop(dialogContext, _OrderEntryMethod.ocr),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
        ],
      ),
    );
    if (!context.mounted || method == null) return;
    if (method == _OrderEntryMethod.ocr) {
      await _showImportDialog(context, ref);
    } else {
      await _showOrderDialog(context, ref);
    }
  }

  Future<void> _showImportDialog(BuildContext context, WidgetRef ref) async {
    final store = ref.read(appStoreProvider);
    if (!store.data.cards.any((card) => card.isCredit)) {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('請先建立信用卡'),
          content: const Text('Uber Eats 截圖匯入需要指定付款信用卡。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(dialogContext);
                context.go('/cards');
              },
              child: const Text('前往信用卡'),
            ),
          ],
        ),
      );
      return;
    }
    List<PickedImportImage>? files;
    try {
      files = await pickImportImages();
    } on Object catch (error) {
      if (context.mounted) {
        await showDialog<void>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('無法開啟圖片選擇器'),
            content: Text('請用 Safari 直接開啟本網站，重新整理後再試。\n\n$error'),
            actions: [
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('知道了'),
              ),
            ],
          ),
        );
      }
      return;
    }
    if (files == null) return;
    final selectedFiles = files;
    final validationError = validateUberEatsImportFiles(selectedFiles);
    if (validationError != null) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(validationError)));
      }
      return;
    }
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _UberEatsImportDialog(
        images: [
          for (final file in selectedFiles)
            ImportImage(
              name: file.name,
              mimeType: _mimeType(file.extension),
              bytes: Uint8List.fromList(file.bytes!),
            ),
        ],
      ),
    );
  }

  String _mimeType(String? extension) => switch (extension?.toLowerCase()) {
    'jpg' || 'jpeg' => 'image/jpeg',
    'webp' => 'image/webp',
    _ => 'image/png',
  };

  Future<void> _showOrderDialog(
    BuildContext context,
    WidgetRef ref, [
    GroupOrder? existing,
  ]) async {
    final store = ref.read(appStoreProvider);
    final name = TextEditingController(text: existing?.name);
    final platform = TextEditingController(
      text: existing?.platform ?? 'foodpanda',
    );
    final total = TextEditingController(
      text: existing == null ? '' : (existing.totalMinor / 100).toString(),
    );
    final delivery = TextEditingController(
      text: existing == null
          ? '0'
          : (existing.deliveryFeeMinor / 100).toString(),
    );
    final service = TextEditingController(
      text: existing == null
          ? '0'
          : (existing.serviceFeeMinor / 100).toString(),
    );
    final discount = TextEditingController(
      text: existing == null ? '0' : (existing.discountMinor / 100).toString(),
    );
    final note = TextEditingController(text: existing?.note);
    var date = existing?.date ?? DateTime.now();
    var cardId =
        existing?.cardId ??
        store.data.cards.where((card) => card.isCredit).firstOrNull?.id;
    final splitMethod = existing?.splitMethod ?? SplitMethod.equal;
    var editorStep = 0;
    var includeSelfInDeliveryFee = existing?.includeSelfInDeliveryFee ?? false;
    var includeSelfInServiceFee = existing?.includeSelfInServiceFee ?? false;
    final defaultCollectionMethod = store.lastCollectionMethod;
    final defaultCollectionAccountId =
        defaultCollectionMethod == collectionMethodCash
        ? systemCashAccountId
        : store.defaultBankTransferAccountId;
    final drafts = existing == null
        ? [
            _ParticipantDraft.empty(isSelf: true, name: '我'),
            _ParticipantDraft.empty(
              collectionMethod: defaultCollectionMethod,
              collectionAccountId: defaultCollectionAccountId,
            ),
          ]
        : participantsWithSelfFirst(existing.participants)
              .map(
                (item) => _ParticipantDraft.fromModel(
                  item,
                  manualFee: existing.splitMethod == SplitMethod.manual,
                ),
              )
              .toList();
    bool orderAmountsUnchanged() {
      if (existing == null || existing.participants.length != drafts.length) {
        return false;
      }
      if (parseMoney(total.text) != existing.totalMinor ||
          parseMoney(delivery.text) != existing.deliveryFeeMinor ||
          parseMoney(service.text) != existing.serviceFeeMinor ||
          parseMoney(discount.text) != existing.discountMinor) {
        return false;
      }
      final existingById = {
        for (final participant in existing.participants)
          participant.id: participant,
      };
      return drafts.every((draft) {
        final participant = existingById[draft.id];
        return participant != null &&
            parseMoney(draft.amount.text) == participant.itemAmountMinor;
      });
    }

    bool feeTotalsUnchanged() =>
        existing != null &&
        parseMoney(delivery.text) == existing.deliveryFeeMinor &&
        parseMoney(service.text) == existing.serviceFeeMinor;

    String? error;
    List<int>? syncDiscounts({bool reportError = false}) {
      try {
        final shares = allocateDiscountWholeTwd(
          totalMinor: parseMoney(discount.text),
          discountEligible: [
            for (final draft in drafts) draft.discountEligible,
          ],
          participantCount: drafts.length,
          fixedSharesMinor: [
            for (final draft in drafts)
              draft.discountEligible && draft.discountIsFixed
                  ? parseMoney(draft.discount.text)
                  : null,
          ],
        );
        for (var index = 0; index < drafts.length; index++) {
          if (!drafts[index].discountIsFixed) {
            drafts[index].discount.text = (shares[index] ~/ 100).toString();
          }
        }
        return shares;
      } on FormatException catch (exception) {
        if (reportError) error = exception.message;
        return null;
      }
    }

    AllocationResult? currentAllocation({bool reportError = false}) {
      try {
        return allocateWholeTwd(
          itemAmountsMinor: [
            for (final draft in drafts) parseMoney(draft.amount.text),
          ],
          isSelf: [for (final draft in drafts) draft.isSelf],
          deliveryFeeMinor: parseMoney(delivery.text),
          serviceFeeMinor: parseMoney(service.text),
          discountMinor: parseMoney(discount.text),
          includeSelfInDeliveryFee: includeSelfInDeliveryFee,
          includeSelfInServiceFee: includeSelfInServiceFee,
          discountEligible: [
            for (final draft in drafts) draft.discountEligible,
          ],
          fixedDiscountSharesMinor: [
            for (final draft in drafts)
              draft.discountEligible && draft.discountIsFixed
                  ? parseMoney(draft.discount.text)
                  : null,
          ],
        );
      } on FormatException catch (exception) {
        if (reportError) error = exception.message;
        return null;
      }
    }

    AllocationResult? currentFeeAllocation({bool reportError = false}) {
      try {
        return allocateWholeTwd(
          itemAmountsMinor: [
            for (final draft in drafts) parseMoney(draft.amount.text),
          ],
          isSelf: [for (final draft in drafts) draft.isSelf],
          deliveryFeeMinor: parseMoney(delivery.text),
          serviceFeeMinor: parseMoney(service.text),
          discountMinor: 0,
          includeSelfInDeliveryFee: includeSelfInDeliveryFee,
          includeSelfInServiceFee: includeSelfInServiceFee,
          discountEligible: [for (final _ in drafts) false],
        );
      } on FormatException catch (exception) {
        if (reportError) error = exception.message;
        return null;
      }
    }

    void syncFees({bool resetFixed = false}) {
      final allocation = currentFeeAllocation();
      if (allocation == null) return;
      for (var index = 0; index < drafts.length; index++) {
        final draft = drafts[index];
        if (resetFixed) draft.feeFixed = false;
        if (!draft.feeFixed) {
          final automatic = splitMethod == SplitMethod.manual
              ? allocation.feeShares[index]
              : allocation.collectionFeeShares[index];
          draft.fee.text = (automatic ~/ 100).toString();
        }
      }
    }

    int feeTargetMinor(AllocationResult allocation) {
      final shares = splitMethod == SplitMethod.manual
          ? allocation.feeShares
          : allocation.collectionFeeShares;
      return [
        for (var index = 0; index < drafts.length; index++)
          if (!drafts[index].isSelf) shares[index],
      ].fold<int>(0, (sum, value) => sum + value);
    }

    int feeDifferenceMinor() {
      final allocation = currentFeeAllocation();
      if (allocation == null) return 0;
      return nonSelfFeeDifferenceMinor(
        isSelf: [for (final draft in drafts) draft.isSelf],
        targetSharesMinor: splitMethod == SplitMethod.manual
            ? allocation.feeShares
            : allocation.collectionFeeShares,
        assignedSharesMinor: [
          for (final draft in drafts) parseMoney(draft.fee.text),
        ],
      );
    }

    (int totalCollectionMinor, int resultMinor)? collectionSummary() {
      final allocation = currentAllocation();
      if (allocation == null) return null;
      var totalCollectionMinor = 0;
      var selfExpenseMinor = 0;
      for (var index = 0; index < drafts.length; index++) {
        final draft = drafts[index];
        final itemMinor = parseMoney(draft.amount.text);
        final discountMinor = allocation.discountShares[index];
        if (draft.isSelf) {
          selfExpenseMinor +=
              (itemMinor + allocation.feeShares[index] - discountMinor).clamp(
                0,
                999999999,
              );
        } else {
          totalCollectionMinor +=
              (itemMinor + parseMoney(draft.fee.text) - discountMinor).clamp(
                0,
                999999999,
              );
        }
      }
      final advanceMinor = (parseMoney(total.text) - selfExpenseMinor).clamp(
        0,
        999999999,
      );
      return (totalCollectionMinor, totalCollectionMinor - advanceMinor);
    }

    void redistributeFees() {
      final allocation = currentFeeAllocation(reportError: true);
      if (allocation == null) return;
      try {
        final collectionDrafts = drafts
            .where((draft) => !draft.isSelf)
            .toList();
        final result = redistributeFixedSharesWholeTwd(
          totalMinor: feeTargetMinor(allocation),
          fixedSharesMinor: [
            for (final draft in collectionDrafts)
              draft.feeFixed ? parseMoney(draft.fee.text) : null,
          ],
        );
        for (var index = 0; index < collectionDrafts.length; index++) {
          if (!collectionDrafts[index].feeFixed) {
            collectionDrafts[index].fee.text = (result.shares[index] ~/ 100)
                .toString();
          }
        }
        error = null;
      } on FormatException catch (exception) {
        error = exception.message;
      }
    }

    void adjustAllCollectionFees(int delta) {
      for (final draft in drafts.where((draft) => !draft.isSelf)) {
        final current = int.tryParse(draft.fee.text) ?? 0;
        draft.fee.text = (current + delta).clamp(0, 999999999).toString();
        draft.feeFixed = true;
      }
      error = null;
    }

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          insetPadding: MediaQuery.sizeOf(context).width < 600
              ? EdgeInsets.zero
              : const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
          shape: MediaQuery.sizeOf(context).width < 600
              ? const RoundedRectangleBorder()
              : null,
          title: Text(existing == null ? '新增代訂' : '編輯代訂'),
          content: SizedBox(
            width: 720,
            height: MediaQuery.sizeOf(context).width < 600
                ? MediaQuery.sizeOf(context).height - 180
                : null,
            child: SingleChildScrollView(
              child: Column(
                children: [
                  Row(
                    children: [
                      for (var index = 0; index < 3; index++) ...[
                        CircleAvatar(
                          radius: 14,
                          backgroundColor: index <= editorStep
                              ? Theme.of(context).colorScheme.primary
                              : Theme.of(
                                  context,
                                ).colorScheme.surfaceContainerHighest,
                          foregroundColor: index <= editorStep
                              ? Colors.white
                              : Theme.of(context).colorScheme.onSurfaceVariant,
                          child: Text(
                            '${index + 1}',
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(const ['訂單資訊', '人員與分攤', '確認'][index]),
                        if (index < 2) ...[
                          const SizedBox(width: 8),
                          const Expanded(child: Divider()),
                          const SizedBox(width: 8),
                        ],
                      ],
                    ],
                  ),
                  const SizedBox(height: 18),
                  if (error != null) ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFE9E4),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            Icons.error_outline,
                            color: Color(0xFFB84B3E),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              error!,
                              style: const TextStyle(
                                color: Color(0xFF8F3026),
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (editorStep == 0)
                    Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: TextField(
                            controller: name,
                            decoration: const InputDecoration(
                              labelText: '代訂名稱',
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: platform,
                            decoration: const InputDecoration(
                              labelText: '訂購平台',
                            ),
                          ),
                        ),
                      ],
                    ),
                  if (editorStep == 0) const SizedBox(height: 4),
                  if (editorStep == 0)
                    Builder(
                      builder: (context) {
                        final itemTotal = drafts.fold<int>(
                          0,
                          (sum, draft) => sum + parseMoney(draft.amount.text),
                        );
                        final calculated =
                            itemTotal +
                            parseMoney(delivery.text) +
                            parseMoney(service.text) -
                            parseMoney(discount.text);
                        final entered = parseMoney(total.text);
                        final matches = entered == calculated && calculated > 0;
                        return Row(
                          children: [
                            Expanded(
                              child: Text(
                                '明細計算：${moneyText(calculated)}'
                                '${matches ? '（金額一致）' : ''}',
                                style: TextStyle(
                                  color: matches
                                      ? const Color(0xFF0E7C66)
                                      : Colors.black54,
                                  fontWeight: matches
                                      ? FontWeight.w700
                                      : FontWeight.normal,
                                ),
                              ),
                            ),
                            TextButton(
                              onPressed: calculated <= 0
                                  ? null
                                  : () => setState(() {
                                      total.text = (calculated / 100)
                                          .toStringAsFixed(2);
                                      error = null;
                                    }),
                              child: const Text('帶入總刷卡金額'),
                            ),
                          ],
                        );
                      },
                    ),
                  if (editorStep == 0) const SizedBox(height: 12),
                  if (editorStep == 0)
                    Row(
                      children: [
                        Expanded(
                          child: InkWell(
                            onTap: () async {
                              final value = await showDatePicker(
                                context: context,
                                initialDate: date,
                                firstDate: DateTime(2000),
                                lastDate: DateTime.now().add(
                                  const Duration(days: 365),
                                ),
                              );
                              if (value != null) setState(() => date = value);
                            },
                            child: InputDecorator(
                              decoration: const InputDecoration(
                                labelText: '訂購日期',
                              ),
                              child: Text(dateText(date)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            initialValue:
                                store.data.cards.any(
                                  (item) => item.id == cardId && item.isCredit,
                                )
                                ? cardId
                                : null,
                            decoration: const InputDecoration(
                              labelText: '刷卡信用卡',
                            ),
                            items: store.data.cards
                                .where((card) => card.isCredit)
                                .map(
                                  (card) => DropdownMenuItem(
                                    value: card.id,
                                    child: Text(card.name),
                                  ),
                                )
                                .toList(),
                            onChanged: (value) =>
                                setState(() => cardId = value),
                          ),
                        ),
                      ],
                    ),
                  if (editorStep == 0) const SizedBox(height: 12),
                  if (editorStep == 0)
                    Row(
                      children: [
                        for (final field in [
                          ('總刷卡金額', total),
                          ('外送費', delivery),
                          ('服務費', service),
                          ('折扣', discount),
                        ])
                          Expanded(
                            child: Padding(
                              padding: EdgeInsets.only(
                                right: field.$1 == '折扣' ? 0 : 8,
                              ),
                              child: TextField(
                                controller: field.$2,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                decoration: InputDecoration(
                                  labelText: field.$1,
                                ),
                                onChanged: (_) => setState(() {
                                  if (field.$1 == '折扣') syncDiscounts();
                                }),
                              ),
                            ),
                          ),
                      ],
                    ),
                  if (editorStep == 1) const SizedBox(height: 12),
                  if (editorStep == 1)
                    Builder(
                      builder: (context) {
                        final fixed = drafts
                            .where(
                              (draft) =>
                                  draft.discountEligible &&
                                  draft.discountIsFixed,
                            )
                            .fold<int>(
                              0,
                              (sum, draft) =>
                                  sum + parseMoney(draft.discount.text),
                            );
                        final assigned = drafts
                            .where((draft) => draft.discountEligible)
                            .fold<int>(
                              0,
                              (sum, draft) =>
                                  sum + parseMoney(draft.discount.text),
                            );
                        return _AllocationSettingsCard(
                          hasSelf: drafts.any((draft) => draft.isSelf),
                          includeDelivery: includeSelfInDeliveryFee,
                          includeService: includeSelfInServiceFee,
                          onDeliveryChanged: (value) => setState(() {
                            includeSelfInDeliveryFee = value;
                            syncFees();
                          }),
                          onServiceChanged: (value) => setState(() {
                            includeSelfInServiceFee = value;
                            syncFees();
                          }),
                          discountTotalMinor: parseMoney(discount.text),
                          fixedDiscountMinor: fixed,
                          assignedDiscountMinor: assigned,
                        );
                      },
                    ),
                  if (editorStep == 1) const SizedBox(height: 18),
                  if (editorStep == 1)
                    _UniformFeeAdjuster(
                      peopleFees: [
                        for (final draft in drafts.where(
                          (draft) => !draft.isSelf,
                        ))
                          int.tryParse(draft.fee.text) ?? 0,
                      ],
                      onDelta: (delta) =>
                          setState(() => adjustAllCollectionFees(delta)),
                    ),
                  if (editorStep == 1) const SizedBox(height: 10),
                  if (editorStep == 1)
                    Row(
                      children: [
                        Text(
                          '參與人員與品項',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w900),
                        ),
                        const Spacer(),
                        TextButton.icon(
                          onPressed: () => setState(
                            () => drafts.add(
                              _ParticipantDraft.empty(
                                collectionMethod: defaultCollectionMethod,
                                collectionAccountId: defaultCollectionAccountId,
                              ),
                            ),
                          ),
                          icon: const Icon(Icons.person_add_alt),
                          label: const Text('新增人員'),
                        ),
                      ],
                    ),
                  if (editorStep == 1)
                    for (var index = 0; index < drafts.length; index++)
                      Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: _ParticipantEditor(
                          draft: drafts[index],
                          dueMinor:
                              (parseMoney(drafts[index].amount.text) +
                                      parseMoney(drafts[index].fee.text) -
                                      parseMoney(drafts[index].discount.text))
                                  .clamp(0, 999999999),
                          accounts: store.bankTransferAccounts,
                          canDelete: drafts.length > 1,
                          onDelete: () => setState(() {
                            drafts.removeAt(index);
                            syncDiscounts();
                            syncFees();
                          }),
                          onChanged: () => setState(() {
                            syncDiscounts();
                            syncFees();
                            error = null;
                          }),
                          onFeeDelta: (delta) => setState(() {
                            final current =
                                int.tryParse(drafts[index].fee.text) ?? 0;
                            drafts[index].fee.text = (current + delta)
                                .clamp(0, 999999999)
                                .toString();
                            drafts[index].feeFixed = true;
                            error = null;
                          }),
                          onResetFee: () => setState(() {
                            drafts[index].feeFixed = false;
                            syncFees();
                            error = null;
                          }),
                        ),
                      ),
                  if (editorStep == 1)
                    Builder(
                      builder: (context) {
                        final difference = feeDifferenceMinor();
                        final fixedCount = drafts
                            .where((draft) => !draft.isSelf && draft.feeFixed)
                            .length;
                        return _FeeRedistributionNotice(
                          differenceMinor: difference,
                          fixedCount: fixedCount,
                          onRedistribute: () => setState(redistributeFees),
                          onReset: () => setState(() {
                            syncFees(resetFixed: true);
                            error = null;
                          }),
                        );
                      },
                    ),
                  if (editorStep == 1)
                    Builder(
                      builder: (context) {
                        final summary = collectionSummary();
                        return summary == null
                            ? const SizedBox.shrink()
                            : _CollectionSummary(
                                totalCollectionMinor: summary.$1,
                                resultMinor: summary.$2,
                              );
                      },
                    ),
                  if (editorStep == 2) ...[
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.receipt_long_outlined),
                      title: Text(
                        name.text.trim().isEmpty ? '未命名代訂' : name.text.trim(),
                      ),
                      subtitle: Text(
                        '${drafts.length} 位參與者・${splitMethod.label}',
                      ),
                      trailing: Text(
                        moneyText(parseMoney(total.text)),
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (editorStep == 2)
                    TextField(
                      controller: note,
                      decoration: const InputDecoration(labelText: '備註'),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('取消'),
            ),
            if (editorStep > 0)
              OutlinedButton(
                onPressed: () => setState(() {
                  editorStep -= 1;
                  error = null;
                }),
                child: const Text('上一步'),
              ),
            FilledButton(
              onPressed: () async {
                if (editorStep == 0) {
                  if (name.text.trim().isEmpty ||
                      cardId == null ||
                      parseMoney(total.text) <= 0) {
                    setState(() => error = '請填寫代訂名稱、信用卡與總刷卡金額。');
                    return;
                  }
                  setState(() {
                    // Opening an existing order must not replace its collection
                    // amounts merely because the user is changing how to pay.
                    if (!feeTotalsUnchanged()) syncFees();
                    editorStep = 1;
                    error = null;
                  });
                  return;
                }
                if (editorStep == 1) {
                  if (drafts.any(
                    (item) =>
                        item.name.text.trim().isEmpty ||
                        item.item.text.trim().isEmpty,
                  )) {
                    setState(() => error = '請填寫所有參與人員與品項。');
                    return;
                  }
                  setState(() {
                    editorStep = 2;
                    error = null;
                  });
                  return;
                }
                final itemTotal = drafts.fold<int>(
                  0,
                  (sum, draft) => sum + parseMoney(draft.amount.text),
                );
                final fee =
                    parseMoney(delivery.text) + parseMoney(service.text);
                final discountMinor = parseMoney(discount.text);
                final discountShares = syncDiscounts(reportError: true);
                if (discountShares == null) {
                  setState(() {});
                  return;
                }
                final expected = itemTotal + fee - discountMinor;
                if (name.text.trim().isEmpty ||
                    cardId == null ||
                    drafts.any(
                      (item) =>
                          item.name.text.trim().isEmpty ||
                          item.item.text.trim().isEmpty,
                    )) {
                  setState(() => error = '請填寫名稱、信用卡與所有參與人員品項。');
                  return;
                }
                if (drafts
                    .where((item) => !item.isSelf)
                    .any(
                      (item) =>
                          !supportedCollectionMethods.contains(
                            item.collectionMethod,
                          ) ||
                          (item.collectionMethod ==
                                  collectionMethodBankTransfer &&
                              !store.bankTransferAccounts.any(
                                (account) =>
                                    account.id == item.collectionAccountId,
                              )),
                    )) {
                  setState(() => error = '請為每位參與者選擇現金，或指定有效的銀行轉入帳戶。');
                  return;
                }
                var totalMinor = parseMoney(total.text);
                if (total.text.trim().isEmpty && expected > 0) {
                  totalMinor = expected;
                  total.text = (expected / 100).toStringAsFixed(2);
                }
                if (totalMinor != expected && !orderAmountsUnchanged()) {
                  setState(
                    () => error = '金額不一致：品項＋費用－折扣應為 ${moneyText(expected)}。',
                  );
                  return;
                }
                final allocation = currentAllocation(reportError: true);
                if (allocation == null) {
                  setState(() {});
                  return;
                }
                List<int> actualFeeShares = splitMethod == SplitMethod.manual
                    ? [for (final draft in drafts) parseMoney(draft.fee.text)]
                    : allocation.feeShares;
                if (splitMethod != SplitMethod.manual &&
                    drafts.any((draft) => draft.isSelf && draft.feeFixed)) {
                  try {
                    actualFeeShares = redistributeFixedSharesWholeTwd(
                      totalMinor: fee,
                      fixedSharesMinor: [
                        for (var index = 0; index < drafts.length; index++)
                          drafts[index].isSelf
                              ? (drafts[index].feeFixed
                                    ? parseMoney(drafts[index].fee.text)
                                    : allocation.feeShares[index])
                              : null,
                      ],
                    ).shares;
                  } on FormatException catch (exception) {
                    setState(() => error = exception.message);
                    return;
                  }
                }
                final participants = <OrderParticipant>[];
                for (var index = 0; index < drafts.length; index++) {
                  final draft = drafts[index];
                  final itemMinor = parseMoney(draft.amount.text);
                  final chargedFeeMinor = parseMoney(draft.fee.text);
                  final due =
                      (itemMinor +
                              chargedFeeMinor -
                              allocation.discountShares[index])
                          .clamp(0, 999999999);
                  participants.add(
                    OrderParticipant(
                      id: draft.id ?? store.newId(),
                      name: draft.name.text.trim(),
                      isSelf: draft.isSelf,
                      itemName: draft.item.text.trim(),
                      itemAmountMinor: itemMinor,
                      sharedFeeMinor: actualFeeShares[index],
                      discountMinor: allocation.discountShares[index],
                      discountEligible: draft.discountEligible,
                      discountIsFixed: draft.discountIsFixed,
                      suggestedDueMinor: draft.isSelf ? null : due,
                      finalDueMinor: draft.isSelf
                          ? null
                          : (draft.feeFixed ? due : null),
                      status: draft.isSelf
                          ? CollectionStatus.paid
                          : draft.status,
                      collectionMethod: draft.isSelf
                          ? ''
                          : draft.collectionMethod,
                      collectionAccountId: draft.isSelf
                          ? null
                          : (draft.collectionMethod == collectionMethodCash
                                ? systemCashAccountId
                                : draft.collectionAccountId),
                      token: draft.token ?? store.newId(),
                      collectedAt: draft.collectedAt,
                      note: '',
                    ),
                  );
                }
                try {
                  await store.upsertOrder(
                    GroupOrder(
                      id: existing?.id ?? store.newId(),
                      userId: store.userId,
                      name: name.text.trim(),
                      date: date,
                      platform: platform.text.trim(),
                      cardId: cardId!,
                      totalMinor: totalMinor,
                      deliveryFeeMinor: parseMoney(delivery.text),
                      serviceFeeMinor: parseMoney(service.text),
                      discountMinor: discountMinor,
                      includeSelfInDeliveryFee: includeSelfInDeliveryFee,
                      includeSelfInServiceFee: includeSelfInServiceFee,
                      feeRoundingPolicy: FeeRoundingPolicy.ceilEachFee,
                      splitMethod: splitMethod,
                      note: note.text.trim(),
                      participants: participants,
                      billId: existing?.billId,
                      origin: existing?.origin ?? DataOrigin.user,
                    ),
                  );
                  if (dialogContext.mounted) {
                    Navigator.pop(dialogContext, true);
                  }
                } on Object catch (exception) {
                  setState(() => error = '儲存失敗：$exception');
                }
              },
              child: Text(editorStep < 2 ? '下一步' : '儲存代訂'),
            ),
          ],
        ),
      ),
    );
    if (saved == true && context.mounted) {
      showSaved(context, '代訂已儲存，清單已更新');
    }
  }
}

enum _OrderEntryMethod { manual, ocr }

class OrderEditorLauncher extends ConsumerStatefulWidget {
  const OrderEditorLauncher({required this.orderId, super.key});

  final String orderId;

  @override
  ConsumerState<OrderEditorLauncher> createState() =>
      _OrderEditorLauncherState();
}

class _OrderEditorLauncherState extends ConsumerState<OrderEditorLauncher> {
  bool _opened = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_opened) return;
    _opened = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final order = ref
          .read(appStoreProvider)
          .data
          .orders
          .where((item) => item.id == widget.orderId)
          .firstOrNull;
      if (order != null) {
        await const OrdersPage()._showOrderDialog(context, ref, order);
      }
      if (mounted) Navigator.pop(context);
    });
  }

  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: CircularProgressIndicator()));
}

@visibleForTesting
Widget buildUberEatsImportDialogForTest({
  List<ImportImage> images = const [],
}) => _UberEatsImportDialog(images: images);

class _UberEatsImportDialog extends ConsumerStatefulWidget {
  const _UberEatsImportDialog({required this.images});
  final List<ImportImage> images;

  @override
  ConsumerState<_UberEatsImportDialog> createState() =>
      _UberEatsImportDialogState();
}

class _UberEatsImportDialogState extends ConsumerState<_UberEatsImportDialog> {
  late final List<ImportImage> _images = [...widget.images];
  final ScrollController _scrollController = ScrollController();
  ImportedOrder? _imported;
  List<_ImportPersonDraft> _people = [];
  final Set<String> _confirmedOrderFields = {};
  bool _loading = false;
  bool _recognitionAttempted = false;
  OcrProgress? _ocrProgress;
  String? _error;
  bool _includeDelivery = false;
  bool _includeService = false;
  String? _cardId;
  DateTime _date = DateTime.now();
  final _name = TextEditingController();
  final _platform = TextEditingController(text: 'Uber Eats');
  final _total = TextEditingController();
  final _delivery = TextEditingController();
  final _service = TextEditingController();
  final _discount = TextEditingController();

  int? _wholeMinor(TextEditingController controller) {
    final value = int.tryParse(controller.text.trim());
    return value == null ? null : value * 100;
  }

  Future<void> _recognize() async {
    setState(() {
      _loading = true;
      _recognitionAttempted = true;
      _ocrProgress = null;
      _error = null;
      _confirmedOrderFields.clear();
    });
    try {
      final imported = await ref
          .read(appStoreProvider)
          .importUberEats(
            _images,
            onProgress: (progress) {
              if (!mounted) return;
              setState(() => _ocrProgress = progress);
            },
          );
      final store = ref.read(appStoreProvider);
      final matches = store.data.cards
          .where(
            (card) =>
                card.isCredit && card.lastFour == imported.paymentLastFour,
          )
          .toList();
      setState(() {
        _imported = imported;
        _name.text = imported.name;
        _platform.text = imported.platform;
        _date = imported.date;
        _total.text = _integerText(imported.totalMinor);
        _delivery.text = _integerText(imported.deliveryFeeMinor);
        _service.text = _integerText(imported.serviceFeeMinor);
        _discount.text = _integerText(imported.discountMinor);
        _cardId = matches.length == 1 ? matches.single.id : null;
        _people = [
          for (final person in imported.participants)
            _ImportPersonDraft(
              name: TextEditingController(
                text: person.isSelf
                    ? person.name
                    : _knownParticipantName(person.name, store.data.orders),
              ),
              item: TextEditingController(text: person.itemName),
              amount: TextEditingController(
                text: _integerText(person.itemAmountMinor),
              ),
              fee: TextEditingController(text: '0'),
              feeFixed: false,
              isSelf: person.isSelf,
              discountEligible: false,
              discountIsFixed: false,
              discount: TextEditingController(text: '0'),
              nameConfidence: person.nameConfidence,
              itemConfidence: person.itemConfidence,
              amountConfidence: person.amountConfidence,
            ),
        ];
        if (_hasFractionalAmounts(imported)) {
          _error = '辨識結果含非整數新台幣；相關欄位已留白，請人工填入整數元。';
        }
        _syncFees(resetFixed: true);
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _scrollController.hasClients) {
          _scrollController.jumpTo(0);
        }
      });
    } on Object catch (error) {
      setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _integerText(int minor) =>
      minor % 100 == 0 ? (minor ~/ 100).toString() : '';

  bool _hasFractionalAmounts(ImportedOrder order) => [
    order.totalMinor,
    order.deliveryFeeMinor,
    order.serviceFeeMinor,
    order.discountMinor,
    ...order.participants.map((person) => person.itemAmountMinor),
  ].any((value) => value % 100 != 0);

  AllocationResult? _allocation({bool reportError = false}) {
    final values = [
      _total,
      _delivery,
      _service,
      _discount,
    ].map(_wholeMinor).toList();
    final itemValues = _people
        .map((person) => _wholeMinor(person.amount))
        .toList();
    if (values.any((value) => value == null) ||
        itemValues.any((value) => value == null)) {
      if (reportError) setState(() => _error = '所有金額都必須是整數元。');
      return null;
    }
    try {
      return allocateWholeTwd(
        itemAmountsMinor: itemValues.cast<int>(),
        isSelf: [for (final person in _people) person.isSelf],
        deliveryFeeMinor: values[1]!,
        serviceFeeMinor: values[2]!,
        discountMinor: values[3]!,
        includeSelfInDeliveryFee: _includeDelivery,
        includeSelfInServiceFee: _includeService,
        discountEligible: [
          for (final person in _people) person.discountEligible,
        ],
        fixedDiscountSharesMinor: [
          for (final person in _people)
            person.discountEligible && person.discountIsFixed
                ? _wholeMinor(person.discount)
                : null,
        ],
      );
    } on FormatException catch (error) {
      if (reportError) setState(() => _error = error.message);
      return null;
    }
  }

  AllocationResult? _feeAllocation({bool reportError = false}) {
    final feeValues = [_delivery, _service].map(_wholeMinor).toList();
    final itemValues = _people
        .map((person) => _wholeMinor(person.amount))
        .toList();
    if (feeValues.any((value) => value == null) ||
        itemValues.any((value) => value == null)) {
      if (reportError) _error = '所有金額都必須是整數元。';
      return null;
    }
    try {
      return allocateWholeTwd(
        itemAmountsMinor: itemValues.cast<int>(),
        isSelf: [for (final person in _people) person.isSelf],
        deliveryFeeMinor: feeValues[0]!,
        serviceFeeMinor: feeValues[1]!,
        discountMinor: 0,
        includeSelfInDeliveryFee: _includeDelivery,
        includeSelfInServiceFee: _includeService,
        discountEligible: [for (final _ in _people) false],
      );
    } on FormatException catch (error) {
      if (reportError) _error = error.message;
      return null;
    }
  }

  void _syncFees({bool resetFixed = false}) {
    final allocation = _feeAllocation();
    if (allocation == null) return;
    for (var index = 0; index < _people.length; index++) {
      final person = _people[index];
      if (resetFixed) person.feeFixed = false;
      if (!person.feeFixed) {
        person.fee.text = (allocation.collectionFeeShares[index] ~/ 100)
            .toString();
      }
    }
  }

  int _feeDifferenceMinor() {
    final allocation = _feeAllocation();
    if (allocation == null) return 0;
    final target = allocation.collectionFeeShares.fold<int>(
      0,
      (sum, value) => sum + value,
    );
    final assigned = _people.fold<int>(
      0,
      (sum, person) => sum + (_wholeMinor(person.fee) ?? 0),
    );
    return target - assigned;
  }

  (int totalCollectionMinor, int resultMinor)? _collectionSummary() {
    final allocation = _allocation();
    if (allocation == null) return null;
    var totalCollectionMinor = 0;
    var selfExpenseMinor = 0;
    for (var index = 0; index < _people.length; index++) {
      final person = _people[index];
      final itemMinor = _wholeMinor(person.amount) ?? 0;
      final discountMinor = allocation.discountShares[index];
      if (person.isSelf) {
        selfExpenseMinor +=
            (itemMinor + allocation.feeShares[index] - discountMinor).clamp(
              0,
              999999999,
            );
      } else {
        totalCollectionMinor +=
            (itemMinor + (_wholeMinor(person.fee) ?? 0) - discountMinor).clamp(
              0,
              999999999,
            );
      }
    }
    final totalMinor = _wholeMinor(_total) ?? 0;
    final advanceMinor = (totalMinor - selfExpenseMinor).clamp(0, 999999999);
    return (totalCollectionMinor, totalCollectionMinor - advanceMinor);
  }

  void _redistributeFees() {
    final allocation = _feeAllocation(reportError: true);
    if (allocation == null) return;
    try {
      final result = redistributeFixedSharesWholeTwd(
        totalMinor: allocation.collectionFeeShares.fold<int>(
          0,
          (sum, value) => sum + value,
        ),
        fixedSharesMinor: [
          for (final person in _people)
            person.feeFixed ? _wholeMinor(person.fee) : null,
        ],
      );
      for (var index = 0; index < _people.length; index++) {
        if (!_people[index].feeFixed) {
          _people[index].fee.text = (result.shares[index] ~/ 100).toString();
        }
      }
      _error = null;
    } on FormatException catch (error) {
      _error = error.message;
    }
  }

  void _adjustAllCollectionFees(int delta) {
    for (final person in _people.where((person) => !person.isSelf)) {
      final current = int.tryParse(person.fee.text) ?? 0;
      person.fee.text = (current + delta).clamp(0, 999999999).toString();
      person.feeFixed = true;
    }
    _error = null;
  }

  void _syncDiscounts() {
    final total = _wholeMinor(_discount);
    if (total == null) return;
    try {
      final shares = allocateDiscountWholeTwd(
        totalMinor: total,
        discountEligible: [
          for (final person in _people) person.discountEligible,
        ],
        participantCount: _people.length,
        fixedSharesMinor: [
          for (final person in _people)
            person.discountEligible && person.discountIsFixed
                ? _wholeMinor(person.discount)
                : null,
        ],
      );
      for (var index = 0; index < _people.length; index++) {
        if (!_people[index].discountIsFixed) {
          _people[index].discount.text = (shares[index] ~/ 100).toString();
        }
      }
      _error = null;
    } on FormatException {
      // The validation message is shown when the user confirms the import.
    }
  }

  bool get _hasSelf => _people.any((person) => person.isSelf);

  void _addPerson() {
    setState(() {
      _people.add(_ImportPersonDraft.empty());
      _syncDiscounts();
      _syncFees();
      _error = null;
    });
  }

  void _removePerson(int index) {
    setState(() {
      final removedSelf = _people[index].isSelf;
      _people.removeAt(index).dispose();
      if (removedSelf && !_hasSelf) {
        _includeDelivery = false;
        _includeService = false;
      }
      _syncDiscounts();
      _syncFees();
      _error = null;
    });
  }

  Future<void> _save() async {
    final store = ref.read(appStoreProvider);
    if (_name.text.trim().isEmpty ||
        _cardId == null ||
        _people.isEmpty ||
        _people.any((person) => person.name.text.trim().isEmpty)) {
      setState(() => _error = '請確認名稱、信用卡與所有參與者姓名。');
      return;
    }
    final allocation = _allocation(reportError: true);
    if (allocation == null) return;
    final feeAllocation = _feeAllocation(reportError: true);
    if (feeAllocation == null) return;
    final totalMinor = _wholeMinor(_total)!;
    final itemTotal = _people.fold<int>(
      0,
      (sum, person) => sum + _wholeMinor(person.amount)!,
    );
    final expected =
        itemTotal +
        _wholeMinor(_delivery)! +
        _wholeMinor(_service)! -
        _wholeMinor(_discount)!;
    final difference = totalMinor - expected;
    final lowConfidence = importedLowConfidenceIssues();
    final issues = <String>[
      if (difference != 0) '品項＋費用－折扣與總額相差 ${moneyText(difference.abs())}',
      ...lowConfidence,
    ];
    if (issues.isNotEmpty) {
      final proceed =
          await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('仍有資料需要確認'),
              content: Text(
                '${issues.map((issue) => '• $issue').join('\n')}\n\n'
                '已對照原圖並確認仍要匯入嗎？',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('返回修正'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('仍要匯入'),
                ),
              ],
            ),
          ) ??
          false;
      if (!proceed) return;
    }

    var actualFeeShares = allocation.feeShares;
    if (_people.any((person) => person.isSelf && person.feeFixed)) {
      try {
        actualFeeShares = redistributeFixedSharesWholeTwd(
          totalMinor: _wholeMinor(_delivery)! + _wholeMinor(_service)!,
          fixedSharesMinor: [
            for (var index = 0; index < _people.length; index++)
              _people[index].isSelf
                  ? (_people[index].feeFixed
                        ? _wholeMinor(_people[index].fee)
                        : allocation.feeShares[index])
                  : null,
          ],
        ).shares;
      } on FormatException catch (error) {
        setState(() => _error = error.message);
        return;
      }
    }
    final participants = <OrderParticipant>[];
    for (var i = 0; i < _people.length; i++) {
      final draft = _people[i];
      final chargedFee = _wholeMinor(draft.fee)!;
      final suggestedDue =
          (_wholeMinor(draft.amount)! +
                  chargedFee -
                  allocation.discountShares[i])
              .clamp(0, 999999999);
      participants.add(
        OrderParticipant(
          id: store.newId(),
          name: draft.name.text.trim(),
          isSelf: draft.isSelf,
          itemName: '餐點',
          itemAmountMinor: _wholeMinor(draft.amount)!,
          sharedFeeMinor: actualFeeShares[i],
          discountMinor: allocation.discountShares[i],
          discountEligible: draft.discountEligible,
          discountIsFixed: draft.discountIsFixed,
          suggestedDueMinor: draft.isSelf ? null : suggestedDue,
          finalDueMinor: draft.isSelf || !draft.feeFixed ? null : suggestedDue,
          status: draft.isSelf
              ? CollectionStatus.paid
              : CollectionStatus.unpaid,
          collectionMethod: draft.isSelf ? '' : store.lastCollectionMethod,
          collectionAccountId: draft.isSelf
              ? null
              : (store.lastCollectionMethod == collectionMethodCash
                    ? systemCashAccountId
                    : store.defaultBankTransferAccountId),
          token: store.newId(),
          note: '',
        ),
      );
    }
    final imported = _imported!;
    final orderId = store.newId();
    await store.upsertOrder(
      GroupOrder(
        id: orderId,
        userId: store.userId,
        name: _name.text.trim(),
        date: _date,
        platform: _platform.text.trim(),
        cardId: _cardId!,
        totalMinor: totalMinor,
        deliveryFeeMinor: _wholeMinor(_delivery)!,
        serviceFeeMinor: _wholeMinor(_service)!,
        discountMinor: _wholeMinor(_discount)!,
        includeSelfInDeliveryFee: _includeDelivery,
        includeSelfInServiceFee: _includeService,
        feeRoundingPolicy: FeeRoundingPolicy.ceilEachFee,
        importSource: 'uberEatsScreenshot',
        importWarnings: imported.warnings,
        reconciliationDifferenceMinor: difference,
        paymentLastFour: imported.paymentLastFour,
        splitMethod: SplitMethod.equal,
        note: imported.warnings.join('；'),
        participants: participants,
      ),
    );
    if (!store.data.orders.any((order) => order.id == orderId)) {
      if (mounted) {
        setState(() => _error = store.lastSyncError ?? '儲存失敗，資料尚未寫入。');
      }
      return;
    }
    if (mounted) Navigator.pop(context);
  }

  List<String> importedLowConfidenceIssues() {
    final imported = _imported;
    if (imported == null) return const [];
    final issues = <String>[];
    if (imported.fieldConfidence.entries.any(
      (entry) =>
          entry.value < 0.75 && !_confirmedOrderFields.contains(entry.key),
    )) {
      issues.add('部分訂單金額為低信心 OCR 結果');
    }
    if (_people.any(
      (person) =>
          person.nameConfidence < 0.75 || person.amountConfidence < 0.75,
    )) {
      issues.add('部分參與者或金額為低信心 OCR 結果');
    }
    if (imported.warnings.any((warning) => warning.contains('未辨識到「您」'))) {
      issues.add('本人身分為系統暫時猜測');
    }
    return issues;
  }

  String _conciseImportWarning() {
    final imported = _imported!;
    final messages = <String>[];
    if (imported.warnings.any((warning) => warning.contains('未辨識到「您」'))) {
      messages.add('請確認本人');
    }
    if (imported.reconciliationDifferenceMinor != 0) {
      messages.add(
        '訂單差額 ${moneyText(imported.reconciliationDifferenceMinor.abs())}',
      );
    }
    if (importedLowConfidenceIssues().isNotEmpty ||
        imported.warnings.any((warning) => warning.contains('低信心'))) {
      messages.add('黃色欄位需核對');
    }
    if (messages.isEmpty && imported.warnings.isNotEmpty) {
      messages.add('部分辨識結果需確認');
    }
    return messages.join('・');
  }

  InputDecoration _ocrDecoration(String label, {required bool lowConfidence}) =>
      InputDecoration(
        labelText: lowConfidence ? '$label・待確認' : label,
        filled: lowConfidence,
        fillColor: lowConfidence ? const Color(0xFFFFF8E8) : null,
        enabledBorder: lowConfidence
            ? const OutlineInputBorder(
                borderSide: BorderSide(color: Color(0xFFE0A11A)),
              )
            : null,
      );

  Widget _responsivePair({
    required bool compact,
    required Widget first,
    required Widget second,
    double? desktopSecondWidth,
  }) {
    if (compact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [first, const SizedBox(height: 8), second],
      );
    }
    return Row(
      children: [
        Expanded(child: first),
        const SizedBox(width: 8),
        if (desktopSecondWidth == null)
          Expanded(child: second)
        else
          SizedBox(width: desktopSecondWidth, child: second),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final store = ref.watch(appStoreProvider);
    final compact = MediaQuery.sizeOf(context).width < 600;
    final content = SingleChildScrollView(
      key: const ValueKey('uber-eats-import-scroll'),
      controller: _scrollController,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_error != null)
            Container(
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(bottom: 12),
              color: const Color(0xFFFFE9E4),
              child: Text(_error!),
            ),
          if (_imported == null) ...[
            const Text('請確認截圖順序，重疊品項會自動去除。'),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF1F7F5),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.privacy_tip_outlined, size: 20),
                  SizedBox(width: 8),
                  Expanded(child: Text('截圖只在此裝置辨識，不會上傳或保存。')),
                ],
              ),
            ),
            const ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: Text('首次辨識與模型下載'),
              childrenPadding: EdgeInsets.only(bottom: 8),
              children: [
                Text(
                  '首次使用需下載 OCR 模型；iPhone 約 5 MB、其他行動裝置約 '
                  '22 MB，電腦最高約 100 MB。建議連接 Wi‑Fi 並保持此頁開啟，'
                  '下載後會保存在此裝置。',
                ),
              ],
            ),
            if (_loading) ...[
              const SizedBox(height: 8),
              LinearProgressIndicator(
                value: (_ocrProgress?.progress ?? 0) > 0
                    ? (_ocrProgress!.progress).clamp(0, 1)
                    : null,
              ),
              const SizedBox(height: 8),
              Text(
                _ocrProgress?.message ??
                    '首次使用需下載 OCR 模型；'
                        '下載後會保存在此裝置。',
                style: const TextStyle(color: Colors.black54),
              ),
              if ((_ocrProgress?.engine ?? '').isNotEmpty)
                Text(
                  _ocrProgress!.engine,
                  style: const TextStyle(color: Colors.black45, fontSize: 12),
                ),
            ],
            for (var i = 0; i < _images.length; i++)
              Card(
                margin: const EdgeInsets.only(top: 8),
                child: ListTile(
                  leading: SizedBox(
                    width: 52,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: Image.memory(
                            _images[i].bytes,
                            fit: BoxFit.cover,
                          ),
                        ),
                        Align(
                          alignment: Alignment.topLeft,
                          child: CircleAvatar(
                            radius: 10,
                            child: Text(
                              '${i + 1}',
                              style: const TextStyle(fontSize: 10),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  title: Text(_images[i].name),
                  trailing: compact
                      ? null
                      : Wrap(
                          children: [
                            IconButton(
                              onPressed: i == 0
                                  ? null
                                  : () => setState(() {
                                      final image = _images.removeAt(i);
                                      _images.insert(i - 1, image);
                                    }),
                              icon: const Icon(Icons.arrow_upward),
                            ),
                            IconButton(
                              onPressed: i == _images.length - 1
                                  ? null
                                  : () => setState(() {
                                      final image = _images.removeAt(i);
                                      _images.insert(i + 1, image);
                                    }),
                              icon: const Icon(Icons.arrow_downward),
                            ),
                            IconButton(
                              onPressed: _images.length == 1
                                  ? null
                                  : () => setState(() => _images.removeAt(i)),
                              icon: const Icon(Icons.close),
                            ),
                          ],
                        ),
                  subtitle: compact
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${(_images[i].bytes.length / 1024).round()} KB',
                            ),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                IconButton(
                                  tooltip: '往前移',
                                  onPressed: i == 0
                                      ? null
                                      : () => setState(() {
                                          final image = _images.removeAt(i);
                                          _images.insert(i - 1, image);
                                        }),
                                  icon: const Icon(Icons.arrow_upward),
                                ),
                                IconButton(
                                  tooltip: '往後移',
                                  onPressed: i == _images.length - 1
                                      ? null
                                      : () => setState(() {
                                          final image = _images.removeAt(i);
                                          _images.insert(i + 1, image);
                                        }),
                                  icon: const Icon(Icons.arrow_downward),
                                ),
                                IconButton(
                                  tooltip: '移除截圖',
                                  onPressed: _images.length == 1
                                      ? null
                                      : () =>
                                            setState(() => _images.removeAt(i)),
                                  icon: const Icon(Icons.close),
                                ),
                              ],
                            ),
                          ],
                        )
                      : Text('${(_images[i].bytes.length / 1024).round()} KB'),
                ),
              ),
          ] else ...[
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: const Text('查看原始截圖'),
              subtitle: const Text('低信心欄位請對照原圖修正'),
              children: [
                SizedBox(
                  height: 220,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: _images.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (context, index) => ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.memory(
                        _images[index].bytes,
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            TextField(
              controller: _name,
              decoration: const InputDecoration(labelText: '代訂名稱'),
            ),
            const SizedBox(height: 8),
            _responsivePair(
              compact: compact,
              first: TextField(
                controller: _platform,
                decoration: const InputDecoration(labelText: '平台'),
              ),
              second: DropdownButtonFormField<String>(
                initialValue: _cardId,
                decoration: const InputDecoration(labelText: '付款信用卡'),
                items: [
                  for (final card in store.data.cards.where(
                    (card) => card.isCredit,
                  ))
                    DropdownMenuItem(
                      value: card.id,
                      child: Text('${card.name} ••••${card.lastFour}'),
                    ),
                ],
                onChanged: (value) => setState(() => _cardId = value),
              ),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () async {
                final selected = await showDatePicker(
                  context: context,
                  initialDate: _date,
                  firstDate: DateTime(2020),
                  lastDate: DateTime.now().add(const Duration(days: 1)),
                );
                if (selected != null) {
                  setState(
                    () => _date = DateTime(
                      selected.year,
                      selected.month,
                      selected.day,
                      _date.hour,
                      _date.minute,
                    ),
                  );
                }
              },
              icon: const Icon(Icons.calendar_today_outlined),
              label: Text('訂購日期 ${dateText(_date)}'),
            ),
            if (_imported!.warnings.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: const BoxDecoration(
                  color: Color(0xFFFFF8E8),
                  borderRadius: BorderRadius.all(Radius.circular(12)),
                ),
                child: Text('請確認：${_conciseImportWarning()}'),
              ),
            ],
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final entry in [
                  ('總額', 'total', _total),
                  ('外送費', 'delivery', _delivery),
                  ('服務費', 'service', _service),
                  ('折扣', 'discount', _discount),
                ])
                  SizedBox(
                    width: compact ? double.infinity : 165,
                    child: TextField(
                      controller: entry.$3,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration:
                          _ocrDecoration(
                            '${entry.$1}（元）',
                            lowConfidence:
                                _imported!.isLowConfidence(entry.$2) &&
                                !_confirmedOrderFields.contains(entry.$2),
                          ).copyWith(
                            helperText: entry.$2 == 'discount'
                                ? '可直接修正；再於下方勾選「有折扣」的人員'
                                : null,
                          ),
                      onChanged: (_) => setState(() {
                        _confirmedOrderFields.add(entry.$2);
                        if (entry.$2 == 'discount') {
                          _syncDiscounts();
                        }
                        _syncFees();
                      }),
                    ),
                  ),
              ],
            ),
            Builder(
              builder: (context) {
                final fixed = _people
                    .where(
                      (person) =>
                          person.discountEligible && person.discountIsFixed,
                    )
                    .fold<int>(
                      0,
                      (sum, person) =>
                          sum + (_wholeMinor(person.discount) ?? 0),
                    );
                final assigned = _people
                    .where((person) => person.discountEligible)
                    .fold<int>(
                      0,
                      (sum, person) =>
                          sum + (_wholeMinor(person.discount) ?? 0),
                    );
                final total = _wholeMinor(_discount) ?? 0;
                return _AllocationSettingsCard(
                  hasSelf: _hasSelf,
                  includeDelivery: _includeDelivery,
                  includeService: _includeService,
                  onDeliveryChanged: (value) => setState(() {
                    _includeDelivery = value;
                    _syncFees();
                  }),
                  onServiceChanged: (value) => setState(() {
                    _includeService = value;
                    _syncFees();
                  }),
                  discountTotalMinor: total,
                  fixedDiscountMinor: fixed,
                  assignedDiscountMinor: assigned,
                );
              },
            ),
            const SizedBox(height: 8),
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 4,
              children: [
                Text(
                  '參與人員與金額',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                TextButton.icon(
                  key: const ValueKey('import-add-person'),
                  onPressed: _addPerson,
                  icon: const Icon(Icons.person_add_alt),
                  label: const Text('新增人員'),
                ),
              ],
            ),
            _UniformFeeAdjuster(
              peopleFees: [
                for (final person in _people.where((person) => !person.isSelf))
                  int.tryParse(person.fee.text) ?? 0,
              ],
              onDelta: (delta) =>
                  setState(() => _adjustAllCollectionFees(delta)),
            ),
            const SizedBox(height: 8),
            if (_people.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Center(child: Text('目前沒有人員，請新增至少一位才能匯入。')),
              ),
            for (var i = 0; i < _people.length; i++)
              Card(
                color: const Color(0xFFF5F8F7),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: _responsivePair(
                              compact: compact,
                              first: TextField(
                                controller: _people[i].name,
                                decoration: _ocrDecoration(
                                  _people[i].isSelf ? '姓名（自己）' : '姓名',
                                  lowConfidence:
                                      _people[i].nameConfidence < 0.75,
                                ),
                                onChanged: (_) => setState(
                                  () => _people[i].nameConfidence = 1,
                                ),
                              ),
                              second: TextField(
                                controller: _people[i].amount,
                                keyboardType: TextInputType.number,
                                inputFormatters: [
                                  FilteringTextInputFormatter.digitsOnly,
                                ],
                                decoration: _ocrDecoration(
                                  '餐點（元）',
                                  lowConfidence:
                                      _people[i].amountConfidence < 0.75,
                                ),
                                onChanged: (_) => setState(() {
                                  _people[i].amountConfidence = 1;
                                  _syncDiscounts();
                                  _syncFees();
                                }),
                              ),
                              desktopSecondWidth: 130,
                            ),
                          ),
                          IconButton(
                            key: ValueKey('import-remove-person-$i'),
                            tooltip: _people[i].isSelf ? '移除本人' : '移除參與者',
                            onPressed: () => _removePerson(i),
                            icon: const Icon(Icons.close),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Builder(
                        builder: (context) {
                          final checkbox = SizedBox(
                            width: 92,
                            child: CheckboxListTile(
                              contentPadding: EdgeInsets.zero,
                              dense: true,
                              title: const Text('折扣'),
                              value: _people[i].discountEligible,
                              onChanged: (value) => setState(() {
                                _people[i].discountEligible = value ?? false;
                                if (!_people[i].discountEligible) {
                                  _people[i].discountIsFixed = false;
                                  _people[i].discount.text = '0';
                                }
                                _syncDiscounts();
                              }),
                            ),
                          );
                          final discount = TextField(
                            controller: _people[i].discount,
                            enabled: _people[i].discountEligible,
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                            ],
                            decoration: InputDecoration(
                              labelText: _people[i].discountIsFixed
                                  ? '折扣（固定）'
                                  : '折扣（自動）',
                              suffixIcon: _people[i].discountIsFixed
                                  ? IconButton(
                                      tooltip: '恢復自動',
                                      onPressed: () => setState(() {
                                        _people[i].discountIsFixed = false;
                                        _syncDiscounts();
                                      }),
                                      icon: const Icon(Icons.refresh),
                                    )
                                  : null,
                            ),
                            onChanged: (_) => setState(() {
                              _people[i].discountIsFixed = true;
                              _syncDiscounts();
                            }),
                          );
                          final fee = _FeeStepper(
                            controller: _people[i].fee,
                            label: _people[i].isSelf ? '本人負擔費用' : '收款附加費',
                            fixed: _people[i].feeFixed,
                            onDelta: (delta) => setState(() {
                              final current =
                                  int.tryParse(_people[i].fee.text) ?? 0;
                              _people[i].fee.text = (current + delta)
                                  .clamp(0, 999999999)
                                  .toString();
                              _people[i].feeFixed = true;
                              _error = null;
                            }),
                            onReset: () => setState(() {
                              _people[i].feeFixed = false;
                              _syncFees();
                              _error = null;
                            }),
                          );
                          final due = _ReadOnlyAmount(
                            label: _people[i].isSelf ? '本人合計' : '預計收款',
                            amountMinor:
                                ((_wholeMinor(_people[i].amount) ?? 0) +
                                        (_wholeMinor(_people[i].fee) ?? 0) -
                                        (_wholeMinor(_people[i].discount) ?? 0))
                                    .clamp(0, 999999999),
                          );
                          if (compact) {
                            return Column(
                              children: [
                                _responsivePair(
                                  compact: true,
                                  first: checkbox,
                                  second: discount,
                                ),
                                const SizedBox(height: 8),
                                fee,
                                const SizedBox(height: 8),
                                due,
                              ],
                            );
                          }
                          return Row(
                            children: [
                              checkbox,
                              const SizedBox(width: 8),
                              SizedBox(width: 170, child: discount),
                              const SizedBox(width: 10),
                              Expanded(child: fee),
                              const SizedBox(width: 10),
                              SizedBox(width: 145, child: due),
                            ],
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
            if (_people.isNotEmpty)
              _FeeRedistributionNotice(
                differenceMinor: _feeDifferenceMinor(),
                fixedCount: _people.where((person) => person.feeFixed).length,
                onRedistribute: () => setState(_redistributeFees),
                onReset: () => setState(() {
                  _syncFees(resetFixed: true);
                  _error = null;
                }),
              ),
            if (_people.isNotEmpty)
              Builder(
                builder: (context) {
                  final summary = _collectionSummary();
                  return summary == null
                      ? const SizedBox.shrink()
                      : _CollectionSummary(
                          totalCollectionMinor: summary.$1,
                          resultMinor: summary.$2,
                        );
                },
              ),
          ],
        ],
      ),
    );
    final actions = <Widget>[
      TextButton(
        onPressed: _loading ? null : () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      if (_imported == null)
        FilledButton.icon(
          onPressed: _loading ? null : _recognize,
          icon: _loading
              ? const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.auto_awesome),
          label: Text(
            _loading
                ? '辨識中…'
                : _recognitionAttempted
                ? '重新辨識'
                : '開始辨識',
          ),
        )
      else
        FilledButton(onPressed: _save, child: const Text('確認匯入')),
    ];
    if (compact) {
      return Dialog.fullscreen(
        child: Scaffold(
          appBar: AppBar(
            title: const Text('從 Uber Eats 截圖匯入'),
            leading: IconButton(
              tooltip: '取消',
              onPressed: _loading ? null : () => Navigator.pop(context),
              icon: const Icon(Icons.close),
            ),
          ),
          body: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: content,
            ),
          ),
          bottomNavigationBar: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  for (var index = 0; index < actions.length; index++) ...[
                    if (index > 0) const SizedBox(width: 8),
                    actions[index],
                  ],
                ],
              ),
            ),
          ),
        ),
      );
    }
    return AlertDialog(
      title: const Text('從 Uber Eats 截圖匯入'),
      content: SizedBox(width: 760, child: content),
      actions: actions,
    );
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _name.dispose();
    _platform.dispose();
    _total.dispose();
    _delivery.dispose();
    _service.dispose();
    _discount.dispose();
    for (final person in _people) {
      person.dispose();
    }
    super.dispose();
  }
}

class _ImportPersonDraft {
  _ImportPersonDraft({
    required this.name,
    required this.item,
    required this.amount,
    required this.fee,
    required this.feeFixed,
    required this.isSelf,
    required this.discountEligible,
    required this.discountIsFixed,
    required this.discount,
    required this.nameConfidence,
    required this.itemConfidence,
    required this.amountConfidence,
  });

  factory _ImportPersonDraft.empty() => _ImportPersonDraft(
    name: TextEditingController(),
    item: TextEditingController(),
    amount: TextEditingController(),
    fee: TextEditingController(text: '0'),
    feeFixed: false,
    isSelf: false,
    discountEligible: false,
    discountIsFixed: false,
    discount: TextEditingController(text: '0'),
    nameConfidence: 1,
    itemConfidence: 1,
    amountConfidence: 1,
  );

  final TextEditingController name;
  final TextEditingController item;
  final TextEditingController amount;
  final TextEditingController fee;
  bool feeFixed;
  final bool isSelf;
  bool discountEligible;
  bool discountIsFixed;
  final TextEditingController discount;
  double nameConfidence;
  double itemConfidence;
  double amountConfidence;

  void dispose() {
    name.dispose();
    item.dispose();
    amount.dispose();
    fee.dispose();
    discount.dispose();
  }
}

class OrderDetailPage extends ConsumerWidget {
  const OrderDetailPage({required this.orderId, super.key});
  final String orderId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final store = ref.watch(appStoreProvider);
    final matches = store.data.orders.where((item) => item.id == orderId);
    final order = matches.isEmpty ? null : matches.first;
    if (order == null) {
      return const EmptyState(
        icon: Icons.search_off,
        title: '找不到代訂',
        message: '這筆代訂可能已被刪除。',
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            IconButton(
              onPressed: () => context.go('/orders'),
              icon: const Icon(Icons.arrow_back),
            ),
            Expanded(
              child: PageHeader(
                title: order.name,
                subtitle:
                    '${dateText(order.date)}・${order.platform}・${order.splitMethod.label}',
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        ResponsiveGrid(
          children: [
            SummaryCard(
              label: '總刷卡金額',
              value: moneyText(order.totalMinor),
              compactValue: compactMoneyText(order.totalMinor),
              icon: Icons.credit_card,
            ),
            SummaryCard(
              label: '本人信用卡消費',
              value: moneyText(order.selfExpenseMinor),
              compactValue: compactMoneyText(order.selfExpenseMinor),
              icon: Icons.person_outline,
            ),
            SummaryCard(
              label: '代收代墊刷卡',
              value: moneyText(order.advanceCardMinor),
              compactValue: compactMoneyText(order.advanceCardMinor),
              icon: Icons.account_balance_wallet_outlined,
            ),
            SummaryCard(
              label: '預計收款',
              value: moneyText(order.expectedCollectionMinor),
              compactValue: compactMoneyText(order.expectedCollectionMinor),
              icon: Icons.request_quote_outlined,
            ),
            SummaryCard(
              label: order.expectedCollectionResultMinor >= 0
                  ? '預期代收收益'
                  : '預期代收損失',
              value: moneyText(order.expectedCollectionResultMinor.abs()),
              compactValue: compactMoneyText(
                order.expectedCollectionResultMinor.abs(),
              ),
              icon: order.expectedCollectionResultMinor >= 0
                  ? Icons.trending_up
                  : Icons.trending_down,
              tone: order.expectedCollectionResultMinor >= 0
                  ? const Color(0xFF0E7C66)
                  : const Color(0xFFB84B3E),
            ),
            SummaryCard(
              label: '尚未收回',
              value: moneyText(order.outstandingMinor),
              compactValue: compactMoneyText(order.outstandingMinor),
              icon: Icons.handshake_outlined,
              tone: const Color(0xFFE27848),
            ),
            SummaryCard(
              label: order.recognizedCollectionResultMinor >= 0
                  ? '已認列收益'
                  : '已認列損失',
              value: moneyText(order.recognizedCollectionResultMinor.abs()),
              compactValue: compactMoneyText(
                order.recognizedCollectionResultMinor.abs(),
              ),
              icon: Icons.done_all,
              tone: order.recognizedCollectionResultMinor >= 0
                  ? const Color(0xFF0E7C66)
                  : const Color(0xFFB84B3E),
              caption: '僅計算已確認收款',
            ),
          ],
        ),
        const SizedBox(height: 18),
        Card(
          child: Column(
            children: [
              for (
                var index = 0;
                index < order.participants.length;
                index++
              ) ...[
                _ParticipantRow(
                  order: order,
                  person: order.participants[index],
                ),
                if (index < order.participants.length - 1)
                  const Divider(height: 1, indent: 72),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _ParticipantRow extends ConsumerWidget {
  const _ParticipantRow({required this.order, required this.person});
  final GroupOrder order;
  final OrderParticipant person;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final store = ref.read(appStoreProvider);
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      leading: CircleAvatar(
        child: person.isSelf
            ? const Icon(Icons.person)
            : Text(person.name.characters.first),
      ),
      title: Row(
        children: [
          Text(
            person.name,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          if (person.isSelf)
            const Padding(
              padding: EdgeInsets.only(left: 8),
              child: Chip(label: Text('自己')),
            ),
        ],
      ),
      subtitle: Text(
        '${order.importSource == 'uberEatsScreenshot' ? '餐點金額' : person.itemName} '
        '${moneyText(person.itemAmountMinor)}・'
        '實際費用 ${moneyText(person.sharedFeeMinor)}・'
        '折扣 -${moneyText(person.discountMinor)}'
        '${person.isSelf ? '' : '・實際成本 ${moneyText(person.calculatedDueMinor)}'}'
        '${person.isSelf || person.collectionResultMinor == 0 ? '' : '・'
                  '${person.collectionResultMinor > 0 ? '代收收益' : '代收損失'} '
                  '${moneyText(person.collectionResultMinor.abs())}'}'
        '${person.status == CollectionStatus.paid && person.collectionAccountId != null ? '・已入帳 ${store.accountById(person.collectionAccountId)?.name ?? '指定帳戶'} '
                  '${moneyText(person.dueMinor)}' : ''}',
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                moneyText(person.dueMinor),
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
              Text(
                person.status.label,
                style: TextStyle(color: _statusColor(person.status)),
              ),
            ],
          ),
          if (!person.isSelf &&
              (person.status == CollectionStatus.unpaid ||
                  person.status == CollectionStatus.pending)) ...[
            const SizedBox(width: 10),
            FilledButton(
              onPressed: () async {
                final saved = await store.confirmParticipantCollection(
                  order.id,
                  person.id,
                );
                if (context.mounted) {
                  showSaved(
                    context,
                    saved ? '已確認收款' : store.lastSyncError ?? '無法確認收款，請先檢查收款設定',
                  );
                }
              },
              child: const Text('確認收款'),
            ),
          ],
        ],
      ),
    );
  }

  Color _statusColor(CollectionStatus status) => switch (status) {
    CollectionStatus.paid => const Color(0xFF0E7C66),
    CollectionStatus.pending => const Color(0xFFE27848),
    CollectionStatus.unpaid => const Color(0xFFB84B3E),
    CollectionStatus.cancelled => Colors.grey,
  };
}

String _knownParticipantName(String recognized, List<GroupOrder> orders) {
  final source = _ocrNameKey(recognized);
  if (source.length < 4 || !RegExp(r'^[a-z]+$').hasMatch(source)) {
    return recognized;
  }
  String? best;
  var bestDistance = 3;
  for (final participant
      in orders
          .expand((order) => order.participants)
          .where((participant) => !participant.isSelf)) {
    final candidate = _ocrNameKey(participant.name);
    if (!RegExp(r'^[a-z]+$').hasMatch(candidate)) continue;
    final distance = _editDistance(source, candidate);
    if (distance < bestDistance) {
      bestDistance = distance;
      best = participant.name;
    }
  }
  return best ?? recognized;
}

String _ocrNameKey(String value) => value
    .toLowerCase()
    .replaceAll(RegExp(r'\s+'), '')
    .replaceAll(RegExp(r'[l1]'), 'i')
    .replaceAll('0', 'o');

int _editDistance(String left, String right) {
  var previous = List<int>.generate(right.length + 1, (index) => index);
  for (var row = 1; row <= left.length; row++) {
    final current = List<int>.filled(right.length + 1, 0)..[0] = row;
    for (var column = 1; column <= right.length; column++) {
      final substitution =
          previous[column - 1] + (left[row - 1] == right[column - 1] ? 0 : 1);
      final insertion = current[column - 1] + 1;
      final deletion = previous[column] + 1;
      current[column] = [
        substitution,
        insertion,
        deletion,
      ].reduce((a, b) => a < b ? a : b);
    }
    previous = current;
  }
  return previous.last;
}

class _AllocationSettingsCard extends StatelessWidget {
  const _AllocationSettingsCard({
    required this.hasSelf,
    required this.includeDelivery,
    required this.includeService,
    required this.onDeliveryChanged,
    required this.onServiceChanged,
    required this.discountTotalMinor,
    required this.fixedDiscountMinor,
    required this.assignedDiscountMinor,
  });

  final bool hasSelf;
  final bool includeDelivery;
  final bool includeService;
  final ValueChanged<bool> onDeliveryChanged;
  final ValueChanged<bool> onServiceChanged;
  final int discountTotalMinor;
  final int fixedDiscountMinor;
  final int assignedDiscountMinor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final automaticDiscountMinor = (discountTotalMinor - fixedDiscountMinor)
        .clamp(0, discountTotalMinor < 0 ? 0 : discountTotalMinor)
        .toInt();

    return Container(
      key: const ValueKey('allocation-settings-card'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F8F7),
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.call_split_rounded,
                  size: 20,
                  color: scheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '分攤設定',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      '設定本人是否一起分攤附加費',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Text(
                '本人分攤附加費',
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (!hasSelf) ...[
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '目前沒有本人參與者',
                    textAlign: TextAlign.end,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.error,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 520;
              final delivery = _SelfFeeSwitch(
                switchKey: const ValueKey('include-self-delivery'),
                label: '外送費',
                value: hasSelf && includeDelivery,
                onChanged: hasSelf ? onDeliveryChanged : null,
              );
              final service = _SelfFeeSwitch(
                switchKey: const ValueKey('include-self-service'),
                label: '服務費',
                value: hasSelf && includeService,
                onChanged: hasSelf ? onServiceChanged : null,
              );
              if (compact) {
                return Column(
                  children: [delivery, const SizedBox(height: 8), service],
                );
              }
              return Row(
                children: [
                  Expanded(child: delivery),
                  const SizedBox(width: 10),
                  Expanded(child: service),
                ],
              );
            },
          ),
          const SizedBox(height: 16),
          Divider(height: 1, color: scheme.outlineVariant),
          const SizedBox(height: 16),
          Text(
            '折扣分配',
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 520;
              final spacing = compact ? 8.0 : 10.0;
              final columns = compact ? 2 : 4;
              final width =
                  (constraints.maxWidth - spacing * (columns - 1)) / columns;
              final metrics = [
                ('discount-total', '訂單折扣', discountTotalMinor),
                ('discount-fixed', '手動固定', fixedDiscountMinor),
                ('discount-automatic', '自動分配', automaticDiscountMinor),
                ('discount-assigned', '已分配', assignedDiscountMinor),
              ];
              return Wrap(
                spacing: spacing,
                runSpacing: 8,
                children: [
                  for (final metric in metrics)
                    SizedBox(
                      width: width,
                      child: _AllocationMetric(
                        metricKey: ValueKey(metric.$1),
                        label: metric.$2,
                        valueMinor: metric.$3,
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _SelfFeeSwitch extends StatelessWidget {
  const _SelfFeeSwitch({
    required this.switchKey,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final Key switchKey;
  final String label;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minHeight: 64),
    padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surface,
      border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      children: [
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
              Text(
                '本人一起分攤',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        Switch(key: switchKey, value: value, onChanged: onChanged),
      ],
    ),
  );
}

class _AllocationMetric extends StatelessWidget {
  const _AllocationMetric({
    required this.metricKey,
    required this.label,
    required this.valueMinor,
  });

  final Key metricKey;
  final String label;
  final int valueMinor;

  @override
  Widget build(BuildContext context) => Container(
    key: metricKey,
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(10),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          moneyText(valueMinor),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
        ),
      ],
    ),
  );
}

class _CollectionSummary extends StatelessWidget {
  const _CollectionSummary({
    required this.totalCollectionMinor,
    required this.resultMinor,
  });

  final int totalCollectionMinor;
  final int resultMinor;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(top: 10),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: const Color(0xFFF1F7F5),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      children: [
        Expanded(
          child: _SummaryAmount(
            label: '總共收款',
            value: moneyText(totalCollectionMinor),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _SummaryAmount(
            label: resultMinor >= 0 ? '預計多收' : '預計少收',
            value: moneyText(resultMinor.abs()),
            tone: resultMinor >= 0
                ? const Color(0xFF0E7C66)
                : const Color(0xFFB84B3E),
          ),
        ),
      ],
    ),
  );
}

class _SummaryAmount extends StatelessWidget {
  const _SummaryAmount({required this.label, required this.value, this.tone});

  final String label;
  final String value;
  final Color? tone;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: Theme.of(context).textTheme.labelMedium),
      const SizedBox(height: 2),
      Text(
        value,
        style: Theme.of(context).textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w900,
          color: tone,
        ),
      ),
    ],
  );
}

class _ReadOnlyAmount extends StatelessWidget {
  const _ReadOnlyAmount({required this.label, required this.amountMinor});

  final String label;
  final int amountMinor;

  @override
  Widget build(BuildContext context) => Container(
    height: 52,
    padding: const EdgeInsets.symmetric(horizontal: 12),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerLowest,
      border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      children: [
        Expanded(
          child: Text(label, style: Theme.of(context).textTheme.labelMedium),
        ),
        Text(
          moneyText(amountMinor),
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
      ],
    ),
  );
}

class _UniformFeeAdjuster extends StatelessWidget {
  const _UniformFeeAdjuster({required this.peopleFees, required this.onDelta});

  final List<int> peopleFees;
  final ValueChanged<int> onDelta;

  @override
  Widget build(BuildContext context) {
    final same = peopleFees.isNotEmpty && peopleFees.toSet().length == 1;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F7F5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '統一調整收款附加費',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                Text('其他參與者每人一起調整 1 元'),
              ],
            ),
          ),
          IconButton(
            key: const ValueKey('all-fees-minus'),
            tooltip: '每人減少 1 元',
            onPressed: peopleFees.isEmpty || peopleFees.every((fee) => fee <= 0)
                ? null
                : () => onDelta(-1),
            icon: const Icon(Icons.remove_circle_outline),
          ),
          SizedBox(
            width: 72,
            child: Text(
              same ? '${peopleFees.first} 元' : '各自設定',
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
          IconButton(
            key: const ValueKey('all-fees-plus'),
            tooltip: '每人增加 1 元',
            onPressed: peopleFees.isEmpty ? null : () => onDelta(1),
            icon: const Icon(Icons.add_circle_outline),
          ),
        ],
      ),
    );
  }
}

class _FeeStepper extends StatelessWidget {
  const _FeeStepper({
    required this.controller,
    required this.label,
    required this.fixed,
    required this.onDelta,
    required this.onReset,
  });

  final TextEditingController controller;
  final String label;
  final bool fixed;
  final ValueChanged<int> onDelta;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Container(
          height: 52,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          decoration: BoxDecoration(
            border: Border.all(
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelMedium,
                ),
              ),
              IconButton(
                key: ValueKey('fee-minus-$label'),
                tooltip: '減少 1 元',
                onPressed: (int.tryParse(controller.text) ?? 0) <= 0
                    ? null
                    : () => onDelta(-1),
                icon: const Icon(Icons.remove_circle_outline),
              ),
              SizedBox(
                width: 36,
                child: Text(
                  controller.text.isEmpty ? '0' : controller.text,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const Text('元'),
              IconButton(
                key: ValueKey('fee-plus-$label'),
                tooltip: '增加 1 元',
                onPressed: () => onDelta(1),
                icon: const Icon(Icons.add_circle_outline),
              ),
            ],
          ),
        ),
      ),
      const SizedBox(width: 6),
      if (fixed)
        IconButton(
          tooltip: '已固定，點擊恢復自動',
          onPressed: onReset,
          icon: const Icon(Icons.lock_outline),
        )
      else
        const Tooltip(
          message: '自動分配',
          child: Icon(Icons.auto_awesome, size: 20),
        ),
    ],
  );
}

class _FeeRedistributionNotice extends StatelessWidget {
  const _FeeRedistributionNotice({
    required this.differenceMinor,
    required this.fixedCount,
    required this.onRedistribute,
    required this.onReset,
  });

  final int differenceMinor;
  final int fixedCount;
  final VoidCallback onRedistribute;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final balanced = differenceMinor == 0;
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: balanced || differenceMinor < 0
            ? const Color(0xFFF1F7F5)
            : const Color(0xFFFFF8E8),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Icon(
            balanced ? Icons.check_circle_outline : Icons.sync_problem,
            color: balanced || differenceMinor < 0
                ? const Color(0xFF0E7C66)
                : const Color(0xFFB56A00),
          ),
          Text(
            balanced
                ? '費用已平衡・$fixedCount 人手動固定'
                : differenceMinor > 0
                ? '目前少收 ${moneyText(differenceMinor)}，仍可直接儲存'
                : '目前多收 ${moneyText(differenceMinor.abs())}，會列入代收收益',
          ),
          if (!balanced)
            FilledButton.tonalIcon(
              key: const ValueKey('redistribute-fees'),
              onPressed: onRedistribute,
              icon: const Icon(Icons.sync),
              label: const Text('重套系統分配'),
            ),
          TextButton(onPressed: onReset, child: const Text('全部恢復自動')),
        ],
      ),
    );
  }
}

class _ParticipantDraft {
  _ParticipantDraft({
    required this.id,
    required this.name,
    required this.isSelf,
    required this.item,
    required this.amount,
    required this.fee,
    required this.feeFixed,
    required this.discount,
    required this.discountEligible,
    required this.discountIsFixed,
    required this.status,
    required this.collectionMethod,
    required this.collectionAccountId,
    required this.token,
    required this.collectedAt,
  });

  factory _ParticipantDraft.empty({
    bool isSelf = false,
    String name = '',
    String collectionMethod = collectionMethodBankTransfer,
    String? collectionAccountId,
  }) => _ParticipantDraft(
    id: null,
    name: TextEditingController(text: name),
    isSelf: isSelf,
    item: TextEditingController(),
    amount: TextEditingController(),
    fee: TextEditingController(text: '0'),
    feeFixed: false,
    discount: TextEditingController(text: '0'),
    discountEligible: false,
    discountIsFixed: false,
    status: isSelf ? CollectionStatus.paid : CollectionStatus.unpaid,
    collectionMethod: isSelf ? '' : collectionMethod,
    collectionAccountId: isSelf
        ? null
        : (collectionMethod == collectionMethodCash
              ? systemCashAccountId
              : collectionAccountId),
    token: null,
    collectedAt: null,
  );

  factory _ParticipantDraft.fromModel(
    OrderParticipant item, {
    bool manualFee = false,
  }) => _ParticipantDraft(
    id: item.id,
    name: TextEditingController(text: item.name),
    isSelf: item.isSelf,
    item: TextEditingController(text: item.itemName),
    amount: TextEditingController(
      text: (item.itemAmountMinor / 100).toString(),
    ),
    fee: TextEditingController(
      text: (collectionFeeMinorForEditing(item) ~/ 100).toString(),
    ),
    feeFixed:
        manualFee ||
        (!item.isSelf &&
            item.finalDueMinor != null &&
            item.finalDueMinor != item.suggestedDueMinor),
    discount: TextEditingController(
      text: (item.discountMinor / 100).toString(),
    ),
    discountEligible: item.discountEligible,
    discountIsFixed: item.discountIsFixed,
    status: item.status,
    collectionMethod: item.collectionMethod,
    collectionAccountId: item.collectionAccountId,
    token: item.token,
    collectedAt: item.collectedAt,
  );

  final String? id;
  final TextEditingController name;
  final bool isSelf;
  final TextEditingController item;
  final TextEditingController amount;
  final TextEditingController fee;
  bool feeFixed;
  final TextEditingController discount;
  bool discountEligible;
  bool discountIsFixed;
  final CollectionStatus status;
  String collectionMethod;
  String? collectionAccountId;
  final String? token;
  final DateTime? collectedAt;
}

class _ParticipantEditor extends StatelessWidget {
  const _ParticipantEditor({
    required this.draft,
    required this.dueMinor,
    required this.accounts,
    required this.canDelete,
    required this.onDelete,
    required this.onChanged,
    required this.onFeeDelta,
    required this.onResetFee,
  });

  final _ParticipantDraft draft;
  final int dueMinor;
  final List<Account> accounts;
  final bool canDelete;
  final VoidCallback onDelete;
  final VoidCallback onChanged;
  final ValueChanged<int> onFeeDelta;
  final VoidCallback onResetFee;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: const Color(0xFFF5F8F7),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: draft.name,
                  decoration: InputDecoration(
                    labelText: draft.isSelf ? '姓名（自己）' : '姓名',
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: TextField(
                  controller: draft.item,
                  decoration: const InputDecoration(labelText: '品項'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: draft.amount,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(labelText: '餐點金額'),
                  onChanged: (_) => onChanged(),
                ),
              ),
              if (canDelete && !draft.isSelf)
                IconButton(onPressed: onDelete, icon: const Icon(Icons.close)),
            ],
          ),
          const SizedBox(height: 8),
          LayoutBuilder(
            builder: (context, constraints) {
              final discountControls = Row(
                children: [
                  SizedBox(
                    width: 92,
                    child: CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      title: const Text('折扣'),
                      value: draft.discountEligible,
                      onChanged: (value) {
                        draft.discountEligible = value ?? false;
                        if (!draft.discountEligible) {
                          draft.discountIsFixed = false;
                          draft.discount.text = '0';
                        }
                        onChanged();
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: draft.discount,
                      enabled: draft.discountEligible,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: InputDecoration(
                        labelText: draft.discountIsFixed
                            ? '折扣金額（固定）'
                            : '折扣金額（自動）',
                        suffixIcon: draft.discountIsFixed
                            ? IconButton(
                                tooltip: '恢復自動',
                                onPressed: () {
                                  draft.discountIsFixed = false;
                                  onChanged();
                                },
                                icon: const Icon(Icons.refresh),
                              )
                            : null,
                      ),
                      onChanged: (_) {
                        draft.discountIsFixed = true;
                        onChanged();
                      },
                    ),
                  ),
                ],
              );
              final fee = _FeeStepper(
                controller: draft.fee,
                label: draft.isSelf ? '本人負擔費用' : '收款附加費',
                fixed: draft.feeFixed,
                onDelta: onFeeDelta,
                onReset: onResetFee,
              );
              final due = _ReadOnlyAmount(
                label: draft.isSelf ? '本人合計' : '預計收款',
                amountMinor: dueMinor,
              );
              if (constraints.maxWidth < 620) {
                return Column(
                  children: [
                    discountControls,
                    const SizedBox(height: 8),
                    fee,
                    const SizedBox(height: 8),
                    due,
                  ],
                );
              }
              return Row(
                children: [
                  SizedBox(width: 250, child: discountControls),
                  const SizedBox(width: 10),
                  Expanded(child: fee),
                  const SizedBox(width: 10),
                  SizedBox(width: 145, child: due),
                ],
              );
            },
          ),
          if (!draft.isSelf) ...[
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              key: ValueKey(
                'collection-method-${draft.id ?? draft.name.hashCode}',
              ),
              initialValue:
                  supportedCollectionMethods.contains(draft.collectionMethod)
                  ? draft.collectionMethod
                  : null,
              decoration: const InputDecoration(labelText: '收款方式'),
              hint: const Text('請選擇收款方式'),
              items: supportedCollectionMethods
                  .map(
                    (value) =>
                        DropdownMenuItem(value: value, child: Text(value)),
                  )
                  .toList(),
              onChanged: (value) {
                draft.collectionMethod = value!;
                draft.collectionAccountId = value == collectionMethodCash
                    ? systemCashAccountId
                    : (accounts.any(
                            (account) =>
                                account.id == draft.collectionAccountId,
                          )
                          ? draft.collectionAccountId
                          : accounts.firstOrNull?.id);
                onChanged();
              },
            ),
            if (draft.collectionMethod == collectionMethodBankTransfer) ...[
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                key: ValueKey(
                  'collection-account-${draft.id ?? draft.name.hashCode}',
                ),
                initialValue:
                    accounts.any(
                      (account) => account.id == draft.collectionAccountId,
                    )
                    ? draft.collectionAccountId
                    : null,
                decoration: const InputDecoration(labelText: '轉入帳戶'),
                hint: const Text('請選擇 TWD 銀行帳戶'),
                items: accounts
                    .map(
                      (account) => DropdownMenuItem(
                        value: account.id,
                        child: Text(account.name),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  draft.collectionAccountId = value;
                  onChanged();
                },
              ),
            ],
          ],
        ],
      ),
    ),
  );
}
