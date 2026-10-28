import { assertEquals } from 'https://deno.land/std@0.224.0/assert/mod.ts'
import { parseLinePayOcr } from './line_pay_ocr.ts'

// What「從影像擷取文字」returns for a LINE Pay chat screenshot: label and
// value on one line, wrapped store names, chat times and date separators.
const screenshot = [
  '10/2 (週五)',
  '付款',
  'LINE Pay money',
  'NT$ 692',
  '付款完成。',
  '2026.10.24 20:30 (GMT+0800)',
  '商店名稱 麥當勞',
  '瞭解更多',
  '晚上8:30',
  '付款',
  'LINE Pay',
  'NT$ 243',
  '付款完成。',
  '2026.10.24 20:57 (GMT+0800)',
  '商店名稱 統康生活',
  '瞭解更多',
  '晚上8:57',
  '10/10 (週六)',
  '付款',
  'LINE Pay money',
  'NT$ 2,372',
  '付款完成。',
  '2026.10.25 17:57 (GMT+0800)',
  '商店名稱 京站時尚廣場 Q',
  'square',
  '瞭解更多',
  '下午5:57',
  '昨天',
  '付款',
  'LINE Pay',
  'NT$ 162',
  '付款完成。',
  '2026.10.26 16:05 (GMT+0800)',
  '商店名稱',
  '台灣中油條碼支付台',
  '北處人工島',
  '瞭解更多',
  '下午4:05',
].join('\n')

Deno.test('reads every payment card in a LINE Pay chat screenshot', () => {
  const captures = parseLinePayOcr(screenshot)
  assertEquals(captures.map((c) => [c.source, c.amountMinor, c.merchant, c.cardLabel]), [
    ['linePayMoney', 69200, '麥當勞', 'LINE Pay Money'],
    ['linePay', 24300, '統康生活', 'LINE Pay'],
    ['linePayMoney', 237200, '京站時尚廣場 Q square', 'LINE Pay Money'],
    ['linePay', 16200, '台灣中油條碼支付台北處人工島', 'LINE Pay'],
  ])
  assertEquals(captures[0].occurredAt, '2026-10-24T12:30:00.000Z')
  assertEquals(captures[0].externalRef, 'ocr:2026-10-24T12:30:69200')
  assertEquals(captures[0].currency, 'TWD')
})

Deno.test('tolerates OCR quirks: full-width text, NTS, split amount, value before label', () => {
  const captures = parseLinePayOcr([
    '付款',
    'LINE Pay',
    'NTS 1,630',
    '付款完成。',
    '２０２６.10.09 18:33 （GMT+0800）',
    '新光三越台北信義新天地A11館',
    '商店名稱',
    '瞭解更多',
    '付款',
    'LINE Pay money',
    'NT$',
    '29',
    '2026.10.10 13:46 (GMT+0800)',
    '商店名稱：統一超商',
  ].join('\n'))
  assertEquals(captures.map((c) => [c.source, c.amountMinor, c.merchant, c.occurredAt]), [
    ['linePay', 163000, '新光三越台北信義新天地A11館', '2026-10-09T10:33:00.000Z'],
    ['linePayMoney', 2900, '統一超商', '2026-10-10T05:46:00.000Z'],
  ])
})

Deno.test('skips refunds, cards without a time and unrelated text', () => {
  assertEquals(parseLinePayOcr('隨便一段文字\nNT$ 100 優惠'), [])
  assertEquals(parseLinePayOcr([
    '退款',
    'LINE Pay',
    'NT$ 500',
    '退款完成。',
    '2026.10.20 12:00 (GMT+0800)',
    '商店名稱 家樂福',
  ].join('\n')), [])
})

Deno.test('a coupon line does not become part of the store name', () => {
  const [capture] = parseLinePayOcr([
    '付款',
    'LINE Pay money',
    'NT$ 1,140',
    '付款完成。',
    '2026.10.15 16:33 (GMT+0800)',
    '商店名稱 新光三越台北信義新天地',
    'A11館',
    '活動',
    '優惠券 1',
    '瞭解更多',
  ].join('\n'))
  assertEquals(capture.merchant, '新光三越台北信義新天地A11館')
})

// Real「從影像擷取文字」output for two screenshots: a long stitched one OCR
// could barely read (no times, so nothing is kept from it) and a normal one
// where the logo and store name come out of order.
const realOcr = `NI$448
LINE Pay
NT$ 1,630
新光三地集甜原認點
NT$ 515
NT$ 490
何款元成。
NT$ 29
LINe Pay money
NT$ 285
宅神爺玩具 5號店
NT$ 477
NT$ 321
LINe Pay money
NT$ 80
NT$ 1,140
LINE Pay money
矫光三趣矣拈赁樽錾
NT$ 56
NT$ 33
NT$ 1,610
何款元成
NT$ 840
10/2（週五）
LINE
Pay money
付款
NT$ 692
付款完成。
2026.10.24 20:30 (GMT+0800)
商店名稱
麥當勞
瞭解更多
晚上8:30
LINE
Pay
付款
NT$ 243
付款完成。
2026.10.24 20:57 (GMT+0800)
商店名稱
統康生活
瞭解更多
晚上8:57
10/10（週六）
付款
LINE
Pay money
NT$ 2,372
付款完成。
2026.10.2517:57 (GMT+0800)
商店名稱
京站時尚廣場Q
square
瞭解更多
下午5:57
付款
NT$ 530
付款完成。
2026.10.25 19:11 (GMT+0800)
商店名稱
LINE Pay money
京站時尚廣場Q
square
瞭解更多
晚上7:11
昨天
付款
NT$ 162
付款完成。
LINE
Pay
2026.10.26 16:05 (GMT+0800)
商店名稱
台灣中油條碼支付台北處人工島
瞭解更多
下午4:05`

Deno.test('reads real iPhone OCR output with the logo and store name out of order', () => {
  assertEquals(
    parseLinePayOcr(realOcr).map((c) => [c.source, c.amountMinor, c.merchant, c.occurredAt]),
    [
      ['linePayMoney', 69200, '麥當勞', '2026-10-24T12:30:00.000Z'],
      ['linePay', 24300, '統康生活', '2026-10-24T12:57:00.000Z'],
      ['linePayMoney', 237200, '京站時尚廣場Q square', '2026-10-25T09:57:00.000Z'],
      ['linePayMoney', 53000, '京站時尚廣場Q square', '2026-10-25T11:11:00.000Z'],
      ['linePay', 16200, '台灣中油條碼支付台北處人工島', '2026-10-26T08:05:00.000Z'],
    ],
  )
})
