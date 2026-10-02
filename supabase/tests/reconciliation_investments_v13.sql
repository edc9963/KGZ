begin;
create extension if not exists pgtap with schema extensions;
select plan(6);

insert into auth.users(
  id, instance_id, aud, role, email, encrypted_password,
  email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values (
  '33333333-3333-4333-8333-333333333333',
  '00000000-0000-0000-0000-000000000000',
  'authenticated', 'authenticated', 'invest-reconcile@example.invalid', '',
  now(), '{}', '{}', now(), now()
);

set local role authenticated;
set local request.jwt.claims =
  '{"sub":"33333333-3333-4333-8333-333333333333","role":"authenticated"}';

select is(
  public.save_finance_data(0, jsonb_build_object(
    'schemaVersion', 13, 'settings', '{}'::jsonb,
    'categories', '[]'::jsonb, 'transactions', '[]'::jsonb,
    'accounts', '[]'::jsonb, 'balanceAdjustments', '[]'::jsonb,
    'expenses', '[]'::jsonb, 'recurringExpenses', '[]'::jsonb,
    'recurringExpenseOccurrences', '[]'::jsonb,
    'telecomBillPayments', '[]'::jsonb, 'incomes', '[]'::jsonb,
    'cards', '[]'::jsonb, 'bills', '[]'::jsonb,
    'products', jsonb_build_array(
      jsonb_build_object(
        'id', 'etf', 'userId', '', 'symbol', '0050', 'name', '元大台灣50',
        'type', 'ETF', 'currency', 'TWD', 'currentPriceMinor', 20000,
        'priceUpdatedAt', '2026-10-01T00:00:00Z', 'note', '', 'origin', 'user'
      )
    ),
    'investmentTransactions', '[]'::jsonb,
    'investmentAdjustments', jsonb_build_array(
      jsonb_build_object(
        'id', 'snap', 'userId', '', 'productId', 'etf',
        'date', '2026-10-01T23:59:59Z', 'quantityMicros', 1100000000,
        'averageCostMinor', 15000, 'reason', '對帳調整', 'origin', 'user'
      )
    ),
    'investmentPriceHistory', '[]'::jsonb, 'orders', '[]'::jsonb,
    'reconciliations', jsonb_build_array(
      jsonb_build_object(
        'id', 'rec-etf', 'userId', '', 'targetType', 'investment',
        'targetId', 'etf', 'date', '2026-10-01T00:00:00Z',
        'bookBalanceMinor', 20000000, 'actualBalanceMinor', 22000000,
        'currency', 'TWD', 'adjustmentId', 'snap', 'note', '股票股利',
        'createdAt', '2026-10-01T08:00:00Z', 'origin', 'user',
        'bookQuantityMicros', 1000000000, 'actualQuantityMicros', 1100000000,
        'bookAverageCostMinor', 16500, 'actualAverageCostMinor', 15000
      )
    )
  ))->>'status',
  'saved',
  'v13 save accepts investment reconciliation records'
);

select is(public.load_finance_data()#>>'{data,schemaVersion}', '13',
  'load reports schema v13');
select is(public.load_finance_data()#>>'{data,reconciliations,0,targetType}',
  'investment', 'investment target type round trips');
select is(
  public.load_finance_data()#>>'{data,reconciliations,0,actualQuantityMicros}',
  '1100000000', 'actual quantity round trips');
select is(
  public.load_finance_data()#>>'{data,reconciliations,0,bookAverageCostMinor}',
  '16500', 'book average cost round trips');

select throws_ok(
  $$select public.save_finance_data(1, jsonb_build_object('schemaVersion', 11))$$,
  'unsupported_schema_version_update_required',
  'older clients cannot drop investment reconciliation details'
);

select * from finish();
rollback;
