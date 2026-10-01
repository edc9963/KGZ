-- 對帳 (reconciliation) history, schema v11.
--
-- Each row records one check of an account balance or a credit-card bill
-- against the real bank/statement figure: the book amount the app showed,
-- the actual amount the user confirmed, and the adjustment (a
-- balance_adjustments row for accounts, or the bill's
-- `card-bill-reconciliation:` financial transaction for card bills) that
-- booked the difference. target_id is polymorphic (account or bill id), so
-- it has no foreign key; the client drops records whose target is deleted.
--
-- Same rename-then-wrap convention as card_bill_reminder_state.sql (v10):
-- the v10 functions stay frozen and the new top-level functions delegate
-- to them, then read/write the new side table.

create table public.reconciliation_records_v11 (
  user_id uuid not null references auth.users(id) on delete cascade,
  id text not null,
  target_type text not null check (target_type in ('account', 'cardBill')),
  target_id text not null,
  reconciled_at timestamptz not null,
  book_balance_minor bigint not null,
  actual_balance_minor bigint not null,
  currency text not null default 'TWD',
  adjustment_id text,
  note text not null default '',
  created_at timestamptz not null,
  origin text not null default 'user' check (origin in ('user', 'demo')),
  primary key (user_id, id)
);

create index reconciliation_records_v11_target_idx
  on public.reconciliation_records_v11(user_id, target_type, target_id);

alter table public.reconciliation_records_v11 enable row level security;
create policy reconciliation_records_v11_owner_policy
  on public.reconciliation_records_v11 for all to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());

revoke all on public.reconciliation_records_v11 from anon, authenticated;

alter function public.load_finance_data() rename to load_finance_data_v10;
alter function public.save_finance_data(bigint, jsonb)
  rename to save_finance_data_v10;

create or replace function public.load_finance_data()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  uid uuid := auth.uid();
  response jsonb;
  payload jsonb;
begin
  if uid is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  response := public.load_finance_data_v10();
  if response->>'status' <> 'ok' then return response; end if;
  payload := jsonb_set(
    coalesce(response->'data', '{}'::jsonb),
    '{schemaVersion}', '11'::jsonb, true
  );
  payload := jsonb_set(payload, '{reconciliations}', coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', r.id, 'userId', r.user_id::text,
      'targetType', r.target_type, 'targetId', r.target_id,
      'date', r.reconciled_at,
      'bookBalanceMinor', r.book_balance_minor,
      'actualBalanceMinor', r.actual_balance_minor,
      'currency', r.currency, 'adjustmentId', r.adjustment_id,
      'note', r.note, 'createdAt', r.created_at, 'origin', r.origin
    ) order by r.reconciled_at, r.created_at, r.id)
    from public.reconciliation_records_v11 r
    where r.user_id = uid
  ), '[]'::jsonb), true);
  return jsonb_set(response, '{data}', payload, true);
end
$$;

create or replace function public.save_finance_data(
  expected_revision bigint,
  data jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  uid uuid := auth.uid();
  version integer;
  result jsonb;
  legacy_data jsonb;
  item jsonb;
begin
  if uid is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  if jsonb_typeof(data) <> 'object' then
    raise exception 'invalid_finance_data';
  end if;
  version := coalesce((data->>'schemaVersion')::integer, 0);
  if version <> 11 then
    -- An older client would silently wipe the reconciliation history it
    -- does not know about; make it update first instead.
    if exists (
      select 1 from public.reconciliation_records_v11 where user_id = uid
    ) then
      raise exception 'unsupported_schema_version_update_required';
    end if;
    return public.save_finance_data_v10(expected_revision, data);
  end if;

  legacy_data := jsonb_set(data, '{schemaVersion}', '10'::jsonb, true);
  result := public.save_finance_data_v10(expected_revision, legacy_data);
  if result->>'status' = 'conflict' then return result; end if;

  delete from public.reconciliation_records_v11 where user_id = uid;
  for item in select value from jsonb_array_elements(
    coalesce(data->'reconciliations', '[]'::jsonb)
  ) loop
    insert into public.reconciliation_records_v11(
      user_id, id, target_type, target_id, reconciled_at,
      book_balance_minor, actual_balance_minor, currency, adjustment_id,
      note, created_at, origin
    ) values (
      uid,
      item->>'id',
      coalesce(item->>'targetType', 'account'),
      item->>'targetId',
      (item->>'date')::timestamptz,
      coalesce((item->>'bookBalanceMinor')::bigint, 0),
      coalesce((item->>'actualBalanceMinor')::bigint, 0),
      coalesce(item->>'currency', 'TWD'),
      nullif(item->>'adjustmentId', ''),
      coalesce(item->>'note', ''),
      coalesce((item->>'createdAt')::timestamptz, (item->>'date')::timestamptz),
      coalesce(item->>'origin', 'user')
    );
  end loop;
  return result;
end
$$;

create or replace function public.clear_finance_data(expected_revision bigint)
returns jsonb
language sql
security definer
set search_path = public, pg_temp
as $$
  select public.save_finance_data(expected_revision, jsonb_build_object(
    'schemaVersion', 11, 'settings', '{}'::jsonb,
    'categories', '[]'::jsonb, 'transactions', '[]'::jsonb,
    'accounts', '[]'::jsonb, 'balanceAdjustments', '[]'::jsonb,
    'expenses', '[]'::jsonb, 'recurringExpenses', '[]'::jsonb,
    'recurringExpenseOccurrences', '[]'::jsonb,
    'telecomBillPayments', '[]'::jsonb, 'incomes', '[]'::jsonb,
    'cards', '[]'::jsonb, 'bills', '[]'::jsonb,
    'products', '[]'::jsonb, 'investmentTransactions', '[]'::jsonb,
    'investmentAdjustments', '[]'::jsonb,
    'investmentPriceHistory', '[]'::jsonb, 'orders', '[]'::jsonb,
    'reconciliations', '[]'::jsonb
  ));
$$;

revoke all on function public.load_finance_data_v10() from public, anon, authenticated;
revoke all on function public.save_finance_data_v10(bigint, jsonb)
  from public, anon, authenticated;
revoke all on function public.load_finance_data() from public;
revoke all on function public.save_finance_data(bigint, jsonb) from public;
revoke all on function public.clear_finance_data(bigint) from public;
grant execute on function public.load_finance_data() to authenticated;
grant execute on function public.save_finance_data(bigint, jsonb)
  to authenticated;
grant execute on function public.clear_finance_data(bigint) to authenticated;
