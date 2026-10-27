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
      kind: 'capture',
      source: 'linePay',
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
    kind: 'capture',
    source: 'linePay',
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
    kind: 'capture',
    source: 'linePay',
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
  assertEquals(result.kind === 'capture' && result.capture.occurredAt, '2026-12-31T15:50:00.000Z')
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
    kind: 'capture',
    source: 'linePay',
    capture: {
      amountMinor: 12000,
      currency: 'TWD',
      merchant: '麥當勞',
      cardLabel: '',
      occurredAt: '2026-10-27T01:35:00.000Z',
    },
  })
})

// Structure of a real 彰化銀行數位存款帳戶 notice (name and account replaced).
function chbNotice(info: string, amount = 'TWD             65.00'): string {
  const span = (text: string) => `<span>${text}</span><br>
      `
  return '<html><head><title>彰化銀行即時訊息通知</title><style>.font-9 { color: #333; }</style>' +
    '</head><body><table><tr><td>' +
    span('親愛的 王○明 您好:') +
    span('2026/10/27 09:14:00 您的數位存款帳戶金額異動，特此通知。') +
    span('') +
    span(`交易資訊：${info}`) +
    span('交易日期： 2026/10/27') +
    span('記帳日期： 2026/10/27') +
    span('轉出帳號：1234-56-XXX78-9-00') +
    span(`交易金額：${amount}`) +
    span('如有任何問題，可至網路銀行查詢交易明細，感謝您使用【彰化銀行數位存款帳戶】！') +
    span('0800-365-889；412-2222(市話撥打)；02-412-2222(手機撥打)') +
    '</td></tr></table>&copy;2021 彰銀版權所有</body></html>'
}

const chb = {
  from: '彰化銀行 <service@bill.chb.com.tw>',
  subject: '【彰化銀行數位存款帳戶】扣帳通知(信件編號:53636-28547568)',
  receivedAt: '2026-10-27T01:14:06Z',
}

Deno.test('彰銀 TWPAY scan debit becomes a twPay capture on the account', () => {
  assertEquals(parseCardEmail({ ...chb, body: chbNotice('彰銀行動掃碼購貨') }), {
    kind: 'capture',
    source: 'twPay',
    capture: {
      amountMinor: 6500,
      currency: 'TWD',
      merchant: '',
      cardLabel: '彰化銀行 1234-56-XXX78-9-00',
      occurredAt: '2026-10-27T01:14:00.000Z',
    },
  })
})

Deno.test('彰銀 debit-card purchase becomes a debitCard capture', () => {
  const result = parseCardEmail({ ...chb, body: chbNotice('金融卡消費', 'TWD 1,280.00') })
  assertEquals(result.kind === 'capture' && [result.source, result.capture.amountMinor], [
    'debitCard',
    128000,
  ])
})

Deno.test('彰銀 transfers and reversals are not purchases', () => {
  assertEquals(parseCardEmail({ ...chb, body: chbNotice('網路銀行轉帳') }), {
    kind: 'ignored',
    reason: 'not_purchase',
  })
  assertEquals(parseCardEmail({ ...chb, body: chbNotice('ATM 提款') }), {
    kind: 'ignored',
    reason: 'not_purchase',
  })
  assertEquals(parseCardEmail({ ...chb, body: chbNotice('掃碼購貨沖正') }), {
    kind: 'ignored',
    reason: 'refund',
  })
})
