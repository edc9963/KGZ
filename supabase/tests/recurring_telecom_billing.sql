begin;
create extension if not exists pgtap with schema extensions;
select plan(10);

insert into auth.users(
  id, instance_id, aud, role, email, encrypted_password,
  email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values (
  '44444444-4444-4444-8444-444444444444',
  '00000000-0000-0000-0000-000000000000',
  'authenticated', 'authenticated', 'recurring@example.invalid', '',
  now(), '{}', '{}', now(), now()
);

insert into public.accounts(
  user_id, id, name, institution, account_type, currency,
  opening_balance_minor, is_active, note, created_at, updated_at, origin
) values (
  '44444444-4444-4444-8444-444444444444', 'bank', '銀行', '', '銀行帳戶',
  'TWD', 60000, true, '', '2026-01-01T00:00:00Z',
  '2026-01-01T00:00:00Z', 'user'
);

insert into public.finance_sync_state(user_id, revision) values
  ('44444444-4444-4444-8444-444444444444', 0);

insert into public.recurring_expenses(
  user_id, id, item, category, amount_minor, payment_method,
  day_of_month, start_month, telecom_debit_account_id,
  is_active, is_necessary, note, origin
) values (
  '44444444-4444-4444-8444-444444444444', 'phone', '手機月租', '訂閱',
  59900, 'telecomBill', 31, '2026-08', 'bank', true, true, '', 'user'
);

insert into public.expenses(
  user_id, id, expense_date, amount_minor, payment_method, item, category,
  account_id, card_id, bill_id, merchant, note, is_necessary, origin
) values
  ('44444444-4444-4444-8444-444444444444', 'purchase-before-due',
   '2026-08-05T00:00:00Z', 10000, 'telecomBill', 'App 代收', '娛樂',
   null, null, null, '', '', false, 'user'),
  ('44444444-4444-4444-8444-444444444444', 'purchase-on-due',
   '2026-08-30T16:00:00Z', 5000, 'telecomBill', '繳費日代收', '娛樂',
   null, null, null, '', '', false, 'user');

select is(
  public.process_due_recurring_expenses('2026-08-31'::date),
  1,
  'one due recurring rule is processed'
);
select is(
  (select count(*) from public.recurring_expense_occurrences
   where user_id = '44444444-4444-4444-8444-444444444444'),
  1::bigint,
  'one occurrence is generated'
);
select is(
  (select amount_minor from public.telecom_bill_payments
   where user_id = '44444444-4444-4444-8444-444444444444'),
  69900::bigint,
  'payment combines the monthly fee and prior-cycle purchase'
);
select is(
  (select count(*) from public.telecom_bill_expenses
   where user_id = '44444444-4444-4444-8444-444444444444'),
  2::bigint,
  'payment links exactly the monthly fee and prior-cycle purchase'
);
select ok(
  not exists(select 1 from public.telecom_bill_expenses
    where user_id = '44444444-4444-4444-8444-444444444444'
      and expense_id = 'purchase-on-due'),
  'purchase on the due day rolls into the next cycle'
);
select ok(
  (select balance_insufficient from public.telecom_bill_payments
   where user_id = '44444444-4444-4444-8444-444444444444'),
  'insufficient balance is recorded without blocking payment'
);
select is(
  (select revision from public.finance_sync_state
   where user_id = '44444444-4444-4444-8444-444444444444'),
  1::bigint,
  'scheduled processing increments the sync revision'
);
select is(
  public.process_due_recurring_expenses('2026-08-31'::date),
  0,
  're-running the schedule is idempotent'
);
select throws_like(
  $$insert into public.recurring_expenses(
      user_id, id, item, category, amount_minor, payment_method,
      day_of_month, start_month, telecom_debit_account_id,
      is_active, is_necessary, note, origin
    ) values (
      '44444444-4444-4444-8444-444444444444', 'phone-2', '第二門號', '訂閱',
      39900, 'telecomBill', 10, '2026-08', 'bank', true, true, '', 'user'
    )$$,
  '%duplicate key value violates unique constraint%',
  'only one active telecom rule is allowed per user'
);
select ok(
  not has_function_privilege(
    'authenticated', 'public.process_due_recurring_expenses(date)', 'execute'
  ),
  'authenticated clients cannot run the scheduler directly'
);

select * from finish();
rollback;
