// Parses a bank's credit-card transaction notice email and keeps only LINE
// Pay charges. Used by card-email-ingest; the Gmail Apps Script only
// forwards subject / sender / plain body, so formats can be fixed here
// without touching the user's script.
//
// Banks differ, so the parser looks for common labelled fields in either
// layout:
//   消費金額：NT$1,234          (label and value on one line)
//   消費金額\nNT$1,234          (HTML table flattened by getPlainBody)
// and falls back to sentences such as
//   您於10/27 09:31在連加*全家便利商店刷卡消費新台幣85元
import { parseCaptureAmount } from './capture.ts'

export type CardEmail = {
  from?: unknown
  subject?: unknown
  body?: unknown
  receivedAt?: unknown
}

export type CardEmailCapture = {
  amountMinor: number
  currency: string
  merchant: string
  cardLabel: string
  occurredAt: string
}

export type CardEmailResult =
  | { kind: 'linePay'; capture: CardEmailCapture }
  | { kind: 'ignored'; reason: 'not_line_pay' | 'refund' | 'no_amount' }

const linePayMarker = /連加|LINE\s*PAY/i
// "連加*全家" / "LINE PAY*全家" / "LINEPAY-全家": the descriptor banks print
// for LINE Pay charges. Ads and footers mention LINE Pay without the
// separator, so this is what counts as evidence in the body.
const linePayDescriptor = /(?:連加|LINE\s*PAY)\s*[*＊\-－_]\s*[^\s，,。；;]*/i
const refundWords = /退款|退貨|退刷|沖正|撤銷|取消交易|交易取消|refund/i

const amountLabels = ['消費金額', '交易金額', '刷卡金額', '授權金額', '金額']
const merchantLabels = [
  '消費商店', '商店名稱', '特店名稱', '消費特店', '交易商店', '消費地點',
  '交易說明', '消費說明', '商店', '特店',
]
const cardLabels = ['卡號末四碼', '末四碼', '卡片末四碼', '卡號', '卡片號碼', '消費卡號']
const dateLabels = ['消費日期', '交易日期', '授權日期']
const clockLabels = ['消費時間', '交易時間', '授權時間', '刷卡時間']
const typeLabels = ['交易類別', '交易類型', '交易種類']

// Sender domain → bank name, so the card label reads like the bank and
// capture_match_card can fall back to a bank-name match.
const bankDomains: [RegExp, string][] = [
  [/cathaybk|cathay/i, '國泰世華'],
  [/ctbc/i, '中國信託'],
  [/taishin/i, '台新'],
  [/esun/i, '玉山'],
  [/fubon/i, '台北富邦'],
  [/sinopac/i, '永豐'],
  [/megabank|megaicbc/i, '兆豐'],
  [/firstbank/i, '第一銀行'],
  [/hncb/i, '華南'],
  [/tcb-bank|tcbbank/i, '合作金庫'],
  [/landbank/i, '土地銀行'],
  [/scsb/i, '上海商銀'],
  [/ubot/i, '聯邦'],
  [/dbs/i, '星展'],
  [/hsbc/i, '滙豐'],
  [/citi/i, '花旗'],
  [/feib|fareast/i, '遠東商銀'],
  [/kgibank|kgi/i, '凱基'],
  [/skbank/i, '新光'],
  [/yuanta/i, '元大'],
]

export function parseCardEmail(email: CardEmail, now = new Date()): CardEmailResult {
  const subject = normalize(text(email.subject))
  const body = normalize(htmlToText(text(email.body)))
  const lines = body.split('\n').map((line) => line.trim()).filter(Boolean)

  const merchantField = field(lines, merchantLabels)
  const descriptor = `${subject}\n${body}`.match(linePayDescriptor)?.[0] ?? ''
  const isLinePay = linePayMarker.test(merchantField) || linePayMarker.test(subject) ||
    descriptor !== ''
  if (!isLinePay) return { kind: 'ignored', reason: 'not_line_pay' }

  if (refundWords.test(subject) || refundWords.test(field(lines, typeLabels))) {
    return { kind: 'ignored', reason: 'refund' }
  }

  const amount = parseCaptureAmount(field(lines, amountLabels)) ??
    parseCaptureAmount(sentenceAmount(`${subject}\n${body}`))
  if (!amount) return { kind: 'ignored', reason: 'no_amount' }

  const receivedAt = validDate(text(email.receivedAt)) ?? now
  return {
    kind: 'linePay',
    capture: {
      amountMinor: amount.amountMinor,
      currency: amount.currency,
      merchant: cleanMerchant(linePayMarker.test(merchantField) ? merchantField : descriptor) ||
        cleanMerchant(merchantField),
      cardLabel: cardLabel(text(email.from), field(lines, cardLabels) || body),
      occurredAt: occurredAt(timeText(lines) || body, receivedAt),
    },
  }
}

function text(value: unknown): string {
  return typeof value === 'string' ? value : ''
}

const fullWidth = /[０-９：＊／－（），．　]/g

function normalize(value: string): string {
  return value
    .replace(fullWidth, (char) =>
      char === '　' ? ' ' : String.fromCharCode(char.charCodeAt(0) - 0xFEE0))
    .replace(/ /g, ' ')
    .replace(/\r\n?/g, '\n')
    .replace(/[ \t]+/g, ' ')
}

function htmlToText(value: string): string {
  if (!/<[a-z][\s\S]*>/i.test(value)) return value
  return value
    .replace(/<(script|style)[\s\S]*?<\/\1>/gi, '')
    .replace(/<br\s*\/?>|<\/(p|div|tr|li|h\d)>/gi, '\n')
    .replace(/<\/t[dh]>/gi, '\n')
    .replace(/<[^>]+>/g, '')
    .replace(/&nbsp;/g, ' ')
    .replace(/&amp;/g, '&')
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>')
    .replace(/&#(\d+);/g, (_, code) => String.fromCharCode(Number(code)))
}

// "標籤：值" on one line, or a bare "標籤" line followed by the value line.
// Labels are tried in order, so the specific ones win over「金額」/「商店」.
function field(lines: string[], labels: string[]): string {
  for (const label of labels) {
    for (let index = 0; index < lines.length; index++) {
      const line = lines[index].replace(/^[\s•●◆■□▪\-*·]+/, '')
      if (!line.startsWith(label)) continue
      const rest = line.substring(label.length)
      const inline = rest.match(/^\s*(?:\([^)]*\))?\s*[:=]\s*(.+)$/)
      if (inline) return inline[1].trim()
      if (/^\s*(?:\([^)]*\))?\s*:?\s*$/.test(rest) && index + 1 < lines.length) {
        return lines[index + 1].trim()
      }
    }
  }
  return ''
}

// Some banks print「消費時間：2026/10/27 09:31」, others split the date and
// the clock into two fields.
function timeText(lines: string[]): string {
  const clock = field(lines, clockLabels)
  if (/\d[/\-.年月]\d/.test(clock)) return clock
  return [field(lines, dateLabels), clock].filter(Boolean).join(' ')
}

function sentenceAmount(value: string): string {
  const match = value.match(
    /(?:新(?:台|臺)幣|NT\$|NTD|TWD)\s*([\d,]+(?:\.\d+)?)|([\d,]+(?:\.\d+)?)\s*元/i,
  )
  return match ? (match[1] ?? match[2]) : ''
}

function cleanMerchant(value: string): string {
  return value
    .replace(/^(?:連加|LINE\s*PAY)\s*[*\-_:]?\s*/i, '')
    .replace(/[，,。；;].*$/, '')
    .replace(/(?:刷卡消費|消費新|新(?:台|臺)幣|NT\$|之?消費金額).*$/i, '')
    .trim()
    .slice(0, 80)
}

function cardLabel(from: string, cardText: string): string {
  const lastFour = cardText.match(/(?:末四碼|末4碼)\s*:?\s*(\d{4})(?!\d)|[*xX]{2,}[\s\-]*(\d{4})(?!\d)/)
    ?.slice(1).find(Boolean) ??
    cardText.match(/^\D*(\d{4})\D*$/)?.[1] ??
    ''
  const bank = bankDomains.find(([pattern]) => pattern.test(from))?.[1] ?? ''
  return [bank, lastFour ? `*${lastFour}` : ''].filter(Boolean).join(' ')
}

const taipeiOffset = '+08:00'

// Bank times are Taiwan local; years may be Gregorian, ROC (115/10/27) or
// missing (10/27 09:31). Date-only notices use the email's arrival time when
// it is the same day.
function occurredAt(value: string, receivedAt: Date): string {
  // A bare "1.5" (e.g. 回饋1.5%) is not a date, so '.' needs a year.
  const match = value.match(
    /(\d{2,4})[/\-.年](\d{1,2})[/\-.月](\d{1,2})日?(?:\s*(\d{1,2}):(\d{2})(?::(\d{2}))?)?/,
  ) ?? value.match(/()(\d{1,2})[/月](\d{1,2})日?(?:\s*(\d{1,2}):(\d{2})(?::(\d{2}))?)?/)
  if (!match) return receivedAt.toISOString()
  const receivedLocal = taipeiParts(receivedAt)
  let year = match[1] ? Number(match[1]) : receivedLocal.year
  if (year < 100) year += 2000
  else if (year < 1911) year += 1911 // 民國
  const month = Number(match[2])
  const day = Number(match[3])
  if (month < 1 || month > 12 || day < 1 || day > 31) return receivedAt.toISOString()
  if (!match[1] && (month > receivedLocal.month ||
    (month === receivedLocal.month && day > receivedLocal.day))) {
    year -= 1 // a December charge noticed in January
  }

  if (match[4] === undefined) {
    if (year === receivedLocal.year && month === receivedLocal.month &&
      day === receivedLocal.day) {
      return receivedAt.toISOString()
    }
    return toIso(year, month, day, 12, 0, 0) ?? receivedAt.toISOString()
  }
  return toIso(year, month, day, Number(match[4]), Number(match[5]), Number(match[6] ?? 0)) ??
    receivedAt.toISOString()
}

function toIso(
  year: number,
  month: number,
  day: number,
  hour: number,
  minute: number,
  second: number,
): string | null {
  if (hour > 23 || minute > 59 || second > 59) return null
  const pad = (number: number) => String(number).padStart(2, '0')
  const parsed = new Date(
    `${year}-${pad(month)}-${pad(day)}T${pad(hour)}:${pad(minute)}:${pad(second)}${taipeiOffset}`,
  )
  return Number.isNaN(parsed.getTime()) ? null : parsed.toISOString()
}

function taipeiParts(date: Date): { year: number; month: number; day: number } {
  const local = new Date(date.getTime() + 8 * 60 * 60 * 1000)
  return {
    year: local.getUTCFullYear(),
    month: local.getUTCMonth() + 1,
    day: local.getUTCDate(),
  }
}

function validDate(value: string): Date | null {
  if (!value) return null
  const parsed = new Date(value)
  return Number.isNaN(parsed.getTime()) ? null : parsed
}
