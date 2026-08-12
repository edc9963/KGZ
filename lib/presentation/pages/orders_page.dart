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
                onPressed: () => _showOrderDialog(context, ref),
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
              onPressed: () => _showOrderDialog(context, ref),
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

  Future<void> _showImportDialog(BuildContext context, WidgetRef ref) async {
    final store = ref.read(appStoreProvider);
    if (store.data.cards.isEmpty) {
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
        (store.data.cards.isEmpty ? null : store.data.cards.first.id);
    var splitMethod = existing?.splitMethod ?? SplitMethod.equal;
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
        : existing.participants.map(_ParticipantDraft.fromModel).toList();
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

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(existing == null ? '新增代訂' : '編輯代訂'),
          content: SizedBox(
            width: 720,
            child: SingleChildScrollView(
              child: Column(
                children: [
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
                  Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: TextField(
                          controller: name,
                          decoration: const InputDecoration(labelText: '代訂名稱'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: platform,
                          decoration: const InputDecoration(labelText: '訂購平台'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
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
                  const SizedBox(height: 12),
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
                              store.data.cards.any((item) => item.id == cardId)
                              ? cardId
                              : null,
                          decoration: const InputDecoration(labelText: '刷卡信用卡'),
                          items: store.data.cards
                              .map(
                                (card) => DropdownMenuItem(
                                  value: card.id,
                                  child: Text(card.name),
                                ),
                              )
                              .toList(),
                          onChanged: (value) => setState(() => cardId = value),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
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
                              decoration: InputDecoration(labelText: field.$1),
                              onChanged: (_) => setState(() {
                                if (field.$1 == '折扣') syncDiscounts();
                              }),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SegmentedButton<SplitMethod>(
                    segments: [
                      for (final method in SplitMethod.values)
                        ButtonSegment(value: method, label: Text(method.label)),
                    ],
                    selected: {splitMethod},
                    onSelectionChanged: (value) =>
                        setState(() => splitMethod = value.first),
                  ),
                  if (splitMethod == SplitMethod.equal) ...[
                    const SizedBox(height: 10),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('外送費包含本人'),
                      value: includeSelfInDeliveryFee,
                      onChanged: (value) =>
                          setState(() => includeSelfInDeliveryFee = value),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('服務費包含本人'),
                      value: includeSelfInServiceFee,
                      onChanged: (value) =>
                          setState(() => includeSelfInServiceFee = value),
                    ),
                  ],
                  const SizedBox(height: 18),
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
                  for (var index = 0; index < drafts.length; index++)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: _ParticipantEditor(
                        draft: drafts[index],
                        accounts: store.bankTransferAccounts,
                        manual: splitMethod == SplitMethod.manual,
                        canDelete: drafts.length > 1,
                        onDelete: () => setState(() {
                          drafts.removeAt(index);
                          syncDiscounts();
                        }),
                        onChanged: () => setState(() {
                          syncDiscounts();
                          error = null;
                        }),
                      ),
                    ),
                  Builder(
                    builder: (context) {
                      final fixed = drafts
                          .where(
                            (draft) =>
                                draft.discountEligible && draft.discountIsFixed,
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
                      return Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          '折扣：訂單 ${moneyText(parseMoney(discount.text))}・'
                          '已固定 ${moneyText(fixed)}・'
                          '已分配 ${moneyText(assigned)}',
                          style: const TextStyle(color: Colors.black54),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 12),
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
            FilledButton(
              onPressed: () async {
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
                if (drafts.where((item) => !item.isSelf).any((item) {
                  final value = item.finalDue.text.trim();
                  return value.isNotEmpty && int.tryParse(value) == null;
                })) {
                  setState(() => error = '最終收款只能輸入整數元。');
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
                if (totalMinor != expected) {
                  setState(
                    () => error = '金額不一致：品項＋費用－折扣應為 ${moneyText(expected)}。',
                  );
                  return;
                }
                if (splitMethod == SplitMethod.manual) {
                  final shared = drafts.fold(
                    0,
                    (sum, item) => sum + parseMoney(item.fee.text),
                  );
                  if (shared != fee) {
                    setState(() => error = '手動分攤的費用合計必須等於訂單設定。');
                    return;
                  }
                }
                AllocationResult? allocation;
                if (splitMethod == SplitMethod.equal) {
                  try {
                    allocation = allocateWholeTwd(
                      itemAmountsMinor: [
                        for (final draft in drafts)
                          parseMoney(draft.amount.text),
                      ],
                      isSelf: [for (final draft in drafts) draft.isSelf],
                      deliveryFeeMinor: parseMoney(delivery.text),
                      serviceFeeMinor: parseMoney(service.text),
                      discountMinor: discountMinor,
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
                    setState(() => error = exception.message);
                    return;
                  }
                }
                final participants = <OrderParticipant>[];
                for (var index = 0; index < drafts.length; index++) {
                  final draft = drafts[index];
                  participants.add(
                    OrderParticipant(
                      id: draft.id ?? store.newId(),
                      name: draft.name.text.trim(),
                      isSelf: draft.isSelf,
                      itemName: draft.item.text.trim(),
                      itemAmountMinor: parseMoney(draft.amount.text),
                      sharedFeeMinor: splitMethod == SplitMethod.equal
                          ? allocation!.feeShares[index]
                          : parseMoney(draft.fee.text),
                      discountMinor: splitMethod == SplitMethod.equal
                          ? allocation!.discountShares[index]
                          : discountShares[index],
                      discountEligible: draft.discountEligible,
                      discountIsFixed: draft.discountIsFixed,
                      suggestedDueMinor: splitMethod == SplitMethod.equal
                          ? allocation!.suggestedDues[index]
                          : null,
                      finalDueMinor: draft.isSelf
                          ? null
                          : (draft.finalDue.text.trim().isEmpty
                                ? (splitMethod == SplitMethod.equal
                                      ? allocation!.suggestedDues[index]
                                      : null)
                                : int.tryParse(draft.finalDue.text.trim())! *
                                      100),
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
              child: const Text('儲存代訂'),
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
          .where((card) => card.lastFour == imported.paymentLastFour)
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
              finalDue: TextEditingController(),
              isSelf: person.isSelf,
              discountEligible: false,
              discountIsFixed: false,
              discount: TextEditingController(text: '0'),
              nameConfidence: person.nameConfidence,
              itemConfidence: person.itemConfidence,
              amountConfidence: person.amountConfidence,
              finalDueIsManual: false,
            ),
        ];
        if (_hasFractionalAmounts(imported)) {
          _error = '辨識結果含非整數新台幣；相關欄位已留白，請人工填入整數元。';
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

  void _applySuggestedDues({required bool resetManual}) {
    final allocation = _allocation();
    if (allocation == null) return;
    for (var index = 0; index < _people.length; index++) {
      final person = _people[index];
      if (person.isSelf) continue;
      if (resetManual) person.finalDueIsManual = false;
      if (!person.finalDueIsManual) {
        person.finalDue.text = (allocation.suggestedDues[index] ~/ 100)
            .toString();
      }
    }
  }

  bool get _hasSelf => _people.any((person) => person.isSelf);

  void _addPerson() {
    setState(() {
      _people.add(_ImportPersonDraft.empty());
      _syncDiscounts();
      _applySuggestedDues(resetManual: false);
      _error = null;
    });
  }

  void _removePerson(int index) {
    setState(() {
      final removedSelf = _people[index].isSelf;
      _people.removeAt(index);
      if (removedSelf && !_hasSelf) {
        _includeDelivery = false;
        _includeService = false;
      }
      _syncDiscounts();
      _applySuggestedDues(resetManual: false);
      _error = null;
    });
  }

  Future<void> _save() async {
    final store = ref.read(appStoreProvider);
    if (_name.text.trim().isEmpty ||
        _cardId == null ||
        _people.isEmpty ||
        _people.any(
          (person) =>
              person.name.text.trim().isEmpty ||
              person.item.text.trim().isEmpty,
        )) {
      setState(() => _error = '請確認名稱、信用卡與所有參與者資料。');
      return;
    }
    final allocation = _allocation(reportError: true);
    if (allocation == null) return;
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

    final participants = <OrderParticipant>[];
    for (var i = 0; i < _people.length; i++) {
      final draft = _people[i];
      final finalText = draft.finalDue.text.trim();
      final finalDue = draft.isSelf
          ? null
          : finalText.isEmpty
          ? allocation.suggestedDues[i]
          : int.tryParse(finalText) == null
          ? null
          : int.parse(finalText) * 100;
      if (!draft.isSelf && finalDue == null) {
        setState(() => _error = '最終收款只能輸入整數元。');
        return;
      }
      participants.add(
        OrderParticipant(
          id: store.newId(),
          name: draft.name.text.trim(),
          isSelf: draft.isSelf,
          itemName: draft.item.text.trim(),
          itemAmountMinor: _wholeMinor(draft.amount)!,
          sharedFeeMinor: allocation.feeShares[i],
          discountMinor: allocation.discountShares[i],
          discountEligible: draft.discountEligible,
          discountIsFixed: draft.discountIsFixed,
          suggestedDueMinor: allocation.suggestedDues[i],
          finalDueMinor: finalDue,
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
    await store.upsertOrder(
      GroupOrder(
        id: store.newId(),
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
          person.nameConfidence < 0.75 ||
          person.itemConfidence < 0.75 ||
          person.amountConfidence < 0.75,
    )) {
      issues.add('部分參與者或品項為低信心 OCR 結果');
    }
    if (imported.warnings.any((warning) => warning.contains('未辨識到「您」'))) {
      issues.add('本人身分為系統暫時猜測');
    }
    return issues;
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
    final allocation = _imported == null ? null : _allocation();
    if (allocation != null) {
      for (var index = 0; index < _people.length; index++) {
        final person = _people[index];
        if (!person.isSelf && !person.finalDueIsManual) {
          final suggested = (allocation.suggestedDues[index] ~/ 100).toString();
          if (person.finalDue.text != suggested) {
            person.finalDue.text = suggested;
          }
        }
      }
    }
    final compact = MediaQuery.sizeOf(context).width < 600;
    final content = SingleChildScrollView(
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
            const Text('請確認截圖順序；相鄰圖片的重疊品項會自動去除。'),
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
                  Expanded(
                    child: Text(
                      '截圖只在這台手機的瀏覽器內辨識，不會上傳或保存。'
                      '首次使用需下載 OCR 模型（Safari 約 10 MB，'
                      '其他瀏覽器最高約 100 MB），'
                      '建議連接 Wi‑Fi 並保持此頁開啟。',
                    ),
                  ),
                ],
              ),
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
                        '下載後會保存在這台電腦。',
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
                  for (final card in store.data.cards)
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
                child: Text('請確認：${_imported!.warnings.join('；')}'),
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
                        _applySuggestedDues(resetManual: false);
                      }),
                    ),
                  ),
              ],
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('外送費包含本人'),
              value: _includeDelivery,
              subtitle: _hasSelf ? null : const Text('目前沒有本人參與者'),
              onChanged: !_hasSelf
                  ? null
                  : (value) => setState(() {
                      _includeDelivery = value ?? false;
                      _applySuggestedDues(resetManual: false);
                    }),
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('服務費包含本人'),
              value: _includeService,
              subtitle: _hasSelf ? null : const Text('目前沒有本人參與者'),
              onChanged: !_hasSelf
                  ? null
                  : (value) => setState(() {
                      _includeService = value ?? false;
                      _applySuggestedDues(resetManual: false);
                    }),
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
                return Container(
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF5F8F7),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: _responsivePair(
                    compact: compact,
                    first: Text(
                      '折扣分配：訂單 ${moneyText(total)}・'
                      '已固定 ${moneyText(fixed)}・'
                      '待自動分配 '
                      '${moneyText((total - fixed).clamp(0, total))}・'
                      '已分配 ${moneyText(assigned)}',
                    ),
                    second: TextButton.icon(
                      onPressed: allocation == null
                          ? null
                          : () => setState(() {
                              _applySuggestedDues(resetManual: true);
                            }),
                      icon: const Icon(Icons.refresh),
                      label: const Text('重新套用建議收款'),
                    ),
                    desktopSecondWidth: 200,
                  ),
                );
              },
            ),
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 4,
              children: [
                Text(
                  '參與人員與品項',
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
                                  _applySuggestedDues(resetManual: false);
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
                      TextField(
                        controller: _people[i].item,
                        decoration: _ocrDecoration(
                          '品項',
                          lowConfidence: _people[i].itemConfidence < 0.75,
                        ),
                        onChanged: (_) =>
                            setState(() => _people[i].itemConfidence = 1),
                      ),
                      const SizedBox(height: 8),
                      _responsivePair(
                        compact: compact,
                        first: CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                          title: const Text('有折扣'),
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
                        second: TextField(
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
                        ),
                        desktopSecondWidth: 190,
                      ),
                      if (!_people[i].isSelf) ...[
                        const SizedBox(height: 8),
                        TextField(
                          controller: _people[i].finalDue,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                          decoration: InputDecoration(
                            labelText: allocation == null
                                ? '最終收款（整數元）'
                                : '最終收款（建議 ${allocation.suggestedDues[i] ~/ 100} 元）',
                          ),
                          onChanged: (_) => setState(
                            () => _people[i].finalDueIsManual = true,
                          ),
                        ),
                        if (allocation != null &&
                            _people[i].finalDue.text.isNotEmpty &&
                            int.tryParse(_people[i].finalDue.text) != null)
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Text(() {
                              final difference =
                                  int.parse(_people[i].finalDue.text) -
                                  allocation.suggestedDues[i] ~/ 100;
                              if (difference == 0) return '與建議相同';
                              return difference > 0
                                  ? '多收 NT\$$difference'
                                  : '少收 NT\$${difference.abs()}';
                            }()),
                          ),
                      ],
                    ],
                  ),
                ),
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
}

class _ImportPersonDraft {
  _ImportPersonDraft({
    required this.name,
    required this.item,
    required this.amount,
    required this.finalDue,
    required this.isSelf,
    required this.discountEligible,
    required this.discountIsFixed,
    required this.discount,
    required this.nameConfidence,
    required this.itemConfidence,
    required this.amountConfidence,
    required this.finalDueIsManual,
  });

  factory _ImportPersonDraft.empty() => _ImportPersonDraft(
    name: TextEditingController(),
    item: TextEditingController(),
    amount: TextEditingController(),
    finalDue: TextEditingController(),
    isSelf: false,
    discountEligible: false,
    discountIsFixed: false,
    discount: TextEditingController(text: '0'),
    nameConfidence: 1,
    itemConfidence: 1,
    amountConfidence: 1,
    finalDueIsManual: false,
  );

  final TextEditingController name;
  final TextEditingController item;
  final TextEditingController amount;
  final TextEditingController finalDue;
  final bool isSelf;
  bool discountEligible;
  bool discountIsFixed;
  final TextEditingController discount;
  double nameConfidence;
  double itemConfidence;
  double amountConfidence;
  bool finalDueIsManual;
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
              icon: Icons.credit_card,
            ),
            SummaryCard(
              label: '本人信用卡消費',
              value: moneyText(order.selfExpenseMinor),
              icon: Icons.person_outline,
            ),
            SummaryCard(
              label: '代收代墊刷卡',
              value: moneyText(order.advanceCardMinor),
              icon: Icons.account_balance_wallet_outlined,
            ),
            SummaryCard(
              label: '預計收款',
              value: moneyText(order.expectedCollectionMinor),
              icon: Icons.request_quote_outlined,
            ),
            SummaryCard(
              label: order.expectedCollectionResultMinor >= 0
                  ? '預期代收收益'
                  : '預期代收損失',
              value: moneyText(order.expectedCollectionResultMinor.abs()),
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
              icon: Icons.handshake_outlined,
              tone: const Color(0xFFE27848),
            ),
            SummaryCard(
              label: order.recognizedCollectionResultMinor >= 0
                  ? '已認列收益'
                  : '已認列損失',
              value: moneyText(order.recognizedCollectionResultMinor.abs()),
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
        '${person.itemName} ${moneyText(person.itemAmountMinor)}・'
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

class _ParticipantDraft {
  _ParticipantDraft({
    required this.id,
    required this.name,
    required this.isSelf,
    required this.item,
    required this.amount,
    required this.fee,
    required this.discount,
    required this.discountEligible,
    required this.discountIsFixed,
    required this.finalDue,
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
    discount: TextEditingController(text: '0'),
    discountEligible: false,
    discountIsFixed: false,
    finalDue: TextEditingController(),
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

  factory _ParticipantDraft.fromModel(OrderParticipant item) =>
      _ParticipantDraft(
        id: item.id,
        name: TextEditingController(text: item.name),
        isSelf: item.isSelf,
        item: TextEditingController(text: item.itemName),
        amount: TextEditingController(
          text: (item.itemAmountMinor / 100).toString(),
        ),
        fee: TextEditingController(
          text: (item.sharedFeeMinor / 100).toString(),
        ),
        discount: TextEditingController(
          text: (item.discountMinor / 100).toString(),
        ),
        discountEligible: item.discountEligible,
        discountIsFixed: item.discountIsFixed,
        finalDue: TextEditingController(
          text: item.finalDueMinor == null
              ? ''
              : (item.finalDueMinor! ~/ 100).toString(),
        ),
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
  final TextEditingController discount;
  bool discountEligible;
  bool discountIsFixed;
  final TextEditingController finalDue;
  final CollectionStatus status;
  String collectionMethod;
  String? collectionAccountId;
  final String? token;
  final DateTime? collectedAt;
}

class _ParticipantEditor extends StatelessWidget {
  const _ParticipantEditor({
    required this.draft,
    required this.accounts,
    required this.manual,
    required this.canDelete,
    required this.onDelete,
    required this.onChanged,
  });

  final _ParticipantDraft draft;
  final List<Account> accounts;
  final bool manual;
  final bool canDelete;
  final VoidCallback onDelete;
  final VoidCallback onChanged;

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
          if (manual) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: draft.fee,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(labelText: '費用分攤'),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: const Text('有折扣'),
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
                    labelText: draft.discountIsFixed ? '折扣金額（固定）' : '折扣金額（自動）',
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
          ),
          if (!draft.isSelf) ...[
            const SizedBox(height: 8),
            TextField(
              controller: draft.finalDue,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                labelText: '最終收款（整數元，空白則採系統建議）',
              ),
            ),
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
