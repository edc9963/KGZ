import 'local_ocr_worker.dart';
import 'ocr_models.dart';
import 'repositories.dart';

class LocalUberEatsOrderImportRepository implements OrderImportRepository {
  const LocalUberEatsOrderImportRepository();

  @override
  Future<ImportedOrder> importUberEats(
    List<ImportImage> images, {
    OcrProgressCallback? onProgress,
  }) async {
    final pages = await recognizeImportImages(images, onProgress: onProgress);
    onProgress?.call(
      const OcrProgress(stage: 'parse', progress: 1, message: '正在解析與對帳'),
    );
    return parseUberEatsOcrPages(pages);
  }
}

ImportedOrder parseUberEatsOcrPages(
  List<OcrPage> pages, {
  DateTime? fallbackDate,
}) {
  final orderedPages = [...pages]
    ..sort((a, b) {
      final byRank = _receiptPageRank(
        a.text,
      ).compareTo(_receiptPageRank(b.text));
      return byRank != 0 ? byRank : a.pageIndex.compareTo(b.pageIndex);
    });
  final mergedPages = <String>[];
  final fieldConfidence = <String, double>{};
  final participantConfidence = <String, (double, double, double)>{};

  for (final page in orderedPages) {
    final textLines =
        page.lines
            .where((line) => line.kind == 'text' && line.text.trim().isNotEmpty)
            .toList()
          ..sort((a, b) {
            final byTop = a.top.compareTo(b.top);
            return byTop != 0 ? byTop : a.left.compareTo(b.left);
          });
    final amountLines = page.lines
        .where(
          (line) => line.kind == 'amount' && _looseMoneyText(line.text) != null,
        )
        .toList();
    final output = <String>[];
    for (final line in textLines) {
      var text = line.text.trim();
      if (_isAmountOnly(text)) continue;
      final sameRow =
          amountLines
              .where(
                (amount) =>
                    (amount.centerY - line.centerY).abs() <=
                    ((line.bottom - line.top).abs() * 0.9).clamp(0.012, 0.032),
              )
              .toList()
            ..sort((a, b) {
              final byDistance = (a.centerY - line.centerY).abs().compareTo(
                (b.centerY - line.centerY).abs(),
              );
              return byDistance != 0 ? byDistance : b.left.compareTo(a.left);
            });
      OcrLine? pairedAmount;
      if (sameRow.isNotEmpty) {
        pairedAmount = sameRow.first;
        final amount = _looseMoneyText(pairedAmount.text);
        if (amount != null) text = '$text \$$amount';
      }
      output.add(text);

      final confidence = pairedAmount == null
          ? line.confidence
          : (line.confidence < pairedAmount.confidence
                ? line.confidence
                : pairedAmount.confidence);
      final field = _summaryField(text);
      if (field != null) {
        fieldConfidence[field] = _bestConfidence(
          fieldConfidence[field],
          confidence,
        );
      }
      final item = _itemFromLine(text);
      if (item != null) {
        participantConfidence['item:${item.name}:${item.amountMinor}'] = (
          line.confidence,
          line.confidence,
          confidence,
        );
      }
    }
    mergedPages.add(output.join('\n'));
  }

  final candidates = <(ImportedOrder, int)>[];
  for (final entry in [
    ([for (final page in orderedPages) page.text], 0),
    (mergedPages, 30),
  ]) {
    try {
      candidates.add((
        parseUberEatsReceiptText(entry.$1, fallbackDate: fallbackDate),
        entry.$2,
      ));
    } on Object {
      // The other OCR representation may still be usable.
    }
  }
  if (candidates.isEmpty) {
    throw StateError('未辨識到參與者與餐點，請改用較清晰的 Uber Eats 電子明細截圖');
  }
  candidates.sort(
    (a, b) => (_receiptCandidateScore(a.$1) + a.$2).compareTo(
      _receiptCandidateScore(b.$1) + b.$2,
    ),
  );
  final parsed = candidates.first.$1;
  final participants = <ImportedParticipant>[];
  for (final participant in parsed.participants) {
    final matching = participantConfidence.entries
        .where(
          (entry) =>
              entry.key.endsWith(':${participant.itemAmountMinor}') ||
              participant.itemName
                  .split('、')
                  .any((name) => entry.key.startsWith('item:$name:')),
        )
        .map((entry) => entry.value)
        .toList();
    final amountConfidence = matching.isEmpty
        ? 0.65
        : matching.map((value) => value.$3).reduce((a, b) => a < b ? a : b);
    participants.add(
      ImportedParticipant(
        name: participant.name,
        isSelf: participant.isSelf,
        itemName: '餐點',
        itemAmountMinor: participant.itemAmountMinor,
        nameConfidence: participant.name == '本人' || participant.name == '待確認'
            ? 0.35
            : _plausibleNameConfidence(participant.name),
        itemConfidence: 1,
        amountConfidence: amountConfidence,
      ),
    );
  }

  final warnings = [...parsed.warnings];
  if (participants.any(
    (participant) =>
        participant.nameConfidence < 0.75 ||
        participant.amountConfidence < 0.75,
  )) {
    warnings.add('黃色欄位為低信心辨識結果，請對照原圖確認');
  }
  final itemTotal = participants.fold<int>(
    0,
    (sum, participant) => sum + participant.itemAmountMinor,
  );
  if (parsed.discountMinor > itemTotal) {
    fieldConfidence['discount'] = 0.1;
    warnings.add('折扣金額大於餐點小計，極可能辨識錯誤');
  }
  for (final field in const ['total', 'delivery', 'service', 'discount']) {
    fieldConfidence.putIfAbsent(field, () => 0.35);
  }

  return ImportedOrder(
    name: parsed.name,
    platform: parsed.platform,
    date: parsed.date,
    totalMinor: parsed.totalMinor,
    deliveryFeeMinor: parsed.deliveryFeeMinor,
    serviceFeeMinor: parsed.serviceFeeMinor,
    discountMinor: parsed.discountMinor,
    paymentLastFour: parsed.paymentLastFour,
    participants: participants,
    warnings: warnings.toSet().toList(),
    reconciliationDifferenceMinor: parsed.reconciliationDifferenceMinor,
    fieldConfidence: fieldConfidence,
  );
}

int _receiptPageRank(String source) {
  final compact = source.replaceAll(RegExp(r'\s+'), '');
  var rank = 0;
  if (compact.contains('總計') && !compact.startsWith('餐點小計')) rank -= 1000;
  if (compact.contains('(您)') || compact.contains('（您）')) rank -= 500;
  if (compact.contains('款項')) rank += 1000;
  if (compact.contains('JCB')) rank += 300;
  return rank;
}

int _receiptCandidateScore(ImportedOrder order) {
  var score = order.reconciliationDifferenceMinor.abs() ~/ 100;
  if (order.warnings.any((warning) => warning.startsWith('餐點合計 '))) {
    score += 400;
  }
  if (order.totalMinor <= 0) score += 500;
  if (order.paymentLastFour == null) score += 20;
  if (order.participants.length < 2) score += 250;
  if (!order.participants.any((participant) => participant.isSelf)) {
    score += 100;
  }
  for (final participant in order.participants) {
    final compactName = participant.name.replaceAll(' ', '');
    if (compactName.contains('明細') ||
        compactName.contains('總計') ||
        participant.name == '待確認' ||
        participant.name == '本人') {
      score += 300;
    }
  }
  final itemTotal = order.participants.fold<int>(
    0,
    (sum, participant) => sum + participant.itemAmountMinor,
  );
  if (order.discountMinor >
      itemTotal + order.deliveryFeeMinor + order.serviceFeeMinor) {
    score += 500;
  }
  return score;
}

ImportedOrder parseUberEatsReceiptText(
  List<String> pages, {
  DateTime? fallbackDate,
}) {
  final now = fallbackDate ?? DateTime.now();
  final warnings = <String>['使用瀏覽器本機 OCR，請逐項確認辨識結果'];
  final participants = <_ParticipantBuffer>[];
  _ParticipantBuffer? current;
  var pageBoundary = false;
  var totalMinor = 0;
  var priorityDeliveryFeeMinor = 0;
  var grossDeliveryFeeMinor = 0;
  var grossServiceFeeMinor = 0;
  var deliveryFeeDiscountMinor = 0;
  var serviceFeeDiscountMinor = 0;
  var orderDiscountMinor = 0;
  final seenOrderDiscountRows = <String>{};
  var receiptSubtotalMinor = 0;
  var advertisedRewardsMinor = 0;
  String? paymentLastFour;
  DateTime? orderDate;

  for (var pageIndex = 0; pageIndex < pages.length; pageIndex++) {
    final lines = _normalizedLines(pages[pageIndex]);
    pageBoundary = pageIndex > 0;
    var summarySectionStarted = false;
    for (var index = 0; index < lines.length; index++) {
      final line = lines[index];
      paymentLastFour ??= _lastFour(line);
      orderDate ??= _dateFromLine(line);
      if (_hasLabel(line, '餐點小計') || _hasLabel(line, '款項')) {
        summarySectionStarted = true;
      }

      final summaryAmount = _moneyFromLine(line);
      if (summaryAmount != null) {
        if (_hasLabel(line, '餐點小計')) {
          receiptSubtotalMinor = _largerAmount(
            receiptSubtotalMinor,
            summaryAmount.abs(),
          );
          continue;
        }
        if (_hasLabel(line, '總計') && !_hasLabel(line, '小計')) {
          totalMinor = _largerAmount(totalMinor, summaryAmount.abs());
          continue;
        }
        if (_isPaymentTotalLine(line)) {
          totalMinor = _largerAmount(totalMinor, summaryAmount.abs());
          continue;
        }
        if (_hasLabel(line, '已使用') &&
            (_hasLabel(line, '優惠') || _hasLabel(line, '獎勵'))) {
          advertisedRewardsMinor = summaryAmount.abs();
          continue;
        }
        if (_isDeliveryDiscountLine(line)) {
          deliveryFeeDiscountMinor = _largerAmount(
            deliveryFeeDiscountMinor,
            summaryAmount.abs(),
          );
          continue;
        }
        if (_isPriorityDeliveryLine(line)) {
          priorityDeliveryFeeMinor = _largerAmount(
            priorityDeliveryFeeMinor,
            summaryAmount.abs(),
          );
          continue;
        }
        if (_isRegularDeliveryFeeLine(line)) {
          grossDeliveryFeeMinor = _largerAmount(
            grossDeliveryFeeMinor,
            summaryAmount.abs(),
          );
          continue;
        }
        if (_isMemberRewardLine(line)) {
          serviceFeeDiscountMinor = _largerAmount(
            serviceFeeDiscountMinor,
            summaryAmount.abs(),
          );
          continue;
        }
        if (_hasLabel(line, '服務費')) {
          grossServiceFeeMinor = _largerAmount(
            grossServiceFeeMinor,
            summaryAmount.abs(),
          );
          continue;
        }
        if (_isDiscountLine(line)) {
          final fingerprint = _discountLineFingerprint(
            line,
            summaryAmount.abs(),
          );
          if (seenOrderDiscountRows.add(fingerprint)) {
            orderDiscountMinor += summaryAmount.abs();
          }
          continue;
        }
      }

      if (summarySectionStarted) continue;

      if (_isModifierLine(line)) {
        if (!pageBoundary && current != null) {
          current.addModifier(_modifierText(line));
        }
        continue;
      }

      if (_isSelfHeader(line)) {
        current = _findOrCreateParticipant(
          participants,
          _participantName(line, fallback: '本人'),
          isSelf: true,
        );
        pageBoundary = false;
        continue;
      }

      final item = _itemFromLine(line);
      if (item != null) {
        if (current == null) {
          warnings.add('已忽略姓名出現前的疑似優惠或品項文字');
          continue;
        }
        if (pageBoundary &&
            participants.any((participant) => participant.contains(item))) {
          pageBoundary = false;
          continue;
        }
        if (pageIndex > 0 && current.contains(item)) {
          pageBoundary = false;
          continue;
        }
        current.add(item);
        pageBoundary = false;
        continue;
      }

      if (_looksLikeParticipantHeader(line, lines, index)) {
        current = _findOrCreateParticipant(
          participants,
          _participantName(line),
          isSelf: false,
        );
        pageBoundary = false;
      }
    }
  }

  participants.removeWhere((participant) => participant.items.isEmpty);
  if (participants.isEmpty) {
    throw StateError('未辨識到參與者與餐點，請改用較清晰的 Uber Eats 電子明細截圖');
  }
  if (!participants.any((participant) => participant.isSelf)) {
    participants.first.isSelf = true;
    warnings.add('未辨識到「您」，已暫時將第一位參與者設為本人');
  }
  final selfIndex = participants.indexWhere(
    (participant) => participant.isSelf,
  );
  if (selfIndex > 0) {
    final self = participants.removeAt(selfIndex);
    participants.insert(0, self);
  }
  if (totalMinor == 0) warnings.add('未辨識到訂單總額，請手動確認');
  if (paymentLastFour == null) warnings.add('未辨識到付款卡末四碼');
  if (orderDate == null) warnings.add('未辨識到日期，已使用今天日期');

  final itemTotal = participants.fold<int>(
    0,
    (sum, participant) => sum + participant.amountMinor,
  );
  final combinedGrossDeliveryFeeMinor =
      priorityDeliveryFeeMinor + grossDeliveryFeeMinor;
  if (receiptSubtotalMinor > 0 && itemTotal != receiptSubtotalMinor) {
    warnings.add(
      '餐點合計 ${itemTotal ~/ 100} 與畫面餐點小計 '
      '${receiptSubtotalMinor ~/ 100} 不符',
    );
  }
  if (totalMinor > 0 &&
      receiptSubtotalMinor > 0 &&
      itemTotal == receiptSubtotalMinor) {
    final requiredDiscount =
        receiptSubtotalMinor +
        combinedGrossDeliveryFeeMinor +
        grossServiceFeeMinor -
        totalMinor;
    var missingDiscount =
        requiredDiscount -
        deliveryFeeDiscountMinor -
        serviceFeeDiscountMinor -
        orderDiscountMinor;
    if (missingDiscount > 0 &&
        (advertisedRewardsMinor == 0 ||
            (requiredDiscount - advertisedRewardsMinor).abs() <= 100)) {
      final deliveryCapacity =
          combinedGrossDeliveryFeeMinor - deliveryFeeDiscountMinor;
      final inferredDelivery = missingDiscount
          .clamp(0, deliveryCapacity)
          .toInt();
      deliveryFeeDiscountMinor += inferredDelivery;
      missingDiscount -= inferredDelivery;
      final serviceCapacity = grossServiceFeeMinor - serviceFeeDiscountMinor;
      final inferredService = missingDiscount.clamp(0, serviceCapacity).toInt();
      serviceFeeDiscountMinor += inferredService;
      missingDiscount -= inferredService;
      if (missingDiscount > 0) orderDiscountMinor += missingDiscount;
      warnings.add('已依餐點小計、總額與優惠合計補足漏讀的優惠');
    }
  }
  var deliveryFeeMinor =
      (combinedGrossDeliveryFeeMinor - deliveryFeeDiscountMinor)
          .clamp(0, combinedGrossDeliveryFeeMinor)
          .toInt();
  var serviceFeeMinor = (grossServiceFeeMinor - serviceFeeDiscountMinor)
      .clamp(0, grossServiceFeeMinor)
      .toInt();
  final discountMinor = orderDiscountMinor;
  if (totalMinor > 0 &&
      receiptSubtotalMinor > 0 &&
      itemTotal == receiptSubtotalMinor) {
    final expectedNetFees = totalMinor + discountMinor - receiptSubtotalMinor;
    final unidentifiedNetFee =
        expectedNetFees - deliveryFeeMinor - serviceFeeMinor;
    if (expectedNetFees >= 0 && unidentifiedNetFee > 0) {
      serviceFeeMinor += unidentifiedNetFee;
      if (grossServiceFeeMinor == 0 && serviceFeeDiscountMinor > 0) {
        grossServiceFeeMinor = serviceFeeMinor + serviceFeeDiscountMinor;
      }
      warnings.add(
        '服務費明細辨識不完整，已依餐點小計 '
        '${receiptSubtotalMinor ~/ 100} 與總額 ${totalMinor ~/ 100}'
        '補算淨服務費 ${unidentifiedNetFee ~/ 100}',
      );
    }
  }
  if (deliveryFeeDiscountMinor > 0) {
    final calculation = priorityDeliveryFeeMinor > 0
        ? '${priorityDeliveryFeeMinor ~/ 100}＋'
              '${grossDeliveryFeeMinor ~/ 100}－優惠 '
              '${deliveryFeeDiscountMinor ~/ 100}＝'
              '${deliveryFeeMinor ~/ 100}'
        : '${grossDeliveryFeeMinor ~/ 100}－優惠 '
              '${deliveryFeeDiscountMinor ~/ 100}＝'
              '${deliveryFeeMinor ~/ 100}';
    warnings.add('外送費 $calculation');
  }
  if (serviceFeeDiscountMinor > 0) {
    warnings.add(
      '服務費 ${grossServiceFeeMinor ~/ 100}－會員獎勵 '
      '${serviceFeeDiscountMinor ~/ 100}＝${serviceFeeMinor ~/ 100}',
    );
  }
  final calculatedTotal =
      itemTotal + deliveryFeeMinor + serviceFeeMinor - discountMinor;
  final effectiveTotal = totalMinor == 0 ? calculatedTotal : totalMinor;
  final reconciliationDifference = effectiveTotal - calculatedTotal;
  if (reconciliationDifference != 0) {
    warnings.add('對帳差額 NT\$${reconciliationDifference.abs() ~/ 100}');
  }

  return ImportedOrder(
    name: 'Uber Eats 代訂 ${_dateLabel(orderDate ?? now)}',
    platform: 'Uber Eats',
    date: orderDate ?? DateTime(now.year, now.month, now.day),
    totalMinor: effectiveTotal,
    deliveryFeeMinor: deliveryFeeMinor,
    serviceFeeMinor: serviceFeeMinor,
    discountMinor: discountMinor,
    paymentLastFour: paymentLastFour,
    participants: [
      for (final participant in participants)
        ImportedParticipant(
          name: participant.name,
          isSelf: participant.isSelf,
          itemName: '餐點',
          itemAmountMinor: participant.amountMinor,
        ),
    ],
    warnings: warnings,
    reconciliationDifferenceMinor: reconciliationDifference,
    fieldConfidence: const {
      'total': 1,
      'delivery': 1,
      'service': 1,
      'discount': 1,
    },
  );
}

double _bestConfidence(double? current, double next) =>
    current == null || next > current ? next : current;

String? _summaryField(String line) {
  if (_hasLabel(line, '總計') && !_hasLabel(line, '小計')) return 'total';
  if (_isPaymentTotalLine(line)) return 'total';
  if (_isDeliveryDiscountLine(line)) return 'delivery';
  if (_isMemberRewardLine(line)) return 'service';
  if (_isPriorityDeliveryLine(line) || _isRegularDeliveryFeeLine(line)) {
    return 'delivery';
  }
  if (_hasLabel(line, '服務費')) return 'service';
  if (_isDiscountLine(line)) return 'discount';
  return null;
}

bool _isAmountOnly(String text) => RegExp(
  r'^\s*[-−]?\s*(?:NT\s*)?\$?\s*[\d,]+(?:\.\d{1,2})?\s*$',
  caseSensitive: false,
).hasMatch(text);

String? _looseMoneyText(String text) {
  final matches = RegExp(
    r'[-−]?\s*\$?\s*([\d,]+(?:\.\d{1,2})?)',
  ).allMatches(text);
  if (matches.isEmpty) return null;
  var value = matches.last.group(1);
  if (value == null || value.replaceAll(RegExp(r'\D'), '').length > 6) {
    return null;
  }
  if (!value.contains('.') &&
      RegExp(r'^\d{2,3}00$').hasMatch(value.replaceAll(',', ''))) {
    value =
        '${value.substring(0, value.length - 2)}.'
        '${value.substring(value.length - 2)}';
  }
  return value;
}

double _plausibleNameConfidence(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty ||
      trimmed.length > 30 ||
      RegExp(r'^[^\p{L}]+$', unicode: true).hasMatch(trimmed)) {
    return 0.3;
  }
  return 0.85;
}

List<String> _normalizedLines(String source) => source
    .replaceAll('\r', '\n')
    .replaceAll('＄', r'$')
    .replaceAll('−', '-')
    .replaceAll('–', '-')
    .replaceAllMapped(
      RegExp(r'(\d)[Zz](\d{2})'),
      (match) => '${match.group(1)}.${match.group(2)}',
    )
    .replaceAllMapped(
      RegExp(r'\$(\d{2,3})00(?!\d)'),
      (match) => '\$${match.group(1)}.00',
    )
    .split(RegExp(r'\n+'))
    .map((line) => _joinHanSpacing(line.replaceAll(RegExp(r'\s+'), ' ').trim()))
    .where((line) => line.isNotEmpty)
    .toList();

String _joinHanSpacing(String source) {
  var value = source;
  final betweenHan = RegExp(r'([\u3400-\u9FFF])\s+([\u3400-\u9FFF])');
  while (betweenHan.hasMatch(value)) {
    value = value.replaceAllMapped(
      betweenHan,
      (match) => '${match.group(1)}${match.group(2)}',
    );
  }
  return value;
}

bool _hasLabel(String line, String label) =>
    line.replaceAll(' ', '').contains(label);

bool _isDiscountLine(String line) =>
    !_hasLabel(line, '已使用') &&
    !_isDeliveryDiscountLine(line) &&
    !_isMemberRewardLine(line) &&
    (_hasLabel(line, '優惠') ||
        _hasLabel(line, '折抵') ||
        _hasLabel(line, '折扣') ||
        _isUberOnePointsLine(line));

bool _isUberOnePointsLine(String line) {
  final compact = line.replaceAll(' ', '').toLowerCase();
  return compact.contains('uberone') && compact.contains('點數');
}

String _discountLineFingerprint(String line, int amountMinor) {
  if (_isUberOnePointsLine(line)) return 'uber-one-points:$amountMinor';
  final label = line
      .toLowerCase()
      .replaceAll(
        RegExp(
          r'[-−]?\s*(?:NT\s*)?\$\s*[\d,]+(?:\.\d{1,2})?|[-−]\s*[\d,]+(?:\.\d{1,2})?',
          caseSensitive: false,
        ),
        '',
      )
      .replaceAll(RegExp(r'[^\p{L}\p{N}]', unicode: true), '');
  return '$label:$amountMinor';
}

bool _isPriorityDeliveryLine(String line) =>
    _hasLabel(line, '優先外送') || _hasLabel(line, '優先配送');

bool _isDeliveryDiscountLine(String line) =>
    !_hasLabel(line, '已使用') &&
    (_hasLabel(line, '外送') || _hasLabel(line, '配送')) &&
    (_hasLabel(line, '優惠') || _hasLabel(line, '折抵') || _hasLabel(line, '折扣'));

bool _isRegularDeliveryFeeLine(String line) =>
    !_isPriorityDeliveryLine(line) &&
    !_isDeliveryDiscountLine(line) &&
    (_hasLabel(line, '外送費') || _hasLabel(line, '配送費'));

bool _isMemberRewardLine(String line) =>
    _hasLabel(line, '會員獎勵') || (_hasLabel(line, '會員') && _hasLabel(line, '獎勵'));

bool _isPaymentTotalLine(String line) {
  final compact = line.replaceAll(' ', '').toUpperCase();
  return compact.contains('JCB') ||
      compact.contains('VISA') ||
      compact.contains('MASTERCARD') ||
      compact.contains('信用卡');
}

int _largerAmount(int current, int candidate) =>
    candidate > current ? candidate : current;

int? _moneyFromLine(String line) {
  final matches = RegExp(
    r'[-−]?\s*(?:NT\s*)?\$\s*([\d,]+)(?:\.(\d{1,2}))?|[-−]\s*([\d,]+)(?:\.(\d{1,2}))?',
    caseSensitive: false,
  ).allMatches(line).toList();
  if (matches.isEmpty) return null;
  final match = matches.last;
  final whole = (match.group(1) ?? match.group(3))?.replaceAll(',', '');
  if (whole == null) return null;
  final fraction = (match.group(2) ?? match.group(4) ?? '').padRight(2, '0');
  return int.parse(whole) * 100 +
      (fraction.isEmpty ? 0 : int.parse(fraction.substring(0, 2)));
}

_ParsedItem? _itemFromLine(String line) {
  if (_isSummaryLine(line) ||
      RegExp(r'^\s*\d+\s*個(?:\s|\(|（|$)').hasMatch(line)) {
    return null;
  }
  if (RegExp(
    r'[\(（]\s*[-−]?\s*(?:NT\s*)?\$\s*[\d,]+(?:\.\d{1,2})?\s*[\)）]\s*$',
    caseSensitive: false,
  ).hasMatch(line)) {
    return null;
  }
  final amount = _moneyFromLine(line);
  if (amount == null) return null;
  var name = line
      .replaceAll(
        RegExp(
          r'[-−]?\s*(?:NT\s*)?\$\s*[\d,]+(?:\.\d{1,2})?',
          caseSensitive: false,
        ),
        '',
      )
      .replaceFirst(RegExp(r'^\s*\d+\s+'), '')
      .trim();
  if (name.isEmpty || RegExp(r'^\d+\s*個').hasMatch(name)) return null;
  return _ParsedItem(name, amount.abs());
}

bool _isSummaryLine(String line) {
  const labels = [
    '總計',
    '餐點小計',
    '外送費',
    '配送費',
    '優先外送',
    '優先配送',
    '服務費',
    '優惠',
    '折抵',
    '折扣',
    '會員獎勵',
    '款項',
  ];
  return labels.any((label) => _hasLabel(line, label)) ||
      _isPaymentTotalLine(line);
}

bool _isSelfHeader(String line) =>
    line.replaceAll(' ', '').contains('(您)') ||
    line.replaceAll(' ', '').contains('（您）');

String _participantName(String line, {String fallback = '待確認'}) {
  final value = line
      .replaceAll(RegExp(r'\s*[\(（]\s*您\s*[\)）]'), '')
      .replaceAll(RegExp(r'[:：]$'), '')
      .trim();
  return value.isEmpty ? fallback : value;
}

bool _looksLikeParticipantHeader(String line, List<String> lines, int index) {
  final trimmed = line.trim();
  final compact = trimmed.replaceAll(' ', '');
  if (trimmed.length > 30 ||
      _moneyFromLine(line) != null ||
      _isSummaryLine(line) ||
      _hasLabel(line, '明細') ||
      RegExp(r'\d').hasMatch(line) ||
      _looksLikeModifierText(trimmed) ||
      _looksLikeMenuText(compact) ||
      const ['電子明細', '款項', '搜尋'].any((label) => _hasLabel(line, label))) {
    return false;
  }
  for (var next = index + 1; next < lines.length && next <= index + 2; next++) {
    if (_itemFromLine(lines[next]) != null) return true;
  }
  return false;
}

bool _looksLikeModifierText(String line) {
  final compact = line.replaceAll(' ', '').toLowerCase();
  if (RegExp(r'^[\(（\[].*[\)）\]]$').hasMatch(compact)) return true;
  const labels = [
    'medium',
    'combo',
    'frenchfries',
    'pepsi',
    'greentea',
    '7up',
    '百事',
    '可樂',
    '綠茶',
    '七喜',
    '中薯',
    '大薯',
    '套餐',
    '選項',
  ];
  return labels.any(compact.contains);
}

bool _looksLikeMenuText(String compact) {
  final hanCount = RegExp(r'[\u3400-\u9FFF]').allMatches(compact).length;
  if (hanCount <= 6) return false;
  const menuTerms = ['餐', '堡', '肉', '蝦', '薯', '圈', '飯', '麵', '餃', '湯'];
  return menuTerms.any(compact.contains);
}

String? _lastFour(String line) {
  final match = RegExp(
    r'(?:[•·‧。＊*]{2,}|末四碼\D*|JCB\D+)(\d{4})',
    caseSensitive: false,
  ).firstMatch(line);
  return match?.group(1);
}

DateTime? _dateFromLine(String line) {
  final match = RegExp(r'(20\d{2})[/-](\d{1,2})[/-](\d{1,2})').firstMatch(line);
  if (match == null) return null;
  return DateTime(
    int.parse(match.group(1)!),
    int.parse(match.group(2)!),
    int.parse(match.group(3)!),
  );
}

String _dateLabel(DateTime date) =>
    '${date.year}/${date.month.toString().padLeft(2, '0')}/${date.day.toString().padLeft(2, '0')}';

_ParticipantBuffer _findOrCreateParticipant(
  List<_ParticipantBuffer> participants,
  String name, {
  required bool isSelf,
}) {
  for (final participant in participants) {
    if (_participantNamesMatch(participant.name, name)) {
      participant.isSelf = participant.isSelf || isSelf;
      return participant;
    }
  }
  final participant = _ParticipantBuffer(name, isSelf);
  participants.add(participant);
  return participant;
}

bool _participantNamesMatch(String left, String right) {
  final leftKey = _participantKey(left);
  final rightKey = _participantKey(right);
  if (leftKey == rightKey) return true;
  if (!RegExp(r'^[a-z]+$').hasMatch(leftKey) ||
      !RegExp(r'^[a-z]+$').hasMatch(rightKey) ||
      leftKey.length < 6 ||
      rightKey.length < 6 ||
      (leftKey.length - rightKey.length).abs() > 1) {
    return false;
  }
  return _ocrEditDistance(leftKey, rightKey) <= 2;
}

int _ocrEditDistance(String left, String right) {
  var previous = List<int>.generate(right.length + 1, (index) => index);
  for (var row = 1; row <= left.length; row++) {
    final current = List<int>.filled(right.length + 1, 0)..[0] = row;
    for (var column = 1; column <= right.length; column++) {
      final replace =
          previous[column - 1] + (left[row - 1] == right[column - 1] ? 0 : 1);
      current[column] = [
        replace,
        current[column - 1] + 1,
        previous[column] + 1,
      ].reduce((a, b) => a < b ? a : b);
    }
    previous = current;
  }
  return previous.last;
}

String _participantKey(String value) {
  final compact = value.toLowerCase().replaceAll(RegExp(r'\s+'), '');
  if (RegExp(r'^[a-z0-9]+$').hasMatch(compact)) {
    return compact.replaceAll(RegExp(r'[l1]'), 'i').replaceAll('0', 'o');
  }
  return compact;
}

class _ParticipantBuffer {
  _ParticipantBuffer(this.name, this.isSelf);
  final String name;
  bool isSelf;
  final List<_ParsedItem> items = [];

  int get amountMinor => items.fold(0, (sum, item) => sum + item.amountMinor);

  void add(_ParsedItem item) => items.add(item);

  void addModifier(String modifier) {
    if (items.isEmpty || modifier.isEmpty) return;
    final previous = items.last;
    final marker = '（$modifier）';
    if (previous.name.contains(marker)) return;
    items[items.length - 1] = _ParsedItem(
      '${previous.name}$marker',
      previous.amountMinor,
    );
  }

  bool contains(_ParsedItem candidate) =>
      items.any((item) => _itemsMatch(item, candidate));
}

bool _itemsMatch(_ParsedItem left, _ParsedItem right) =>
    left.amountMinor == right.amountMinor &&
    _itemNamesMatch(left.name, right.name);

bool _itemNamesMatch(String left, String right) {
  final leftKey = _itemKey(_withoutModifiers(left));
  final rightKey = _itemKey(_withoutModifiers(right));
  if (leftKey == rightKey) return true;
  if (leftKey.length < 3 || rightKey.length < 3) return false;
  if (leftKey.contains(rightKey) || rightKey.contains(leftKey)) return true;
  return (leftKey.length - rightKey.length).abs() <= 2 &&
      _ocrEditDistance(leftKey, rightKey) <= 2;
}

bool _isModifierLine(String line) => line.trimLeft().startsWith('[選項]');

String _modifierText(String line) =>
    line.trimLeft().replaceFirst(RegExp(r'^\[選項\]\s*'), '').trim();

String _withoutModifiers(String value) =>
    value.replaceAll(RegExp(r'[（(][^）)]*[）)]'), '');

String _itemKey(String value) => value
    .toLowerCase()
    .replaceAll(RegExp(r'[^\p{L}\p{N}]', unicode: true), '')
    .replaceFirst(RegExp(r'^(?:開|閱|闊|間|人|入|個)'), '');

class _ParsedItem {
  const _ParsedItem(this.name, this.amountMinor);
  final String name;
  final int amountMinor;
}
