import { createClient, SupabaseClient } from 'npm:@supabase/supabase-js@2'
import type { LineAction, LineMessage } from '../_shared/line.ts'
import {
  postback,
  replyLine,
  textMessage,
  verifyLineSignature,
} from '../_shared/line.ts'

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
  return [helpMessage()]
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
      Object.entries(paymentMethods).map(([key, label]) =>
        postback(label, `expense:payment:${key}`, label)
      ),
    )]
  }

  if (data.startsWith('expense:payment:') && conversation.step === 'payment') {
    const method = data.substring('expense:payment:'.length)
    if (!paymentMethods[method]) return [textMessage('付款方式無效。')]
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
    '快記帳可在一對一聊天室查詢財務總覽、快速記錄支出及處理待收款。複雜編輯與刪除請使用網頁。',
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
