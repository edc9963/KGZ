-- 投資對帳 (investment reconciliation), schema v13.
--
-- An investment record checks one product's holding against the broker:
-- target_id is the product id, adjustment_id the investment_adjustments
-- snapshot that reset the holding to the broker's figures. Besides the
-- market values already stored in book/actual_balance_minor, it keeps the
-- units and average cost on both sides, which need four new columns.
--
-- save_finance_data_v11 inserts an explicit column list, so it keeps
-- working unchanged with the new nullable columns; the new top-level
-- functions wrap it (rename-then-wrap, as in v9-v11) and read/write the
-- extra columns. Older clients don't know these fields (and builds before
-- this one fail to parse the 'investment' type), so they are refused once
-- investment records exist.

alter table public.reconciliation_records_v11
  drop constraint reconciliation_records_v11_target_type_check;
alter table public.reconciliation_records_v11
  add constraint reconciliation_records_v11_target_type_check
  check (target_type in ('account', 'cardBill', 'telecomBill', 'investment'));

alter table public.reconciliation_records_v11
  add column book_quantity_micros bigint,
  add column actual_quantity_micros bigint,
  add column book_average_cost_minor bigint,
  add column actual_average_cost_minor bigint;

alter function public.load_finance_data() rename to load_finance_data_v11;
alter function public.save_finance_data(bigint, jsonb)
  rename to save_finance_data_v11;

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
  response := public.load_finance_data_v11();
  if response->>'status' <> 'ok' then return response; end if;
  payload := jsonb_set(
    coalesce(response->'data', '{}'::jsonb),
    '{schemaVersion}', '13'::jsonb, true
  );
  payload := jsonb_set(payload, '{reconciliations}', coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', r.id, 'userId', r.user_id::text,
      'targetType', r.target_type, 'targetId', r.target_id,
      'date', r.reconciled_at,
      'bookBalanceMinor', r.book_balance_minor,
      'actualBalanceMinor', r.actual_balance_minor,
      'currency', r.currency, 'adjustmentId', r.adjustment_id,
      'note', r.note, 'createdAt', r.created_at, 'origin', r.origin,
      'bookQuantityMicros', r.book_quantity_micros,
      'actualQuantityMicros', r.actual_quantity_micros,
      'bookAverageCostMinor', r.book_average_cost_minor,
      'actualAverageCostMinor', r.actual_average_cost_minor
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
  if version <> 13 then
    if exists (
      select 1 from public.reconciliation_records_v11
      where user_id = uid and target_type = 'investment'
    ) then
      raise exception 'unsupported_schema_version_update_required';
    end if;
    return public.save_finance_data_v11(expected_revision, data);
  end if;

  legacy_data := jsonb_set(data, '{schemaVersion}', '11'::jsonb, true);
  result := public.save_finance_data_v11(expected_revision, legacy_data);
  if result->>'status' = 'conflict' then return result; end if;

  for item in select value from jsonb_array_elements(
    coalesce(data->'reconciliations', '[]'::jsonb)
  ) loop
    update public.reconciliation_records_v11 set
      book_quantity_micros = (item->>'bookQuantityMicros')::bigint,
      actual_quantity_micros = (item->>'actualQuantityMicros')::bigint,
      book_average_cost_minor = (item->>'bookAverageCostMinor')::bigint,
      actual_average_cost_minor = (item->>'actualAverageCostMinor')::bigint
    where user_id = uid and id = item->>'id';
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
    'schemaVersion', 13, 'settings', '{}'::jsonb,
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

revoke all on function public.load_finance_data_v11() from public, anon, authenticated;
revoke all on function public.save_finance_data_v11(bigint, jsonb)
  from public, anon, authenticated;
revoke all on function public.load_finance_data() from public;
revoke all on function public.save_finance_data(bigint, jsonb) from public;
revoke all on function public.clear_finance_data(bigint) from public;
grant execute on function public.load_finance_data() to authenticated;
grant execute on function public.save_finance_data(bigint, jsonb)
  to authenticated;
grant execute on function public.clear_finance_data(bigint) to authenticated;
