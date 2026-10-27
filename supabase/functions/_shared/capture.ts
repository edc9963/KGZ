// Shared by apple-pay-ingest (push after an Apple Pay tap) and line-webhook
// (re-opening a pending capture, card picker). Postback formats:
//   capture:cat:<inboxId>:<categoryId>
//   capture:card:<inboxId>:<cardId | __none__>
//   capture:skip:<inboxId>
//   capture:open:<inboxId>
import type { LineAction, LineMessage } from './line.ts'
import { postback, textMessage } from './line.ts'

type Json = Record<string, unknown>

export const NO_CARD = '__none__'

export type ParsedAmount = { amountMinor: number; currency: string }

const fullWidthDigits = /[０-９．，]/g

// Shortcuts hands over the Wallet amount as localized text, e.g.
// "NT$85.00", "$1,234", "85 元", "US$12.34", or a bare number.
export function parseCaptureAmount(value: unknown): ParsedAmount | null {
  if (typeof value === 'number') {
    return toParsed(value, 'TWD')
  }
  if (typeof value !== 'string') return null
  const text = value.trim().replace(fullWidthDigits, (char) =>
    char === '．' ? '.' : char === '，' ? ',' : String(char.charCodeAt(0) - 0xFF10)
  )
  if (!text || text.length > 40) return null
  if (/^-|\(\s*[\d$]|−/.test(text)) return null // refunds are not purchases
  const currency = detectCurrency(text)
  const match = text.replace(/,/g, '').match(/\d+(?:\.\d+)?/)
  if (!match) return null
  return toParsed(Number(match[0]), currency)
}

function detectCurrency(text: string): string {
  const upper = text.toUpperCase()
  if (/US\$|USD/.test(upper)) return 'USD'
  if (/JP¥|JPY|円/.test(upper)) return 'JPY'
  if (/HK\$|HKD/.test(upper)) return 'HKD'
  if (/€|EUR/.test(upper)) return 'EUR'
  if (/£|GBP/.test(upper)) return 'GBP'
  if (/KRW|₩/.test(upper)) return 'KRW'
  if (/CN¥|CNY|RMB/.test(upper)) return 'CNY'
  if (/[¥￥]/.test(upper) && !/NT/.test(upper)) return 'JPY'
  const code = upper.match(/\b([A-Z]{3})\b/)
  if (code && code[1] !== 'TWD' && code[1] !== 'NTD') return code[1]
  return 'TWD'
}

function toParsed(major: number, currency: string): ParsedAmount | null {
  if (!Number.isFinite(major) || major <= 0) return null
  const amountMinor = Math.round(major * 100)
  if (amountMinor <= 0 || amountMinor > 999999999999) return null
  return { amountMinor, currency }
}

export function generateCaptureToken(): string {
  const bytes = crypto.getRandomValues(new Uint8Array(24))
  const encoded = btoa(String.fromCharCode(...bytes))
    .replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '')
  return `kgz_${encoded}`
}

export async function sha256Hex(value: string): Promise<string> {
  const digest = new Uint8Array(
    await crypto.subtle.digest('SHA-256', new TextEncoder().encode(value)),
  )
  return Array.from(digest, (byte) => byte.toString(16).padStart(2, '0')).join('')
}

export function formatCaptureMoney(minor: number, currency = 'TWD'): string {
  if (currency === 'TWD') {
    return `NT$${(minor / 100).toLocaleString('zh-TW', {
      maximumFractionDigits: 2,
    })}`
  }
  return `${currency} ${(minor / 100).toLocaleString('en-US', {
    maximumFractionDigits: 2,
  })}`
}

export function formatTaipeiTime(value: string): string {
  const parts = new Intl.DateTimeFormat('zh-TW', {
    timeZone: 'Asia/Taipei',
    month: 'numeric',
    day: 'numeric',
    hour: '2-digit',
    minute: '2-digit',
    hour12: false,
  }).formatToParts(new Date(value))
  const get = (type: string) => parts.find((part) => part.type === type)?.value ?? ''
  return `${get('month')}/${get('day')} ${get('hour')}:${get('minute')}`
}

export function captureSourceName(source: unknown): string {
  return source === 'linePay' ? 'LINE Pay' : 'Apple Pay'
}

// The pending-capture message: details plus one-tap category buttons.
export function captureMessage(capture: Json): LineMessage {
  const id = String(capture.inboxId)
  const currency = String(capture.currency ?? 'TWD')
  const merchant = String(capture.merchant ?? '') || '（未提供商家）'
  const amount = formatCaptureMoney(Number(capture.amountMinor), currency)
  const lines = [`${captureSourceName(capture.source)} 消費待確認`, `${merchant}　${amount}`]
  lines.push(`時間：${formatTaipeiTime(String(capture.occurredAt))}`)

  const cardLabel = String(capture.cardLabel ?? '')
  if (capture.cardResolution === 'card' && capture.cardName) {
    const lastFour = capture.cardLastFour ? ` ${capture.cardLastFour}` : ''
    lines.push(`卡片：${capture.cardName}${lastFour}`)
  } else if (capture.cardResolution === 'none') {
    lines.push('卡片：不指定')
  } else {
    lines.push(`卡片：${cardLabel || '未知'}（選完分類後會請你對應卡片）`)
  }

  if (currency !== 'TWD') {
    lines.push('', '這是外幣消費，LINE 無法直接入帳，請到網頁記錄。')
    return textMessage(lines.join('\n'), [
      postback('略過', `capture:skip:${id}`, '略過這筆'),
    ])
  }

  const categories = (capture.categories ?? []) as Json[]
  const suggestedId = capture.suggestedCategoryId
    ? String(capture.suggestedCategoryId)
    : null
  const suggested = categories.find((item) => String(item.id) === suggestedId)
  const ordered = suggested
    ? [suggested, ...categories.filter((item) => item !== suggested)]
    : categories
  const actions: LineAction[] = ordered.slice(0, 12).map((item) => {
    const name = String(item.name)
    return postback(
      (item === suggested ? `✓ ${name}` : name).slice(0, 20),
      `capture:cat:${id}:${String(item.id)}`,
      `${name}`,
    )
  })
  actions.push(postback('略過', `capture:skip:${id}`, '略過這筆'))
  lines.push('', suggested ? `上次記成「${suggested.name}」，點分類即入帳：` : '點分類即入帳：')
  return textMessage(lines.join('\n'), actions)
}

export function cardPickerMessage(
  inboxId: string,
  cardLabel: string,
  cards: Json[],
  source: unknown = 'applePay',
): LineMessage {
  const actions = cards.slice(0, 12).map((card) =>
    postback(
      `${String(card.name).slice(0, 14)} ${String(card.lastFour ?? '')}`.trim().slice(0, 20),
      `capture:card:${inboxId}:${String(card.id)}`,
      `${card.name}`,
    )
  )
  actions.push(postback('不指定卡片', `capture:card:${inboxId}:${NO_CARD}`, '不指定卡片'))
  const label = source === 'linePay'
    ? cardLabel ? `刷卡通知的「${cardLabel}」` : '這筆 LINE Pay 扣款的卡片'
    : cardLabel ? `Wallet 的「${cardLabel}」` : '這張 Wallet 卡片'
  return textMessage(`${label}對應快記帳的哪張卡？之後會自動記住。`, actions)
}

// "capture:cat:<uuid>:<rest>" → { id, rest }
export function splitCapturePostback(
  data: string,
  prefix: string,
): { id: string; rest: string } | null {
  if (!data.startsWith(prefix)) return null
  const tail = data.substring(prefix.length)
  const id = tail.slice(0, 36)
  if (!/^[0-9a-f-]{36}$/i.test(id)) return null
  const rest = tail.length > 36 ? tail.slice(37) : ''
  if (tail.length > 36 && tail[36] !== ':') return null
  return { id, rest }
}
