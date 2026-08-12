class AllocationResult {
  const AllocationResult({
    required this.feeShares,
    required this.collectionFeeShares,
    required this.discountShares,
    required this.actualDues,
    required this.suggestedDues,
  });

  /// Exact card-cost shares. Their total equals the receipt fees.
  final List<int> feeShares;

  /// Fee amounts used when collecting from participants. Each fee component is
  /// rounded up independently for non-self participants.
  final List<int> collectionFeeShares;
  final List<int> discountShares;
  final List<int> actualDues;
  final List<int> suggestedDues;
}

/// Allocates a TWD order in whole dollars. All inputs must be multiples of 100.
AllocationResult allocateWholeTwd({
  required List<int> itemAmountsMinor,
  required List<bool> isSelf,
  required int deliveryFeeMinor,
  required int serviceFeeMinor,
  required int discountMinor,
  required bool includeSelfInDeliveryFee,
  required bool includeSelfInServiceFee,
  required List<bool> discountEligible,
  List<int?>? fixedDiscountSharesMinor,
}) {
  final amounts = [
    deliveryFeeMinor,
    serviceFeeMinor,
    discountMinor,
    ...itemAmountsMinor,
  ];
  if (amounts.any((amount) => amount % 100 != 0)) {
    throw const FormatException('TWD 分攤金額必須是整數元');
  }
  if (itemAmountsMinor.length != isSelf.length ||
      itemAmountsMinor.length != discountEligible.length ||
      (fixedDiscountSharesMinor != null &&
          itemAmountsMinor.length != fixedDiscountSharesMinor.length)) {
    throw ArgumentError('參與者與餐點金額數量不一致');
  }
  if (itemAmountsMinor.isEmpty) {
    return const AllocationResult(
      feeShares: [],
      collectionFeeShares: [],
      discountShares: [],
      actualDues: [],
      suggestedDues: [],
    );
  }

  List<int> eligible(bool includeSelf) => [
    for (var i = 0; i < itemAmountsMinor.length; i++)
      if (includeSelf || !isSelf[i]) i,
  ];

  final deliveryEligible = eligible(includeSelfInDeliveryFee);
  final serviceEligible = eligible(includeSelfInServiceFee);
  final discountIndexes = [
    for (var i = 0; i < discountEligible.length; i++)
      if (discountEligible[i]) i,
  ];
  if ((deliveryFeeMinor > 0 && deliveryEligible.isEmpty) ||
      (serviceFeeMinor > 0 && serviceEligible.isEmpty)) {
    throw const FormatException('外送費與服務費至少需要一位可分攤的參與者');
  }
  if (discountMinor > 0 && discountIndexes.isEmpty) {
    throw const FormatException('訂單有折扣，請至少勾選一位「有折扣」的參與者');
  }

  final fees = List<int>.filled(itemAmountsMinor.length, 0);
  final collectionFees = List<int>.filled(itemAmountsMinor.length, 0);
  void addExact(int totalMinor, List<int> indexes) {
    if (totalMinor == 0) return;
    final dollars = totalMinor ~/ 100;
    final base = dollars ~/ indexes.length;
    final remainder = dollars.remainder(indexes.length);
    for (var position = 0; position < indexes.length; position++) {
      fees[indexes[position]] += (base + (position < remainder ? 1 : 0)) * 100;
    }
  }

  void addRoundedCollection(int totalMinor, List<int> indexes) {
    if (totalMinor == 0) return;
    final roundedEachDollars =
        ((totalMinor ~/ 100) + indexes.length - 1) ~/ indexes.length;
    for (final index in indexes) {
      collectionFees[index] += isSelf[index] ? 0 : roundedEachDollars * 100;
    }
  }

  addExact(deliveryFeeMinor, deliveryEligible);
  addExact(serviceFeeMinor, serviceEligible);
  addRoundedCollection(deliveryFeeMinor, deliveryEligible);
  addRoundedCollection(serviceFeeMinor, serviceEligible);
  for (var index = 0; index < fees.length; index++) {
    if (isSelf[index]) collectionFees[index] = fees[index];
  }

  final discounts = allocateDiscountWholeTwd(
    totalMinor: discountMinor,
    discountEligible: discountEligible,
    participantCount: itemAmountsMinor.length,
    fixedSharesMinor: fixedDiscountSharesMinor,
  );
  final actual = [
    for (var i = 0; i < itemAmountsMinor.length; i++)
      itemAmountsMinor[i] + fees[i] - discounts[i] < 0
          ? 0
          : itemAmountsMinor[i] + fees[i] - discounts[i],
  ];
  final suggested = [
    for (var i = 0; i < itemAmountsMinor.length; i++)
      itemAmountsMinor[i] + collectionFees[i] - discounts[i] < 0
          ? 0
          : itemAmountsMinor[i] + collectionFees[i] - discounts[i],
  ];
  return AllocationResult(
    feeShares: fees,
    collectionFeeShares: collectionFees,
    discountShares: discounts,
    actualDues: actual,
    suggestedDues: suggested,
  );
}

List<int> allocateDiscountWholeTwd({
  required int totalMinor,
  required List<bool> discountEligible,
  required int participantCount,
  required List<int?>? fixedSharesMinor,
}) {
  if (totalMinor < 0 || totalMinor % 100 != 0) {
    throw const FormatException('訂單折扣必須是非負整數元');
  }
  if (discountEligible.length != participantCount ||
      (fixedSharesMinor != null &&
          fixedSharesMinor.length != participantCount)) {
    throw ArgumentError('參與者與折扣設定數量不一致');
  }
  final eligibleIndexes = [
    for (var i = 0; i < discountEligible.length; i++)
      if (discountEligible[i]) i,
  ];
  final result = List<int>.filled(participantCount, 0);
  final totalDollars = totalMinor ~/ 100;
  if (totalDollars == 0) return result;
  if (eligibleIndexes.isEmpty) {
    throw const FormatException('訂單有折扣，請至少勾選一位「有折扣」的參與者');
  }

  var fixedDollars = 0;
  final automaticIndexes = <int>[];
  for (final index in eligibleIndexes) {
    final fixed = fixedSharesMinor?[index];
    if (fixed == null) {
      automaticIndexes.add(index);
      continue;
    }
    if (fixed < 0 || fixed % 100 != 0) {
      throw const FormatException('固定折扣必須是非負整數元');
    }
    result[index] = fixed;
    fixedDollars += fixed ~/ 100;
  }
  if (fixedDollars > totalDollars) {
    throw const FormatException('已固定的折扣合計不能超過訂單折扣');
  }
  final remaining = totalDollars - fixedDollars;
  if (automaticIndexes.isEmpty) {
    if (remaining != 0) {
      throw const FormatException('尚有折扣未分配，請新增自動分配者或調整固定金額');
    }
    return result;
  }
  final base = remaining ~/ automaticIndexes.length;
  final remainder = remaining.remainder(automaticIndexes.length);
  for (var position = 0; position < automaticIndexes.length; position++) {
    result[automaticIndexes[position]] =
        (base + (position < remainder ? 1 : 0)) * 100;
  }
  return result;
}
