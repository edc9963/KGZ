import { assertEquals } from 'https://deno.land/std@0.224.0/assert/mod.ts'
import {
  captureMessage,
  NO_CARD,
  cardPickerMessage,
  parseCaptureAmount,
  paymentKindMessage,
  splitCapturePostback,
} from './capture.ts'

Deno.test('parses Wallet amount formats', () => {
  assertEquals(parseCaptureAmount('NT$85.00'), { amountMinor: 8500, currency: 'TWD' })
  assertEquals(parseCaptureAmount('$1,234'), { amountMinor: 123400, currency: 'TWD' })
  assertEquals(parseCaptureAmount('85 元'), { amountMinor: 8500, currency: 'TWD' })
  assertEquals(parseCaptureAmount('TWD 59'), { amountMinor: 5900, currency: 'TWD' })
  assertEquals(parseCaptureAmount('１２０'), { amountMinor: 12000, currency: 'TWD' })
  assertEquals(parseCaptureAmount(42.5), { amountMinor: 4250, currency: 'TWD' })
  assertEquals(parseCaptureAmount('US$12.34'), { amountMinor: 1234, currency: 'USD' })
  assertEquals(parseCaptureAmount('¥1,200'), { amountMinor: 120000, currency: 'JPY' })
})

Deno.test('rejects refunds and junk', () => {
  assertEquals(parseCaptureAmount('-NT$85'), null)
  assertEquals(parseCaptureAmount('0'), null)
  assertEquals(parseCaptureAmount(''), null)
  assertEquals(parseCaptureAmount('abc'), null)
  assertEquals(parseCaptureAmount(null), null)
})

Deno.test('splits capture postbacks', () => {
  const id = '0f8fad5b-d9cb-469f-a165-70867728950e'
  assertEquals(splitCapturePostback(`capture:cat:${id}:expense-food`, 'capture:cat:'), {
    id,
    rest: 'expense-food',
  })
  assertEquals(splitCapturePostback(`capture:card:${id}:a:b`, 'capture:card:'), {
    id,
    rest: 'a:b',
  })
  assertEquals(splitCapturePostback(`capture:skip:${id}`, 'capture:skip:'), { id, rest: '' })
  assertEquals(splitCapturePostback('capture:cat:bad', 'capture:cat:'), null)
})

Deno.test('capture message puts the learned category first and fits LINE limits', () => {
  const categories = Array.from({ length: 15 }, (_, index) => ({
    id: `c${index}`,
    name: `分類${index}`,
  }))
  const message = captureMessage({
    inboxId: '0f8fad5b-d9cb-469f-a165-70867728950e',
    amountMinor: 8500,
    currency: 'TWD',
    merchant: '7-ELEVEN',
    cardLabel: '國泰 CUBE',
    cardResolution: 'card',
    cardName: 'CUBE 卡',
    cardLastFour: '1234',
    occurredAt: '2026-10-27T01:31:00Z',
    suggestedCategoryId: 'c7',
    categories,
  })
  const items = (message.quickReply as { items: { action: { label: string; data: string } }[] })
    .items
  assertEquals(items.length, 13)
  assertEquals(items[0].action.label, '✓ 分類7')
  assertEquals(items[12].action.label, '略過')
  for (const item of items) {
    if (item.action.label.length > 20) throw new Error('label too long')
    if (item.action.data.length > 300) throw new Error('data too long')
  }
  const text = String(message.text)
  if (!text.includes('NT$85') || !text.includes('10/27 09:31')) throw new Error(text)
})

Deno.test('foreign currency only offers skip', () => {
  const message = captureMessage({
    inboxId: '0f8fad5b-d9cb-469f-a165-70867728950e',
    amountMinor: 1234,
    currency: 'USD',
    merchant: 'Apple',
    cardResolution: 'unknown',
    occurredAt: '2026-10-27T01:31:00Z',
    categories: [{ id: 'a', name: '餐飲' }],
  })
  const items = (message.quickReply as { items: unknown[] }).items
  assertEquals(items.length, 1)
})

Deno.test('card picker always offers 不指定卡片', () => {
  const message = cardPickerMessage('0f8fad5b-d9cb-469f-a165-70867728950e', 'CUBE', [
    { id: 'card-1', name: '國泰世華 CUBE 信用卡超長名稱', lastFour: '1234' },
  ])
  const items = (message.quickReply as { items: { action: { label: string; data: string } }[] })
    .items
  assertEquals(items.length, 2)
  assertEquals(items[1].action.data.endsWith(NO_CARD), true)
  for (const item of items) {
    if (item.action.label.length > 20) throw new Error('label too long')
  }
})

Deno.test('LINE Pay captures say LINE Pay', () => {
  const message = captureMessage({
    inboxId: '0f8fad5b-d9cb-469f-a165-70867728950e',
    source: 'linePay',
    amountMinor: 8500,
    currency: 'TWD',
    merchant: '全家',
    cardLabel: '國泰世華 *1234',
    cardResolution: 'unknown',
    occurredAt: '2026-10-27T01:31:00Z',
    categories: [{ id: 'a', name: '餐飲' }],
  })
  assertEquals(String(message.text).startsWith('LINE Pay 消費待確認'), true)
  const picker = cardPickerMessage('0f8fad5b-d9cb-469f-a165-70867728950e', '國泰世華 *1234', [], 'linePay')
  assertEquals(String(picker.text).startsWith('刷卡通知的「國泰世華 *1234」'), true)
})

Deno.test('LINE Pay Money asks card or account before the list', () => {
  const id = '0f8fad5b-d9cb-469f-a165-70867728950e'
  const message = captureMessage({
    inboxId: id,
    source: 'linePayMoney',
    amountMinor: 69200,
    currency: 'TWD',
    merchant: '麥當勞',
    cardLabel: 'LINE Pay Money',
    cardResolution: 'unknown',
    occurredAt: '2026-10-24T12:30:00Z',
    categories: [{ id: 'a', name: '餐飲' }],
  })
  assertEquals(String(message.text).includes('付款來源：未知'), true)
  const kind = paymentKindMessage(id)
  const items = (kind.quickReply as { items: { action: { data: string } }[] }).items
  assertEquals(items.map((item) => item.action.data), [
    `capture:pay:${id}:card`,
    `capture:pay:${id}:acct`,
    `capture:card:${id}:${NO_CARD}`,
  ])
})
