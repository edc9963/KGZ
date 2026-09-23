-- Per-bill "I've seen this auto-debit reminder" flag, plus the server-side
-- pieces the new LINE push reminder (supabase/functions/card-bill-reminders)
-- and its LINE quick-reply acknowledgement need.
--
-- This is a new side table (schema v10) rather than a new column on
-- card_bill_reconciliation_v9 (v9), because save_finance_data_v9's body
-- does a fixed positional `insert into card_bill_reconciliation_v9 values
-- (...)` - adding a column to that table would break that insert's column
-- count for every save, not just new ones. A fresh table sidesteps that.

create table public.card_bill_reminder_state (
  user_id uuid not null,
  bill_id text not null,
  reminder_dismissed boolean not null default false,
  primary key (user_id, bill_id),
  foreign key (user_id, bill_id)
    references public.card_bills(user_id, id) on delete cascade
    deferrable initially deferred
);

alter table public.card_bill_reminder_state enable row level security;
create policy card_bill_reminder_state_owner_policy
  on public.card_bill_reminder_state for all to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());

revoke all on public.card_bill_reminder_state from anon, authenticated;

alter function public.load_finance_data() rename to load_finance_data_v9;
alter function public.save_finance_data(bigint, jsonb)
  rename to save_finance_data_v9;

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
  response := public.load_finance_data_v9();
  if response->>'status' <> 'ok' then return response; end if;
  payload := jsonb_set(
    coalesce(response->'data', '{}'::jsonb),
    '{schemaVersion}', '10'::jsonb, true
  );
  select coalesce(jsonb_agg(
    bill_item || jsonb_build_object(
      'reminderDismissed', coalesce(state.reminder_dismissed, false)
    ) order by bill_item->>'month', bill_item->>'id'
  ), '[]'::jsonb)
  into rebuilt
  from jsonb_array_elements(coalesce(payload->'bills', '[]'::jsonb)) bill_item
  left join public.card_bill_reminder_state state
    on state.user_id = uid and state.bill_id = bill_item->>'id';
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
  if version <> 10 then
    if exists (
      select 1 from public.card_bill_reminder_state where user_id = uid
    ) then
      raise exception 'unsupported_schema_version_update_required';
    end if;
    return public.save_finance_data_v9(expected_revision, data);
  end if;

  legacy_data := jsonb_set(data, '{schemaVersion}', '9'::jsonb, true);
  result := public.save_finance_data_v9(expected_revision, legacy_data);
  if result->>'status' = 'conflict' then return result; end if;

  delete from public.card_bill_reminder_state where user_id = uid;
  for item in select value from jsonb_array_elements(
    coalesce(data->'bills', '[]'::jsonb)
  ) loop
    if coalesce((item->>'reminderDismissed')::boolean, false) then
      insert into public.card_bill_reminder_state(
        user_id, bill_id, reminder_dismissed
      ) values (uid, item->>'id', true);
    end if;
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
    'schemaVersion', 10, 'settings', '{}'::jsonb,
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

revoke all on function public.load_finance_data_v9() from public, anon, authenticated;
revoke all on function public.save_finance_data_v9(bigint, jsonb)
  from public, anon, authenticated;
revoke all on function public.load_finance_data() from public;
revoke all on function public.save_finance_data(bigint, jsonb) from public;
revoke all on function public.clear_finance_data(bigint) from public;
grant execute on function public.load_finance_data() to authenticated;
grant execute on function public.save_finance_data(bigint, jsonb)
  to authenticated;
grant execute on function public.clear_finance_data(bigint) to authenticated;

-- ---------------------------------------------------------------------
-- Server-side support for the LINE push reminder (cron-triggered edge
-- function) and its LINE quick-reply "confirm, don't remind me again"
-- acknowledgement. Both are server-only, same convention as line_bot.sql.
-- ---------------------------------------------------------------------

-- A bill's charge total before any manual reconciliation override: manual
-- adjustment + everything currently attributed to it via
-- card_bill_expenses / card_bill_orders. This is the exact fallback
-- formula load_finance_data() (card_billing_v9.sql) inlines when building
-- each bill's statementAmountMinor for the client. Factored out here so
-- card_bill_reminder_candidates below doesn't carry its own second copy -
-- load_finance_data_v9's own body is left untouched (it's meant to stay a
-- frozen snapshot, per this repo's rename-then-wrap convention), since in
-- steady state every bill already has a saved statement_amount_minor and
-- this fallback rarely actually runs; the client always writes one on
-- save (see CardsManager.upsertBill), so this only matters for bills that
-- somehow never went through that path (e.g. pre-v9 data).
create or replace function public.card_bill_calculated_amount_minor(
  p_user_id uuid,
  p_bill_id text
)
returns bigint
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select coalesce(b.manual_adjustment_minor, 0)
    + coalesce((
        select sum(e.amount_minor) from public.card_bill_expenses cbe
        join public.expenses e
          on e.user_id = cbe.user_id and e.id = cbe.expense_id
        where cbe.user_id = p_user_id and cbe.bill_id = p_bill_id
      ), 0)
    + coalesce((
        select sum(o.total_minor) from public.card_bill_orders cbo
        join public.group_orders o
          on o.user_id = cbo.user_id and o.id = cbo.order_id
        where cbo.user_id = p_user_id and cbo.bill_id = p_bill_id
      ), 0)
  from public.card_bills b
  where b.user_id = p_user_id and b.id = p_bill_id;
$$;

-- Bills the daily reminder sweep should push today: outstanding balance,
-- not dismissed, and the owner has an enabled LINE account link. Mirrors
-- the same three cases the in-app reminder list shows (see
-- LedgerQueries.reminders): auto-debit already failed, bill overdue, or
-- auto-debit date is 3/1/0 days away.
create or replace function public.card_bill_reminder_candidates(
  p_reference_date date default current_date
)
returns table (
  bill_id text,
  user_id uuid,
  line_user_id text,
  card_name text,
  bill_month text,
  auto_debit_date date,
  due_date date,
  outstanding_minor bigint,
  kind text
)
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select
    b.id, b.user_id, link.line_user_id, c.name, b.bill_month,
    b.auto_debit_date::date, b.due_date::date,
    greatest(0,
      coalesce(
        rec.statement_amount_minor,
        public.card_bill_calculated_amount_minor(b.user_id, b.id)
      ) - b.paid_minor
    ),
    case
      when coalesce(rec.auto_debit_state, 'pending') = 'failed'
        then 'debit_failed'
      when p_reference_date > b.due_date::date then 'overdue'
      else 'debit_soon'
    end
  from public.card_bills b
  join public.credit_cards c on c.user_id = b.user_id and c.id = b.card_id
  left join public.card_bill_reconciliation_v9 rec
    on rec.user_id = b.user_id and rec.bill_id = b.id
  left join public.card_bill_reminder_state state
    on state.user_id = b.user_id and state.bill_id = b.id
  join public.line_account_links link
    on link.user_id = b.user_id and link.enabled
  where greatest(0,
      coalesce(
        rec.statement_amount_minor,
        public.card_bill_calculated_amount_minor(b.user_id, b.id)
      ) - b.paid_minor
    ) > 0
    and (
      -- Failed/overdue alerts are never suppressed by reminder_dismissed:
      -- that flag only means "I've seen the upcoming-auto-debit heads-up",
      -- matching LedgerQueries.reminders on the client, where the
      -- dismissed check only guards the debit_soon branch below.
      coalesce(rec.auto_debit_state, 'pending') = 'failed'
      or p_reference_date > b.due_date::date
      or (
        coalesce(state.reminder_dismissed, false) = false
        and (b.auto_debit_date::date - p_reference_date) in (0, 1, 3)
      )
    );
$$;

-- Called from the LINE webhook when the user taps the reminder's "確認，
-- 這筆帳單不用再提醒" quick reply.
create or replace function public.line_acknowledge_bill_reminder(
  p_line_user_id text,
  p_bill_id text
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  uid uuid := public.line_linked_owner_id(p_line_user_id);
  card_name text;
  bill_month text;
begin
  if uid is null then
    return jsonb_build_object('status', 'not_linked');
  end if;
  select c.name, b.bill_month into card_name, bill_month
  from public.card_bills b
  join public.credit_cards c on c.user_id = b.user_id and c.id = b.card_id
  where b.user_id = uid and b.id = p_bill_id;
  if card_name is null then
    return jsonb_build_object('status', 'not_found');
  end if;
  insert into public.card_bill_reminder_state(user_id, bill_id, reminder_dismissed)
  values (uid, p_bill_id, true)
  on conflict (user_id, bill_id) do update set reminder_dismissed = true;
  return jsonb_build_object(
    'status', 'saved', 'cardName', card_name, 'billMonth', bill_month
  );
end
$$;

do $$
declare
  signature text;
begin
  foreach signature in array array[
    'card_bill_calculated_amount_minor(uuid,text)',
    'card_bill_reminder_candidates(date)',
    'line_acknowledge_bill_reminder(text,text)'
  ]
  loop
    execute format('revoke all on function public.%s from public', signature);
    execute format('grant execute on function public.%s to service_role', signature);
  end loop;
end
$$;
