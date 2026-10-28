// Parses the text iOS「從影像擷取文字」reads off a screenshot of the LINE Pay
// official account chat. Each payment there is a card like
//
//   付款                         LINE Pay money
//   NT$ 692
//   付款完成。
//   2026.10.24 20:30 (GMT+0800)
//   商店名稱                     麥當勞
//   瞭解更多
//                                        晚上8:30
//
// "LINE Pay" alone means the bound credit card paid, "LINE Pay money" the
// LINE Pay Money wallet. One screenshot usually holds several cards, and OCR
// may put a label and its value on one line or on separate lines, or wrap a
// long store name. Text in the right column (the logo, sometimes the store
// name) is often read after the left column, e.g.
//
//   付款 / NT$ 530 / 付款完成。/ 2026.10.25 19:11 (GMT+0800) / 商店名稱 /
//   LINE Pay money / 京站時尚廣場Q / square / 瞭解更多 / 晚上7:11
//
// so the text is first cut into cards at 瞭解更多 and the chat bubble time,
// and everything inside one cut counts for that card.
import { parseCaptureAmount } from './capture.ts'

export type LinePayOcrSource = 'linePay' | 'linePayMoney'

export type LinePayOcrCapture = {
  source: LinePayOcrSource
  amountMinor: number
  currency: string
  merchant: string
  cardLabel: string
  occurredAt: string
  // Same payment in two overlapping screenshots → same ref.
  externalRef: string
}

const amountLine = /NT\s*[$S＄]\s*([\d,]+(?:\.\d+)?)/i
const bareCurrency = /^NT\s*[$S＄]$/i
// OCR sometimes drops the space between the day and the hour:
// "2026.10.2517:57".
const timestamp =
  /(\d{4})\s*[.\/-]\s*(\d{1,2})\s*[.\/-]\s*(\d{1,2})\s*(\d{1,2})\s*[:：]\s*(\d{2})(?:\s*[（(]?\s*GMT\s*([+-])\s*(\d{2})\s*:?\s*(\d{2}))?/i
const merchantLabel = /^商店名稱\s*[:：]?\s*/
const bubbleTime = /^(上午|下午|晚上|早上|中午|凌晨|清晨|午夜)\s*\d{1,2}\s*[:：]\s*\d{2}$/
const cardEnd = [/瞭解更多|了解更多/, bubbleTime]
// The logo, possibly split over lines: "LINE" / "Pay money".
const logoLine = /^(LINE|Pay|money|LINE\s*Pay|Pay\s*money|LINE\s*Pay\s*money)$/i
// Lines that end a store name: the card's other fields, date separators
// and the next card's header.
const stopLine = [
  /^付款完成/,
  /^付款$/,
  /^\d{1,2}\s*\/\s*\d{1,2}\s*[（(]\s*週.\s*[)）]$/,
  /^(今天|昨天)$/,
  /^(活動|優惠|優惠券|折扣|點數|品項|商品|付款方式|備註)/,
]
const refundLine = /退款|取消付款|付款取消|退貨/

function normalize(text: string): string[] {
  return text
    .replace(/[！-～]/g, (char) =>
      // Full-width ASCII from OCR, except the CJK punctuation used above.
      '（）：'.includes(char) ? char : String.fromCharCode(char.charCodeAt(0) - 0xFEE0)
    )
    .replace(/　/g, ' ')
    .split(/\r?\n/)
    .map((line) => line.replace(/\s+/g, ' ').trim())
    .filter(Boolean)
}

function isStop(line: string): boolean {
  return amountLine.test(line) || bareCurrency.test(line) || timestamp.test(line) ||
    stopLine.some((pattern) => pattern.test(line))
}

// "京站時尚廣場 Q" + "square" → "京站時尚廣場 Q square";
// "台灣中油條碼支付台" + "北處人工島" → no space between CJK.
function joinWrapped(parts: string[]): string {
  return parts.reduce((joined, part) =>
    !joined
      ? part
      : /[A-Za-z0-9]$/.test(joined) && /^[A-Za-z0-9]/.test(part)
      ? `${joined} ${part}`
      : `${joined}${part}`, '')
}

function occurredAt(match: RegExpMatchArray): string | null {
  const [, year, month, day, hour, minute, sign, offsetHour, offsetMinute] = match
  const offset = sign ? `${sign}${offsetHour}:${offsetMinute}` : '+08:00'
  const iso = `${year}-${month.padStart(2, '0')}-${day.padStart(2, '0')}T` +
    `${hour.padStart(2, '0')}:${minute}:00${offset}`
  const date = new Date(iso)
  return Number.isNaN(date.getTime()) ? null : date.toISOString()
}

function amountAt(lines: string[], index: number): string | null {
  const inline = lines[index].match(amountLine)?.[1]
  if (inline) return inline
  if (bareCurrency.test(lines[index]) && /^[\d,]+(?:\.\d+)?$/.test(lines[index + 1] ?? '')) {
    return lines[index + 1]
  }
  return null
}

function readCard(
  lines: string[],
  amountText: string,
  amountIndex: number,
): LinePayOcrCapture | null {
  if (lines.some((line) => refundLine.test(line))) return null
  let time: string | null = null
  const merchant: string[] = []
  // Text after the time that is not a field, in case OCR read the store
  // name apart from 商店名稱.
  const loose: string[] = []
  let collecting = false
  for (const line of lines.slice(amountIndex + 1)) {
    const match = line.match(timestamp)
    if (match && !time) {
      time = occurredAt(match)
      continue
    }
    if (merchantLabel.test(line)) {
      const rest = line.replace(merchantLabel, '')
      if (rest) merchant.push(rest)
      collecting = true
      continue
    }
    if (logoLine.test(line)) continue
    if (collecting && !isStop(line)) {
      merchant.push(line)
      continue
    }
    collecting = false
    if (time && !isStop(line)) loose.push(line)
  }
  if (!time) return null
  const amount = parseCaptureAmount(`NT$${amountText}`)
  if (!amount) return null
  const money = lines.some((line) => /money/i.test(line))
  return {
    source: money ? 'linePayMoney' : 'linePay',
    amountMinor: amount.amountMinor,
    currency: amount.currency,
    merchant: joinWrapped(merchant.length ? merchant : loose).slice(0, 80),
    cardLabel: money ? 'LINE Pay Money' : 'LINE Pay',
    occurredAt: time,
    externalRef: `ocr:${time.slice(0, 16)}:${amount.amountMinor}`,
  }
}

export function parseLinePayOcr(text: string): LinePayOcrCapture[] {
  const segments: string[][] = [[]]
  for (const line of normalize(text)) {
    if (cardEnd.some((pattern) => pattern.test(line))) segments.push([])
    else segments[segments.length - 1].push(line)
  }

  const captures: LinePayOcrCapture[] = []
  for (const segment of segments) {
    // A cut normally holds one card; one holding several means OCR missed
    // the 瞭解更多 between them, so each amount gets the lines up to the next.
    const amounts: [number, string][] = []
    for (let index = 0; index < segment.length; index++) {
      const amountText = amountAt(segment, index)
      if (amountText) amounts.push([index, amountText])
    }
    amounts.forEach(([index, amountText], position) => {
      const from = position === 0 ? 0 : amounts[position - 1][0] + 1
      const to = position + 1 < amounts.length ? amounts[position + 1][0] : segment.length
      const capture = readCard(segment.slice(from, to), amountText, index - from)
      if (capture) captures.push(capture)
    })
  }
  return captures
}
