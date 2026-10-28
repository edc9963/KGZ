// Parses the text iOS「從影像擷取文字」reads off a screenshot of a telecom
// bill's 代收服務明細 (purchases such as the App Store charged to the phone
// bill). Each row is
//
//   115/09/26  10:11:53  計次型  ◎Apple商店消費《訂單編號：MX5XZNBQQ0》
//                                https://reportaproblem.apple.com
//                                0800-095-988                330.00
//
// with a 民國 date. OCR may read the table row by row or column by column
// (all dates, then all times, ... then all amounts), so dates, times, items
// and amounts are each collected in reading order and paired by position.
// A table whose columns do not line up is refused rather than guessed.
import { parseCaptureAmount } from './capture.ts'

export type TelecomBillOcrCapture = {
  source: 'telecomBill'
  amountMinor: number
  currency: string
  merchant: string
  cardLabel: string
  occurredAt: string
  // Same charge in two overlapping screenshots → same ref. The order number
  // is not used: OCR easily confuses 0/O in it.
  externalRef: string
}

export const telecomBillLabel = '電信帳單'

const rocDate = /(?<!\d)(1\d{2})\s*\/\s*(\d{1,2})\s*\/\s*(\d{1,2})(?!\d)/g
const clock = /(?<![\d:])(\d{1,2})\s*[:：]\s*(\d{2})\s*[:：]\s*(\d{2})(?![\d:])/g
// "330.00", "1,234.00", "-115.00"; phone numbers have no decimals.
const amount = /(?<![\d.,])(-?\d{1,3}(?:,\d{3})*\.\d{2})(?![\d.])/g
const item = /◎?\s*([^◎《》]+?)\s*《/g
const totalLine = /小計|合計|總計|應繳/
const tableMarker = /代收服務明細|代收服務|計次型|月租型/

function normalize(text: string): string[] {
  return text
    .replace(/[！-～]/g, (char) =>
      '（）：'.includes(char) ? char : String.fromCharCode(char.charCodeAt(0) - 0xFEE0)
    )
    .replace(/　/g, ' ')
    .split(/\r?\n/)
    .map((line) => line.replace(/\s+/g, ' ').trim())
    .filter(Boolean)
}

function occurredAt(date: RegExpMatchArray, time: RegExpMatchArray): string | null {
  const [, rocYear, month, day] = date
  const [, hour, minute, second] = time
  const iso = `${Number(rocYear) + 1911}-${month.padStart(2, '0')}-${day.padStart(2, '0')}T` +
    `${hour.padStart(2, '0')}:${minute}:${second}+08:00`
  const value = new Date(iso)
  return Number.isNaN(value.getTime()) ? null : value.toISOString()
}

export function parseTelecomBillOcr(text: string): TelecomBillOcrCapture[] {
  const lines = normalize(text)
  if (!lines.some((line) => tableMarker.test(line))) return []

  const dates: RegExpMatchArray[] = []
  const times: RegExpMatchArray[] = []
  const items: string[] = []
  const amounts: string[] = []
  let afterTotal = false
  for (const line of lines) {
    // The subtotal ("0958***718 小計NT$ 3,980.00", or its amount on the
    // next line) is not a charge.
    const isTotal = totalLine.test(line)
    const skip = isTotal || (afterTotal && /^-?[\d,]+\.\d{2}$/.test(line))
    afterTotal = isTotal
    if (skip) continue
    dates.push(...line.matchAll(rocDate))
    times.push(...line.matchAll(clock))
    items.push(...[...line.matchAll(item)].map((match) => match[1].trim()))
    amounts.push(...[...line.matchAll(amount)].map((match) => match[1]))
  }
  // Read column by column, the subtotal may land on a line of its own.
  if (amounts.length === dates.length + 1) {
    const rows = amounts.slice(0, -1)
    const sum = rows.reduce((total, value) => total + Number(value.replace(/,/g, '')), 0)
    if (Math.abs(sum - Number(amounts[amounts.length - 1].replace(/,/g, ''))) < 0.005) {
      amounts.pop()
    }
  }
  if (dates.length === 0 || times.length !== dates.length || amounts.length !== dates.length) {
    return []
  }

  const captures: TelecomBillOcrCapture[] = []
  dates.forEach((date, index) => {
    // Refunds and adjustments are negative; they are not purchases.
    if (amounts[index].startsWith('-')) return
    const time = occurredAt(date, times[index])
    const parsed = parseCaptureAmount(`NT$${amounts[index]}`)
    if (!time || !parsed) return
    captures.push({
      source: 'telecomBill',
      amountMinor: parsed.amountMinor,
      currency: parsed.currency,
      merchant: (items.length === dates.length ? items[index] : '').slice(0, 80),
      cardLabel: telecomBillLabel,
      occurredAt: time,
      externalRef: `telecom:${time.slice(0, 19)}:${parsed.amountMinor}`,
    })
  })
  return captures
}
