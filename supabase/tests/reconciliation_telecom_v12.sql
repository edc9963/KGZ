begin;
create extension if not exists pgtap with schema extensions;
select plan(2);

insert into auth.users(
  id, instance_id, aud, role, email, encrypted_password,
  email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values (
  '22222222-2222-4222-8222-222222222222',
  '00000000-0000-0000-0000-000000000000',
  'authenticated', 'authenticated', 'telecom-reconcile@example.invalid', '',
  now(), '{}', '{}', now(), now()
);

select lives_ok(
  $$insert into public.reconciliation_records_v11(
      user_id, id, target_type, target_id, reconciled_at,
      book_balance_minor, actual_balance_minor, adjustment_id, created_at
    ) values (
      '22222222-2222-4222-8222-222222222222', 'rec-telecom', 'telecomBill',
      'telecom-payment-1', now(), 59900, 61200, 'adj-telecom', now()
    )$$,
  'telecomBill reconciliation records are accepted'
);

select throws_ok(
  $$insert into public.reconciliation_records_v11(
      user_id, id, target_type, target_id, reconciled_at,
      book_balance_minor, actual_balance_minor, created_at
    ) values (
      '22222222-2222-4222-8222-222222222222', 'rec-bad', 'somethingElse',
      'x', now(), 0, 0, now()
    )$$,
  '23514',
  null,
  'unknown target types are still rejected'
);

select * from finish();
rollback;
