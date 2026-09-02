const fs = require('node:fs')
const path = require('node:path')
const sharp = require('sharp')

const width = 2500
const height = 1686
const outputDir = path.join(__dirname, 'designs')

const palette = {
  primary: '#2387B8',
  primaryPale: '#E4F3FA',
  graphite: '#26343A',
  background: '#F4F6F7',
  surface: '#FFFFFF',
  text: '#1F2D33',
  muted: '#68777D',
  border: '#DCE3E6',
  income: '#2A9D8F',
  incomePale: '#E5F5F1',
  expense: '#D65A52',
  expensePale: '#FBEAE8',
  amber: '#B07A32',
  amberPale: '#F7F0E5',
}

const cards = [
  { key: 'summary', label: '財務總覽', col: 0, row: 0 },
  { key: 'expense', label: '快速支出', col: 1, row: 0 },
  { key: 'pending', label: '待收款', col: 0, row: 1 },
  { key: 'openApp', label: '開啟快記帳', col: 1, row: 1 },
]

const layout = {
  marginX: 64,
  marginY: 58,
  gapX: 34,
  gapY: 34,
  cardW: 1169,
  cardH: 768,
}

const f = (value) => Number(value.toFixed(1))

function cardPosition(card) {
  return {
    x: layout.marginX + card.col * (layout.cardW + layout.gapX),
    y: layout.marginY + card.row * (layout.cardH + layout.gapY),
  }
}

function icon(key, cx, cy, color, background = 'none') {
  const x = cx - 145
  const y = cy - 145
  const stroke = `stroke="${color}" stroke-width="18" stroke-linecap="round" stroke-linejoin="round" fill="none"`
  const backdrop = background === 'none'
    ? ''
    : `<rect x="${x}" y="${y}" width="290" height="290" rx="68" fill="${background}"/>`

  if (key === 'summary') {
    return `<g>${backdrop}
      <rect x="${x + 44}" y="${y + 51}" width="202" height="188" rx="24" ${stroke}/>
      <path d="M ${x + 44} ${y + 98} H ${x + 246}" ${stroke}/>
      <path d="M ${x + 77} ${y + 204} V ${y + 157}" ${stroke}/>
      <path d="M ${x + 125} ${y + 204} V ${y + 133}" ${stroke}/>
      <path d="M ${x + 173} ${y + 204} V ${y + 173}" ${stroke}/>
      <path d="M ${x + 215} ${y + 204} V ${y + 122}" ${stroke}/>
      <circle cx="${x + 78}" cy="${y + 75}" r="6" fill="${color}" stroke="none"/>
      <circle cx="${x + 100}" cy="${y + 75}" r="6" fill="${color}" stroke="none"/>
    </g>`
  }

  if (key === 'expense') {
    return `<g>${backdrop}
      <path d="M ${x + 72} ${y + 46} H ${x + 198} Q ${x + 222} ${y + 46} ${x + 222} ${y + 70} V ${y + 218} L ${x + 198} ${y + 200} L ${x + 174} ${y + 218} L ${x + 150} ${y + 200} L ${x + 126} ${y + 218} L ${x + 102} ${y + 200} L ${x + 78} ${y + 218} V ${y + 64}" ${stroke}/>
      <path d="M ${x + 106} ${y + 92} H ${x + 181}" ${stroke}/>
      <path d="M ${x + 106} ${y + 128} H ${x + 160}" ${stroke}/>
      <circle cx="${x + 212}" cy="${y + 201}" r="47" fill="${background === 'none' ? palette.surface : background}" stroke="${color}" stroke-width="16"/>
      <path d="M ${x + 212} ${y + 179} V ${y + 223} M ${x + 190} ${y + 201} H ${x + 234}" ${stroke}/>
    </g>`
  }

  if (key === 'pending') {
    return `<g>${backdrop}
      <rect x="${x + 63}" y="${y + 51}" width="135" height="188" rx="20" ${stroke}/>
      <path d="M ${x + 95} ${y + 95} H ${x + 165}" ${stroke}/>
      <path d="M ${x + 95} ${y + 132} H ${x + 148}" ${stroke}/>
      <circle cx="${x + 202}" cy="${y + 199}" r="56" fill="${background === 'none' ? palette.surface : background}" stroke="${color}" stroke-width="16"/>
      <path d="M ${x + 202} ${y + 166} V ${y + 200} L ${x + 225} ${y + 215}" ${stroke}/>
    </g>`
  }

  if (key === 'openApp') {
    return `<g>${backdrop}
      <rect x="${x + 50}" y="${y + 57}" width="190" height="176" rx="24" ${stroke}/>
      <path d="M ${x + 50} ${y + 101} H ${x + 240}" ${stroke}/>
      <circle cx="${x + 79}" cy="${y + 79}" r="6" fill="${color}" stroke="none"/>
      <circle cx="${x + 101}" cy="${y + 79}" r="6" fill="${color}" stroke="none"/>
      <path d="M ${x + 128} ${y + 192} L ${x + 207} ${y + 123} M ${x + 162} ${y + 121} H ${x + 209} V ${y + 168}" ${stroke}/>
    </g>`
  }

  return `<g>${backdrop}
    <circle cx="${x + 170}" cy="${y + 91}" r="39" ${stroke}/>
    <text x="${x + 170}" y="${y + 94}" text-anchor="middle" dominant-baseline="middle"
      font-family="Arial, sans-serif" font-size="49" font-weight="700" fill="${color}">$</text>
    <path d="M ${x + 47} ${y + 200} Q ${x + 81} ${y + 170} ${x + 116} ${y + 181} L ${x + 157} ${y + 195} H ${x + 215} Q ${x + 236} ${y + 195} ${x + 240} ${y + 211} Q ${x + 243} ${y + 229} ${x + 219} ${y + 232} H ${x + 135} Q ${x + 104} ${y + 232} ${x + 81} ${y + 215} L ${x + 47} ${y + 200}" ${stroke}/>
    <path d="M ${x + 120} ${y + 181} H ${x + 165} Q ${x + 181} ${y + 181} ${x + 181} ${y + 196}" ${stroke}/>
  </g>`
}

function textLabel(label, cx, y, color, size = 88) {
  return `<text x="${cx}" y="${y}" text-anchor="middle" dominant-baseline="middle"
    font-family="Noto Sans TC, Microsoft JhengHei, sans-serif" font-size="${size}" font-weight="700"
    letter-spacing="4" fill="${color}">${label}</text>`
}

function baseSvg(background, content, extraDefs = '') {
  return `<svg xmlns="http://www.w3.org/2000/svg" width="${width}" height="${height}" viewBox="0 0 ${width} ${height}">
    <defs>
      <filter id="shadow" x="-20%" y="-20%" width="140%" height="140%">
        <feDropShadow dx="0" dy="12" stdDeviation="18" flood-color="#26343A" flood-opacity="0.08"/>
      </filter>
      ${extraDefs}
    </defs>
    <rect width="${width}" height="${height}" fill="${background}"/>
    ${content}
  </svg>`
}

function productCardsSvg() {
  const accents = {
    summary: palette.primary,
    expense: palette.expense,
    pending: palette.income,
    openApp: palette.amber,
  }
  const pales = {
    summary: palette.primaryPale,
    expense: palette.expensePale,
    pending: palette.incomePale,
    openApp: palette.amberPale,
  }
  const content = cards.map((card) => {
    const { x, y } = cardPosition(card)
    const cx = x + layout.cardW / 2
    return `<g filter="url(#shadow)">
      <rect x="${x}" y="${y}" width="${layout.cardW}" height="${layout.cardH}" rx="30" fill="${palette.surface}" stroke="${palette.border}" stroke-width="3"/>
      <rect x="${x}" y="${y}" width="${layout.cardW}" height="12" rx="6" fill="${accents[card.key]}"/>
    </g>
    ${icon(card.key, cx, y + 298, accents[card.key], pales[card.key])}
    ${textLabel(card.label, cx, y + 604, palette.text, 86)}`
  }).join('\n')
  return baseSvg(palette.background, content)
}

function graphiteSvg() {
  const content = cards.map((card) => {
    const { x, y } = cardPosition(card)
    const cx = x + layout.cardW / 2
    const highlighted = card.key === 'expense'
    const fill = highlighted ? palette.primary : '#2E3D43'
    const border = highlighted ? '#48A7D4' : '#526168'
    const ink = '#FFFFFF'
    const iconBackdrop = highlighted ? '#1876A3' : '#34474E'
    return `<g>
      <rect x="${x}" y="${y}" width="${layout.cardW}" height="${layout.cardH}" rx="30" fill="${fill}" stroke="${border}" stroke-width="3"/>
      <rect x="${x + 34}" y="${y + 34}" width="8" height="82" rx="4" fill="${highlighted ? '#FFFFFF' : palette.primary}"/>
    </g>
    ${icon(card.key, cx, y + 298, ink, iconBackdrop)}
    ${textLabel(card.label, cx, y + 604, ink, 86)}`
  }).join('\n')
  return baseSvg(palette.graphite, content)
}

function categoryTilesSvg() {
  const styles = {
    summary: { fill: palette.primaryPale, accent: palette.primary },
    expense: { fill: palette.expensePale, accent: palette.expense },
    pending: { fill: palette.incomePale, accent: palette.income },
    openApp: { fill: palette.primaryPale, accent: palette.primary },
  }
  const content = cards.map((card) => {
    const { x, y } = cardPosition(card)
    const cx = x + layout.cardW / 2
    const style = styles[card.key]
    return `<g>
      <rect x="${x}" y="${y}" width="${layout.cardW}" height="${layout.cardH}" rx="36" fill="${style.fill}"/>
      <circle cx="${x + 74}" cy="${y + 74}" r="12" fill="${style.accent}"/>
      <path d="M ${x + 101} ${y + 74} H ${x + 181}" stroke="${style.accent}" stroke-width="8" stroke-linecap="round" opacity="0.45"/>
    </g>
    ${icon(card.key, cx, y + 298, style.accent, '#FFFFFF')}
    ${textLabel(card.label, cx, y + 604, palette.text, 86)}`
  }).join('\n')
  return baseSvg(palette.background, content)
}

const variants = [
  ['rich-menu-four-a-product-cards.png', productCardsSvg()],
  ['rich-menu-four-b-graphite.png', graphiteSvg()],
  ['rich-menu-four-c-category-tiles.png', categoryTilesSvg()],
]

async function main() {
  await fs.promises.mkdir(outputDir, { recursive: true })
  for (const [filename, svg] of variants) {
    const destination = path.join(outputDir, filename)
    await sharp(Buffer.from(svg))
      .png({ compressionLevel: 9, adaptiveFiltering: true, palette: true, quality: 100 })
      .toFile(destination)
    const stats = await fs.promises.stat(destination)
    console.log(`${filename}: ${stats.size} bytes`)
  }
}

main().catch((error) => {
  console.error(error)
  process.exitCode = 1
})
