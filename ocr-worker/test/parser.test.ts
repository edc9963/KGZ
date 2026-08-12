import assert from 'node:assert/strict'
import test from 'node:test'
import { parseUberEatsText } from '../src/parser.js'

test('parses a Traditional Chinese Uber Eats receipt', () => {
  const draft = parseUberEatsText([`
    測試餐廳
    牛肉麵 NT$180
    紅茶 $40
    外送費 $20
    服務費 $10
    優惠 -$30
    總計 NT$220
    Visa **** 1234
    2026/07/31
  `])
  assert.equal(draft.merchant, '測試餐廳')
  assert.equal(draft.items.length, 2)
  assert.equal(draft.totalMinor, 22000)
  assert.equal(draft.deliveryFeeMinor, 2000)
  assert.equal(draft.serviceFeeMinor, 1000)
  assert.equal(draft.discountMinor, 3000)
  assert.equal(draft.paymentLastFour, '1234')
  assert.equal(draft.warnings.length, 0)
})

