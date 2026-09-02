begin;
create extension if not exists pgtap with schema extensions;
select plan(9);

insert into auth.users(
  id, instance_id, aud, role, email, encrypted_password,
  email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values (
  '77777777-7777-4777-8777-777777777777',
  '00000000-0000-0000-0000-000000000000',
  'authenticated', 'authenticated', 'ledger@example.invalid', '',
  now(), '{}', '{}', now(), now()
);

set local role authenticated;
set local request.jwt.claims =
  '{"sub":"77777777-7777-4777-8777-777777777777","role":"authenticated"}';

select is(
  public.save_finance_data(0, jsonb_build_object(
    'schemaVersion', 7,
    'settings', jsonb_build_object(
      'defaultCategory', '餐飲',
      'defaultExpenseCategoryId', 'expense-food'
    ),
    'categories', jsonb_build_array(jsonb_build_object(
      'id', 'expense-food', 'name', '餐飲', 'kind', 'expense',
      'iconKey', 'restaurant', 'colorKey', 'coral', 'sortOrder', 0,
      'isActive', true, 'isBuiltIn', true
    )),
    'transactions', jsonb_build_array(jsonb_build_object(
      'id', 'expense:lunch', 'date', '2026-08-11T04:00:00Z',
      'type', 'expense', 'label', '午餐', 'amountMinor', 12000,
      'currency', 'TWD', 'categoryId', 'expense-food', 'note', '',
      'relatedEntityType', 'expense', 'relatedEntityId', 'lunch',
      'origin', 'user', 'impacts', jsonb_build_array(jsonb_build_object(
        'accountId', 'bank', 'amountMinor', -12000, 'currency', 'TWD'
      ))
    )),
    'accounts', jsonb_build_array(jsonb_build_object(
      'id', 'bank', 'name', '銀行', 'institution', '',
      'type', '銀行帳戶', 'kind', 'asset', 'subtype', 'bank',
      'currency', 'TWD', 'openingBalanceMinor', 100000,
      'isActive', true, 'note', '',
      'createdAt', '2026-08-01T00:00:00Z',
      'updatedAt', '2026-08-01T00:00:00Z', 'origin', 'user'
    )),
    'balanceAdjustments', '[]'::jsonb,
    'expenses', jsonb_build_array(jsonb_build_object(
      'id', 'lunch', 'date', '2026-08-11T04:00:00Z',
      'amountMinor', 12000, 'paymentMethod', 'debitCard', 'item', '午餐',
      'category', '餐飲', 'accountId', 'bank', 'cardId', 'debit-card', 'merchant', '',
      'note', '', 'isNecessary', false, 'origin', 'user'
    )),
    'recurringExpenses', '[]'::jsonb,
    'recurringExpenseOccurrences', '[]'::jsonb,
    'telecomBillPayments', '[]'::jsonb, 'incomes', '[]'::jsonb,
    'cards', jsonb_build_array(jsonb_build_object(
      'id', 'debit-card', 'name', '日常金融卡', 'bank', '銀行',
      'lastFour', '5678', 'closingDay', 1, 'dueDay', 1,
      'autoDebitDay', 1, 'debitAccountId', 'bank',
      'isActive', true, 'note', '', 'origin', 'user',
      'cardType', 'debit'
    )), 'bills', '[]'::jsonb,
    'products', '[]'::jsonb, 'investmentTransactions', '[]'::jsonb,
    'investmentAdjustments', '[]'::jsonb,
    'investmentPriceHistory', '[]'::jsonb, 'orders', '[]'::jsonb
  ))->>'status',
  'saved',
  'v7 snapshot saves atomically'
);

select is(public.load_finance_data()#>>'{data,schemaVersion}', '9',
  'load returns the current schema after upgrade');
select is(public.load_finance_data()#>>'{data,categories,0,name}', '餐飲',
  'category round trips');
select is(public.load_finance_data()#>>'{data,accounts,0,kind}', 'asset',
  'financial account kind round trips');
select is(
  public.load_finance_data()#>>'{data,transactions,0,impacts,0,amountMinor}',
  '-12000', 'signed account impact round trips'
);
select is(public.load_finance_data()#>>'{data,cards,0,cardType}', 'debit',
  'debit card type round trips');
select is(public.load_finance_data()#>>'{data,cards,0,debitAccountId}', 'bank',
  'debit card keeps its directly linked account');
select throws_like(
  $$select public.save_finance_data(1, '{"schemaVersion":6}'::jsonb)$$,
  '%unsupported_schema_version_update_required%',
  'old client cannot overwrite an upgraded user'
);
select is(public.clear_finance_data(1)->>'status', 'saved',
  'clear accepts schema v7 data');

select * from finish();
rollback;
