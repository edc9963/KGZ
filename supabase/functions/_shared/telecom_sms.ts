// Parses the SMS a carrier sends right after a purchase charged to the phone
// bill, forwarded by an iOS Shortcuts「訊息」automation:
//
//   【遠傳Apple商店交易成功通知】您本次代收金額160元將隨最近一期帳單計算
//   (訂單編號MX5Y1J24XX)，完整交易紀錄, 請至 https://reportaproblem.apple.com ...
//
// The message carries no time, so the charge is dated when it arrives (the
// automation runs as the SMS comes in). It is the same charge the bill's
// 代收服務明細 lists a month later; capture_ingest pairs the two.
import { parseCaptureAmount } from './capture.ts'
import { telecomBillLabel, type TelecomBillOcrCapture } from './telecom_bill_ocr.ts'

const notice = /【\s*([^】]*?)\s*交易成功通知\s*】[^【]*?代收金額\s*([\d,]+)\s*元/g
const orderNumber = /訂單編號\s*[:：]?\s*([A-Za-z0-9]{6,40})/
const carrier = /^(?:遠傳電信|遠傳|中華電信|台灣大哥大|台哥大|亞太電信|台灣之星)\s*/

export function parseTelecomSms(text: string, now = new Date()): TelecomBillOcrCapture[] {
  const normalized = text.replace(/[！-～]/g, (char) =>
    String.fromCharCode(char.charCodeAt(0) - 0xFEE0)
  )
  const occurredAt = now.toISOString()
  const captures: TelecomBillOcrCapture[] = []
  for (const match of normalized.matchAll(notice)) {
    const parsed = parseCaptureAmount(`NT$${match[2]}`)
    if (!parsed) continue
    const service = match[1].replace(carrier, '').trim()
    const rest = normalized.slice(match.index! + match[0].length).split('【')[0]
    const order = rest.match(orderNumber)?.[1]
    captures.push({
      source: 'telecomBill',
      amountMinor: parsed.amountMinor,
      currency: parsed.currency,
      merchant: (service ? `${service}消費` : '').slice(0, 80),
      cardLabel: telecomBillLabel,
      occurredAt,
      // A re-run automation sends the same order number again.
      externalRef: order
        ? `telecom-sms:${order.toUpperCase()}`
        : `telecom-sms:${occurredAt.slice(0, 16)}:${parsed.amountMinor}:${captures.length}`,
    })
  }
  return captures
}
