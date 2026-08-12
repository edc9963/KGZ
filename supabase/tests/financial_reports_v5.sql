begin;
create extension if not exists pgtap with schema extensions;
select plan(6);

insert into auth.users(
  id, instance_id, aud, role, email, encrypted_password,
  email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values (
  '33333333-3333-4333-8333-333333333333',
  '00000000-0000-0000-0000-000000000000',
  'authenticated', 'authenticated', 'reports@example.invalid', '',
  now(), '{}', '{}', now(), now()
);

set local role authenticated;
set local request.jwt.claims =
  '{"sub":"33333333-3333-4333-8333-333333333333","role":"authenticated"}';

select throws_like(
  $$select public.save_finance_data(0, '{"schemaVersion":5}'::jsonb)$$,
  '%unsupported_schema_version_update_required%',
  'v5 clients cannot overwrite v6 finance data'
);

select is(
  public.save_finance_data(
    0,
    jsonb_build_object(
      'schemaVersion', 6,
      'settings', jsonb_build_object(),
      'accounts', jsonb_build_array(jsonb_build_object(
        'id', 'bank', 'name', '銀行', 'institution', '',
        'type', '銀行帳戶', 'currency', 'TWD',
        'openingBalanceMinor', 100000, 'isActive', true, 'note', '',
        'createdAt', '2026-01-01T00:00:00Z',
        'updatedAt', '2026-01-01T00:00:00Z',
        'openingBalanceDate', '2026-01-01T00:00:00Z', 'origin', 'user'
      )),
      'balanceAdjustments', '[]'::jsonb,
      'expenses', '[]'::jsonb,
      'recurringExpenses', '[]'::jsonb,
      'recurringExpenseOccurrences', '[]'::jsonb,
      'telecomBillPayments', '[]'::jsonb,
      'incomes', jsonb_build_array(jsonb_build_object(
        'id', 'salary', 'date', '2026-01-10T00:00:00Z',
        'amountMinor', 50000, 'item', '薪資', 'category', '薪資',
        'accountId', 'bank', 'note', '', 'origin', 'user'
      )),
      'cards', '[]'::jsonb,
      'bills', '[]'::jsonb,
      'products', '[]'::jsonb,
      'investmentTransactions', '[]'::jsonb,
      'investmentAdjustments', '[]'::jsonb,
      'investmentPriceHistory', '[]'::jsonb,
      'orders', '[]'::jsonb
    )
  )->>'status',
  'saved',
  'v6 payload saves atomically'
);

select is(
  public.load_finance_data()#>>'{data,schemaVersion}',
  '6',
  'load returns schema v6'
);

select is(
  public.load_finance_data()#>>'{data,incomes,0,item}',
  '薪資',
  'income round trips through the wrapper'
);

select is(
  public.load_finance_data()#>>'{data,accounts,0,openingBalanceDate}',
  '2026-01-01T00:00:00+00:00',
  'opening balance date round trips'
);

select is(
  public.clear_finance_data(1)->>'status',
  'saved',
  'clear accepts and persists an empty v6 payload'
);

select * from finish();
rollback;
