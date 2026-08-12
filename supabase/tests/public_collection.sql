begin;
create extension if not exists pgtap with schema extensions;
select plan(7);

insert into auth.users(
  id, instance_id, aud, role, email, encrypted_password,
  email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values (
  '88888888-8888-4888-8888-888888888888',
  '00000000-0000-0000-0000-000000000000',
  'authenticated', 'authenticated', 'collection@example.invalid', '',
  now(), '{}', '{}', now(), now()
);

insert into public.finance_sync_state(user_id, revision)
values ('88888888-8888-4888-8888-888888888888', 0);
insert into public.accounts(
  user_id, id, name, institution, account_type, currency,
  opening_balance_minor, is_active, note, created_at, updated_at
) values (
  '88888888-8888-4888-8888-888888888888', 'bank', '測試銀行', '',
  '銀行帳戶', 'TWD', 0, true, '', now(), now()
);
insert into public.user_settings(
  user_id, default_collection_account_id, bank_qr_data, bank_account_info
) values (
  '88888888-8888-4888-8888-888888888888', 'bank',
  'bank-qr-secret', '銀行 000-123456'
);
insert into public.credit_cards(
  user_id, id, name, bank, last_four, closing_day, due_day,
  auto_debit_day, debit_account_id
) values (
  '88888888-8888-4888-8888-888888888888', 'card', '測試卡', '測試銀行',
  '1234', 10, 25, 25, 'bank'
);
insert into public.group_orders(
  user_id, id, name, order_date, platform, card_id, total_minor,
  split_method, note
) values (
  '88888888-8888-4888-8888-888888888888', 'lunch', '跨裝置午餐',
  '2026-08-12T04:00:00Z', 'Uber Eats', 'card', 18000, 'equal', '測試備註'
);
insert into public.order_participants(
  user_id, order_id, id, name, is_self, item_name, item_amount_minor,
  shared_fee_minor, discount_minor, collection_status, collection_method,
  collection_account_id, collection_token, note
) values (
  '88888888-8888-4888-8888-888888888888', 'lunch', 'friend', '朋友', false,
  '便當', 17000, 2000, 1000, 'unpaid', '銀行轉帳', 'bank',
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', ''
);

set local role anon;

select is(
  public.load_public_collection('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa')->>'status',
  'ok', 'anonymous token loads one collection request'
);
select is(
  public.load_public_collection('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa')->>'dueMinor',
  '18000', 'public due amount is calculated in minor units'
);
select ok(
  not (public.load_public_collection(
    'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
  ) ? 'userId'),
  'public response does not expose owner id'
);
select is(
  public.load_public_collection('missing')->>'status',
  'not_found', 'unknown token reveals no collection data'
);
select is(
  public.mark_public_collection_pending(
    'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
  )->>'status',
  'ok', 'anonymous payer can mark the request pending'
);
select is(
  public.load_public_collection(
    'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
  )->>'collectionStatus',
  'pending', 'public status reflects the payment notification'
);

reset role;
select is(
  (select revision from public.finance_sync_state
   where user_id = '88888888-8888-4888-8888-888888888888'),
  1::bigint, 'anonymous state change increments owner revision'
);

select * from finish();
rollback;
