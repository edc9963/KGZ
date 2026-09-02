begin;
create extension if not exists pgtap with schema extensions;
select plan(7);

insert into auth.users(
  id, instance_id, aud, role, email, encrypted_password,
  email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values (
  '99999999-9999-4999-8999-999999999999',
  '00000000-0000-0000-0000-000000000000',
  'authenticated', 'authenticated', 'bills@example.invalid', '',
  now(), '{}', '{}', now(), now()
);

set local role authenticated;
set local request.jwt.claims =
  '{"sub":"99999999-9999-4999-8999-999999999999","role":"authenticated"}';

select is(
  public.save_finance_data(0, jsonb_build_object(
    'schemaVersion', 9, 'settings', '{}'::jsonb,
    'categories', '[]'::jsonb,
    'transactions', jsonb_build_array(
      jsonb_build_object(
        'id', 'card-payment:bill:first', 'date', '2026-09-10T00:00:00Z',
        'type', 'cardPayment', 'label', '部分繳款', 'amountMinor', 4000,
        'currency', 'TWD', 'note', '', 'relatedEntityType', 'cardBill',
        'relatedEntityId', 'bill', 'origin', 'user',
        'impacts', jsonb_build_array(
          jsonb_build_object('accountId', 'bank', 'amountMinor', -4000, 'currency', 'TWD'),
          jsonb_build_object('accountId', 'liability', 'amountMinor', -4000, 'currency', 'TWD')
        )
      ),
      jsonb_build_object(
        'id', 'card-payment:bill:second', 'date', '2026-09-12T00:00:00Z',
        'type', 'cardPayment', 'label', '部分繳款', 'amountMinor', 3000,
        'currency', 'TWD', 'note', '', 'relatedEntityType', 'cardBill',
        'relatedEntityId', 'bill', 'origin', 'user',
        'impacts', jsonb_build_array(
          jsonb_build_object('accountId', 'bank', 'amountMinor', -3000, 'currency', 'TWD'),
          jsonb_build_object('accountId', 'liability', 'amountMinor', -3000, 'currency', 'TWD')
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
      ),
      jsonb_build_object(
        'id', 'liability', 'name', '核對卡未繳', 'institution', '',
        'type', '信用卡負債', 'currency', 'TWD', 'openingBalanceMinor', 0,
        'isActive', true, 'note', '', 'createdAt', '2026-01-01T00:00:00Z',
        'updatedAt', '2026-01-01T00:00:00Z',
        'openingBalanceDate', '2026-01-01T00:00:00Z',
        'kind', 'liability', 'subtype', 'creditCard', 'origin', 'user'
      )
    ),
    'balanceAdjustments', '[]'::jsonb, 'expenses', '[]'::jsonb,
    'recurringExpenses', '[]'::jsonb,
    'recurringExpenseOccurrences', '[]'::jsonb,
    'telecomBillPayments', '[]'::jsonb, 'incomes', '[]'::jsonb,
    'cards', jsonb_build_array(jsonb_build_object(
      'id', 'card', 'name', '核對卡', 'bank', '銀行', 'lastFour', '1234',
      'closingDay', 15, 'dueDay', 28, 'autoDebitDay', 28,
      'debitAccountId', 'bank', 'isActive', true, 'note', '',
      'cardType', 'credit', 'liabilityAccountId', 'liability', 'origin', 'user'
    )),
    'bills', jsonb_build_array(jsonb_build_object(
      'id', 'bill', 'cardId', 'card', 'month', '2026-08',
      'chargeIds', '[]'::jsonb, 'manualAdjustmentMinor', 0,
      'paidMinor', 7000, 'dueDate', '2026-09-15T00:00:00Z',
      'autoDebitDate', '2026-09-15T00:00:00Z', 'note', '',
      'paidAt', '2026-09-12T00:00:00Z', 'origin', 'user',
      'statementAmountMinor', 12000,
      'reconciliationReason', 'feeOrInterest',
      'reconciliationNote', '年費', 'autoDebitState', 'failed'
    )),
    'products', '[]'::jsonb, 'investmentTransactions', '[]'::jsonb,
    'investmentAdjustments', '[]'::jsonb,
    'investmentPriceHistory', '[]'::jsonb, 'orders', '[]'::jsonb
  ))->>'status',
  'saved', 'v9 statement saves atomically'
);

select is(public.load_finance_data()#>>'{data,schemaVersion}', '9',
  'load returns schema v9');
select is(public.load_finance_data()#>>'{data,bills,0,statementAmountMinor}', '12000',
  'actual statement amount round trips');
select is(public.load_finance_data()#>>'{data,bills,0,reconciliationReason}', 'feeOrInterest',
  'reconciliation reason round trips');
select is(public.load_finance_data()#>>'{data,bills,0,autoDebitState}', 'failed',
  'auto-debit state round trips');
select is((select count(*)::text from public.financial_transactions
  where user_id = auth.uid() and related_entity_id = 'bill'), '2',
  'multiple payment transactions persist');
select is((select sum(amount_minor)::text from public.financial_transactions
  where user_id = auth.uid() and related_entity_id = 'bill'), '7000',
  'payment amounts round trip without aggregation loss');

select * from finish();
rollback;
