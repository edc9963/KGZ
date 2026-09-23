// Daily sweep that pushes a LINE message for each credit-card bill that
// needs an auto-debit reminder today (auto-debit already failed, bill
// overdue, or auto-debit date is 3/1/0 days away - same set the in-app
// "今日待處理" list shows, see LedgerQueries.reminders). Not scheduled from
// inside this project; call it once a day the same way the existing
// investment-quotes refresh is scheduled, with:
//   POST /card-bill-reminders  { "action": "send" }
//   header  x-cron-secret: <CARD_REMINDER_CRON_SECRET>
//
// The pushed message carries a quick-reply postback (`bill:ack:<billId>`)
// so the user can confirm straight from LINE; supabase/functions/
// line-webhook/index.ts handles that postback by calling
// line_acknowledge_bill_reminder.

import { createClient } from 'npm:@supabase/supabase-js@2'
import { postback, pushLine, textMessage } from '../_shared/line.ts'

type Json = Record<string, unknown>
type Candidate = {
  bill_id: string
  user_id: string
  line_user_id: string
  card_name: string
  bill_month: string
  auto_debit_date: string
  due_date: string
  outstanding_minor: number
  kind: 'debit_failed' | 'overdue' | 'debit_soon'
}

const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? ''
const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
const channelAccessToken = Deno.env.get('LINE_CHANNEL_ACCESS_TOKEN') ?? ''
const cronSecret = Deno.env.get('CARD_REMINDER_CRON_SECRET') ?? ''

const database = createClient(supabaseUrl, serviceRoleKey, {
  auth: { persistSession: false, autoRefreshToken: false },
})

function response(body: Json, status = 200): Response {
  return Response.json(body, { status, headers: { 'Cache-Control': 'no-store' } })
}

function formatTwd(minor: number): string {
  return (minor / 100).toLocaleString('zh-TW', {
    minimumFractionDigits: 0,
    maximumFractionDigits: 2,
  })
}

function formatDate(value: string): string {
  const date = new Date(value)
  return `${date.getMonth() + 1}/${date.getDate()}`
}

function messageFor(candidate: Candidate): string {
  const amount = formatTwd(candidate.outstanding_minor)
  if (candidate.kind === 'debit_failed') {
    return `⚠️ ${candidate.card_name}（${candidate.bill_month}）自動扣款失敗，尚未繳 NT$${amount}，請盡快處理。`
  }
  if (candidate.kind === 'overdue') {
    return `⚠️ ${candidate.card_name}（${candidate.bill_month}）帳單已逾期（繳款截止 ${formatDate(candidate.due_date)}），尚未繳 NT$${amount}。`
  }
  const days = daysUntil(candidate.auto_debit_date)
  const when = days === 0 ? '今天' : `${days} 天後`
  return `💳 ${candidate.card_name}（${candidate.bill_month}）${when}將自動扣款 NT$${amount}（${formatDate(candidate.auto_debit_date)}），請確認扣款帳戶餘額足夠。`
}

function daysUntil(dateText: string): number {
  const today = new Date()
  const target = new Date(dateText)
  const utcToday = Date.UTC(today.getFullYear(), today.getMonth(), today.getDate())
  const utcTarget = Date.UTC(target.getFullYear(), target.getMonth(), target.getDate())
  return Math.round((utcTarget - utcToday) / 86_400_000)
}

async function sendReminders(): Promise<{ sent: number; failed: number; total: number }> {
  const { data, error } = await database.rpc('card_bill_reminder_candidates')
  if (error) throw error
  const candidates = (data ?? []) as Candidate[]
  let sent = 0
  let failed = 0
  for (const candidate of candidates) {
    try {
      // Only the upcoming-auto-debit heads-up is dismissable - a failed or
      // overdue bill needs the user to actually resolve it, so it isn't
      // offered a "don't remind me again" quick reply (mirrors the
      // dashboard, and card_bill_reminder_candidates itself never lets
      // reminder_dismissed suppress those two kinds).
      const actions = candidate.kind === 'debit_soon'
        ? [postback('確認，這筆帳單不用再提醒', `bill:ack:${candidate.bill_id}`)]
        : []
      await pushLine(channelAccessToken, candidate.line_user_id, [
        textMessage(messageFor(candidate), actions),
      ])
      sent += 1
    } catch (pushError) {
      failed += 1
      console.error(JSON.stringify({
        code: 'card_bill_reminder_push_failed',
        billId: candidate.bill_id,
        message: pushError instanceof Error ? pushError.message : String(pushError),
      }))
    }
  }
  return { sent, failed, total: candidates.length }
}

Deno.serve(async (request) => {
  if (request.method !== 'POST') {
    return response({ error: 'method_not_allowed' }, 405)
  }
  if (!supabaseUrl || !serviceRoleKey || !channelAccessToken || !cronSecret) {
    return response({ error: 'server_not_configured' }, 503)
  }
  let body: Json
  try {
    body = await request.json()
  } catch {
    return response({ error: 'invalid_json' }, 400)
  }
  const isCron = body.action === 'send' &&
    request.headers.get('x-cron-secret') === cronSecret
  if (!isCron) {
    return response({ error: 'forbidden' }, 403)
  }
  try {
    const result = await sendReminders()
    return response({ ok: true, ...result })
  } catch (error) {
    console.error(JSON.stringify({
      code: 'card_bill_reminder_sweep_failed',
      message: error instanceof Error ? error.message : String(error),
    }))
    return response({ error: 'sweep_failed' }, 500)
  }
})
