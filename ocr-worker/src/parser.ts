export type OcrDraftItem = {
  name: string
  amountMinor: number
}

export type OcrDraft = {
  merchant: string
  orderDate: string | null
  totalMinor: number | null
  deliveryFeeMinor: number
  serviceFeeMinor: number
  discountMinor: number
  paymentLastFour: string | null
  items: OcrDraftItem[]
  warnings: string[]
  rawText: string
}

const moneyPattern = /(?:NT\$|\$)?\s*(-?\d{1,6}(?:,\d{3})*(?:\.\d{1,2})?)\s*$/

export function parseUberEatsText(pages: string[]): OcrDraft {
  const rawText = pages.join('\n')
  const lines = rawText
    .split(/\r?\n/)
    .map(normalize)
    .filter(Boolean)
  let totalMinor: number | null = null
  let deliveryFeeMinor = 0
  let serviceFeeMinor = 0
  let discountMinor = 0
  let paymentLastFour: string | null = null
  let orderDate: string | null = null
  let merchant = ''
  const items: OcrDraftItem[] = []

  for (const line of lines) {
    const amount = trailingMoney(line)
    const compact = line.replace(/\s/g, '')
    if (amount !== null && /(?:總計|合計|訂單總額)/.test(compact) &&
        !/(?:小計|商品總計)/.test(compact)) {
      totalMinor = Math.abs(amount)
      continue
    }
    if (amount !== null && /(?:外送費|運費)/.test(compact)) {
      deliveryFeeMinor += amount
      continue
    }
    if (amount !== null && /服務費/.test(compact)) {
      serviceFeeMinor += amount
      continue
    }
    if (amount !== null && /(?:優惠|折扣|抵用|會員獎勵)/.test(compact)) {
      discountMinor += Math.abs(amount)
      continue
    }
    const card = compact.match(/(?:末四碼|尾號|[·•*xX]{2,})?(\d{4})$/)
    if (card && /(?:Visa|Master|JCB|信用卡|卡片)/i.test(compact)) {
      paymentLastFour = card[1]
    }
    const date = parseDate(line)
    if (date) orderDate = date
  }

  for (const line of lines) {
    const amount = trailingMoney(line)
    if (amount === null || isSummaryLine(line) || isMetadataLine(line)) continue
    const name = line.replace(moneyPattern, '').replace(/^\d+\s*[xX×個份]?\s*/, '').trim()
    if (name && !/^(?:NT\$|\$|\d+)$/.test(name)) {
      items.push({ name: name.slice(0, 80), amountMinor: Math.abs(amount) })
    }
  }

  const firstCandidate = lines.find((line) =>
    !isSummaryLine(line) && trailingMoney(line) === null &&
    line.length >= 2 && line.length <= 60 &&
    !/(?:Uber|Eats|訂單|收據|謝謝)/i.test(line)
  )
  merchant = firstCandidate ?? 'Uber Eats'
  const warnings: string[] = []
  if (items.length === 0) warnings.push('未辨識到品項')
  if (totalMinor === null) warnings.push('未辨識到訂單總額')
  if (totalMinor !== null && items.length > 0) {
    const computed = items.reduce((sum, item) => sum + item.amountMinor, 0) +
      deliveryFeeMinor + serviceFeeMinor - discountMinor
    if (Math.abs(computed - totalMinor) > 100) warnings.push('品項加總與總額不一致')
  }
  return {
    merchant,
    orderDate,
    totalMinor,
    deliveryFeeMinor,
    serviceFeeMinor,
    discountMinor,
    paymentLastFour,
    items,
    warnings,
    rawText,
  }
}

function normalize(value: string): string {
  return value.replace(/[|｜]/g, ' ').replace(/\s+/g, ' ').trim()
}

function trailingMoney(line: string): number | null {
  const match = line.match(moneyPattern)
  if (!match) return null
  const value = Number(match[1].replace(/,/g, ''))
  return Number.isFinite(value) ? Math.round(value * 100) : null
}

function isSummaryLine(line: string): boolean {
  return /(?:總計|合計|小計|商品總計|外送費|運費|服務費|優惠|折扣|抵用|會員獎勵|稅額)/.test(
    line.replace(/\s/g, ''),
  )
}

function isMetadataLine(line: string): boolean {
  return /(?:Visa|Master|JCB|信用卡|卡片|末四碼|尾號)/i.test(line) ||
    /20\d{2}[\/.-]\d{1,2}[\/.-]\d{1,2}/.test(line)
}

function parseDate(line: string): string | null {
  const match = line.match(/(20\d{2})[\/.-](\d{1,2})[\/.-](\d{1,2})/)
  if (!match) return null
  const date = new Date(Date.UTC(Number(match[1]), Number(match[2]) - 1, Number(match[3])))
  return Number.isNaN(date.getTime()) ? null : date.toISOString()
}
