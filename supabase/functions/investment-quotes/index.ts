import { createClient } from 'npm:@supabase/supabase-js@2'
import {
  normalizeMarketText,
  parseTwseClosingPrices,
} from '../_shared/twse.ts'

type Json = Record<string, unknown>
type CatalogueRow = {
  market: string
  symbol: string
  name: string
  instrument_type: string
  currency: string
  source_updated_at: string
  quote_date: string | null
  close_price_minor: number | null
}

const TWSE_CLOSE_URL =
  'https://openapi.twse.com.tw/v1/exchangeReport/STOCK_DAY_AVG_ALL'
const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? ''
const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
const cronSecret = Deno.env.get('INVESTMENT_QUOTE_CRON_SECRET') ?? ''
const database = createClient(supabaseUrl, serviceRoleKey, {
  auth: { persistSession: false, autoRefreshToken: false },
})

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}

function response(body: Json, status = 200, cache = 'no-store'): Response {
  return Response.json(body, {
    status,
    headers: { ...corsHeaders, 'Cache-Control': cache },
  })
}

function normalize(value: unknown): string {
  return normalizeMarketText(value)
}

async function requireUser(request: Request): Promise<boolean> {
  const authorization = request.headers.get('authorization')
  if (!authorization?.startsWith('Bearer ')) return false
  const client = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
    global: { headers: { Authorization: authorization } },
  })
  const { data, error } = await client.auth.getUser(
    authorization.slice('Bearer '.length),
  )
  return !error && data.user != null
}

async function refresh(): Promise<{ quoteDate: string; count: number }> {
  const startedAt = new Date().toISOString()
  await database.from('market_sync_runs').upsert({
    market: 'TWSE', started_at: startedAt, completed_at: null,
    status: 'running', quote_date: null, item_count: 0, error_message: '',
  })
  try {
    const upstream = await fetch(TWSE_CLOSE_URL, {
      headers: { Accept: 'application/json' },
      signal: AbortSignal.timeout(15_000),
    })
    if (!upstream.ok) throw new Error(`twse_http_${upstream.status}`)
    const now = new Date().toISOString()
    const { instruments, quotes, latestDate } = parseTwseClosingPrices(
      await upstream.json(), now,
    )
    if (instruments.length === 0 || !latestDate) {
      throw new Error('twse_no_supported_quotes')
    }

    for (let index = 0; index < instruments.length; index += 500) {
      const { error } = await database.from('market_instruments')
        .upsert(instruments.slice(index, index + 500))
      if (error) throw error
    }
    const { error: deactivateError } = await database
      .from('market_instruments').update({ is_active: false })
      .eq('market', 'TWSE').lt('source_updated_at', now)
    if (deactivateError) throw deactivateError
    for (let index = 0; index < quotes.length; index += 500) {
      const { error } = await database
        .from('market_quote_history').upsert(quotes.slice(index, index + 500))
      if (error) throw error
    }
    await database.from('market_sync_runs').upsert({
      market: 'TWSE', started_at: startedAt,
      completed_at: new Date().toISOString(), status: 'success',
      quote_date: latestDate, item_count: quotes.length, error_message: '',
    })
    return { quoteDate: latestDate, count: quotes.length }
  } catch (error) {
    await database.from('market_sync_runs').upsert({
      market: 'TWSE', started_at: startedAt,
      completed_at: new Date().toISOString(), status: 'failed',
      item_count: 0, error_message: String(error).slice(0, 500),
    })
    throw error
  }
}

async function refreshIfStale(): Promise<void> {
  const { data } = await database.from('market_sync_runs')
    .select('started_at,completed_at,status').eq('market', 'TWSE').maybeSingle()
  const completed = data?.completed_at ? Date.parse(data.completed_at) : 0
  const started = data?.started_at ? Date.parse(data.started_at) : 0
  if (data?.status === 'running' && Date.now() - started < 5 * 60 * 1000) {
    return
  }
  if (data?.status !== 'success' || Date.now() - completed > 24 * 60 * 60 * 1000) {
    try {
      await refresh()
    } catch (error) {
      const { count } = await database.from('market_instruments')
        .select('*', { count: 'exact', head: true }).eq('market', 'TWSE')
      if (!count) throw error
    }
  }
}

async function rowsWithQuotes(query?: string, symbols?: string[]) {
  let rows: CatalogueRow[] = []
  for (let page = 0; ; page += 1) {
    let request = database.from('market_catalogue_with_latest_quotes')
      .select('market,symbol,name,instrument_type,currency,source_updated_at,quote_date,close_price_minor')
      .eq('market', 'TWSE').eq('is_active', true)
    if (symbols) request = request.in('symbol', symbols)
    const { data, error } = await request.order('symbol')
      .range(page * 1000, page * 1000 + 999)
    if (error) throw error
    const pageRows = (data ?? []) as CatalogueRow[]
    rows = rows.concat(pageRows)
    if (pageRows.length < 1000 || symbols) break
  }
  if (query) {
    const normalized = normalize(query)
    rows = rows.filter((item) =>
      item.symbol.includes(normalized) || normalize(item.name).includes(normalized)
    ).sort((left, right) => {
      const leftExact = left.symbol === normalized ? 0 : 1
      const rightExact = right.symbol === normalized ? 0 : 1
      if (leftExact !== rightExact) return leftExact - rightExact
      const leftPrefix = left.symbol.startsWith(normalized) ? 0 : 1
      const rightPrefix = right.symbol.startsWith(normalized) ? 0 : 1
      return leftPrefix - rightPrefix || left.symbol.localeCompare(right.symbol)
    }).slice(0, 8)
  }
  return rows.map((item) => ({
      market: item.market, symbol: item.symbol, name: item.name,
      type: item.instrument_type, currency: item.currency,
      closePriceMinor: item.close_price_minor ?? 0,
      quoteDate: item.quote_date ?? null, source: 'twse',
    }))
}

Deno.serve(async (request) => {
  if (request.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })
  if (request.method !== 'POST') return response({ error: 'method_not_allowed' }, 405)
  let body: Json
  try { body = await request.json() } catch { return response({ error: 'invalid_json' }, 400) }
  const action = body.action
  const isCron = action === 'refresh' && cronSecret.length > 0 &&
    request.headers.get('x-cron-secret') === cronSecret
  if (!isCron && !await requireUser(request)) {
    return response({ error: 'not_authenticated' }, 401)
  }
  try {
    if (action === 'refresh') {
      if (!isCron) return response({ error: 'forbidden' }, 403)
      const result = await refresh()
      return response({ status: 'ok', ...result })
    }
    await refreshIfStale()
    if (action === 'catalog') {
      const items = await rowsWithQuotes()
      return response(
        { version: items.reduce((v, item) => item.quoteDate && item.quoteDate > v ? item.quoteDate : v, ''), items },
        200, 'private, max-age=3600',
      )
    }
    if (action === 'search') {
      const query = normalize(body.query)
      if (query.length < 2) return response({ items: [] })
      return response({ items: await rowsWithQuotes(query) })
    }
    if (action === 'lookup') {
      const symbol = normalize(body.symbol)
      if (!symbol) return response({ error: 'invalid_symbol' }, 400)
      const items = await rowsWithQuotes(undefined, [symbol])
      return items.length === 0
        ? response({ error: 'not_found' }, 404)
        : response(items[0] as Json)
    }
    if (action === 'quotes') {
      const symbols = Array.isArray(body.symbols)
        ? body.symbols.map(normalize).filter(Boolean).slice(0, 100) : []
      return response({ items: await rowsWithQuotes(undefined, symbols) })
    }
    return response({ error: 'unknown_action' }, 400)
  } catch (error) {
    return response({ error: 'upstream_unavailable', detail: String(error).slice(0, 200) }, 503)
  }
})
