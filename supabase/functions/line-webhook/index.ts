import { createClient, SupabaseClient } from 'npm:@supabase/supabase-js@2'
import type { LineAction, LineMessage } from '../_shared/line.ts'
import {
  postback,
  replyLine,
  textMessage,
  verifyLineSignature,
} from '../_shared/line.ts'
import {
  accountPickerMessage,
  captureMessage,
  captureSourceName,
  cardPickerMessage,
  formatCaptureMoney,
  formatTaipeiTime,
  generateCaptureToken,
  NO_CARD,
  paymentKindMessage,
  sha256Hex,
  splitCapturePostback,
} from '../_shared/capture.ts'

type Json = Record<string, unknown>
type LineEvent = {
  type: string
  webhookEventId?: string
  replyToken?: string
  source?: { type?: string; userId?: string }
  message?: { type?: string; text?: string; id?: string }
  postback?: { data?: string }
}

type Conversation = {
  flow: string
  step: string
  payload: Json
  expires_at: string
}

const channelSecret = Deno.env.get('LINE_CHANNEL_SECRET') ?? ''
const channelAccessToken = Deno.env.get('LINE_CHANNEL_ACCESS_TOKEN') ?? ''
const expectedDestination = Deno.env.get('LINE_BOT_USER_ID') ?? ''
const appPublicUrl = (Deno.env.get('APP_PUBLIC_URL') ?? '').replace(/\/$/, '')
const appLoginUrl = appPublicUrl
  ? `${appPublicUrl}/login?source=line_oa&next=%2Fdashboard`
  : ''
const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? ''
const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''

const database = createClient(supabaseUrl, serviceRoleKey, {
  auth: { persistSession: false, autoRefreshToken: false },
})

const paymentMethods: Record<string, string> = {
  cash: '現金',
  linePay: 'LINE Pay',
  creditCard: '信用卡',
  transfer: '銀行轉帳',
  debitCard: '簽帳金融卡',
  telecomBill: '電信帳單繳費',
  other: '其他',
}

// Offered in the bot's payment picker; kept in sync with the web app's
// selectable methods (PaymentMethod.isSelectable). The full map above still
// labels older records that used a retired method.
const selectablePaymentMethods = [
  'cash',
  'transfer',
  'debitCard',
  'creditCard',
  'telecomBill',
]

Deno.serve(async (request) => {
  if (request.method !== 'POST') {
    return Response.json({ error: 'method_not_allowed' }, { status: 405 })
  }
  if (!channelSecret || !channelAccessToken || !supabaseUrl || !serviceRoleKey) {
    return Response.json({ error: 'server_not_configured' }, { status: 503 })
  }

  const rawBody = await request.text()
  if (!await verifyLineSignature(
    rawBody,
    request.headers.get('x-line-signature'),
    channelSecret,
  )) {
    return Response.json({ error: 'invalid_signature' }, { status: 401 })
  }

  let body: { destination?: string; events?: LineEvent[] }
  try {
    body = JSON.parse(rawBody)
  } catch {
    return Response.json({ error: 'invalid_json' }, { status: 400 })
  }
  if (expectedDestination && body.destination !== expectedDestination) {
    // A valid LINE signature already authenticates the channel that sent the
    // request. Keep destination as a deployment diagnostic, but do not let a
    // stale/mistyped optional Bot User ID disable every signed webhook event.
    console.warn(JSON.stringify({
      code: 'line_destination_mismatch',
      eventCount: body.events?.length ?? 0,
    }))
  }

  const work = Promise.allSettled(
    (body.events ?? []).map((event) => processEvent(database, event)),
  )
  // Supabase Edge Runtime keeps the isolate alive after returning 200.
  // deno-lint-ignore no-explicit-any
  const runtime = (globalThis as any).EdgeRuntime
  if (runtime?.waitUntil) {
    runtime.waitUntil(work)
  } else {
    await work
  }
  return Response.json({ ok: true })
})

async function processEvent(db: SupabaseClient, event: LineEvent) {
  // webhookEventId is present on current LINE deliveries, but using a stable
  // digest keeps older/test deliveries functional without giving up
  // idempotency or storing their raw payload as the primary key.
  const eventId = event.webhookEventId ?? await fallbackEventId(event)
  const lineUserId = event.source?.userId

  const { error: eventError } = await db.from('line_webhook_events').insert({
    webhook_event_id: eventId,
    line_user_id: lineUserId ?? null,
    event_type: event.type,
  })
  if (eventError?.code === '23505') {
    const { data: prior, error: priorError } = await db
      .from('line_webhook_events')
      .select('status,received_at')
      .eq('webhook_event_id', eventId)
      .single()
    if (priorError) throw priorError
    const stale = Date.now() - new Date(prior.received_at).getTime() > 5 * 60 * 1000
    if (prior.status !== 'failed' && !(prior.status === 'processing' && stale)) {
      return
    }
    const { error: retryError } = await db.from('line_webhook_events').update({
      status: 'processing',
      error_code: null,
      received_at: new Date().toISOString(),
      processed_at: null,
    }).eq('webhook_event_id', eventId)
    if (retryError) throw retryError
  }
  if (eventError && eventError.code !== '23505') throw eventError

  let status = 'completed'
  let errorCode: string | null = null
  try {
    if (!event.replyToken || !lineUserId) {
      status = 'ignored'
      return
    }
    if (event.source?.type !== 'user') {
      await reply(event.replyToken, [
        textMessage('為保護財務隱私，快記帳只在一對一聊天室提供操作。'),
      ])
      status = 'ignored'
      return
    }
    const messages = await routeEvent(db, lineUserId, event)
    if (messages.length > 0) await reply(event.replyToken, messages)
  } catch (error) {
    status = 'failed'
    errorCode = safeErrorCode(error)
    console.error(JSON.stringify({
      code: 'line_event_failed',
      eventType: event.type,
      errorCode,
    }))
    if (event.replyToken) {
      try {
        await reply(event.replyToken, [
          textMessage('操作暫時失敗，請稍後重試。資料沒有被重複寫入。'),
        ])
      } catch {
        // The original reply failure is the useful diagnostic.
      }
    }
  } finally {
    await db.from('line_webhook_events').update({
      status,
      error_code: errorCode,
      processed_at: new Date().toISOString(),
    }).eq('webhook_event_id', eventId)
  }
}

async function routeEvent(
  db: SupabaseClient,
  lineUserId: string,
  event: LineEvent,
): Promise<LineMessage[]> {
  if (event.type === 'follow') return identityPrompt(db, lineUserId)
  if (event.type === 'postback') {
    return handlePostback(db, lineUserId, event.postback?.data ?? '')
  }
  if (event.type !== 'message') return []
  if (event.message?.type === 'image') {
    return [textMessage(
      'LINE 圖片記帳目前不支援；這張圖片不會被下載或保存。',
    )]
  }
  if (event.message?.type !== 'text') return []
  return handleText(db, lineUserId, event.message.text?.trim() ?? '')
}

async function identityPrompt(
  db: SupabaseClient,
  lineUserId: string,
): Promise<LineMessage[]> {
  const identity = await rpc(db, 'line_resolve_identity', {
    p_line_user_id: lineUserId,
  })
  if (identity.status === 'linked') return [helpMessage()]
  if (identity.status === 'available') {
    return [textMessage(
      '已找到你使用 LINE 登入的快記帳資料。請確認是否將此官方帳號連結到該資料。',
      [
        postback('確認連結', 'account:link', '確認連結快記帳'),
        postback('暫不連結', 'account:cancel', '暫不連結'),
      ],
    )]
  }
  const suffix = appPublicUrl
    ? `\n請先登入：${appPublicUrl}/login?source=line_oa&next=%2Fdashboard`
    : '\n請先在快記帳網站完成 LINE 登入，再回來輸入「連結」。'
  return [textMessage(`目前找不到可連結的快記帳帳號。${suffix}`)]
}

async function handleText(
  db: SupabaseClient,
  lineUserId: string,
  text: string,
): Promise<LineMessage[]> {
  const normalized = text.replace(/\s+/g, '')
  if (['說明', '幫助', 'help', 'Help', 'HELP'].includes(text)) {
    return [helpMessage()]
  }
  if (normalized === '連結') return identityPrompt(db, lineUserId)
  if (normalized === '取消') {
    await clearConversation(db, lineUserId)
    return [textMessage('已取消目前操作。', menuActions())]
  }
  if (normalized === '財務總覽' || normalized === '總覽') {
    return summaryMessages(db, lineUserId)
  }
  if (normalized === '快速支出' || normalized === '記帳') {
    return startExpense(db, lineUserId)
  }
  if (normalized === '待收款') return receivableMessages(db, lineUserId)
  if (['已繳費', '已繳款', '繳費', '已繳'].includes(normalized)) {
    return unpaidBillMessages(db, lineUserId)
  }
  if (['捷徑設定', '捷徑', 'ApplePay', 'applepay', 'APPLEPAY', 'ApplePay設定']
    .includes(normalized)) {
    return captureSetupMessages(db, lineUserId)
  }
  if (normalized === '待確認') return pendingCaptureMessages(db, lineUserId)

  const conversation = await getConversation(db, lineUserId)
  if (!conversation) return [helpMessage()]
  if (conversation.flow !== 'expense') {
    await clearConversation(db, lineUserId)
    return [helpMessage()]
  }
  if (conversation.step === 'amount') {
    const amount = parseTwd(text)
    if (amount === null) {
      return [textMessage('請輸入大於 0 的金額，例如：120。輸入「取消」可結束。')]
    }
    await saveConversation(db, lineUserId, 'expense', 'item', {
      ...conversation.payload,
      amountMinor: amount,
    })
    return [textMessage('這筆支出的品項是什麼？（1–80 字）')]
  }
  if (conversation.step === 'item') {
    if (text.length < 1 || text.length > 80) {
      return [textMessage('品項請輸入 1–80 個字。')]
    }
    const result = await rpc(db, 'line_list_bookkeeping_categories', {
      p_line_user_id: lineUserId,
    })
    if (result.status === 'not_linked') return identityPrompt(db, lineUserId)
    const categories = (result.items ?? []) as Json[]
    const payload = { ...conversation.payload, item: text, categories }
    await saveConversation(db, lineUserId, 'expense', 'category', payload)
    return [categoryPicker(categories, 0)]
  }
  return [textMessage('請使用畫面上的按鈕繼續，或輸入「取消」。')]
}

async function handlePostback(
  db: SupabaseClient,
  lineUserId: string,
  data: string,
): Promise<LineMessage[]> {
  if (data === 'account:link') {
    const result = await rpc(db, 'line_link_account', {
      p_line_user_id: lineUserId,
    })
    return result.status === 'linked'
      ? [textMessage('連結完成。現在可以從選單查總覽或快速記帳。', menuActions())]
      : identityPrompt(db, lineUserId)
  }
  if (data === 'account:cancel') {
    return [textMessage('未進行連結。之後輸入「連結」即可重新開始。')]
  }
  if (data === 'menu:summary') return summaryMessages(db, lineUserId)
  if (data === 'expense:start') return startExpense(db, lineUserId)
  if (data === 'receivables:list') return receivableMessages(db, lineUserId)
  if (data === 'menu:help') return [helpMessage()]
  if (data === 'ocr:disabled') {
    return [textMessage('Uber Eats 截圖辨識尚未啟用，圖片不會被保存。')]
  }
  if (data === 'web:disabled') {
    return [textMessage('網頁公開網址尚未設定。')]
  }

  const conversation = await getConversation(db, lineUserId)
  if (data.startsWith('expense:')) {
    if (!conversation || conversation.flow !== 'expense') {
      return [textMessage('這個操作已逾時，請重新選擇「快速支出」。')]
    }
    return expensePostback(db, lineUserId, data, conversation)
  }
  if (data.startsWith('receive:confirm:')) {
    return markReceivedMessages(
      db,
      lineUserId,
      data.substring('receive:confirm:'.length),
    )
  }
  if (data.startsWith('receive:save:')) {
    return markReceivedMessages(
      db,
      lineUserId,
      data.substring('receive:save:'.length),
    )
  }
  if (data === 'receive:cancel') return [textMessage('未變更收款狀態。')]
  if (data.startsWith('bill:ack:')) {
    return acknowledgeBillMessages(db, lineUserId, data.substring('bill:ack:'.length))
  }
  if (data.startsWith('bill:paid:')) {
    return markBillPaidMessages(db, lineUserId, data.substring('bill:paid:'.length))
  }
  if (data.startsWith('capture:')) return capturePostback(db, lineUserId, data)
  return [helpMessage()]
}

// ---- Apple Pay／LINE Pay 收件匣（見 supabase/functions/apple-pay-ingest、
// card-email-ingest）----

const functionsBaseUrl = supabaseUrl
  ? `${supabaseUrl.replace(/\/$/, '')}/functions/v1`
  : ''
const captureIngestUrl = functionsBaseUrl ? `${functionsBaseUrl}/apple-pay-ingest` : ''
const cardEmailIngestUrl = functionsBaseUrl ? `${functionsBaseUrl}/card-email-ingest` : ''
const lineScreenshotIngestUrl = functionsBaseUrl
  ? `${functionsBaseUrl}/line-pay-screenshot-ingest`
  : ''

async function captureSetupMessages(
  db: SupabaseClient,
  lineUserId: string,
): Promise<LineMessage[]> {
  const identity = await rpc(db, 'line_resolve_identity', {
    p_line_user_id: lineUserId,
  })
  if (identity.status !== 'linked') return identityPrompt(db, lineUserId)
  return [textMessage(
    [
      'Apple Pay／LINE Pay 自動記帳',
      '在 iPhone「捷徑」建立「交易」自動化後，每次感應 Apple Pay，這裡就會跳出一則待確認訊息，點分類即入帳。',
      'LINE Pay 付款後，對 LINE Pay 官方帳號的付款訊息截圖，再執行「LINE Pay 截圖記帳」捷徑，就會跳出待確認訊息（一張截圖可含多筆）。',
      'TWPAY 掃碼或金融卡消費時，用 Gmail 的 Apps Script 轉送銀行通知信，也會跳出待確認訊息。',
      '',
      '按「產生金鑰」取得要用的網址與金鑰（兩者共用同一把）。重新產生後，舊金鑰會立即失效。',
    ].join('\n'),
    [
      postback('產生金鑰', 'capture:token:new', '產生捷徑金鑰'),
      postback('待確認', 'capture:pending', '待確認'),
    ],
  )]
}

async function issueCaptureToken(
  db: SupabaseClient,
  lineUserId: string,
): Promise<LineMessage[]> {
  const token = generateCaptureToken()
  const result = await rpc(db, 'capture_issue_token', {
    p_line_user_id: lineUserId,
    p_token_hash: await sha256Hex(token),
  })
  if (result.status === 'not_linked') return identityPrompt(db, lineUserId)
  return [
    textMessage([
      '已產生新金鑰（舊金鑰已失效）。在捷徑的「取得 URL 內容」設定：',
      `網址：${captureIngestUrl}`,
      '方法：POST',
      '標頭：x-capture-token ＝ 下一則訊息的金鑰',
      '要求本文：JSON，欄位 amount（金額）、merchant（商家）、card（卡片或票卡）',
      '',
      'LINE Pay 截圖捷徑（同一把金鑰）：',
      `網址：${lineScreenshotIngestUrl}`,
      '要求本文：JSON，欄位 text ＝「從影像擷取文字」的結果',
      '',
      '銀行通知信（Gmail Apps Script 的指令碼屬性）：',
      `KGZ_URL ＝ ${cardEmailIngestUrl}`,
      'KGZ_TOKEN ＝ 下一則訊息的金鑰',
      '',
      '金鑰等同記帳權限，請勿轉傳給他人。',
    ].join('\n')),
    textMessage(token),
  ]
}

async function pendingCaptureMessages(
  db: SupabaseClient,
  lineUserId: string,
): Promise<LineMessage[]> {
  const result = await rpc(db, 'line_capture_list_pending', {
    p_line_user_id: lineUserId,
  })
  if (result.status === 'not_linked') return identityPrompt(db, lineUserId)
  const items = (result.items ?? []) as Json[]
  if (items.length === 0) {
    return [textMessage('目前沒有待確認的自動記帳消費。', menuActions())]
  }
  const lines = items.map((item, index) => {
    const merchant = String(item.merchant ?? '') || '（未提供商家）'
    const amount = formatCaptureMoney(Number(item.amountMinor), String(item.currency))
    const source = item.source && item.source !== 'applePay'
      ? `［${captureSourceName(item.source)}］`
      : ''
    return `${index + 1}. ${formatTaipeiTime(String(item.occurredAt))} ${source}${merchant} ${amount}`
  })
  const total = Number(result.total ?? items.length)
  const header = total > items.length
    ? `待確認（共 ${total} 筆，顯示最近 ${items.length} 筆）`
    : `待確認（共 ${total} 筆）`
  return [textMessage(
    [header, ...lines, '', '點選要處理的那一筆：'].join('\n'),
    items.slice(0, 13).map((item, index) =>
      postback(`第 ${index + 1} 筆`, `capture:open:${item.inboxId}`, `處理第 ${index + 1} 筆`)
    ),
  )]
}

async function capturePostback(
  db: SupabaseClient,
  lineUserId: string,
  data: string,
): Promise<LineMessage[]> {
  if (data === 'capture:token:new') return issueCaptureToken(db, lineUserId)
  if (data === 'capture:pending') return pendingCaptureMessages(db, lineUserId)

  const open = splitCapturePostback(data, 'capture:open:')
  if (open) {
    const result = await rpc(db, 'line_capture_open', {
      p_line_user_id: lineUserId,
      p_inbox_id: open.id,
    })
    if (result.status === 'ok') return [captureMessage(result.capture as Json)]
    return captureStatusMessages(db, lineUserId, result)
  }

  const skip = splitCapturePostback(data, 'capture:skip:')
  if (skip) {
    const result = await rpc(db, 'line_capture_dismiss', {
      p_line_user_id: lineUserId,
      p_inbox_id: skip.id,
    })
    if (result.status === 'dismissed') {
      return withNextCapture(db, lineUserId, skip.id, [textMessage('已略過這筆，不會記帳。')])
    }
    return captureStatusMessages(db, lineUserId, result)
  }

  const category = splitCapturePostback(data, 'capture:cat:')
  if (category?.rest) {
    return confirmCapture(db, lineUserId, category.id, category.rest, null, null)
  }
  const card = splitCapturePostback(data, 'capture:card:')
  if (card?.rest) {
    return confirmCapture(db, lineUserId, card.id, null, card.rest, null)
  }
  const account = splitCapturePostback(data, 'capture:acct:')
  if (account?.rest) {
    return confirmCapture(db, lineUserId, account.id, null, null, account.rest)
  }
  const pay = splitCapturePostback(data, 'capture:pay:')
  if (pay?.rest === 'card' || pay?.rest === 'acct') {
    return confirmCapture(db, lineUserId, pay.id, null, null, null, pay.rest)
  }
  return [textMessage('按鈕已失效，請輸入「待確認」重新開啟。')]
}

async function confirmCapture(
  db: SupabaseClient,
  lineUserId: string,
  inboxId: string,
  categoryId: string | null,
  cardChoice: string | null,
  accountChoice: string | null,
  // LINE Pay Money: the list the user asked for after「卡片／帳戶」.
  pick: 'card' | 'acct' | null = null,
): Promise<LineMessage[]> {
  const result = await rpc(db, 'line_capture_confirm', {
    p_line_user_id: lineUserId,
    p_inbox_id: inboxId,
    p_category_id: categoryId,
    p_card_choice: cardChoice,
    p_account_choice: accountChoice,
  })
  if (result.status === 'saved') {
    const card = result.cardName
      ? `／${result.cardName}`
      : cardChoice === NO_CARD
      ? '／不指定卡片'
      : accountChoice === NO_CARD
      ? '／不指定帳戶'
      : ''
    const amount = formatCaptureMoney(Number(result.amountMinor))
    return withNextCapture(db, lineUserId, inboxId, [textMessage(
      result.duplicate
        ? '這筆先前已經入帳。'
        : `已入帳：${result.merchant} ${amount}（${result.category}${card}）`,
    )])
  }
  if (result.status === 'needs_card' && result.source === 'linePayMoney') {
    if (pick === 'acct') {
      return [accountPickerMessage(
        inboxId,
        String(result.cardLabel ?? ''),
        (result.accounts ?? []) as Json[],
        result.source,
      )]
    }
    if (pick !== 'card') return [paymentKindMessage(inboxId)]
  }
  if (result.status === 'needs_card') {
    return [cardPickerMessage(
      inboxId,
      String(result.cardLabel ?? ''),
      (result.cards ?? []) as Json[],
      result.source,
    )]
  }
  if (result.status === 'needs_account') {
    return [accountPickerMessage(
      inboxId,
      String(result.cardLabel ?? ''),
      (result.accounts ?? []) as Json[],
      result.source,
    )]
  }
  if (result.status === 'invalid_category') {
    const reopened = await rpc(db, 'line_capture_open', {
      p_line_user_id: lineUserId,
      p_inbox_id: inboxId,
    })
    if (reopened.status === 'ok') {
      return [
        textMessage('分類清單已變更，請重新選擇。'),
        captureMessage(reopened.capture as Json),
      ]
    }
    return captureStatusMessages(db, lineUserId, reopened)
  }
  if (result.status === 'invalid_card') {
    return [textMessage('這張卡已停用或刪除，請輸入「待確認」重新選擇。')]
  }
  if (result.status === 'invalid_account') {
    return [textMessage('這個帳戶已停用或刪除，請輸入「待確認」重新選擇。')]
  }
  if (result.status === 'telecom_bill_not_configured') {
    return [textMessage(
      '還沒設定電信帳單：請先到網頁新增付款方式為「電信帳單繳費」的定期支出（電話費），再輸入「待確認」入帳這筆。',
    )]
  }
  return captureStatusMessages(db, lineUserId, result)
}

// Quick reply buttons only stay on the newest message, so when several
// captures arrive together only the last push can be answered. After one is
// handled, offer the next waiting capture right away.
async function withNextCapture(
  db: SupabaseClient,
  lineUserId: string,
  handledId: string,
  messages: LineMessage[],
): Promise<LineMessage[]> {
  const pending = await rpc(db, 'line_capture_list_pending', {
    p_line_user_id: lineUserId,
  })
  const items = ((pending.items ?? []) as Json[])
    .filter((item) => String(item.inboxId) !== handledId)
  if (items.length === 0) return messages
  const next = await rpc(db, 'line_capture_open', {
    p_line_user_id: lineUserId,
    p_inbox_id: String(items[0].inboxId),
  })
  if (next.status !== 'ok') return messages
  const total = Number(pending.total ?? items.length)
  return [
    ...messages,
    textMessage(`還有 ${total} 筆待確認，下一筆：`),
    captureMessage(next.capture as Json),
  ]
}

async function captureStatusMessages(
  db: SupabaseClient,
  lineUserId: string,
  result: Json,
): Promise<LineMessage[]> {
  switch (result.status) {
    case 'not_linked':
      return identityPrompt(db, lineUserId)
    case 'already_confirmed':
      return [textMessage('這筆已經入帳過了。')]
    case 'already_dismissed':
      return [textMessage('這筆已經略過了。')]
    case 'unsupported_currency':
      return [textMessage('外幣消費無法從 LINE 入帳，請到網頁記錄後按「略過」。')]
    default:
      return [textMessage('找不到這筆消費，可能已經處理過了。')]
  }
}

async function unpaidBillMessages(
  db: SupabaseClient,
  lineUserId: string,
): Promise<LineMessage[]> {
  const result = await rpc(db, 'line_list_unpaid_card_bills', {
    p_line_user_id: lineUserId,
  })
  if (result.status === 'not_linked') return identityPrompt(db, lineUserId)
  const items = (result.items ?? []) as Json[]
  if (items.length === 0) return [textMessage('目前沒有未繳的信用卡帳單。')]
  const lines = items.map((item) =>
    `・${item.cardName}（${item.billMonth}）未繳 ${formatMoney(Number(item.outstandingMinor))}`
  )
  const actions = items.map((item) =>
    postback(
      `${item.cardName} ${item.billMonth}`.slice(0, 20),
      `bill:paid:${item.billId}`,
      `${item.cardName}（${item.billMonth}）已繳費`,
    )
  )
  return [textMessage(`請選擇已繳費的帳單：\n${lines.join('\n')}`, actions)]
}

async function markBillPaidMessages(
  db: SupabaseClient,
  lineUserId: string,
  billId: string,
): Promise<LineMessage[]> {
  const result = await rpc(db, 'line_mark_card_bill_paid', {
    p_line_user_id: lineUserId,
    p_bill_id: billId,
  })
  const bill = `${result.cardName}（${result.billMonth}）`
  if (result.status === 'saved') {
    return [textMessage(
      `已記錄繳款 ${formatMoney(Number(result.amountMinor))}，${bill}帳單已結清，不會再提醒。`,
    )]
  }
  if (result.status === 'already_paid') {
    return [textMessage(`${bill}帳單已經結清，不會再提醒。`)]
  }
  if (result.status === 'needs_app') {
    return [textMessage(`${bill}無法從 LINE 直接記錄繳款，請到 App 的信用卡帳單頁記錄。`)]
  }
  if (result.status === 'not_linked') return identityPrompt(db, lineUserId)
  return [textMessage('找不到這筆帳單，可能已經被刪除或修改。')]
}

async function acknowledgeBillMessages(
  db: SupabaseClient,
  lineUserId: string,
  billId: string,
): Promise<LineMessage[]> {
  const result = await rpc(db, 'line_acknowledge_bill_reminder', {
    p_line_user_id: lineUserId,
    p_bill_id: billId,
  })
  if (result.status === 'saved') {
    return [textMessage(
      `已確認，${result.cardName}（${result.billMonth}）這筆帳單不會再提醒。`,
    )]
  }
  if (result.status === 'not_linked') return identityPrompt(db, lineUserId)
  return [textMessage('找不到這筆帳單，可能已經被刪除或修改。')]
}

async function markReceivedMessages(
  db: SupabaseClient,
  lineUserId: string,
  token: string,
): Promise<LineMessage[]> {
  const result = await rpc(db, 'line_mark_received', {
    p_line_user_id: lineUserId,
    p_token: token,
  })
  if (result.status === 'saved') {
    return [textMessage('已標記為收款，網頁資料也已同步更新。', menuActions())]
  }
  if (result.status === 'invalid_collection') {
    return [textMessage(
      '請先到網頁將收款方式設為現金，或選擇有效的銀行轉入帳戶。',
      menuActions(),
    )]
  }
  if (['already_paid', 'already_processed'].includes(String(result.status))) {
    return [textMessage('這筆款項已經處理完成。', menuActions())]
  }
  return [textMessage('操作已逾時，請重新開啟「待收款」。')]
}

async function startExpense(
  db: SupabaseClient,
  lineUserId: string,
): Promise<LineMessage[]> {
  const sources = await rpc(db, 'line_list_payment_sources', {
    p_line_user_id: lineUserId,
  })
  if (sources.status === 'not_linked') return identityPrompt(db, lineUserId)
  await saveConversation(db, lineUserId, 'expense', 'amount', {
    sources,
    commandId: crypto.randomUUID(),
  })
  return [textMessage('請輸入支出金額（新台幣），例如：120。')]
}

async function expensePostback(
  db: SupabaseClient,
  lineUserId: string,
  data: string,
  conversation: Conversation,
): Promise<LineMessage[]> {
  const payload = conversation.payload
  if (data.startsWith('expense:category-page:') && conversation.step === 'category') {
    const page = Number(data.substring('expense:category-page:'.length))
    const categories = (payload.categories ?? []) as Json[]
    if (!Number.isInteger(page) || page < 0 || page * 10 >= categories.length) {
      return [textMessage('分類頁面已失效，請重新開始。')]
    }
    return [categoryPicker(categories, page)]
  }
  if (data.startsWith('expense:category:') && conversation.step === 'category') {
    const id = data.substring('expense:category:'.length)
    const categories = (payload.categories ?? []) as Json[]
    const category = categories.find((item) => String(item.id) === id)
    if (!category) {
      return [textMessage('分類選項無效，請重新開始。')]
    }
    await saveConversation(db, lineUserId, 'expense', 'payment', {
      ...payload,
      category: String(category.name),
      categoryId: String(category.id),
    })
    return [textMessage(
      '選擇付款方式：',
      selectablePaymentMethods.map((key) =>
        postback(paymentMethods[key], `expense:payment:${key}`, paymentMethods[key])
      ),
    )]
  }

  if (data.startsWith('expense:payment:') && conversation.step === 'payment') {
    const method = data.substring('expense:payment:'.length)
    if (!selectablePaymentMethods.includes(method)) {
      return [textMessage('付款方式無效。')]
    }
    const next = { ...payload, paymentMethod: method }
    const sources = payload.sources as Json
    if (method === 'creditCard' || method === 'debitCard') {
      const requiredType = method === 'creditCard' ? 'credit' : 'debit'
      const cards = ((sources.cards ?? []) as Json[]).filter(
        (card) => String(card.cardType ?? 'credit') === requiredType,
      )
      if (cards.length === 0) {
        return [textMessage(
          method === 'creditCard'
            ? '目前沒有可用信用卡，請先到網頁新增，或選擇其他付款方式。'
            : '目前沒有可用金融卡，請先到網頁新增，或選擇其他付款方式。',
        )]
      }
      await saveConversation(db, lineUserId, 'expense', 'card', next)
      return [textMessage(
        method === 'creditCard' ? '選擇信用卡：' : '選擇金融卡：',
        cards.slice(0, 10).map((card, index) =>
          postback(
            `${String(card.name).slice(0, 12)} ${String(card.lastFour)}`,
            `expense:card:${index}`,
          )
        ),
      )]
    }
    if (method === 'transfer') {
      const accounts = (sources.accounts ?? []) as Json[]
      if (accounts.length === 0) {
        return [textMessage('目前沒有可用帳戶，請先到網頁新增，或選擇其他付款方式。')]
      }
      await saveConversation(db, lineUserId, 'expense', 'account', next)
      return [textMessage(
        '選擇扣款帳戶：',
        accounts.slice(0, 10).map((account, index) =>
          postback(String(account.name).slice(0, 20), `expense:account:${index}`)
        ),
      )]
    }
    if (method === 'telecomBill' && sources.telecomBillConfigured !== true) {
      return [textMessage(
        '請先到網頁的固定支出，設定電信帳單的扣款日與扣款帳戶。',
      )]
    }
    await saveConversation(db, lineUserId, 'expense', 'confirm', next)
    return [expenseConfirmation(next)]
  }

  if (data.startsWith('expense:card:') && conversation.step === 'card') {
    const index = Number(data.split(':')[2])
    const sources = payload.sources as Json
    const requiredType = payload.paymentMethod === 'debitCard'
      ? 'debit'
      : 'credit'
    const cards = ((sources.cards ?? []) as Json[]).filter(
      (card) => String(card.cardType ?? 'credit') === requiredType,
    )
    if (!Number.isInteger(index) || !cards[index]) {
      return [textMessage('卡片選項已失效，請重新開始。')]
    }
    const next = {
      ...payload,
      cardId: cards[index].id,
      ...(requiredType === 'debit'
        ? { accountId: cards[index].debitAccountId }
        : {}),
    }
    await saveConversation(db, lineUserId, 'expense', 'confirm', next)
    return [expenseConfirmation(next)]
  }

  if (data.startsWith('expense:account:') && conversation.step === 'account') {
    const index = Number(data.split(':')[2])
    const sources = payload.sources as Json
    const accounts = (sources.accounts ?? []) as Json[]
    if (!Number.isInteger(index) || !accounts[index]) {
      return [textMessage('帳戶選項已失效，請重新開始。')]
    }
    const next = { ...payload, accountId: accounts[index].id }
    await saveConversation(db, lineUserId, 'expense', 'confirm', next)
    return [expenseConfirmation(next)]
  }

  if (data === 'expense:save' && conversation.step === 'confirm') {
    const result = await rpc(db, 'line_confirm_expense', {
      p_line_user_id: lineUserId,
      p_command_id: payload.commandId,
      p_amount_minor: payload.amountMinor,
      p_item: payload.item,
      p_category: payload.category,
      p_payment_method: payload.paymentMethod,
      p_account_id: payload.accountId ?? null,
      p_card_id: payload.cardId ?? null,
      p_expense_date: new Date().toISOString(),
    })
    await clearConversation(db, lineUserId)
    if (result.status === 'saved') {
      return [textMessage(
        result.duplicate
          ? '這筆支出先前已經儲存。'
          : '支出已儲存，網頁資料也已同步更新。',
        menuActions(),
      )]
    }
    return [textMessage('儲存失敗，資料沒有被寫入。請重新操作。')]
  }
  if (data === 'expense:cancel') {
    await clearConversation(db, lineUserId)
    return [textMessage('已取消這筆支出。', menuActions())]
  }
  return [textMessage('按鈕已失效，請重新選擇「快速支出」。')]
}

function categoryPicker(categories: Json[], page: number): LineMessage {
  const start = page * 10
  const visible = categories.slice(start, start + 10)
  const actions = visible.map((item) =>
    postback(
      String(item.name).slice(0, 20),
      `expense:category:${String(item.id)}`,
      String(item.name).slice(0, 20),
    )
  )
  if (page > 0) {
    actions.push(postback('上一頁', `expense:category-page:${page - 1}`))
  }
  if (start + 10 < categories.length) {
    actions.push(postback('下一頁', `expense:category-page:${page + 1}`))
  }
  return textMessage(`選擇分類（第 ${page + 1} 頁）：`, actions)
}

function expenseConfirmation(payload: Json): LineMessage {
  const amount = formatMoney(Number(payload.amountMinor))
  const payment = paymentMethods[String(payload.paymentMethod)] ?? '其他'
  return textMessage(
    `請確認支出：\n${payload.item}\n${amount}\n分類：${payload.category}\n付款：${payment}\n日期：今天`,
    [
      postback('確認儲存', 'expense:save', '確認儲存'),
      postback('取消', 'expense:cancel', '取消'),
    ],
  )
}

async function summaryMessages(
  db: SupabaseClient,
  lineUserId: string,
): Promise<LineMessage[]> {
  const result = await rpc(db, 'line_finance_summary', {
    p_line_user_id: lineUserId,
  })
  if (result.status === 'not_linked') return identityPrompt(db, lineUserId)
  return [textMessage(
    [
      '財務總覽',
      `帳戶餘額：${formatMoney(Number(result.accountBalanceMinor))}`,
      `本月支出：${formatMoney(Number(result.monthExpenseMinor))}`,
      `信用卡待繳：${formatMoney(Number(result.pendingCardMinor))}`,
      `待收款：${formatMoney(Number(result.receivablesMinor))}`,
    ].join('\n'),
    menuActions(),
  )]
}

async function receivableMessages(
  db: SupabaseClient,
  lineUserId: string,
): Promise<LineMessage[]> {
  const result = await rpc(db, 'line_list_receivables', {
    p_line_user_id: lineUserId,
    // A null limit asks the RPC for every outstanding receivable.  The LINE
    // reply is kept to one message so the platform's five-message reply cap
    // cannot silently hide the later entries.
    p_limit: null,
  })
  if (result.status === 'not_linked') return identityPrompt(db, lineUserId)
  const items = (result.items ?? []) as Json[]
  if (items.length === 0) {
    return [textMessage('目前沒有待收款項。', menuActions())]
  }
  const lines = items.map((item, index) =>
    `${index + 1}. ${item.orderName}｜${item.participantName}：${formatMoney(Number(item.amountMinor))}`
  )
  const actions = items.slice(0, 13).map((item, index) =>
    postback(
      `收第 ${index + 1} 筆`,
      `receive:confirm:${item.token}`,
      `確認 ${item.participantName} 已付款`,
    )
  )
  return [textMessage(
    [`待收款（共 ${items.length} 筆）`, ...lines].join('\n'),
    actions,
  )]
}

function helpMessage(): LineMessage {
  return textMessage(
    '快記帳可在一對一聊天室查詢財務總覽、快速記錄支出及處理待收款；輸入「捷徑設定」可開啟 Apple Pay／LINE Pay／TWPAY 自動記帳，「待確認」可處理尚未入帳的消費。複雜編輯與刪除請使用網頁。',
    menuActions(),
  )
}

function menuActions() {
  return [
    postback('財務總覽', 'menu:summary'),
    postback('快速支出', 'expense:start'),
    postback('待收款', 'receivables:list'),
    websiteAction(),
  ]
}

function websiteAction(): LineAction {
  return appLoginUrl
    ? { type: 'uri', label: '開啟網站', uri: appLoginUrl }
    : postback('開啟網站', 'web:disabled')
}

async function getConversation(
  db: SupabaseClient,
  lineUserId: string,
): Promise<Conversation | null> {
  const { data, error } = await db.from('line_conversations')
    .select('flow,step,payload,expires_at')
    .eq('line_user_id', lineUserId)
    .maybeSingle()
  if (error) throw error
  if (!data) return null
  if (new Date(data.expires_at).getTime() <= Date.now()) {
    await clearConversation(db, lineUserId)
    return null
  }
  return data as Conversation
}

async function saveConversation(
  db: SupabaseClient,
  lineUserId: string,
  flow: string,
  step: string,
  payload: Json,
) {
  const expiresAt = new Date(Date.now() + 15 * 60 * 1000).toISOString()
  const { error } = await db.from('line_conversations').upsert({
    line_user_id: lineUserId,
    flow,
    step,
    payload,
    expires_at: expiresAt,
    updated_at: new Date().toISOString(),
  })
  if (error) throw error
}

async function clearConversation(db: SupabaseClient, lineUserId: string) {
  const { error } = await db.from('line_conversations')
    .delete().eq('line_user_id', lineUserId)
  if (error) throw error
}

async function rpc(
  db: SupabaseClient,
  name: string,
  parameters: Json,
): Promise<Json> {
  const { data, error } = await db.rpc(name, parameters)
  if (error) throw error
  return (data ?? {}) as Json
}

async function reply(replyToken: string, messages: LineMessage[]) {
  await replyLine(channelAccessToken, replyToken, messages)
}

function parseTwd(value: string): number | null {
  const normalized = value.replace(/[,$元\s]/g, '')
  if (!/^\d{1,10}(\.\d{1,2})?$/.test(normalized)) return null
  const major = Number(normalized)
  if (!Number.isFinite(major) || major <= 0) return null
  const minor = Math.round(major * 100)
  return minor <= 999999999999 ? minor : null
}

function formatMoney(minor: number): string {
  return `NT$${Math.round(minor / 100).toLocaleString('zh-TW')}`
}

function safeErrorCode(error: unknown): string {
  if (error && typeof error === 'object' && 'code' in error) {
    return String((error as { code: unknown }).code).slice(0, 80)
  }
  if (error instanceof Error) return error.message.split(':')[0].slice(0, 80)
  return 'unknown_error'
}

async function fallbackEventId(event: LineEvent): Promise<string> {
  const digest = new Uint8Array(
    await crypto.subtle.digest(
      'SHA-256',
      new TextEncoder().encode(JSON.stringify(event)),
    ),
  )
  return `legacy-${Array.from(digest, (byte) =>
    byte.toString(16).padStart(2, '0')
  ).join('')}`
}
