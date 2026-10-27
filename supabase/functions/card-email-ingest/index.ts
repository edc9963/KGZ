// Receives one bank transaction notice email from the Gmail Apps Script
// (tool/line-pay-gmail-forwarder.gs), keeps it only if it is a LINE Pay
// credit-card charge or a TWPAY / debit-card account debit, stores it in
// capture_inbox (source = linePay / twPay / debitCard) and pushes the same
// LINE confirmation message as apple-pay-ingest.
//
//   POST /functions/v1/card-email-ingest
//   header  x-capture-token: kgz_...   (same token as the Apple Pay shortcut)
//   body    { "messageId": "...", "from": "...", "subject": "...",
//             "body": "<plain text>", "receivedAt": "2026-10-27T01:31:00Z" }
//
// Deploy with --no-verify-jwt: the capture token is the auth boundary. Email
// content is never logged.
import { createClient } from 'npm:@supabase/supabase-js@2'
import { pushLine } from '../_shared/line.ts'
import { captureMessage, sha256Hex } from '../_shared/capture.ts'
import { parseCardEmail } from '../_shared/card_email.ts'

type Json = Record<string, unknown>

const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? ''
const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
const channelAccessToken = Deno.env.get('LINE_CHANNEL_ACCESS_TOKEN') ?? ''

const database = createClient(supabaseUrl, serviceRoleKey, {
  auth: { persistSession: false, autoRefreshToken: false },
})

const tokenPattern = /^kgz_[A-Za-z0-9_-]{20,64}$/

function respond(status: number, body: Json): Response {
  return Response.json(body, { status, headers: { 'Cache-Control': 'no-store' } })
}

function text(value: unknown): string {
  return typeof value === 'string' ? value : ''
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
  let body: Json
  try {
    body = raw ? JSON.parse(raw) : {}
    if (!body || typeof body !== 'object' || Array.isArray(body)) throw new Error()
  } catch {
    return respond(400, { ok: false, message: 'invalid_json' })
  }

  const parsed = parseCardEmail(body)
  if (parsed.kind === 'ignored') {
    return respond(200, { ok: true, status: 'ignored', reason: parsed.reason })
  }

  const { capture } = parsed
  const { data, error } = await database.rpc('capture_ingest', {
    p_token_hash: await sha256Hex(token),
    p_amount_minor: capture.amountMinor,
    p_currency: capture.currency,
    p_merchant: capture.merchant,
    p_card_label: capture.cardLabel,
    p_occurred_at: capture.occurredAt,
    p_source: parsed.source,
    p_external_ref: text(body.messageId).slice(0, 200) || null,
  })
  if (error) {
    console.error(JSON.stringify({ code: 'card_email_ingest_failed', errorCode: error.code }))
    return respond(500, { ok: false, message: 'ingest_failed' })
  }
  const result = (data ?? {}) as Json
  if (result.status === 'invalid_token') {
    return respond(401, { ok: false, message: 'invalid_token' })
  }
  if (result.status === 'rate_limited') {
    return respond(429, { ok: false, message: 'rate_limited' })
  }
  if (result.status !== 'created') {
    return respond(200, { ok: true, status: String(result.status ?? 'unknown') })
  }

  const lineUserId = text(result.lineUserId)
  if (!lineUserId || !channelAccessToken) {
    return respond(200, { ok: true, status: 'created', pushed: false })
  }
  try {
    await pushLine(channelAccessToken, lineUserId, [captureMessage(result.capture as Json)])
  } catch (pushError) {
    console.error(JSON.stringify({
      code: 'card_email_push_failed',
      errorCode: pushError instanceof Error ? pushError.message.split(':')[0] : 'unknown',
    }))
    return respond(200, { ok: true, status: 'created', pushed: false })
  }
  return respond(200, { ok: true, status: 'created', pushed: true })
})
