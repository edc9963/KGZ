begin;
create extension if not exists pgtap with schema extensions;
select plan(8);

insert into auth.users(
  id, instance_id, aud, role, email, encrypted_password,
  email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values (
  '88888888-8888-4888-8888-888888888888',
  '00000000-0000-0000-0000-000000000000',
  'authenticated', 'authenticated', 'quotes@example.invalid', '',
  now(), '{}', '{}', now(), now()
);

insert into public.market_instruments(
  market, symbol, name, normalized_name, instrument_type, currency
) values ('TWSE', '0050', '元大台灣50', '元大台灣50', 'ETF', 'TWD');
insert into public.market_quote_history(
  market, symbol, quote_date, close_price_minor
) values ('TWSE', '0050', '2026-08-19', 10310);

set local role authenticated;
set local request.jwt.claims =
  '{"sub":"88888888-8888-4888-8888-888888888888","role":"authenticated"}';

select is(
  public.save_finance_data(0, jsonb_build_object(
    'schemaVersion', 9, 'settings', '{}'::jsonb,
    'categories', '[]'::jsonb, 'transactions', '[]'::jsonb,
    'accounts', '[]'::jsonb, 'balanceAdjustments', '[]'::jsonb,
    'expenses', '[]'::jsonb, 'recurringExpenses', '[]'::jsonb,
    'recurringExpenseOccurrences', '[]'::jsonb,
    'telecomBillPayments', '[]'::jsonb, 'incomes', '[]'::jsonb,
    'cards', '[]'::jsonb, 'bills', '[]'::jsonb,
    'products', jsonb_build_array(jsonb_build_object(
      'id', 'p1', 'symbol', '0050', 'name', '舊名稱', 'type', 'ETF',
      'currency', 'TWD', 'currentPriceMinor', 1,
      'priceUpdatedAt', '2026-08-01T00:00:00Z', 'note', '', 'origin', 'user',
      'priceSource', 'twse', 'market', 'TWSE', 'marketSymbol', '0050',
      'quoteLinkedAt', '2026-08-20T00:00:00Z'
    )),
    'investmentTransactions', '[]'::jsonb,
    'investmentAdjustments', jsonb_build_array(jsonb_build_object(
      'id', 'a1', 'productId', 'p1', 'date', '2026-08-01T00:00:00Z',
      'quantityMicros', 1000000000, 'averageCostMinor', 8000,
      'reason', '期初', 'origin', 'user'
    )),
    'investmentPriceHistory', '[]'::jsonb, 'orders', '[]'::jsonb
  ))->>'status',
  'saved', 'v8 linked product saves'
);

select is(public.load_finance_data()#>>'{data,schemaVersion}', '9',
  'load returns schema v8');
select is(public.load_finance_data()#>>'{data,products,0,name}', '元大台灣50',
  'official metadata overlays the user product');
select is(public.load_finance_data()#>>'{data,products,0,currentPriceMinor}', '10310',
  'latest official close overlays stale client price');
select is(
  public.load_finance_data()#>>'{data,investmentAdjustments,0,quantityMicros}',
  '1000000000', 'linking does not change inventory inputs'
);
select is(public.load_finance_data()#>>'{revision}', '1',
  'market overlays do not create a finance revision');

reset role;
insert into public.market_quote_history(
  market, symbol, quote_date, close_price_minor
) values ('TWSE', '0050', '2026-08-20', 10400);
set local role authenticated;
set local request.jwt.claims =
  '{"sub":"88888888-8888-4888-8888-888888888888","role":"authenticated"}';

select is(public.load_finance_data()#>>'{data,products,0,currentPriceMinor}', '10400',
  'new market close updates valuation without a user save');
select is(public.load_finance_data()#>>'{revision}', '1',
  'daily quote update leaves the finance revision unchanged');

select * from finish();
rollback;
