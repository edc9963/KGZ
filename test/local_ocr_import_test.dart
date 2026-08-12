import 'package:flutter_test/flutter_test.dart';
import 'package:quick_ledger/data/local_ocr_import_repository.dart';
import 'package:quick_ledger/data/ocr_models.dart';

void main() {
  test('parses and reconciles adjacent Uber Eats receipt screenshots', () {
    final order = parseUberEatsReceiptText(const [
      '''
電子明細
總計 \$636.00
均維 (您)
1 高麗菜豬肉手工水餃 \$137.00
15 個 (\$45.00)
Ray
1 綜合水餃 \$100.00
9 個
1 青菜蛋花湯 \$68.00
Jack
1 綜合水餃 \$100.00
9 個
1 三拚 \$68.00
airwind
2 酸辣湯 \$114.00
1 高麗菜豬肉手工水餃 \$92.00
''',
      '''
1 高麗菜豬肉手工水餃 \$92.00
10 個
餐點小計金額 \$679.00
外送費 \$35.00
服務費 \$55.00
優惠 -\$57.00
外送費優惠 -\$35.00
會員獎勵 -\$41.00
JCB ••••4936
2026/7/28 下午 12:10
''',
    ], fallbackDate: DateTime(2026, 7, 28));

    expect(order.totalMinor, 63600);
    expect(order.deliveryFeeMinor, 0);
    expect(order.serviceFeeMinor, 1400);
    expect(order.discountMinor, 5700);
    expect(order.paymentLastFour, '4936');
    expect(order.reconciliationDifferenceMinor, 0);
    expect(
      order.participants
          .map(
            (participant) => (
              participant.name,
              participant.isSelf,
              participant.itemAmountMinor,
            ),
          )
          .toList(),
      [
        ('均維', true, 13700),
        ('Ray', false, 16800),
        ('Jack', false, 16800),
        ('airwind', false, 20600),
      ],
    );
  });

  test(
    'coordinate pairing ignores unrelated numbers and sums discount rows',
    () {
      OcrLine text(String value, double y, {double confidence = .92}) =>
          OcrLine(
            text: value,
            left: .08,
            top: y,
            right: .58,
            bottom: y + .025,
            confidence: confidence,
            kind: 'text',
          );
      OcrLine amount(String value, double y, {double confidence = .94}) =>
          OcrLine(
            text: value,
            left: .78,
            top: y,
            right: .95,
            bottom: y + .025,
            confidence: confidence,
            kind: 'amount',
          );

      final order = parseUberEatsOcrPages([
        OcrPage(
          pageIndex: 0,
          text: '',
          lines: [
            text('總計', .10),
            amount(r'$636.00', .10),
            amount('5776', .16),
            text('均維（您）', .22),
            text('1 高麗菜豬肉手工水餃', .28),
            amount(r'$137.00', .28),
            text('Ray', .38),
            text('1 綜合水餃', .44),
            amount(r'$168.00', .44),
            text('Jack', .54),
            text('綜合水餃、三拼', .60),
            amount(r'$168.00', .60),
            text('airwind', .70),
            text('酸辣湯、高麗菜豬肉手工水餃', .76),
            amount(r'$206.00', .76),
          ],
        ),
        OcrPage(
          pageIndex: 1,
          text: '',
          lines: [
            text('餐點小計金額', .20),
            amount(r'$679.00', .20),
            text('外送費', .30),
            amount(r'$35.00', .30),
            text('服務費', .38),
            amount(r'$55.00', .38),
            text('優惠', .46),
            amount(r'-$57.00', .46),
            text('外送費優惠', .54),
            amount(r'-$35.00', .54),
            text('會員獎勵', .62),
            amount(r'-$41.00', .62),
            text('JCB ••••4936', .72),
            text('2026/7/28 下午 12:10', .80),
          ],
        ),
      ], fallbackDate: DateTime(2026, 7, 28));

      expect(order.totalMinor, 63600);
      expect(order.deliveryFeeMinor, 0);
      expect(order.serviceFeeMinor, 1400);
      expect(order.discountMinor, 5700);
      expect(order.paymentLastFour, '4936');
      expect(order.reconciliationDifferenceMinor, 0);
      expect(order.fieldConfidence['discount'], greaterThanOrEqualTo(.75));
    },
  );

  test('symbol-only OCR item is retained but marked low confidence', () {
    final order = parseUberEatsOcrPages(const [
      OcrPage(
        pageIndex: 0,
        text: '',
        lines: [
          OcrLine(
            text: '總計 \$133.00',
            left: .1,
            top: .1,
            right: .9,
            bottom: .14,
            confidence: .9,
            kind: 'text',
          ),
          OcrLine(
            text: 'wha',
            left: .1,
            top: .2,
            right: .3,
            bottom: .24,
            confidence: .6,
            kind: 'text',
          ),
          OcrLine(
            text: '& \$133.00',
            left: .1,
            top: .3,
            right: .9,
            bottom: .34,
            confidence: .55,
            kind: 'text',
          ),
        ],
      ),
    ], fallbackDate: DateTime(2026, 7, 28));

    expect(order.participants.single.itemName, '&');
    expect(order.participants.single.itemConfidence, lessThan(.75));
    expect(order.warnings.join(), contains('低信心'));
  });

  test('normalizes spacing and common real Tesseract money mistakes', () {
    final order = parseUberEatsReceiptText(const [
      r'''
電子 明細
總 計 $636.00
$133.00 已 使用 Uber One 優惠 和 其 他 獎勵
均 維 (您 )
1 高 麗 菜 豬肉 手工 水 餃 $137Z00
Ray
1 綜合 水 餃 $100.00
1 青菜 蛋 花 湯 $68.00
Jack
1 綜合 水 餃 $100.00
1 三 拚 $68.00
alrwlnd
2 酸 辣 湯 $114.00
1 高 麗 菜 豬肉 手工 水 餃 $92.00
''',
      r'''
1 高 麗 菜 豬肉 手工 水 餃 $92.00
餐 點 小 計 金 額 $679.00
外 送 費 $35.00
服務 費 $55.00
優惠 -$5700
外 送 費 優惠 -$35.00
會 員 獎 勵 -$41.00
JCB‧。*。*4936 $636.00
2026/7/28 下 午 12:10
''',
    ], fallbackDate: DateTime(2026, 7, 28));

    expect(order.totalMinor, 63600);
    expect(order.deliveryFeeMinor, 0);
    expect(order.serviceFeeMinor, 1400);
    expect(order.discountMinor, 5700);
    expect(order.paymentLastFour, '4936');
    expect(order.reconciliationDifferenceMinor, 0);
    expect(order.participants.first.name, '均維');
    expect(order.participants.first.isSelf, isTrue);
    expect(
      order.participants.map((participant) => participant.itemAmountMinor),
      const [13700, 16800, 16800, 20600],
    );
  });

  test('merges confusable latin names and ignores footer after summary', () {
    final order = parseUberEatsReceiptText(const [
      r'''
總計 $250.00
我（您）
餐點甲 $100.00
Alrwlnd
餐點乙 $100.00
''',
      r'''
Airwind
餐點丙 $50.00
餐點小計金額 $250.00
款項
JCB ••••4936 $250.00
如需詳細資訊請前往訂單頁面 $1086.00
''',
    ], fallbackDate: DateTime(2026, 7, 28));

    expect(order.participants.length, 2);
    expect(order.participants.last.name, 'Alrwlnd');
    expect(order.participants.last.itemAmountMinor, 15000);
    expect(order.reconciliationDifferenceMinor, 0);
  });

  test('chooses complete page text over implausible coordinate extraction', () {
    final order = parseUberEatsOcrPages(const [
      OcrPage(
        pageIndex: 0,
        text: r'''
總計 $200.00
我（您）
餐點甲 $100.00
Ray
餐點乙 $100.00
''',
        lines: [
          OcrLine(
            text: '血子明細',
            left: .1,
            top: .1,
            right: .4,
            bottom: .14,
            confidence: .8,
            kind: 'text',
          ),
          OcrLine(
            text: '@',
            left: .1,
            top: .2,
            right: .3,
            bottom: .24,
            confidence: .5,
            kind: 'text',
          ),
          OcrLine(
            text: '99',
            left: .8,
            top: .2,
            right: .9,
            bottom: .24,
            confidence: .6,
            kind: 'amount',
          ),
        ],
      ),
    ], fallbackDate: DateTime(2026, 7, 28));

    expect(order.totalMinor, 20000);
    expect(order.participants.map((person) => person.name), ['我', 'Ray']);
    expect(order.reconciliationDifferenceMinor, 0);
  });

  test(
    'fee discounts offset delivery and service instead of order discount',
    () {
      final order = parseUberEatsReceiptText(const [
        r'''
總計 $801.00
我（您）
餐點甲 $400.00
Airwind
餐點乙 $390.00
餐點小計金額 $790.00
外送費 $55.00
服務費 $55.00
外送費優惠 -$55.00
會員獎勵 -$44.00
''',
      ], fallbackDate: DateTime(2026, 7, 29));

      expect(order.deliveryFeeMinor, 0);
      expect(order.serviceFeeMinor, 1100);
      expect(order.discountMinor, 0);
      expect(order.reconciliationDifferenceMinor, 0);
      expect(order.warnings.join(), contains('外送費 55－優惠 55＝0'));
      expect(order.warnings.join(), contains('服務費 55－會員獎勵 44＝11'));
    },
  );

  test(
    'auto-orders reversed pages, deduplicates overlap, and infers reward',
    () {
      final order = parseUberEatsOcrPages(const [
        OcrPage(
          pageIndex: 0,
          text: r'''
電子明細
Jack
猛獸嫩 G 胸餐盒 $160.00
Alirwlnd
猛獸嫩 G 胸餐盒 $160.00
餐點小計金額 $790.00
外送費 $55.00
服務費 $55.00
外送費優惠 -$55.00
款項
JCB ••••4936 $801.00
''',
          lines: [],
        ),
        OcrPage(
          pageIndex: 1,
          text: r'''
電子明細
總計 $801.00
$99.00 已使用 Uber One 優惠和其他獎勵
均維（您）
蒜泥白肉肉餐盒 $150.00
Jacob
猛獸嫩 G 胸餐盒 $160.00
David
猛獸嫩 G 胸餐盒 $160.00
Jack
猛獸嫩 G 胸餐盒 $160.00
Airwlind
猛獸嫩 G 胸餐盒 $160.00
餐點小計金額 $790.00
外送費 $55.00
''',
          lines: [],
        ),
      ], fallbackDate: DateTime(2026, 7, 29));

      expect(order.participants.length, 5);
      expect(
        order.participants.map((participant) => participant.itemAmountMinor),
        const [15000, 16000, 16000, 16000, 16000],
      );
      expect(order.deliveryFeeMinor, 0);
      expect(order.serviceFeeMinor, 1100);
      expect(order.discountMinor, 0);
      expect(order.reconciliationDifferenceMinor, 0);
      expect(order.warnings.join(), contains('補足漏讀的優惠'));
    },
  );

  test('infers the remaining net service fee when fee rows are missed', () {
    final order = parseUberEatsReceiptText(const [
      r'''
總計 $801.00
$99.00 已使用 Uber One 優惠和其他獎勵
均維（您）
蒜泥白肉肉餐盒 $150.00
Jacob
猛獸嫩 G 胸餐盒 $160.00
David
猛獸嫩 G 胸餐盒 $160.00
Jack
猛獸嫩 G 胸餐盒 $160.00
Airwind
猛獸嫩 G 胸餐盒 $160.00
餐點小計金額 $790.00
''',
    ], fallbackDate: DateTime(2026, 7, 29));

    expect(order.deliveryFeeMinor, 0);
    expect(order.serviceFeeMinor, 1100);
    expect(order.discountMinor, 0);
    expect(order.reconciliationDifferenceMinor, 0);
    expect(order.warnings.join(), contains('補算淨服務費 11'));
  });

  test('applies an aggregate reward to delivery before service', () {
    final order = parseUberEatsReceiptText(const [
      r'''
總計 $801.00
$99.00 已使用 Uber One 優惠和其他獎勵
均維（您）
餐點甲 $400.00
Airwind
餐點乙 $390.00
餐點小計金額 $790.00
外送費 $55.00
服務費 $55.00
''',
    ], fallbackDate: DateTime(2026, 7, 29));

    expect(order.deliveryFeeMinor, 0);
    expect(order.serviceFeeMinor, 1100);
    expect(order.discountMinor, 0);
    expect(order.reconciliationDifferenceMinor, 0);
  });

  test('parses July 30 priority delivery receipt and deduplicates overlap', () {
    final order = parseUberEatsReceiptText(const [
      r'''
電子 明細
均 維 (您 )
1 沙 茶 豬 肉 冬 粉 $120.00
加 麵 ($20.00)
Jack
豬肉 意 麵 $100.00
Airwlind
1 豬肉 意 麵 $100.00
晴 文
1 沙 茶 豬 肉 冬 粉 $100.00
瑛 對
1 沙 茶 豬 肉 冬 粉 $100.00
Jeffrey
1 豬肉 意 麵 $100.00
Ray
1 牛肉 意 麵 $135.00
加 人 金針菇 ($15.00)
幼 珊
1 沙 茶 海鮮 冬 粉 $120.00
David
1 沙 茶 豬 肉 冬 粉 $100.00
''',
      r'''
電子 明細
Ray
1 [牛肉 意 麵 $135.00
加 人 金針菇 ($15.00)
幼 珊
開 沙 茶 海 鮮 冬 粉 $120.00
David
1 ” 沙 茶 豬 肉 冬 粉 $100.00
餐 點 小 計 金 額 $975.00
優先 外 送 $24.00
外 送 費 $35.00
服務 費 $55.00
外 送 費 優惠 -$35.00
會 員 獎 勵 -$44.00
款項
JCB ‧。*。4936 (cube) $1,010.00
2026/7/30 下 午 12:26
''',
    ], fallbackDate: DateTime(2026, 7, 30));

    expect(order.participants, hasLength(9));
    expect(
      order.participants.map((participant) => participant.itemAmountMinor),
      const [12000, 10000, 10000, 10000, 10000, 10000, 13500, 12000, 10000],
    );
    expect(order.totalMinor, 101000);
    expect(order.deliveryFeeMinor, 2400);
    expect(order.serviceFeeMinor, 1100);
    expect(order.discountMinor, 0);
    expect(order.paymentLastFour, '4936');
    expect(order.date, DateTime(2026, 7, 30));
    expect(order.reconciliationDifferenceMinor, 0);
    expect(order.warnings.join(), contains('外送費 24＋35－優惠 35＝24'));
    expect(order.warnings.join(), contains('服務費 55－會員獎勵 44＝11'));
  });

  test('classifies delivery discount variants and ignores modifier prices', () {
    for (final label in const ['外送優惠', '外送費優惠', '外送費折抵', '外送折扣']) {
      final order = parseUberEatsReceiptText([
        '''
總計 \$135.00
我（您）
主餐 \$100.00
加麵 (\$20.00)
餐點小計金額 \$100.00
優先外送 \$24.00
外送費 \$35.00
服務費 \$55.00
$label -\$35.00
會員獎勵 -\$44.00
''',
      ], fallbackDate: DateTime(2026, 7, 30));

      expect(order.participants.single.itemAmountMinor, 10000);
      expect(order.deliveryFeeMinor, 2400, reason: label);
      expect(order.serviceFeeMinor, 1100, reason: label);
      expect(order.discountMinor, 0, reason: label);
      expect(order.reconciliationDifferenceMinor, 0, reason: label);
    }
  });

  test('infers service gross fee when OCR reads only the member reward', () {
    final order = parseUberEatsReceiptText(const [
      r'''
我（您）
餐點甲 $120.00
Jack
餐點乙 $855.00
餐點小計金額 $975.00
優先外送 $24.00
外送費 $35.00
外送費優惠 -$35.00
會員獎勵 -$44.00
JCB ••••4936 $1,010.00
''',
    ], fallbackDate: DateTime(2026, 7, 30));

    expect(order.deliveryFeeMinor, 2400);
    expect(order.serviceFeeMinor, 1100);
    expect(order.discountMinor, 0);
    expect(order.reconciliationDifferenceMinor, 0);
    expect(order.warnings.join(), contains('服務費 55－會員獎勵 44＝11'));
  });

  test('parses July 31 PP-OCR rows and keeps modifiers out of totals', () {
    final order = parseUberEatsReceiptText(const [
      r'''
電子明細
總計 $428.00
$112.00 已使用 Uber One 優惠和其他獎勵
均維（您）
黑蘑王套餐 $145.00
[選項] 中杯奶茶、黑胡椒醬、冰
[選項] 烏龍麵 ($10.00)
布丁奶酥 $30.00
[選項] 吐司
Jack
美式套餐 $140.00
[選項] 中杯奶茶、冰
David
蔥抓餅 $70.00
[選項] 加一顆蛋蛋 ($20.00)
蘿蔔糕 $60.00
餐點小計金額 $445.00
''',
      r'''
電子明細
[選項] 加一顆蛋蛋 ($20.00)
蘿蔔糕 $60.00
餐點小計金額 $445.00
外送費 $55.00
服務費 $40.00
優惠 -$30.00
外送費優惠 -$55.00
會員獎勵 -$27.00
款項
JCB ••••3245 (合庫jcb) $428.00
2026/7/31 下午 12:10
''',
    ], fallbackDate: DateTime(2026, 7, 31));

    expect(order.participants, hasLength(3));
    expect(
      order.participants.map((participant) => participant.itemAmountMinor),
      const [17500, 14000, 13000],
    );
    expect(order.participants.first.itemName, contains('中杯奶茶'));
    expect(order.participants.first.itemName, contains('吐司'));
    expect(order.participants.last.itemName, contains('加一顆蛋蛋'));
    expect(order.totalMinor, 42800);
    expect(order.deliveryFeeMinor, 0);
    expect(order.serviceFeeMinor, 1300);
    expect(order.discountMinor, 3000);
    expect(order.paymentLastFour, '3245');
    expect(order.date, DateTime(2026, 7, 31));
    expect(order.reconciliationDifferenceMinor, 0);
  });

  test('deserializes PP-OCR geometry, confidence, and engine metadata', () {
    final page = OcrPage.fromJson({
      'pageIndex': 1,
      'text': '黑蘑王套餐',
      'engineVersion': 'ppocr-v5',
      'executionProvider': 'webgpu',
      'lines': [
        {
          'text': '黑蘑王套餐',
          'left': .1,
          'top': .2,
          'right': .5,
          'bottom': .25,
          'confidence': .96,
          'kind': 'text',
          'detectionConfidence': .94,
          'recognitionConfidence': .98,
          'engineVersion': 'ppocr-v5',
          'polygon': [
            {'x': .1, 'y': .2},
            {'x': .5, 'y': .2},
            {'x': .5, 'y': .25},
            {'x': .1, 'y': .25},
          ],
        },
      ],
    });

    expect(page.engineVersion, 'ppocr-v5');
    expect(page.executionProvider, 'webgpu');
    expect(page.lines.single.polygon, hasLength(4));
    expect(page.lines.single.detectionConfidence, .94);
    expect(page.lines.single.recognitionConfidence, .98);
  });

  test('accepts the real PP-OCRv5 July 31 text variants', () {
    final order = parseUberEatsReceiptText(const [
      r'''
← 電子明細
總計 $428.00
[選項] $112.00
[選項] 已使用 Uber One 優惠和其他獎勵
均維(您)
1 黑蘑王套餐 $145.00
[選項] 中杯奶茶，黑胡椒醬，冰
[選項] 烏龍麵（$10.00）
1 布丁奶酥 $30.00
[選項] 吐司
Jack
1 美式套餐 $140.00
[選項] 中杯奶茶，冰
David
1 蔥抓餅 $70.00
[選項] 加一颗蛋蛋（$20.00）
1 蘿蔔糕 $60.00
餐點小計金額 $445.00
''',
      r'''
← 電子明細
[選項] 加一顆蛋蛋($20.00)
1 蘿蔔糕 $60.00
餐點小計金額 $445.00
外送費 0 $55.00
服務費 $40.00
優惠 -$30.00
外送費優惠 -$55.00
會員獎勵 -$27.00
款项
JCB 3245(合庫jcb) $428.00
[選項] 2026/7/31下午 12：10
''',
    ], fallbackDate: DateTime(2026, 7, 31));

    expect(order.participants.map((person) => person.name), [
      '均維',
      'Jack',
      'David',
    ]);
    expect(order.participants.map((person) => person.itemAmountMinor), const [
      17500,
      14000,
      13000,
    ]);
    expect(order.totalMinor, 42800);
    expect(order.deliveryFeeMinor, 0);
    expect(order.serviceFeeMinor, 1300);
    expect(order.discountMinor, 3000);
    expect(order.paymentLastFour, '3245');
    expect(order.date, DateTime(2026, 7, 31));
    expect(order.reconciliationDifferenceMinor, 0);
  });

  test('puts self first and treats Uber One points as order discount', () {
    final order = parseUberEatsReceiptText(const [
      r'''
Jack
蠔油炒河粉 $120.00
Jacob
綠咖哩雞飯 $180.00
David
海南雞飯 $180.00
餐點小計金額 $660.00
外送費 $10.00
服務費 $55.00
uber One 點數 -$7.00
外送費優惠 -$10.00
會員獎勵 -$25.00
JCB ••••4936 (cube) $683.00
2026/8/4 下午 12:06
''',
      r'''
均維（您）
綠咖哩雞飯 $180.00
Jack
蠔油炒河粉 $120.00
餐點小計金額 $660.00
外送費 $10.00
服務費 $55.00
uber One 點數 -$7.00
外送費優惠 -$10.00
會員獎勵 -$25.00
''',
    ], fallbackDate: DateTime(2026, 8, 4));

    expect(order.participants.map((person) => person.name), [
      '均維',
      'Jack',
      'Jacob',
      'David',
    ]);
    expect(order.participants.first.isSelf, isTrue);
    expect(order.participants.map((person) => person.itemAmountMinor), [
      18000,
      12000,
      18000,
      18000,
    ]);
    expect(order.deliveryFeeMinor, 0);
    expect(order.serviceFeeMinor, 3000);
    expect(order.discountMinor, 700);
    expect(order.totalMinor, 68300);
    expect(order.reconciliationDifferenceMinor, 0);
  });

  test('keeps distinct order discounts while deduplicating adjacent pages', () {
    final order = parseUberEatsReceiptText(const [
      r'''
我（您）
餐點甲 $100.00
餐點小計金額 $100.00
服務費 $20.00
優惠 -$5.00
uber One 點數 -$7.00
JCB ••••4936 $108.00
''',
      r'''
餐點小計金額 $100.00
服務費 $20.00
優惠 -$5.00
uber One 點數 -$7.00
JCB ••••4936 $108.00
''',
    ], fallbackDate: DateTime(2026, 8, 4));

    expect(order.serviceFeeMinor, 2000);
    expect(order.discountMinor, 1200);
    expect(order.totalMinor, 10800);
    expect(order.reconciliationDifferenceMinor, 0);
  });
}
