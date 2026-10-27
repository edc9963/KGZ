// Receives one Apple Pay tap from the iPhone Shortcuts "Transaction"
// automation, stores it in capture_inbox as pending, and pushes a LINE
// message with one-tap category buttons (handled by line-webhook).
//
//   POST /functions/v1/apple-pay-ingest
//   header  x-capture-token: kgz_...   (from LINE「捷徑設定」)
//   body    { "amount": "NT$85.00", "merchant": "7-ELEVEN", "card": "國泰 CUBE" }
//
// Deploy with --no-verify-jwt: the capture token is the auth boundary. Only
// its SHA-256 is stored; the raw request body is never logged.
import { createClient } from 'npm:@supabase/supabase-js@2'
import { pushLine } from '../_shared/line.ts'
import { captureMessage, parseCaptureAmount, sha256Hex } from '../_shared/capture.ts'

type Json = Record<string, unknown>

const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? ''
const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
const channelAccessToken = Deno.env.get('LINE_CHANNEL_ACCESS_TOKEN') ?? ''

const database = createClient(supabaseUrl, serviceRoleKey, {
  auth: { persistSession: false, autoRefreshToken: false },
})

function respond(status: number, body: Json): Response {
  return Response.json(body, { status, headers: { 'Cache-Control': 'no-store' } })
}

function text(value: unknown): string {
  return typeof value === 'string' ? value : value == null ? '' : String(value)
}

const tokenPattern = /kgz_[A-Za-z0-9_-]{20,64}/

// Shortcuts setups vary (header key typos, pasted with extra text or line
// breaks, token put in the body), so look for a kgz_ token in every
// plausible place instead of only the exact header.
function readToken(request: Request, body: Json): string {
  const candidates = [
    request.headers.get('x-capture-token'),
    request.headers.get('authorization'),
    text(body.token),
    text(body['x-capture-token']),
  ]
  for (const [, value] of request.headers) candidates.push(value)
  for (const candidate of candidates) {
    const match = (candidate ?? '').replace(/\s+/g, '').match(tokenPattern)
    if (match) return match[0]
  }
  return ''
}

function describeTokenProblem(request: Request): string {
  const header = request.headers.get('x-capture-token')
  if (header === null) {
    return '沒收到金鑰：請確認「標頭」的鍵是 x-capture-token'
  }
  if (!header.trim()) return '金鑰是空的：請把 LINE 傳來 kgz_ 開頭的金鑰貼到標頭的值'
  return `金鑰格式不對（收到 ${header.trim().slice(0, 6)}…，長度 ${header.trim().length}），請重新複製 kgz_ 開頭那則訊息`
}

Deno.serve(async (request) => {
  if (request.method !== 'POST') {
    return respond(405, { ok: false, message: 'method_not_allowed' })
  }
  if (!supabaseUrl || !serviceRoleKey) {
    return respond(503, { ok: false, message: 'server_not_configured' })
  }

  const raw = await request.text()
  if (raw.length > 4096) return respond(413, { ok: false, message: '資料太大' })
  let body: Json
  try {
    body = raw ? JSON.parse(raw) : {}
    if (!body || typeof body !== 'object' || Array.isArray(body)) throw new Error()
  } catch {
    return respond(400, { ok: false, message: '格式錯誤，請確認捷徑的「要求本文」是 JSON' })
  }

  const token = readToken(request, body)
  if (!token) return respond(401, { ok: false, message: describeTokenProblem(request) })

  const amount = parseCaptureAmount(body.amount)
  if (!amount) return respond(400, { ok: false, message: '看不懂金額，這筆沒有記錄' })

  let occurredAt = new Date().toISOString()
  const suppliedDate = text(body.date)
  if (suppliedDate) {
    const parsed = new Date(suppliedDate)
    if (!Number.isNaN(parsed.getTime())) occurredAt = parsed.toISOString()
  }

  const { data, error } = await database.rpc('capture_ingest', {
    p_token_hash: await sha256Hex(token),
    p_amount_minor: amount.amountMinor,
    p_currency: amount.currency,
    p_merchant: text(body.merchant).slice(0, 200),
    p_card_label: text(body.card).slice(0, 200),
    p_occurred_at: occurredAt,
  })
  if (error) {
    console.error(JSON.stringify({ code: 'capture_ingest_failed', errorCode: error.code }))
    return respond(500, { ok: false, message: '暫時無法記錄，請稍後再試' })
  }
  const result = (data ?? {}) as Json
  if (result.status === 'invalid_token') {
    return respond(401, { ok: false, message: '金鑰已失效，請到 LINE 輸入「捷徑設定」重新產生' })
  }
  if (result.status === 'invalid_amount') {
    return respond(400, { ok: false, message: '看不懂金額，這筆沒有記錄' })
  }
  if (result.status === 'rate_limited') {
    return respond(429, { ok: false, message: '一小時內送出太多筆，請稍後再試' })
  }
  if (result.status === 'duplicate') {
    return respond(200, { ok: true, status: 'duplicate', message: '這筆已經收過了' })
  }

  const lineUserId = text(result.lineUserId)
  if (!lineUserId || !channelAccessToken) {
    return respond(200, {
      ok: true,
      status: 'created',
      pushed: false,
      message: '已存入待確認；LINE 尚未連結，請到官方帳號輸入「連結」',
    })
  }
  try {
    await pushLine(channelAccessToken, lineUserId, [captureMessage(result.capture as Json)])
  } catch (pushError) {
    console.error(JSON.stringify({
      code: 'capture_push_failed',
      errorCode: pushError instanceof Error ? pushError.message.split(':')[0] : 'unknown',
    }))
    return respond(200, {
      ok: true,
      status: 'created',
      pushed: false,
      message: '已存入待確認，但 LINE 推播失敗；在 LINE 輸入「待確認」即可處理',
    })
  }
  return respond(200, { ok: true, status: 'created', pushed: true, message: '已送到 LINE 待確認' })
})
