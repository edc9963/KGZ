begin;
create extension if not exists pgtap with schema extensions;
select plan(18);

insert into auth.users(
  id, instance_id, aud, role, email, encrypted_password,
  email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  ('11111111-1111-4111-8111-111111111111', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'line-one@example.invalid', '',
   now(), '{}', '{}', now(), now()),
  ('22222222-2222-4222-8222-222222222222', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'line-two@example.invalid', '',
   now(), '{}', '{}', now(), now());

insert into auth.identities(
  id, provider_id, user_id, identity_data, provider,
  last_sign_in_at, created_at, updated_at
) values
  ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'U-line-one',
   '11111111-1111-4111-8111-111111111111', '{"sub":"U-line-one"}',
   'custom:line', now(), now(), now()),
  ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 'U-line-two',
   '22222222-2222-4222-8222-222222222222', '{"sub":"U-line-two"}',
   'custom:line', now(), now(), now());

select is(
  public.line_resolve_identity('U-line-one')->>'status',
  'available',
  'same-provider identity is available before consent'
);
select is(
  public.line_resolve_identity('unknown')->>'status',
  'unknown',
  'unknown LINE user is rejected'
);
select is(
  public.line_link_account('U-line-one')->>'status',
  'linked',
  'known identity can explicitly link'
);
select is(
  public.line_resolve_identity('U-line-one')->>'status',
  'linked',
  'linked identity resolves'
);

select ok(
  not has_function_privilege(
    'anon', 'public.line_confirm_expense(text,uuid,bigint,text,text,text,text,text,timestamptz)',
    'execute'
  ),
  'anon cannot execute LINE write RPC'
);
select ok(
  not has_function_privilege(
    'authenticated', 'public.line_mark_received(text,uuid)', 'execute'
  ),
  'authenticated client cannot execute LINE write RPC'
);

select is(
  public.line_confirm_expense(
    'U-line-one', '10000000-0000-4000-8000-000000000001',
    12000, '午餐', '餐飲', 'cash', null, null, now()
  )->>'status',
  'saved',
  'quick expense saves'
);
select is(
  (select revision from public.finance_sync_state
   where user_id = '11111111-1111-4111-8111-111111111111'),
  1::bigint,
  'quick expense increments revision'
);
select is(
  (select count(*) from public.expenses
   where user_id = '11111111-1111-4111-8111-111111111111'),
  1::bigint,
  'one expense exists'
);
select is(
  public.line_confirm_expense(
    'U-line-one', '10000000-0000-4000-8000-000000000001',
    12000, '午餐', '餐飲', 'cash', null, null, now()
  )->>'duplicate',
  'true',
  'duplicate command is idempotent'
);
select is(
  (select count(*) from public.expenses
   where user_id = '11111111-1111-4111-8111-111111111111'),
  1::bigint,
  'duplicate command does not insert another expense'
);
select is(
  (public.line_finance_summary('U-line-one')->>'monthExpenseMinor')::bigint,
  12000::bigint,
  'summary is scoped to linked owner'
);
select is(
  public.line_finance_summary('U-line-two')->>'status',
  'not_linked',
  'unlinked second user cannot read summary'
);

insert into public.accounts values (
  '11111111-1111-4111-8111-111111111111', 'bank', '銀行', '', '銀行帳戶',
  'TWD', 0, true, '', now(), now(), 'user'
);
insert into public.credit_cards values (
  '11111111-1111-4111-8111-111111111111', 'card', '信用卡', '銀行',
  '1234', 1, 10, 10, 'bank', true, '', 'user'
);
insert into public.group_orders values (
  '11111111-1111-4111-8111-111111111111', 'order', '測試訂單', now(),
  'Uber Eats', 'card', 20000, 0, 0, 0, false, false, 'exactRemainder',
  null, '{}', 0, '1234', 'manual', '', null, 'user'
);
insert into public.order_participants values (
  '11111111-1111-4111-8111-111111111111', 'order', 'friend', '朋友',
  false, '餐點', 20000, 0, 0, false, false, 20000, null, 'unpaid',
  '銀行轉帳', 'bank', 'collection-token', null, ''
);

create temporary table issued_token as
select ((public.line_list_receivables('U-line-one', 8)->'items'->0->>'token')::uuid)
  as token;
select is(
  public.line_mark_received(
    'U-line-one', (select token from issued_token)
  )->>'status',
  'saved',
  'opaque receivable action marks paid'
);
select is(
  (select revision from public.finance_sync_state
   where user_id = '11111111-1111-4111-8111-111111111111'),
  2::bigint,
  'mark received increments revision'
);

insert into public.order_participants values (
  '11111111-1111-4111-8111-111111111111', 'order', 'friend-cash', '現金朋友',
  false, '餐點', 10000, 0, 0, false, false, 10000, null, 'unpaid',
  '現金', null, 'cash-collection-token', null, ''
);
create temporary table cash_token as
select ((public.line_list_receivables('U-line-one', 8)->'items'->0->>'token')::uuid)
  as token;
select is(
  public.line_mark_received(
    'U-line-one', (select token from cash_token)
  )->>'status',
  'saved',
  'cash receivable marks paid directly'
);
select is(
  (select collection_account_id from public.order_participants
   where user_id = '11111111-1111-4111-8111-111111111111'
     and order_id = 'order' and id = 'friend-cash'),
  'system-cash',
  'cash receivable uses the system cash account'
);
select ok(
  exists(select 1 from public.accounts
         where user_id = '11111111-1111-4111-8111-111111111111'
           and id = 'system-cash' and is_active),
  'system cash account exists and is active'
);

select * from finish();
rollback;
