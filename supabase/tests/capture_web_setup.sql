begin;
create extension if not exists pgtap with schema extensions;
select plan(12);

insert into auth.users(
  id, instance_id, aud, role, email, encrypted_password,
  email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values (
  '55555555-5555-4555-8555-555555555555', '00000000-0000-0000-0000-000000000000',
  'authenticated', 'authenticated', 'capture-web@example.invalid', '',
  now(), '{}', '{}', now(), now()
);

select throws_ok(
  'select public.capture_web_status()',
  'not_authenticated', 'status requires a signed-in user'
);

set local role authenticated;
set local request.jwt.claims =
  '{"sub":"55555555-5555-4555-8555-555555555555","role":"authenticated"}';

select is(
  public.capture_web_status()->>'hasToken', 'false', 'no token before issuing'
);
select is(
  public.capture_web_status()->>'lineLinked', 'false', 'LINE link is reported'
);

create temporary table issued as
select public.capture_web_issue_token() as result;
select is((select result->>'status' from issued), 'issued', 'web can issue a token');
select matches(
  (select result->>'token' from issued), '^kgz_[A-Za-z0-9_-]{32}$',
  'token has the same shape as the LINE-issued one'
);
select is(
  public.capture_web_status()->>'hasToken', 'true', 'status sees the new token'
);
select is(
  public.capture_web_status()->>'tokenLastUsedAt', null, 'new token is unused'
);

reset role;
select is(
  (select token_hash from public.capture_tokens
   where user_id = '55555555-5555-4555-8555-555555555555'),
  encode(sha256(convert_to((select result->>'token' from issued), 'UTF8')), 'hex'),
  'only the SHA-256 of the token is stored'
);
select is(
  public.capture_ingest(
    encode(sha256(convert_to((select result->>'token' from issued), 'UTF8')), 'hex'),
    8500, 'TWD', '7-ELEVEN', 'CUBE', now()
  )->>'status',
  'created', 'the web-issued token is accepted by ingest'
);

set local role authenticated;
select is(
  public.capture_web_status()->>'pendingCount', '1', 'pending captures are counted'
);
select isnt(
  public.capture_web_status()->>'tokenLastUsedAt', null, 'ingest marks the token used'
);
select isnt(
  (select public.capture_web_issue_token()->>'token'),
  (select result->>'token' from issued),
  'issuing again replaces the token'
);

select * from finish();
rollback;
