import {
  assertEquals,
  assertThrows,
} from 'https://deno.land/std@0.224.0/assert/mod.ts'
import {
  classifyTwseSymbol,
  parseRocTradingDate,
  parseTwseClosingPrices,
} from './twse.ts'

Deno.test('parses 0050 close and ROC trading date', () => {
  const parsed = parseTwseClosingPrices([{
    Date: '1150819', Code: '0050', Name: '元大台灣50',
    ClosingPrice: '103.10',
  }], '2026-08-20T10:30:00Z')
  assertEquals(parsed.instruments[0].instrument_type, 'ETF')
  assertEquals(parsed.quotes[0].close_price_minor, 10310)
  assertEquals(parsed.latestDate, '2026-08-19')
})

Deno.test('keeps an instrument but ignores a blank close', () => {
  const parsed = parseTwseClosingPrices([{
    Date: '1150819', Code: '00625K', Name: '富邦上証+R', ClosingPrice: '',
  }], '2026-08-20T10:30:00Z')
  assertEquals(parsed.instruments.length, 1)
  assertEquals(parsed.quotes, [])
})

Deno.test('classifies supported symbols and validates dates', () => {
  assertEquals(classifyTwseSymbol('2330'), '股票')
  assertEquals(classifyTwseSymbol('0050'), 'ETF')
  assertEquals(classifyTwseSymbol('02001R'), null)
  assertEquals(parseRocTradingDate('1150819'), '2026-08-19')
  assertThrows(() => parseTwseClosingPrices({}, '2026-08-20T10:30:00Z'))
})

Deno.test('deduplicates monthly rows and keeps the latest 2330 close', () => {
  const parsed = parseTwseClosingPrices([{
    Date: '1150818', Code: '2330', Name: '台積電',
    ClosingPrice: '2,300.00',
  }, {
    Date: '1150819', Code: '2330', Name: '台積電',
    ClosingPrice: '2,350.00',
  }, {
    Date: '1150819', Code: '0050', Name: '元大台灣50',
    ClosingPrice: '103.10',
  }], '2026-08-20T10:30:00Z')

  assertEquals(parsed.instruments.length, 2)
  assertEquals(parsed.quotes.length, 2)
  assertEquals(
    parsed.quotes.find((item) => item.symbol === '2330')?.close_price_minor,
    235000,
  )
  assertEquals(parsed.latestDate, '2026-08-19')
})
