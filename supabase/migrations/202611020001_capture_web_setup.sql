-- 自動記帳 setup from the web app (設定 → 同步 → 自動記帳).
--
-- Until now the capture token could only be issued from LINE (「捷徑設定」→
-- 「產生金鑰」), and every URL had to be copied out of chat. These two RPCs
-- let the signed-in web user see whether automation is set up and issue the
-- same per-user token directly. The token is generated here, only its
-- SHA-256 is stored (the same row LINE writes), and the plaintext is
-- returned once.

create or replace function public.capture_web_status()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  uid uuid := auth.uid();
  token_row public.capture_tokens%rowtype;
  has_token boolean;
begin
  if uid is null then raise exception 'not_authenticated'; end if;
  select * into token_row from public.capture_tokens where user_id = uid;
  has_token := found;
  return jsonb_build_object(
    'status', 'ok',
    'hasToken', has_token,
    'tokenCreatedAt', token_row.created_at,
    'tokenLastUsedAt', token_row.last_used_at,
    'lineLinked', exists (
      select 1 from public.line_account_links l
      where l.user_id = uid and l.enabled
    ),
    'pendingCount', (
      select count(*) from public.capture_inbox i
      where i.user_id = uid and i.status = 'pending'
    ),
    'lastCapturedAt', (
      select max(i.created_at) from public.capture_inbox i
      where i.user_id = uid
    )
  );
end
$$;

create or replace function public.capture_web_issue_token()
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  uid uuid := auth.uid();
  -- Same shape as generateCaptureToken() in supabase/functions/_shared:
  -- kgz_ + base64url of 24 random bytes (32 chars, no padding).
  token text := 'kgz_' || translate(
    encode(extensions.gen_random_bytes(24), 'base64'), '+/', '-_'
  );
begin
  if uid is null then raise exception 'not_authenticated'; end if;
  insert into public.capture_tokens(user_id, token_hash, created_at, last_used_at)
  values (uid, encode(sha256(convert_to(token, 'UTF8')), 'hex'), now(), null)
  on conflict (user_id) do update
  set token_hash = excluded.token_hash, created_at = now(), last_used_at = null;
  return jsonb_build_object('status', 'issued', 'token', token);
end
$$;

revoke all on function public.capture_web_status() from public, anon, authenticated;
revoke all on function public.capture_web_issue_token() from public, anon, authenticated;
grant execute on function public.capture_web_status() to authenticated;
grant execute on function public.capture_web_issue_token() to authenticated;
