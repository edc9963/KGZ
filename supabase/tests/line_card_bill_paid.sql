begin;
create extension if not exists pgtap with schema extensions;
select plan(10);

insert into auth.users(
  id, instance_id, aud, role, email, encrypted_password,
  email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values (
  '33333333-3333-4333-8333-333333333333', '00000000-0000-0000-0000-000000000000',
  'authenticated', 'authenticated', 'line-bill@example.invalid', '',
  now(), '{}', '{}', now(), now()
);
insert into auth.identities(
  id, provider_id, user_id, identity_data, provider,
  last_sign_in_at, created_at, updated_at
) values (
  'cccccccc-cccc-4ccc-8ccc-cccccccccccc', 'U-line-bill',
  '33333333-3333-4333-8333-333333333333', '{"sub":"U-line-bill"}',
  'custom:line', now(), now(), now()
);
select public.line_link_account('U-line-bill');

insert into public.accounts values
  ('33333333-3333-4333-8333-333333333333', 'bank', '銀行', '', '銀行帳戶',
   'TWD', 100000, true, '', now(), now(), 'user'),
  ('33333333-3333-4333-8333-333333333333', 'liability', '卡未繳', '', '信用卡負債',
   'TWD', 0, true, '', now(), now(), 'user');
insert into public.financial_account_metadata values
  ('33333333-3333-4333-8333-333333333333', 'liability', 'liability', 'creditCard');
insert into public.credit_cards values (
  '33333333-3333-4333-8333-333333333333', 'card', '測試卡', '銀行',
  '1234', 15, 28, 28, 'bank', true, '', 'user'
);
insert into public.credit_card_profiles_v7 values
  ('33333333-3333-4333-8333-333333333333', 'card', 'liability');
insert into public.card_bills(
  user_id, id, card_id, bill_month, manual_adjustment_minor, paid_minor,
  due_date, auto_debit_date, note, origin
) values (
  '33333333-3333-4333-8333-333333333333', 'bill', 'card', '2026-08',
  0, 0, now() - interval '2 days', now() - interval '2 days', '', 'user'
);
insert into public.card_bill_reconciliation_v9 values (
  '33333333-3333-4333-8333-333333333333', 'bill', 12000, 'none', '', 'failed'
);

select is(
  jsonb_array_length(public.line_list_unpaid_card_bills('U-line-bill')->'items'),
  1, 'unpaid bill is listed'
);
select is(
  (select count(*)::integer from public.card_bill_reminder_candidates(current_date)
   where bill_id = 'bill'),
  1, 'overdue bill is a reminder candidate before paying'
);
select is(
  public.line_mark_card_bill_paid('U-line-bill', 'bill')->>'status',
  'saved', 'LINE 已繳費 records the payment'
);
select is(
  (select paid_minor from public.card_bills
   where user_id = '33333333-3333-4333-8333-333333333333' and id = 'bill'),
  12000::bigint, 'bill paid_minor covers the statement'
);
select is(
  (select sum(amount_minor) from public.financial_transactions
   where user_id = '33333333-3333-4333-8333-333333333333'
     and transaction_type = 'cardPayment' and related_entity_id = 'bill'),
  12000::numeric, 'a cardPayment transaction is written'
);
select is(
  (select count(*)::integer from public.account_impacts
   where user_id = '33333333-3333-4333-8333-333333333333'
     and transaction_id like 'card-payment:bill:line-%'),
  2, 'payment impacts debit account and card liability'
);
select is(
  (select revision from public.finance_sync_state
   where user_id = '33333333-3333-4333-8333-333333333333'),
  1::bigint, 'payment bumps the finance revision'
);
select is(
  (select count(*)::integer from public.card_bill_reminder_candidates(current_date)
   where bill_id = 'bill'),
  0, 'paid bill stops being a reminder candidate'
);
select is(
  public.line_mark_card_bill_paid('U-line-bill', 'bill')->>'status',
  'already_paid', 'second tap does not pay twice'
);
select is(
  jsonb_array_length(public.line_list_unpaid_card_bills('U-line-bill')->'items'),
  0, 'paid bill is no longer listed'
);

select * from finish();
rollback;
