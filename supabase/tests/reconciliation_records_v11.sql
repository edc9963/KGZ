begin;
create extension if not exists pgtap with schema extensions;
select plan(7);

insert into auth.users(
  id, instance_id, aud, role, email, encrypted_password,
  email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values (
  '11111111-1111-4111-8111-111111111111',
  '00000000-0000-0000-0000-000000000000',
  'authenticated', 'authenticated', 'reconcile@example.invalid', '',
  now(), '{}', '{}', now(), now()
);

set local role authenticated;
set local request.jwt.claims =
  '{"sub":"11111111-1111-4111-8111-111111111111","role":"authenticated"}';

select is(
  public.save_finance_data(0, jsonb_build_object(
    'schemaVersion', 11, 'settings', '{}'::jsonb,
    'categories', '[]'::jsonb,
    'transactions', jsonb_build_array(
      jsonb_build_object(
        'id', 'balance:adj', 'date', '2026-09-30T00:00:00Z',
        'type', 'balanceAdjustment', 'label', '對帳調整', 'amountMinor', 1500,
        'currency', 'TWD', 'note', '', 'relatedEntityType', 'balanceAdjustment',
        'relatedEntityId', 'adj', 'origin', 'user',
        'impacts', jsonb_build_array(
          jsonb_build_object('accountId', 'bank', 'amountMinor', -1500, 'currency', 'TWD')
        )
      )
    ),
    'accounts', jsonb_build_array(
      jsonb_build_object(
        'id', 'bank', 'name', '銀行', 'institution', '', 'type', '活存',
        'currency', 'TWD', 'openingBalanceMinor', 100000, 'isActive', true,
        'note', '', 'createdAt', '2026-01-01T00:00:00Z',
        'updatedAt', '2026-01-01T00:00:00Z',
        'openingBalanceDate', '2026-01-01T00:00:00Z',
        'kind', 'asset', 'subtype', 'bank', 'origin', 'user'
      )
    ),
    'balanceAdjustments', jsonb_build_array(
      jsonb_build_object(
        'id', 'adj', 'userId', '', 'accountId', 'bank', 'amountMinor', -1500,
        'date', '2026-09-30T00:00:00Z', 'reason', '對帳調整', 'origin', 'user'
      )
    ),
    'expenses', '[]'::jsonb, 'recurringExpenses', '[]'::jsonb,
    'recurringExpenseOccurrences', '[]'::jsonb,
    'telecomBillPayments', '[]'::jsonb, 'incomes', '[]'::jsonb,
    'cards', '[]'::jsonb, 'bills', '[]'::jsonb, 'products', '[]'::jsonb,
    'investmentTransactions', '[]'::jsonb, 'investmentAdjustments', '[]'::jsonb,
    'investmentPriceHistory', '[]'::jsonb, 'orders', '[]'::jsonb,
    'reconciliations', jsonb_build_array(
      jsonb_build_object(
        'id', 'rec', 'userId', '', 'targetType', 'account', 'targetId', 'bank',
        'date', '2026-09-30T00:00:00Z', 'bookBalanceMinor', 100000,
        'actualBalanceMinor', 98500, 'currency', 'TWD', 'adjustmentId', 'adj',
        'note', '手續費', 'createdAt', '2026-09-30T08:00:00Z', 'origin', 'user'
      )
    )
  ))->>'status',
  'saved',
  'v11 save accepts reconciliation records'
);

select is(public.load_finance_data()#>>'{data,schemaVersion}', '11',
  'load reports schema v11');
select is(public.load_finance_data()#>>'{data,reconciliations,0,targetId}', 'bank',
  'reconciliation target round trips');
select is(public.load_finance_data()#>>'{data,reconciliations,0,actualBalanceMinor}', '98500',
  'actual balance round trips');
select is(public.load_finance_data()#>>'{data,reconciliations,0,adjustmentId}', 'adj',
  'adjustment link round trips');

select throws_ok(
  $$select public.save_finance_data(1, jsonb_build_object('schemaVersion', 10))$$,
  'unsupported_schema_version_update_required',
  'older clients cannot wipe reconciliation history'
);

select is(
  public.clear_finance_data(1)->>'status', 'saved',
  'clear removes reconciliation history'
);

select * from finish();
rollback;
