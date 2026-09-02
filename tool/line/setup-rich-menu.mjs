import { readFile, stat } from 'node:fs/promises'
import { resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

const token = process.env.LINE_CHANNEL_ACCESS_TOKEN
const appUrl = (process.env.APP_PUBLIC_URL ?? '').replace(/\/$/, '')
const appLoginUrl = appUrl
  ? `${appUrl}/login?source=line_oa&next=%2Fdashboard`
  : ''
const validateOnly = process.argv.includes('--validate-only')
const imageArgument = process.argv.find((value) =>
  !value.startsWith('--') && value !== process.argv[0] && value !== process.argv[1]
)
const imagePath = resolve(
  imageArgument ??
    fileURLToPath(new URL('./assets/rich-menu.png', import.meta.url)),
)

const image = await readFile(imagePath)
const info = await stat(imagePath)
if (image.toString('ascii', 1, 4) !== 'PNG') {
  throw new Error('Rich Menu 圖片必須是 PNG')
}
const width = image.readUInt32BE(16)
const height = image.readUInt32BE(20)
if (width !== 2500 || height !== 1686) {
  throw new Error(`圖片尺寸必須是 2500x1686，目前是 ${width}x${height}`)
}
if (info.size > 1024 * 1024) {
  throw new Error(`圖片必須小於 1 MB，目前是 ${info.size} bytes`)
}
if (validateOnly) {
  console.log(`Rich Menu 圖片驗證通過：${width}x${height}, ${info.size} bytes`)
  if (appLoginUrl) console.log(`開啟快記帳：${appLoginUrl}`)
  process.exit(0)
}
if (!token) throw new Error('請先設定 LINE_CHANNEL_ACCESS_TOKEN')

const actions = [
  postback('menu:summary', '財務總覽'),
  postback('expense:start', '快速支出'),
  postback('receivables:list', '待收款'),
  appLoginUrl
    ? { type: 'uri', label: '開啟快記帳', uri: appLoginUrl }
    : postback('web:disabled', '開啟快記帳'),
]
const areas = actions.map((action, index) => ({
  bounds: {
    x: (index % 2) * 1250,
    y: index < 2 ? 0 : 843,
    width: 1250,
    height: 843,
  },
  action,
}))

const richMenu = await line('/richmenu', {
  method: 'POST',
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify({
    size: { width: 2500, height: 1686 },
    selected: true,
    name: '快記帳主選單',
    chatBarText: '開啟快記帳選單',
    areas,
  }),
})
const richMenuId = richMenu.richMenuId
try {
  await lineData(`/richmenu/${richMenuId}/content`, {
    method: 'POST',
    headers: { 'Content-Type': 'image/png' },
    body: image,
  })
  await line(`/user/all/richmenu/${richMenuId}`, { method: 'POST' })
  console.log(`Rich Menu 已設為預設：${richMenuId}`)
} catch (error) {
  await line(`/richmenu/${richMenuId}`, { method: 'DELETE' }).catch(() => {})
  throw error
}

function postback(data, label) {
  return { type: 'postback', data, label, displayText: label }
}

async function line(path, init) {
  return lineRequest('https://api.line.me/v2/bot', path, init)
}

async function lineData(path, init) {
  return lineRequest('https://api-data.line.me/v2/bot', path, init)
}

async function lineRequest(baseUrl, path, init) {
  const url = `${baseUrl}${path}`
  const response = await fetch(url, {
    ...init,
    headers: {
      Authorization: `Bearer ${token}`,
      ...(init.headers ?? {}),
    },
  })
  if (!response.ok) {
    throw new Error(
      `LINE API ${response.status} ${init.method ?? 'GET'} ${url}: ` +
      (await response.text()).slice(0, 500),
    )
  }
  const text = await response.text()
  return text ? JSON.parse(text) : {}
}
