import { createHmac, timingSafeEqual } from 'node:crypto'
import { createServer, IncomingMessage, ServerResponse } from 'node:http'
import { fileURLToPath } from 'node:url'
import sharp from 'sharp'
import { createWorker, OEM } from 'tesseract.js'
import { parseUberEatsText } from './parser.js'

type Job = {
  jobId: string
  timestamp: number
  nonce: string
  imageUrls: string[]
  callbackUrl: string
  callbackToken: string
}

const port = Number(process.env.PORT ?? 8080)
const secret = process.env.OCR_WORKER_HMAC_SECRET ?? ''
const maxBodyBytes = 64 * 1024
const maxImageBytes = 6 * 1024 * 1024
const languageDataPath = fileURLToPath(new URL('../lang-data', import.meta.url))

createServer(async (request, response) => {
  if (request.method === 'GET' && request.url === '/health') {
    return json(response, 200, { ok: true })
  }
  if (request.method !== 'POST' || request.url !== '/v1/jobs') {
    return json(response, 404, { error: 'not_found' })
  }
  if (!secret) return json(response, 503, { error: 'not_configured' })

  try {
    const raw = await readBody(request, maxBodyBytes)
    if (!verify(raw, request.headers['x-kgz-signature'], secret)) {
      return json(response, 401, { error: 'invalid_signature' })
    }
    const job = JSON.parse(raw.toString('utf8')) as Job
    validateJob(job)
    json(response, 202, { accepted: true, jobId: job.jobId })
    void processJob(job)
  } catch (error) {
    if (!response.headersSent) {
      json(response, 400, { error: errorCode(error) })
    }
  }
}).listen(port, () => console.log(`OCR worker listening on ${port}`))

async function processJob(job: Job) {
  try {
    const worker = await createWorker(['chi_tra', 'eng'], OEM.LSTM_ONLY, {
      langPath: languageDataPath,
      gzip: true,
    })
    const pages: string[] = []
    try {
      for (const url of job.imageUrls) {
        const source = await download(url)
        const prepared = await sharp(source)
          .rotate()
          .grayscale()
          .normalize()
          .sharpen()
          .jpeg({ quality: 92 })
          .toBuffer()
        const result = await worker.recognize(prepared)
        pages.push(result.data.text)
      }
    } finally {
      await worker.terminate()
    }
    await callback(job, {
      status: 'completed',
      draft: parseUberEatsText(pages),
    })
  } catch (error) {
    await callback(job, {
      status: 'failed',
      errorCode: errorCode(error),
    }).catch(() => {})
  }
}

async function download(value: string): Promise<Buffer> {
  const url = new URL(value)
  if (url.protocol !== 'https:') throw new Error('invalid_image_url')
  const response = await fetch(url, { redirect: 'error' })
  if (!response.ok) throw new Error(`image_download_${response.status}`)
  const declared = Number(response.headers.get('content-length') ?? 0)
  if (declared > maxImageBytes) throw new Error('image_too_large')
  const bytes = Buffer.from(await response.arrayBuffer())
  if (bytes.length === 0 || bytes.length > maxImageBytes) {
    throw new Error('image_too_large')
  }
  return bytes
}

async function callback(job: Job, result: Record<string, unknown>) {
  const url = new URL(job.callbackUrl)
  if (url.protocol !== 'https:') throw new Error('invalid_callback_url')
  const response = await fetch(url, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${job.callbackToken}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({ jobId: job.jobId, ...result }),
  })
  if (!response.ok) throw new Error(`callback_${response.status}`)
}

function validateJob(job: Job) {
  if (!job.jobId || !job.nonce || !job.callbackToken) throw new Error('invalid_job')
  if (Math.abs(Date.now() - job.timestamp) > 5 * 60 * 1000) {
    throw new Error('expired_job')
  }
  if (!Array.isArray(job.imageUrls) || job.imageUrls.length < 1 ||
      job.imageUrls.length > 6) {
    throw new Error('invalid_image_count')
  }
  new URL(job.callbackUrl)
}

function verify(raw: Buffer, supplied: string | string[] | undefined, key: string) {
  if (typeof supplied !== 'string') return false
  const expected = createHmac('sha256', key).update(raw).digest()
  let actual: Buffer
  try {
    actual = Buffer.from(supplied, 'base64')
  } catch {
    return false
  }
  return expected.length === actual.length && timingSafeEqual(expected, actual)
}

async function readBody(request: IncomingMessage, limit: number): Promise<Buffer> {
  const chunks: Buffer[] = []
  let size = 0
  for await (const chunk of request) {
    const bytes = Buffer.from(chunk)
    size += bytes.length
    if (size > limit) throw new Error('body_too_large')
    chunks.push(bytes)
  }
  return Buffer.concat(chunks)
}

function json(response: ServerResponse, status: number, value: unknown) {
  response.writeHead(status, {
    'Content-Type': 'application/json',
    'Cache-Control': 'no-store',
  })
  response.end(JSON.stringify(value))
}

function errorCode(error: unknown): string {
  return error instanceof Error ? error.message.split(':')[0].slice(0, 80) : 'unknown'
}
