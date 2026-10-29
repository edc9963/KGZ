import { assertEquals } from 'https://deno.land/std@0.224.0/assert/mod.ts'
import { parseTelecomSms } from './telecom_sms.ts'

const now = new Date('2026-10-21T18:34:12.000Z')

const fetSms = '【遠傳Apple商店交易成功通知】您本次代收金額160元將隨最近一期帳單計算' +
  '(訂單編號MX5Y1J24QA)，完整交易紀錄, 請至 https://reportaproblem.apple.com ' +
  '查詢或洽 Apple 客服：0800-095-988。若當月額度不敷使用可至 ' +
  'https://fetnet.tw/KZX1sE 進行額度調整繳款。'

Deno.test('reads a FET Apple purchase SMS', () => {
  assertEquals(parseTelecomSms(fetSms, now), [{
    source: 'telecomBill',
    amountMinor: 16000,
    currency: 'TWD',
    merchant: 'Apple商店消費',
    cardLabel: '電信帳單',
    occurredAt: '2026-10-21T18:34:12.000Z',
    externalRef: 'telecom-sms:MX5Y1J24QA',
  }])
})

Deno.test('reads spaces, line breaks and full-width punctuation', () => {
  const variant = '【遠傳 Apple商店交易成功通知】您本次代收金額 1,490 元\n' +
    '將隨最近一期帳單計算（訂單編號：MX5Y1J24QB），完整交易紀錄'
  const [capture] = parseTelecomSms(variant, now)
  assertEquals(capture.amountMinor, 149000)
  assertEquals(capture.externalRef, 'telecom-sms:MX5Y1J24QB')
})

Deno.test('several pasted messages each keep their own order number', () => {
  const second = fetSms.replace('160元', '840元').replace('MX5Y1J24QA', 'MX5Y2K11ZZ')
  const captures = parseTelecomSms(`${fetSms}\n${second}`, now)
  assertEquals(captures.map((capture) => [capture.amountMinor, capture.externalRef]), [
    [16000, 'telecom-sms:MX5Y1J24QA'],
    [84000, 'telecom-sms:MX5Y2K11ZZ'],
  ])
})

Deno.test('without an order number the ref falls back to minute and amount', () => {
  const capture = parseTelecomSms(fetSms.replace(/\(訂單編號[^)]*\)/, ''), now)[0]
  assertEquals(capture.externalRef, 'telecom-sms:2026-10-21T18:34:16000:0')
})

Deno.test('other texts are ignored', () => {
  assertEquals(parseTelecomSms('【遠傳電信】您的帳單金額 999 元已出帳', now), [])
  assertEquals(parseTelecomSms('付款\nLINE Pay\nNT$ 243\n付款完成。', now), [])
})
