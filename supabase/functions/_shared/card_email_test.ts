import { assertEquals } from 'https://deno.land/std@0.224.0/assert/mod.ts'
import { parseCardEmail } from './card_email.ts'

const receivedAt = '2026-10-27T01:35:00Z' // 09:35 in Taipei

Deno.test('parses labelled fields on one line', () => {
  assertEquals(
    parseCardEmail({
      from: '國泰世華銀行 <service@cathaybk.com.tw>',
      subject: '信用卡消費通知',
      body: [
        '親愛的客戶您好：',
        '卡號：4311-****-****-1234',
        '消費時間：2026/10/27 09:31:05',
        '消費商店：連加*全家便利商店',
        '消費金額：NT$1,234',
        '本行提供 LINE Pay 回饋 1.5% 優惠',
      ].join('\n'),
      receivedAt,
    }),
    {
      kind: 'linePay',
      capture: {
        amountMinor: 123400,
        currency: 'TWD',
        merchant: '全家便利商店',
        cardLabel: '國泰世華 *1234',
        occurredAt: '2026-10-27T01:31:05.000Z',
      },
    },
  )
})

Deno.test('parses a flattened HTML table with ROC date and split clock', () => {
  const result = parseCardEmail({
    from: 'ctbc@ctbcbank.com',
    subject: '中國信託信用卡交易通知',
    body: '<table><tr><td>卡號末四碼</td><td>5678</td></tr>' +
      '<tr><td>交易日期</td><td>115/10/26</td></tr>' +
      '<tr><td>交易時間</td><td>23:58</td></tr>' +
      '<tr><td>特店名稱</td><td>LINE PAY＊路易莎咖啡</td></tr>' +
      '<tr><td>交易金額</td><td>新臺幣 ８５ 元</td></tr></table>',
    receivedAt,
  })
  assertEquals(result, {
    kind: 'linePay',
    capture: {
      amountMinor: 8500,
      currency: 'TWD',
      merchant: '路易莎咖啡',
      cardLabel: '中國信託 *5678',
      occurredAt: '2026-10-26T15:58:00.000Z',
    },
  })
})

Deno.test('parses a single-sentence notice without a year', () => {
  const result = parseCardEmail({
    from: 'no-reply@esunbank.com',
    subject: '刷卡消費通知',
    body: '您的玉山卡(末四碼9012)於10/27 09:20在連加*台灣大車隊刷卡消費新台幣230元，如有疑問請洽客服。',
    receivedAt,
  })
  assertEquals(result, {
    kind: 'linePay',
    capture: {
      amountMinor: 23000,
      currency: 'TWD',
      merchant: '台灣大車隊',
      cardLabel: '玉山 *9012',
      occurredAt: '2026-10-27T01:20:00.000Z',
    },
  })
})

Deno.test('a year-less December charge noticed in January is last year', () => {
  const result = parseCardEmail({
    subject: '刷卡通知',
    body: '於12/31 23:50在連加*誠品消費新台幣500元',
    receivedAt: '2027-01-01T00:10:00Z',
  })
  assertEquals(result.kind === 'linePay' && result.capture.occurredAt, '2026-12-31T15:50:00.000Z')
})

Deno.test('ignores non LINE Pay charges even with LINE Pay ads in the footer', () => {
  assertEquals(
    parseCardEmail({
      subject: '信用卡消費通知',
      body: '消費商店：7-ELEVEN\n消費金額：NT$85\n\n綁定 LINE Pay 享 1.5% 回饋',
      receivedAt,
    }),
    { kind: 'ignored', reason: 'not_line_pay' },
  )
})

Deno.test('ignores refunds and notices without an amount', () => {
  assertEquals(
    parseCardEmail({
      subject: '信用卡退款通知',
      body: '消費商店：連加*全家\n消費金額：NT$85',
      receivedAt,
    }),
    { kind: 'ignored', reason: 'refund' },
  )
  assertEquals(
    parseCardEmail({
      subject: '交易通知',
      body: '交易類別：取消交易\n消費商店：連加*全家\n消費金額：NT$85',
      receivedAt,
    }),
    { kind: 'ignored', reason: 'refund' },
  )
  assertEquals(
    parseCardEmail({ subject: 'LINE Pay 交易通知', body: '請登入查看', receivedAt }),
    { kind: 'ignored', reason: 'no_amount' },
  )
})

Deno.test('falls back to the arrival time and an empty card label', () => {
  const result = parseCardEmail({
    subject: 'LINE Pay 信用卡消費通知',
    body: '商店：麥當勞\n金額：120',
    receivedAt,
  })
  assertEquals(result, {
    kind: 'linePay',
    capture: {
      amountMinor: 12000,
      currency: 'TWD',
      merchant: '麥當勞',
      cardLabel: '',
      occurredAt: '2026-10-27T01:35:00.000Z',
    },
  })
})
