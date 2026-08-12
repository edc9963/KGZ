export type LineAction = {
  type: 'postback' | 'message' | 'uri'
  label: string
  data?: string
  text?: string
  uri?: string
  displayText?: string
}

export type LineMessage = Record<string, unknown>

const LINE_API = 'https://api.line.me/v2/bot'

export function textMessage(
  text: string,
  actions: LineAction[] = [],
): LineMessage {
  const message: LineMessage = { type: 'text', text }
  if (actions.length > 0) {
    message.quickReply = {
      items: actions.slice(0, 13).map((action) => ({
        type: 'action',
        action,
      })),
    }
  }
  return message
}

export function postback(
  label: string,
  data: string,
  displayText?: string,
): LineAction {
  return {
    type: 'postback',
    label,
    data,
    displayText: displayText ?? label,
  }
}

export async function replyLine(
  channelAccessToken: string,
  replyToken: string,
  messages: LineMessage[],
): Promise<void> {
  const response = await fetch(`${LINE_API}/message/reply`, {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${channelAccessToken}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      replyToken,
      messages: messages.slice(0, 5),
      notificationDisabled: true,
    }),
  })
  if (!response.ok) {
    const body = await response.text()
    throw new Error(`line_reply_${response.status}:${body.slice(0, 300)}`)
  }
}

function fromBase64(value: string): Uint8Array {
  const binary = atob(value)
  return Uint8Array.from(binary, (char) => char.charCodeAt(0))
}

function timingSafeEqual(left: Uint8Array, right: Uint8Array): boolean {
  if (left.length !== right.length) return false
  let difference = 0
  for (let index = 0; index < left.length; index += 1) {
    difference |= left[index] ^ right[index]
  }
  return difference === 0
}

export async function verifyLineSignature(
  body: string,
  signature: string | null,
  channelSecret: string,
): Promise<boolean> {
  if (!signature) return false
  let supplied: Uint8Array
  try {
    supplied = fromBase64(signature)
  } catch {
    return false
  }
  const key = await crypto.subtle.importKey(
    'raw',
    new TextEncoder().encode(channelSecret),
    { name: 'HMAC', hash: 'SHA-256' },
    false,
    ['sign'],
  )
  const expected = new Uint8Array(
    await crypto.subtle.sign('HMAC', key, new TextEncoder().encode(body)),
  )
  return timingSafeEqual(expected, supplied)
}

