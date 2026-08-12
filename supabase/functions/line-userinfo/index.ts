const LINE_USERINFO_URL = 'https://api.line.me/oauth2/v2.1/userinfo'

Deno.serve(async (request) => {
  if (request.method !== 'GET' && request.method !== 'POST') {
    return Response.json(
      { error: 'method_not_allowed' },
      { status: 405, headers: { 'Cache-Control': 'no-store' } },
    )
  }

  const authorization = request.headers.get('authorization')
  if (!authorization?.startsWith('Bearer ')) {
    return Response.json(
      { error: 'missing_access_token' },
      { status: 401, headers: { 'Cache-Control': 'no-store' } },
    )
  }

  const lineResponse = await fetch(LINE_USERINFO_URL, {
    headers: {
      'Authorization': authorization,
      'Accept': 'application/json',
    },
  })
  if (!lineResponse.ok) {
    return Response.json(
      { error: 'invalid_access_token' },
      { status: 401, headers: { 'Cache-Control': 'no-store' } },
    )
  }

  const profile = await lineResponse.json()
  if (typeof profile?.sub !== 'string' || profile.sub.length === 0) {
    return Response.json(
      { error: 'invalid_profile' },
      { status: 502, headers: { 'Cache-Control': 'no-store' } },
    )
  }

  // Supabase's generic OAuth2 adapter currently expects an email even when
  // the provider is configured as email-optional. This deterministic address
  // is an internal identifier only; no real LINE email is collected or used.
  const internalEmail = `${profile.sub.toLowerCase()}@line.invalid`
  return Response.json(
    {
      ...profile,
      id: profile.sub,
      email: internalEmail,
      email_verified: true,
    },
    { headers: { 'Cache-Control': 'no-store' } },
  )
})
