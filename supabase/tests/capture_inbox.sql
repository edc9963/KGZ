begin;
create extension if not exists pgtap with schema extensions;
select plan(44);

insert into auth.users(
  id, instance_id, aud, role, email, encrypted_password,
  email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values (
  '44444444-4444-4444-8444-444444444444', '00000000-0000-0000-0000-000000000000',
  'authenticated', 'authenticated', 'capture@example.invalid', '',
  now(), '{}', '{}', now(), now()
);
insert into auth.identities(
  id, provider_id, user_id, identity_data, provider,
  last_sign_in_at, created_at, updated_at
) values (
  'dddddddd-dddd-4ddd-8ddd-dddddddddddd', 'U-capture',
  '44444444-4444-4444-8444-444444444444', '{"sub":"U-capture"}',
  'custom:line', now(), now(), now()
);

select is(
  public.capture_issue_token('U-capture', repeat('a', 64))->>'status',
  'not_linked', 'token requires a linked LINE account'
);
select public.line_link_account('U-capture');

insert into public.accounts values
  ('44444444-4444-4444-8444-444444444444', 'bank', '銀行', '', '銀行帳戶',
   'TWD', 100000, true, '', now(), now(), 'user'),
  ('44444444-4444-4444-8444-444444444444', 'liability', '卡未繳', '', '信用卡負債',
   'TWD', 0, true, '', now(), now(), 'user');
insert into public.financial_account_metadata values
  ('44444444-4444-4444-8444-444444444444', 'liability', 'liability', 'creditCard');
insert into public.credit_cards values
  ('44444444-4444-4444-8444-444444444444', 'cube', 'CUBE', '國泰世華',
   '1234', 15, 28, 28, 'bank', true, '', 'user'),
  ('44444444-4444-4444-8444-444444444444', 'richart', 'Richart 卡', '台新',
   '5678', 5, 20, 20, 'bank', true, '', 'user');
insert into public.credit_card_profiles_v7 values
  ('44444444-4444-4444-8444-444444444444', 'cube', 'liability'),
  ('44444444-4444-4444-8444-444444444444', 'richart', 'liability');

select is(
  public.capture_issue_token('U-capture', repeat('a', 64))->>'status',
  'issued', 'linked user can issue a capture token'
);
select is(
  public.capture_ingest(repeat('b', 64), 8500, 'TWD', '7-ELEVEN', 'CUBE', now())->>'status',
  'invalid_token', 'unknown token is rejected'
);

-- Wallet card name containing the managed card name resolves to that card.
create temporary table first_capture as
select public.capture_ingest(
  repeat('a', 64), 8500, 'TWD', ' 7-ELEVEN ', '國泰世華 CUBE 卡', now()
) as result;
select is((select result->>'status' from first_capture), 'created', 'tap is captured');
select is(
  (select result->>'lineUserId' from first_capture), 'U-capture',
  'ingest returns the LINE user to push to'
);
select is(
  (select result->'capture'->>'cardResolution' from first_capture), 'card',
  'card is matched by name'
);
select is(
  (select result->'capture'->>'merchant' from first_capture), '7-ELEVEN',
  'merchant is trimmed'
);
select is(
  (select result->'capture'->>'suggestedCategoryId' from first_capture), null,
  'no suggestion without history'
);
select is(
  public.capture_ingest(
    repeat('a', 64), 8500, 'TWD', '7-ELEVEN', '國泰世華 CUBE 卡', now() + interval '30 seconds'
  )->>'status',
  'duplicate', 'a retried shortcut run is not a second purchase'
);

select is(
  public.line_capture_confirm(
    'U-capture', (select (result->'capture'->>'inboxId')::uuid from first_capture),
    'legacy-food', null
  )->>'status',
  'saved', 'choosing a category books the expense'
);
select is(
  (select row(payment_method, card_id, category, item, merchant)::text
   from public.expenses where user_id = '44444444-4444-4444-8444-444444444444'),
  '(creditCard,cube,餐飲,7-ELEVEN,7-ELEVEN)',
  'expense uses the matched credit card, merchant and category'
);
select is(
  (select revision from public.finance_sync_state
   where user_id = '44444444-4444-4444-8444-444444444444'),
  1::bigint, 'booking bumps the cloud revision'
);
select is(
  (select status from public.capture_inbox
   where id = (select (result->'capture'->>'inboxId')::uuid from first_capture)),
  'confirmed', 'inbox row is confirmed'
);
select is(
  public.line_capture_confirm(
    'U-capture', (select (result->'capture'->>'inboxId')::uuid from first_capture),
    'legacy-food', null
  )->>'status',
  'already_confirmed', 'a second tap does not book twice'
);
select is(
  (select count(*) from public.expenses
   where user_id = '44444444-4444-4444-8444-444444444444'),
  1::bigint, 'still one expense'
);

-- The next purchase at the same merchant suggests the last category.
select is(
  public.capture_ingest(
    repeat('a', 64), 4500, 'TWD', '7-eleven', 'CUBE', now()
  )->'capture'->>'suggestedCategoryId',
  'legacy-food', 'category is learned from the merchant history'
);

-- Unknown Wallet card: ask once, then remember.
create temporary table unknown_capture as
select public.capture_ingest(
  repeat('a', 64), 12000, 'TWD', '全聯', 'Apple Card', now()
) as result;
select is(
  (select result->'capture'->>'cardResolution' from unknown_capture), 'unknown',
  'unmatched Wallet card is unknown'
);
select is(
  public.line_capture_confirm(
    'U-capture', (select (result->'capture'->>'inboxId')::uuid from unknown_capture),
    'legacy-shopping', null
  )->>'status',
  'needs_card', 'unknown card asks which card after the category'
);
select is(
  public.line_capture_confirm(
    'U-capture', (select (result->'capture'->>'inboxId')::uuid from unknown_capture),
    null, 'richart'
  )->>'category',
  '購物', 'card answer reuses the stored category'
);
select is(
  (select card_id from public.expenses
   where user_id = '44444444-4444-4444-8444-444444444444' and item = '全聯'),
  'richart', 'expense uses the chosen card'
);
select is(
  public.capture_ingest(
    repeat('a', 64), 3000, 'TWD', '全家', 'Apple Card', now()
  )->'capture'->>'cardResolution',
  'card', 'the Wallet card mapping is remembered'
);

-- 不指定卡片
create temporary table none_capture as
select public.capture_ingest(
  repeat('a', 64), 6000, 'TWD', '', 'Mystery', now()
) as result;
select public.line_capture_confirm(
  'U-capture', (select (result->'capture'->>'inboxId')::uuid from none_capture),
  'legacy-other', null
);
select is(
  public.line_capture_confirm(
    'U-capture', (select (result->'capture'->>'inboxId')::uuid from none_capture),
    null, '__none__'
  )->>'merchant',
  'Apple Pay 消費', 'blank merchant gets a readable item'
);
select is(
  (select payment_method || ':' || coalesce(card_id, '-') from public.expenses
   where user_id = '44444444-4444-4444-8444-444444444444' and amount_minor = 6000),
  'other:-', '不指定卡片 records payment method other'
);

-- Foreign currency, dismiss, invalid category, other users.
create temporary table usd_capture as
select public.capture_ingest(
  repeat('a', 64), 1234, 'USD', 'Apple', 'CUBE', now()
) as result;
select is(
  public.line_capture_confirm(
    'U-capture', (select (result->'capture'->>'inboxId')::uuid from usd_capture),
    'legacy-food', null
  )->>'status',
  'unsupported_currency', 'foreign currency cannot be booked from LINE'
);
select is(
  public.line_capture_dismiss(
    'U-capture', (select (result->'capture'->>'inboxId')::uuid from usd_capture)
  )->>'status',
  'dismissed', 'pending capture can be skipped'
);
select is(
  public.line_capture_open(
    'U-capture', (select (result->'capture'->>'inboxId')::uuid from usd_capture)
  )->>'status',
  'already_dismissed', 'skipped capture cannot be reopened'
);
select is(
  (public.line_capture_list_pending('U-capture')->>'total')::integer,
  2, 'pending list counts unresolved taps'
);
select is(
  public.line_capture_confirm(
    'U-capture', (select (result->'capture'->>'inboxId')::uuid from first_capture),
    'no-such-category', null
  )->>'status',
  'already_confirmed', 'status is checked before the category'
);
select is(
  public.line_capture_open(
    'U-line-unknown', (select (result->'capture'->>'inboxId')::uuid from unknown_capture)
  )->>'status',
  'not_linked', 'other LINE users cannot open a capture'
);

-- LINE Pay 刷卡通知信 (card-email-ingest).
create temporary table line_pay_capture as
select public.capture_ingest(
  repeat('a', 64), 4321, 'TWD', '', '國泰世華 *1234', now(),
  'linePay', '<notice-1@cathaybk.com.tw>'
) as result;
select is(
  (select result->'capture'->>'source' || ':' || (result->'capture'->>'cardResolution')
   from line_pay_capture),
  'linePay:card', 'LINE Pay notice is captured and matched by last four'
);
select is(
  public.capture_ingest(
    repeat('a', 64), 4321, 'TWD', '全家', '國泰世華 *1234', now() - interval '1 hour',
    'linePay', '<notice-1@cathaybk.com.tw>'
  )->>'status',
  'duplicate', 'the same email is captured once even if parsed differently'
);
select is(
  public.capture_ingest(
    repeat('a', 64), 100, 'TWD', 'x', '', now(), 'cash', null
  )->>'status',
  'invalid_source', 'unknown sources are rejected'
);
select is(
  public.line_capture_confirm(
    'U-capture', (select (result->'capture'->>'inboxId')::uuid from line_pay_capture),
    'legacy-food', null
  )->>'merchant',
  'LINE Pay 消費', 'blank LINE Pay merchant gets a readable item'
);
select is(
  (select payment_method || ':' || card_id || ':' || note from public.expenses
   where user_id = '44444444-4444-4444-8444-444444444444' and amount_minor = 4321),
  'creditCard:cube:LINE Pay 刷卡通知建立', 'LINE Pay charge is booked on the card'
);
select is(
  public.line_capture_confirm(
    'U-capture',
    (public.capture_ingest(
      repeat('a', 64), 250, 'TWD', '路易莎', '', now(), 'linePay', '<notice-2@x>'
    )->'capture'->>'inboxId')::uuid,
    'legacy-food', null
  )->>'source',
  'linePay', 'card question knows the capture came from LINE Pay'
);

-- 銀行扣帳通知 (TWPAY / 金融卡) resolve to an asset account.
create temporary table twpay_capture as
select public.capture_ingest(
  repeat('a', 64), 7700, 'TWD', '', '彰化銀行 1234-56-XXX78-9-00', now(),
  'twPay', '<chb-1@bill.chb.com.tw>'
) as result;
select is(
  (select result->'capture'->>'cardResolution' from twpay_capture),
  'account', 'TWPAY notice is matched to the asset account by name'
);
select is(
  public.line_capture_confirm(
    'U-capture', (select (result->'capture'->>'inboxId')::uuid from twpay_capture),
    'legacy-food', null
  )->>'merchant',
  'TWPAY 消費', 'TWPAY capture is booked with a readable item'
);
select is(
  (select payment_method || ':' || account_id || ':' || note from public.expenses
   where user_id = '44444444-4444-4444-8444-444444444444' and amount_minor = 7700),
  'transfer:bank:TWPAY 扣帳通知建立', 'TWPAY is a transfer out of the debited account'
);
select is(
  public.capture_ingest(
    repeat('a', 64), 8500, 'TWD', '', '彰化銀行 1234-56-XXX78-9-00', now(),
    'debitCard', '<chb-2@bill.chb.com.tw>'
  )->>'status',
  'duplicate', 'a debit notice for an Apple Pay tap is not a second purchase'
);
create temporary table debit_capture as
select public.capture_ingest(
  repeat('a', 64), 9900, 'TWD', '', 'Mystery Bank 0000', now(),
  'debitCard', '<other-1@example.invalid>'
) as result;
-- Arrives in the same batch, before the account question is answered.
create temporary table debit_capture_2 as
select public.capture_ingest(
  repeat('a', 64), 9800, 'TWD', '', 'Mystery Bank 0000', now(),
  'debitCard', '<other-2@example.invalid>'
) as result;
select is(
  public.line_capture_confirm(
    'U-capture', (select (result->'capture'->>'inboxId')::uuid from debit_capture),
    'legacy-food', null
  )->>'status',
  'needs_account', 'unknown account asks which account was debited'
);
select is(
  public.line_capture_confirm(
    'U-capture', (select (result->'capture'->>'inboxId')::uuid from debit_capture),
    null, null, 'bank'
  )->>'status',
  'saved', 'the chosen account books the debit-card purchase'
);
select is(
  public.line_capture_confirm(
    'U-capture', (select (result->'capture'->>'inboxId')::uuid from debit_capture_2),
    'legacy-food', null
  )->>'status',
  'saved', 'a capture already waiting with the same label uses the answer'
);

select ok(
  not has_function_privilege(
    'anon',
    'public.capture_ingest(text,bigint,text,text,text,timestamptz,text,text)',
    'execute'
  ),
  'anon cannot call capture_ingest directly'
);
select ok(
  not has_function_privilege(
    'authenticated', 'public.line_capture_confirm(text,uuid,text,text,text)', 'execute'
  ),
  'authenticated client cannot confirm captures'
);

select * from finish();
rollback;
