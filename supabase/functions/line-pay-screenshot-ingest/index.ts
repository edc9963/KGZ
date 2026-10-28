// Receives the text an iOS Shortcut read off a screenshot of the LINE Pay
// official account chat (「從影像擷取文字」runs on the phone; the image never
// leaves it), stores every payment card found in capture_inbox (source =
// linePay for the bound credit card, linePayMoney for the wallet) and pushes
// the newest one to LINE for confirmation; line-webhook offers the rest one
// after another.
//
//   POST /functions/v1/line-pay-screenshot-ingest
//   header  x-capture-token: kgz_...   (same token as the Apple Pay shortcut)
//   body    { "text": "<OCR text>" }   (or the text itself as text/plain)
//
// The response's "message" is meant for the Shortcut's「顯示通知」.
// Payments seen in an earlier screenshot come back as duplicates. Deploy with
// --no-verify-jwt: the capture token is the auth boundary. OCR text is never
// logged.
import { createClient } from 'npm:@supabase/supabase-js@2'
import { pushLine, textMessage } from '../_shared/line.ts'
import { captureMessage, sha256Hex } from '../_shared/capture.ts'
import { parseLinePayOcr } from '../_shared/line_pay_ocr.ts'

type Json = Record<string, unknown>

const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? ''
const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
const channelAccessToken = Deno.env.get('LINE_CHANNEL_ACCESS_TOKEN') ?? ''

const database = createClient(supabaseUrl, serviceRoleKey, {
  auth: { persistSession: false, autoRefreshToken: false },
})

const tokenPattern = /^kgz_[A-Za-z0-9_-]{20,64}$/
// capture_ingest replaces older times with now(); such cards are history.
const maxAgeMs = 30 * 24 * 60 * 60 * 1000

function respond(status: number, body: Json): Response {
  return Response.json(body, { status, headers: { 'Cache-Control': 'no-store' } })
}

Deno.serve(async (request) => {
  if (request.method !== 'POST') {
    return respond(405, { ok: false, message: 'method_not_allowed' })
  }
  if (!supabaseUrl || !serviceRoleKey) {
    return respond(503, { ok: false, message: 'server_not_configured' })
  }

  const token = (request.headers.get('x-capture-token') ?? '').trim()
  if (!tokenPattern.test(token)) {
    return respond(401, { ok: false, message: 'missing_or_malformed_token' })
  }

  const raw = await request.text()
  if (raw.length > 65536) return respond(413, { ok: false, message: 'too_large' })
  let text = raw
  if (/^\s*\{/.test(raw)) {
    try {
      const body = JSON.parse(raw)
      text = typeof body?.text === 'string' ? body.text : ''
    } catch {
      return respond(400, { ok: false, message: 'invalid_json' })
    }
  }

  const now = Date.now()
  const captures = parseLinePayOcr(text).filter((capture) =>
    now - new Date(capture.occurredAt).getTime() <= maxAgeMs
  )
  if (captures.length === 0) {
    return respond(200, {
      ok: true, created: 0, duplicate: 0,
      message: '截圖裡沒有讀到 LINE Pay 付款',
    })
  }

  const tokenHash = await sha256Hex(token)
  const created: Json[] = []
  let duplicate = 0
  let lineUserId = ''
  for (const capture of captures) {
    const { data, error } = await database.rpc('capture_ingest', {
      p_token_hash: tokenHash,
      p_amount_minor: capture.amountMinor,
      p_currency: capture.currency,
      p_merchant: capture.merchant,
      p_card_label: capture.cardLabel,
      p_occurred_at: capture.occurredAt,
      p_source: capture.source,
      p_external_ref: capture.externalRef,
    })
    if (error) {
      console.error(JSON.stringify({ code: 'line_pay_ocr_ingest_failed', errorCode: error.code }))
      return respond(500, { ok: false, message: 'ingest_failed' })
    }
    const result = (data ?? {}) as Json
    if (result.status === 'invalid_token') {
      return respond(401, { ok: false, message: 'invalid_token' })
    }
    if (result.status === 'rate_limited') break
    if (result.status === 'duplicate') duplicate++
    if (result.status === 'created') {
      created.push(result.capture as Json)
      lineUserId = String(result.lineUserId ?? '')
    }
  }

  const message = created.length
    ? `新增 ${created.length} 筆 LINE Pay 待確認` +
      (duplicate ? `（${duplicate} 筆先前已收過）` : '')
    : `${duplicate} 筆都已收過，沒有新的付款`
  if (created.length === 0 || !lineUserId || !channelAccessToken) {
    return respond(200, {
      ok: true, created: created.length, duplicate, pushed: false, message,
    })
  }

  // Newest first, matching the 待確認 list and line-webhook's "next" order.
  created.sort((a, b) => String(b.occurredAt).localeCompare(String(a.occurredAt)))
  const messages = created.length > 1
    ? [textMessage(`收到 ${created.length} 筆 LINE Pay 付款，逐筆確認：`), captureMessage(created[0])]
    : [captureMessage(created[0])]
  try {
    await pushLine(channelAccessToken, lineUserId, messages)
  } catch (pushError) {
    console.error(JSON.stringify({
      code: 'line_pay_ocr_push_failed',
      errorCode: pushError instanceof Error ? pushError.message.split(':')[0] : 'unknown',
    }))
    return respond(200, {
      ok: true, created: created.length, duplicate, pushed: false, message,
    })
  }
  return respond(200, { ok: true, created: created.length, duplicate, pushed: true, message })
})
