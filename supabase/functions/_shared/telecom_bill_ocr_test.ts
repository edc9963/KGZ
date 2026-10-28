import { assertEquals } from 'https://deno.land/std@0.224.0/assert/mod.ts'
import { parseTelecomBillOcr } from './telecom_bill_ocr.ts'

const header = ['115 年 10 月 代收服務明細', '頁 次：5 / 6', '代收服務明細', '0958***718']

// Read row by row: each row's fields on one line, the item's URL below.
const byRow = [
  ...header,
  '日期 起始時間 收費類型 服務項目 廠商服務專線 金額',
  '115/09/04 14:35:25 計次型 ◎Apple商店消費《訂單編號：MX5XX597LY》 0800-095-988 115.00',
  'https://reportaproblem.apple.com',
  '115/09/26 10:10:51 計次型 ◎Apple商店消費《訂單編號：MX5XZNBNKM》 0800-095-988 330.00',
  'https://reportaproblem.apple.com',
  '115/09/26 10:11:53 計次型 ◎Apple商店消費《訂單編號：MX5XZNBQQ0》 0800-095-988 330.00',
  'https://reportaproblem.apple.com',
  '115/10/02 14:54:41 計次型 ◎Apple商店消費《訂單編號：MX5Y02MZ0Z》 0800-095-988 175.00',
  'https://reportaproblem.apple.com',
  '0958***718 小計NT$ 950.00',
].join('\n')

// Read column by column, subtotal amount on its own line.
const byColumn = [
  ...header,
  '日期', '115/09/04', '115/09/26', '115/09/26', '115/10/02',
  '起始時間', '14:35:25', '10:10:51', '10:11:53', '14:54:41',
  '收費類型', '計次型', '計次型', '計次型', '計次型',
  '服務項目',
  '◎Apple商店消費《訂單編號：MX5XX597LY》', 'https://reportaproblem.apple.com',
  '◎Apple商店消費《訂單編號：MX5XZNBNKM》', 'https://reportaproblem.apple.com',
  '◎Apple商店消費《訂單編號：MX5XZNBQQO》', 'https://reportaproblem.apple.com',
  '◎Apple商店消費《訂單編號：MX5Y02MZ0Z》', 'https://reportaproblem.apple.com',
  '廠商服務專線', '0800-095-988', '0800-095-988', '0800-095-988', '0800-095-988',
  '金額', '115.00', '330.00', '330.00', '175.00',
  '0958***718 小計NT$',
  '950.00',
].join('\n')

const expected = [
  ['2026-09-04T06:35:25.000Z', 11500],
  ['2026-09-26T02:10:51.000Z', 33000],
  ['2026-09-26T02:11:53.000Z', 33000],
  ['2026-10-02T06:54:41.000Z', 17500],
]

for (const [name, text] of [['row by row', byRow], ['column by column', byColumn]]) {
  Deno.test(`reads every charge read ${name}`, () => {
    const captures = parseTelecomBillOcr(text)
    assertEquals(
      captures.map((capture) => [capture.occurredAt, capture.amountMinor]),
      expected,
    )
    assertEquals(captures[0].merchant, 'Apple商店消費')
    assertEquals(captures[0].source, 'telecomBill')
    assertEquals(captures[0].cardLabel, '電信帳單')
  })
}

Deno.test('same-amount charges a minute apart stay separate', () => {
  const refs = parseTelecomBillOcr(byRow).map((capture) => capture.externalRef)
  assertEquals(new Set(refs).size, refs.length)
  assertEquals(refs[1], 'telecom:2026-09-26T02:10:51:33000')
})

Deno.test('a table whose columns do not line up is refused', () => {
  const missingAmount = byColumn.replace('\n175.00', '')
  assertEquals(parseTelecomBillOcr(missingAmount), [])
})

Deno.test('refunds are skipped', () => {
  const refund = byRow.replace('175.00', '-175.00')
  assertEquals(parseTelecomBillOcr(refund).length, 3)
})

Deno.test('a LINE Pay chat is not a telecom bill', () => {
  const chat = '付款\nLINE Pay\nNT$ 243\n付款完成。\n2026.10.24 20:57 (GMT+0800)\n商店名稱 統康生活'
  assertEquals(parseTelecomBillOcr(chat), [])
})
