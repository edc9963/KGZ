-- Credit-card statement reconciliation metadata. Payment history continues to
-- use the v7 unified financial transaction tables.

create table public.card_bill_reconciliation_v9 (
  user_id uuid not null,
  bill_id text not null,
  statement_amount_minor bigint not null check (statement_amount_minor >= 0),
  reconciliation_reason text not null default 'none',
  reconciliation_note text not null default '',
  auto_debit_state text not null default 'pending'
    check (auto_debit_state in ('pending', 'succeeded', 'failed')),
  primary key (user_id, bill_id),
  foreign key (user_id, bill_id)
    references public.card_bills(user_id, id) on delete cascade
    deferrable initially deferred
);

alter table public.card_bill_reconciliation_v9 enable row level security;
create policy card_bill_reconciliation_v9_owner_policy
  on public.card_bill_reconciliation_v9 for all to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());

revoke all on public.card_bill_reconciliation_v9 from anon, authenticated;

alter function public.load_finance_data() rename to load_finance_data_v8;
alter function public.save_finance_data(bigint, jsonb)
  rename to save_finance_data_v8;

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
  rebuilt jsonb;
begin
  if uid is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  response := public.load_finance_data_v8();
  payload := jsonb_set(
    coalesce(response->'data', '{}'::jsonb),
    '{schemaVersion}', '9'::jsonb, true
  );
  select coalesce(jsonb_agg(
    bill_item || jsonb_build_object(
      'statementAmountMinor', coalesce(
        metadata.statement_amount_minor,
        greatest(
          0,
          coalesce((bill_item->>'manualAdjustmentMinor')::bigint, 0) +
          coalesce((select sum((expense_item->>'amountMinor')::bigint)
            from jsonb_array_elements(coalesce(payload->'expenses', '[]'::jsonb)) expense_item
            where ('expense:' || (expense_item->>'id')) in (
              select jsonb_array_elements_text(coalesce(bill_item->'chargeIds', '[]'::jsonb))
            )), 0) +
          coalesce((select sum((order_item->>'totalMinor')::bigint)
            from jsonb_array_elements(coalesce(payload->'orders', '[]'::jsonb)) order_item
            where ('order:' || (order_item->>'id')) in (
              select jsonb_array_elements_text(coalesce(bill_item->'chargeIds', '[]'::jsonb))
            )), 0)
        )
      ),
      'reconciliationReason', coalesce(
        metadata.reconciliation_reason,
        case when coalesce((bill_item->>'manualAdjustmentMinor')::bigint, 0) = 0
          then 'none' else 'legacyAdjustment' end
      ),
      'reconciliationNote', coalesce(metadata.reconciliation_note, ''),
      'autoDebitState', coalesce(metadata.auto_debit_state, 'pending')
    ) order by bill_item->>'month', bill_item->>'id'
  ), '[]'::jsonb)
  into rebuilt
  from jsonb_array_elements(coalesce(payload->'bills', '[]'::jsonb)) bill_item
  left join public.card_bill_reconciliation_v9 metadata
    on metadata.user_id = uid and metadata.bill_id = bill_item->>'id';
  payload := jsonb_set(payload, '{bills}', rebuilt, true);
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
  if version <> 9 then
    if exists (
      select 1 from public.card_bill_reconciliation_v9 where user_id = uid
    ) then
      raise exception 'unsupported_schema_version_update_required';
    end if;
    return public.save_finance_data_v8(expected_revision, data);
  end if;

  legacy_data := jsonb_set(data, '{schemaVersion}', '8'::jsonb, true);
  result := public.save_finance_data_v8(expected_revision, legacy_data);
  if result->>'status' = 'conflict' then return result; end if;

  for item in select value from jsonb_array_elements(
    coalesce(data->'bills', '[]'::jsonb)
  ) loop
    insert into public.card_bill_reconciliation_v9 values (
      uid,
      item->>'id',
      greatest(0, coalesce((item->>'statementAmountMinor')::bigint, 0)),
      coalesce(item->>'reconciliationReason', 'none'),
      coalesce(item->>'reconciliationNote', ''),
      coalesce(item->>'autoDebitState', 'pending')
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
    'schemaVersion', 9, 'settings', '{}'::jsonb,
    'categories', '[]'::jsonb, 'transactions', '[]'::jsonb,
    'accounts', '[]'::jsonb, 'balanceAdjustments', '[]'::jsonb,
    'expenses', '[]'::jsonb, 'recurringExpenses', '[]'::jsonb,
    'recurringExpenseOccurrences', '[]'::jsonb,
    'telecomBillPayments', '[]'::jsonb, 'incomes', '[]'::jsonb,
    'cards', '[]'::jsonb, 'bills', '[]'::jsonb,
    'products', '[]'::jsonb, 'investmentTransactions', '[]'::jsonb,
    'investmentAdjustments', '[]'::jsonb,
    'investmentPriceHistory', '[]'::jsonb, 'orders', '[]'::jsonb
  ));
$$;

revoke all on function public.load_finance_data_v8() from public, anon, authenticated;
revoke all on function public.save_finance_data_v8(bigint, jsonb)
  from public, anon, authenticated;
revoke all on function public.load_finance_data() from public;
revoke all on function public.save_finance_data(bigint, jsonb) from public;
revoke all on function public.clear_finance_data(bigint) from public;
grant execute on function public.load_finance_data() to authenticated;
grant execute on function public.save_finance_data(bigint, jsonb) to authenticated;
grant execute on function public.clear_finance_data(bigint) to authenticated;
