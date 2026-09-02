export type TwseInstrumentRow = {
  market: 'TWSE'
  symbol: string
  name: string
  normalized_name: string
  instrument_type: '股票' | 'ETF'
  currency: 'TWD'
  is_active: boolean
  source_updated_at: string
}

export type ParsedTwseData = {
  instruments: TwseInstrumentRow[]
  quotes: Record<string, unknown>[]
  latestDate: string
}

export function normalizeMarketText(value: unknown): string {
  return typeof value === 'string'
    ? value.trim().toUpperCase().replace(/\s+/g, '')
    : ''
}

export function classifyTwseSymbol(
  symbol: string,
): '股票' | 'ETF' | null {
  if (/^00[0-9A-Z]{2,8}$/.test(symbol)) return 'ETF'
  if (/^[1-9][0-9]{3}$/.test(symbol)) return '股票'
  return null
}

export function parseRocTradingDate(value: unknown): string | null {
  if (typeof value !== 'string' || !/^\d{7}$/.test(value)) return null
  const year = Number(value.slice(0, 3)) + 1911
  return `${year.toString().padStart(4, '0')}-${value.slice(3, 5)}-${value.slice(5, 7)}`
}

export function parseTwseClosingPrices(
  raw: unknown,
  fetchedAt: string,
): ParsedTwseData {
  if (!Array.isArray(raw)) throw new Error('twse_invalid_payload')
  const latestBySymbol = new Map<string, {
    instrument: TwseInstrumentRow
    quoteDate: string
    closePriceMinor: number | null
  }>()
  let latestDate = ''
  for (const value of raw) {
    if (value == null || typeof value !== 'object') continue
    const item = value as Record<string, unknown>
    const symbol = normalizeMarketText(item.Code)
    const name = typeof item.Name === 'string' ? item.Name.trim() : ''
    const type = classifyTwseSymbol(symbol)
    const quoteDate = parseRocTradingDate(item.Date)
    if (!type || !name || !quoteDate) continue
    const numericPrice = typeof item.ClosingPrice === 'string'
      ? Number(item.ClosingPrice.replace(/,/g, ''))
      : Number(item.ClosingPrice)
    const existing = latestBySymbol.get(symbol)
    if (existing && existing.quoteDate > quoteDate) continue
    latestBySymbol.set(symbol, {
      instrument: {
      market: 'TWSE', symbol, name,
      normalized_name: normalizeMarketText(name), instrument_type: type,
      currency: 'TWD', is_active: true, source_updated_at: fetchedAt,
      },
      quoteDate,
      closePriceMinor: Number.isFinite(numericPrice) && numericPrice > 0
        ? Math.round(numericPrice * 100)
        : null,
    })
    if (quoteDate > latestDate) latestDate = quoteDate
  }
  const instruments = [...latestBySymbol.values()]
    .map((item) => item.instrument)
  const quotes = [...latestBySymbol.values()]
    .filter((item) => item.closePriceMinor != null)
    .map((item) => ({
      market: 'TWSE', symbol: item.instrument.symbol,
      quote_date: item.quoteDate, close_price_minor: item.closePriceMinor,
      fetched_at: fetchedAt,
    }))
  return { instruments, quotes, latestDate }
}
