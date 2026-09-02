begin;
create extension if not exists pgtap with schema extensions;
select plan(27);

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
insert into public.accounts values
  ('11111111-1111-4111-8111-111111111111', 'debit-bank', '金融卡扣款帳戶', '', '銀行帳戶',
   'TWD', 0, true, '', now(), now(), 'user'),
  ('11111111-1111-4111-8111-111111111111', 'deleted-bank', '已刪除舊帳戶', '', '銀行帳戶',
   'TWD', 0, false, '', now(), now(), 'user'),
  ('11111111-1111-4111-8111-111111111111', 'legacy-liability', '舊卡未繳', '', '信用卡負債',
   'TWD', 0, true, '', now(), now(), 'user');
insert into public.financial_account_metadata values (
  '11111111-1111-4111-8111-111111111111', 'legacy-liability',
  'liability', 'creditCard'
);
insert into public.credit_cards values (
  '11111111-1111-4111-8111-111111111111', 'debit-card', '金融卡', '銀行',
  '5678', 1, 10, 10, 'debit-bank', true, '', 'user'
);
insert into public.payment_card_profiles values (
  '11111111-1111-4111-8111-111111111111', 'debit-card', 'debit'
);
insert into public.recurring_expenses(
  user_id, id, item, category, amount_minor, payment_method,
  day_of_month, start_month, telecom_debit_account_id,
  is_active, is_necessary, note, origin
) values (
  '11111111-1111-4111-8111-111111111111', 'phone', '手機月租', '通訊',
  59900, 'telecomBill', 28, '2026-08', 'bank', true, true, '', 'user'
);

create temporary table payment_sources as
select public.line_list_payment_sources('U-line-one') as payload;
select ok(
  not exists(
    select 1 from jsonb_array_elements(
      (select payload->'accounts' from payment_sources)
    ) item where item->>'id' in ('deleted-bank', 'legacy-liability')
  ),
  'LINE payment sources exclude deleted and internal accounts'
);
select is(
  (select item->>'cardType'
   from payment_sources,
   jsonb_array_elements(payload->'cards') item
   where item->>'id' = 'debit-card'),
  'debit',
  'LINE payment sources expose debit card type'
);
select is(
  (select payload->>'telecomBillConfigured' from payment_sources),
  'true',
  'LINE payment sources expose configured telecom billing'
);
select is(
  public.line_confirm_expense(
    'U-line-one', '10000000-0000-4000-8000-000000000002',
    8000, '金融卡午餐', '餐飲', 'debitCard', null, 'debit-card', now()
  )->>'status',
  'saved',
  'LINE debit card expense saves'
);
select ok(
  exists(
    select 1 from public.expenses
    where user_id = '11111111-1111-4111-8111-111111111111'
      and item = '金融卡午餐' and account_id = 'debit-bank'
      and card_id = 'debit-card'
  ),
  'LINE debit card expense uses its linked account'
);
select is(
  public.line_confirm_expense(
    'U-line-one', '10000000-0000-4000-8000-000000000003',
    9900, '電信代收', '娛樂', 'telecomBill', 'bank', 'card', now()
  )->>'status',
  'saved',
  'LINE telecom-billed expense saves without another selection'
);
select ok(
  exists(
    select 1 from public.expenses
    where user_id = '11111111-1111-4111-8111-111111111111'
      and item = '電信代收' and payment_method = 'telecomBill'
      and account_id is null and card_id is null
  ),
  'LINE telecom-billed expense waits for scheduled account deduction'
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
  4::bigint,
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

insert into public.order_participants
select
  '11111111-1111-4111-8111-111111111111', 'order',
  'all-' || value, '待收朋友 ' || value, false, '餐點', 10000, 0, 0,
  false, false, 10000, null, 'unpaid', '現金', null,
  gen_random_uuid()::text, null, ''
from generate_series(1, 11) value;

insert into public.group_orders values (
  '11111111-1111-4111-8111-111111111111', 'screenshot-order',
  '截圖匯入訂單', now() - interval '1 day', 'Uber Eats', 'card',
  15000, 0, 0, 0, false, false, 'exactRemainder',
  'uberEatsScreenshot', '{}', 0, '1234', 'manual', '', null, 'user'
);
insert into public.order_participants values (
  '11111111-1111-4111-8111-111111111111', 'screenshot-order',
  'screenshot-friend', '截圖朋友', false, '餐點', 15000, 0, 0,
  false, false, 15000, null, 'unpaid', '現金', null,
  'screenshot-collection-token', null, ''
);
create temporary table all_receivables as
select public.line_list_receivables('U-line-one', null) as payload;
select is(
  jsonb_array_length(
    (select payload->'items' from all_receivables)
  ),
  12,
  'null limit returns every outstanding receivable'
);
select ok(
  exists(
    select 1
    from jsonb_array_elements(
      (select payload->'items' from all_receivables)
    ) item
    where item->>'orderName' = '測試訂單'
  ) and exists(
    select 1
    from jsonb_array_elements(
      (select payload->'items' from all_receivables)
    ) item
    where item->>'orderName' = '截圖匯入訂單'
  ),
  'manual and screenshot-imported receivables are synchronized together'
);

select * from finish();
rollback;
