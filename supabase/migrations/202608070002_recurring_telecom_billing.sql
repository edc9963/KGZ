-- Monthly recurring expenses and carrier billing (finance schema v6).

create table public.recurring_expenses (
  user_id uuid not null references auth.users(id) on delete cascade,
  id text not null,
  item text not null,
  category text not null,
  amount_minor bigint not null check (amount_minor > 0),
  payment_method text not null,
  day_of_month integer not null check (day_of_month between 1 and 31),
  start_month text not null check (start_month ~ '^\d{4}-(0[1-9]|1[0-2])$'),
  account_id text,
  card_id text,
  telecom_debit_account_id text,
  is_active boolean not null default true,
  is_necessary boolean not null default false,
  note text not null default '',
  origin text not null default 'user',
  primary key (user_id, id),
  foreign key (user_id, account_id)
    references public.accounts(user_id, id) deferrable initially deferred,
  foreign key (user_id, card_id)
    references public.credit_cards(user_id, id) deferrable initially deferred,
  foreign key (user_id, telecom_debit_account_id)
    references public.accounts(user_id, id) deferrable initially deferred,
  check (
    (payment_method = 'creditCard' and card_id is not null and account_id is null
      and telecom_debit_account_id is null)
    or (payment_method = 'telecomBill' and telecom_debit_account_id is not null
      and account_id is null and card_id is null)
    or (payment_method not in ('creditCard', 'telecomBill')
      and account_id is not null and card_id is null
      and telecom_debit_account_id is null)
  )
);

create unique index recurring_expenses_single_active_telecom_idx
  on public.recurring_expenses(user_id)
  where is_active and payment_method = 'telecomBill';

create table public.recurring_expense_occurrences (
  user_id uuid not null references auth.users(id) on delete cascade,
  id text not null,
  recurring_expense_id text not null,
  occurrence_month text not null,
  expense_id text not null,
  scheduled_date date not null,
  primary key (user_id, id),
  unique (user_id, recurring_expense_id, occurrence_month),
  foreign key (user_id, recurring_expense_id)
    references public.recurring_expenses(user_id, id) on delete cascade,
  foreign key (user_id, expense_id)
    references public.expenses(user_id, id) on delete cascade
);

create table public.telecom_bill_payments (
  user_id uuid not null references auth.users(id) on delete cascade,
  id text not null,
  recurring_expense_id text not null,
  bill_month text not null,
  amount_minor bigint not null check (amount_minor > 0),
  paid_at timestamptz not null,
  debit_account_id text not null,
  balance_insufficient boolean not null default false,
  primary key (user_id, id),
  unique (user_id, recurring_expense_id, bill_month),
  foreign key (user_id, recurring_expense_id)
    references public.recurring_expenses(user_id, id) on delete cascade,
  foreign key (user_id, debit_account_id)
    references public.accounts(user_id, id) deferrable initially deferred
);

create table public.telecom_bill_expenses (
  user_id uuid not null references auth.users(id) on delete cascade,
  payment_id text not null,
  expense_id text not null,
  position integer not null,
  primary key (user_id, payment_id, expense_id),
  foreign key (user_id, payment_id)
    references public.telecom_bill_payments(user_id, id) on delete cascade,
  foreign key (user_id, expense_id)
    references public.expenses(user_id, id) on delete cascade
);

do $$
declare table_name text;
begin
  foreach table_name in array array[
    'recurring_expenses', 'recurring_expense_occurrences',
    'telecom_bill_payments', 'telecom_bill_expenses'
  ] loop
    execute format('alter table public.%I enable row level security', table_name);
    execute format(
      'create policy %I on public.%I for all to authenticated ' ||
      'using (user_id = auth.uid()) with check (user_id = auth.uid())',
      table_name || '_owner_policy', table_name
    );
    execute format('revoke all on public.%I from anon, authenticated', table_name);
  end loop;
end
$$;

alter function public.load_finance_data() rename to load_finance_data_v5;
alter function public.save_finance_data(bigint, jsonb) rename to save_finance_data_v5;

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
  response := public.load_finance_data_v5();
  payload := jsonb_set(coalesce(response->'data', '{}'::jsonb),
    '{schemaVersion}', '6'::jsonb, true);

  payload := jsonb_set(payload, '{recurringExpenses}', coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', r.id, 'userId', r.user_id::text, 'item', r.item,
      'category', r.category, 'amountMinor', r.amount_minor,
      'paymentMethod', r.payment_method, 'dayOfMonth', r.day_of_month,
      'startMonth', r.start_month, 'accountId', r.account_id,
      'cardId', r.card_id, 'telecomDebitAccountId', r.telecom_debit_account_id,
      'isActive', r.is_active, 'isNecessary', r.is_necessary,
      'note', r.note, 'origin', r.origin
    ) order by r.start_month, r.day_of_month, r.id)
    from public.recurring_expenses r where r.user_id = uid
  ), '[]'::jsonb), true);

  payload := jsonb_set(payload, '{recurringExpenseOccurrences}', coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', o.id, 'userId', o.user_id::text,
      'recurringExpenseId', o.recurring_expense_id,
      'month', o.occurrence_month, 'expenseId', o.expense_id,
      'scheduledDate', o.scheduled_date
    ) order by o.scheduled_date, o.id)
    from public.recurring_expense_occurrences o where o.user_id = uid
  ), '[]'::jsonb), true);

  payload := jsonb_set(payload, '{telecomBillPayments}', coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', p.id, 'userId', p.user_id::text,
      'recurringExpenseId', p.recurring_expense_id,
      'month', p.bill_month,
      'expenseIds', coalesce((select jsonb_agg(x.expense_id order by x.position)
        from public.telecom_bill_expenses x
        where x.user_id = uid and x.payment_id = p.id), '[]'::jsonb),
      'amountMinor', p.amount_minor, 'paidAt', p.paid_at,
      'debitAccountId', p.debit_account_id,
      'balanceInsufficient', p.balance_insufficient
    ) order by p.paid_at, p.id)
    from public.telecom_bill_payments p where p.user_id = uid
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
  result jsonb;
  legacy_data jsonb;
  current_revision bigint;
  item jsonb;
  expense_id text;
  expense_position integer;
begin
  if uid is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  if jsonb_typeof(data) <> 'object' then raise exception 'invalid_finance_data'; end if;
  if coalesce((data->>'schemaVersion')::integer, 0) <> 6 then
    raise exception 'unsupported_schema_version_update_required';
  end if;

  insert into public.finance_sync_state(user_id, revision)
  values (uid, 0) on conflict (user_id) do nothing;
  select revision into current_revision from public.finance_sync_state
    where user_id = uid for update;
  if expected_revision <> current_revision then
    return jsonb_build_object(
      'status', 'conflict', 'revision', current_revision,
      'updatedAt', (select updated_at from public.finance_sync_state
        where user_id = uid)
    );
  end if;

  delete from public.recurring_expenses where user_id = uid;

  legacy_data := jsonb_set(data, '{schemaVersion}', '5'::jsonb, true);
  result := public.save_finance_data_v5(expected_revision, legacy_data);
  if result->>'status' = 'conflict' then return result; end if;

  for item in select value from jsonb_array_elements(coalesce(data->'recurringExpenses', '[]'::jsonb))
  loop
    insert into public.recurring_expenses values (
      uid, item->>'id', item->>'item', item->>'category',
      (item->>'amountMinor')::bigint, item->>'paymentMethod',
      (item->>'dayOfMonth')::integer, item->>'startMonth',
      nullif(item->>'accountId', ''), nullif(item->>'cardId', ''),
      nullif(item->>'telecomDebitAccountId', ''),
      coalesce((item->>'isActive')::boolean, true),
      coalesce((item->>'isNecessary')::boolean, false),
      coalesce(item->>'note', ''), coalesce(item->>'origin', 'user')
    );
  end loop;

  for item in select value from jsonb_array_elements(coalesce(data->'recurringExpenseOccurrences', '[]'::jsonb))
  loop
    insert into public.recurring_expense_occurrences values (
      uid, item->>'id', item->>'recurringExpenseId', item->>'month',
      item->>'expenseId', (item->>'scheduledDate')::date
    );
  end loop;

  for item in select value from jsonb_array_elements(coalesce(data->'telecomBillPayments', '[]'::jsonb))
  loop
    insert into public.telecom_bill_payments values (
      uid, item->>'id', item->>'recurringExpenseId', item->>'month',
      (item->>'amountMinor')::bigint, (item->>'paidAt')::timestamptz,
      item->>'debitAccountId',
      coalesce((item->>'balanceInsufficient')::boolean, false)
    );
    expense_position := 0;
    for expense_id in select value #>> '{}'
      from jsonb_array_elements(coalesce(item->'expenseIds', '[]'::jsonb))
    loop
      insert into public.telecom_bill_expenses values (
        uid, item->>'id', expense_id, expense_position
      );
      expense_position := expense_position + 1;
    end loop;
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
    'schemaVersion', 6, 'settings', '{}'::jsonb,
    'accounts', '[]'::jsonb, 'balanceAdjustments', '[]'::jsonb,
    'expenses', '[]'::jsonb, 'recurringExpenses', '[]'::jsonb,
    'recurringExpenseOccurrences', '[]'::jsonb,
    'telecomBillPayments', '[]'::jsonb, 'incomes', '[]'::jsonb,
    'cards', '[]'::jsonb, 'bills', '[]'::jsonb, 'products', '[]'::jsonb,
    'investmentTransactions', '[]'::jsonb,
    'investmentAdjustments', '[]'::jsonb,
    'investmentPriceHistory', '[]'::jsonb, 'orders', '[]'::jsonb
  ));
$$;

create or replace function public.account_balance_for_schedule(
  target_user uuid, target_account text
)
returns bigint
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select coalesce((select a.opening_balance_minor from public.accounts a
      where a.user_id = target_user and a.id = target_account), 0)
    + coalesce((select sum(x.amount_minor) from public.balance_adjustments x
      where x.user_id = target_user and x.account_id = target_account), 0)
    + coalesce((select sum(i.amount_minor) from public.incomes i
      where i.user_id = target_user and i.account_id = target_account), 0)
    - coalesce((select sum(e.amount_minor) from public.expenses e
      where e.user_id = target_user and e.account_id = target_account
        and e.payment_method not in ('creditCard', 'telecomBill')), 0)
    - coalesce((select sum(b.paid_minor) from public.card_bills b
      join public.credit_cards c on c.user_id = b.user_id and c.id = b.card_id
      where b.user_id = target_user and c.debit_account_id = target_account), 0)
    - coalesce((select sum(p.amount_minor) from public.telecom_bill_payments p
      where p.user_id = target_user and p.debit_account_id = target_account), 0)
    + coalesce((select sum(
        (i.quantity_micros * i.price_minor / 1000000) - i.fee_minor - i.tax_minor
      ) from public.investment_transactions i
      where i.user_id = target_user and i.credit_account_id = target_account), 0)
    - coalesce((select sum(
        (i.quantity_micros * i.price_minor / 1000000) + i.fee_minor + i.tax_minor
      )
      from public.investment_transactions i
      where i.user_id = target_user and i.debit_account_id = target_account), 0)
    + coalesce((select sum(coalesce(p.final_due_minor, p.suggested_due_minor,
        greatest(p.item_amount_minor + p.shared_fee_minor - p.discount_minor, 0)))
      from public.order_participants p where p.user_id = target_user
        and p.collection_account_id = target_account
        and p.collection_status = 'paid' and not p.is_self), 0);
$$;

create or replace function public.process_due_recurring_expenses(
  run_date date default ((now() at time zone 'Asia/Taipei')::date)
)
returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  rule public.recurring_expenses%rowtype;
  cycle_month date;
  due_date date;
  previous_due date;
  occurrence_month text;
  occurrence_id text;
  generated_expense_id text;
  payment_id text;
  payment_amount bigint;
  available_balance bigint;
  changed_count integer := 0;
  expense_row record;
  position_value integer;
begin
  for rule in select * from public.recurring_expenses where is_active
  loop
    cycle_month := to_date(rule.start_month || '-01', 'YYYY-MM-DD');
    while cycle_month <= date_trunc('month', run_date)::date loop
      due_date := cycle_month +
        (least(rule.day_of_month,
          extract(day from (cycle_month + interval '1 month - 1 day'))::integer) - 1);
      if due_date <= run_date and not exists (
        select 1 from public.recurring_expense_occurrences o
        where o.user_id = rule.user_id and o.recurring_expense_id = rule.id
          and o.occurrence_month = to_char(cycle_month, 'YYYY-MM')
      ) then
        insert into public.finance_sync_state(user_id, revision)
          values (rule.user_id, 0) on conflict (user_id) do nothing;
        perform 1 from public.finance_sync_state
          where user_id = rule.user_id for update;
        if exists (
          select 1 from public.recurring_expense_occurrences o
          where o.user_id = rule.user_id
            and o.recurring_expense_id = rule.id
            and o.occurrence_month = to_char(cycle_month, 'YYYY-MM')
        ) then
          cycle_month := (cycle_month + interval '1 month')::date;
          continue;
        end if;

        occurrence_month := to_char(cycle_month, 'YYYY-MM');
        occurrence_id := 'recurring-occurrence-' ||
          md5(rule.user_id::text || rule.id || occurrence_month);
        generated_expense_id := 'recurring-expense-' ||
          md5(rule.user_id::text || rule.id || occurrence_month);

        insert into public.expenses(
          user_id, id, expense_date, amount_minor, payment_method,
          item, category, account_id, card_id, bill_id, merchant,
          note, is_necessary, origin
        ) values (
          rule.user_id, generated_expense_id,
          due_date::timestamp at time zone 'Asia/Taipei', rule.amount_minor,
          rule.payment_method, rule.item, rule.category,
          case when rule.payment_method not in ('creditCard', 'telecomBill')
            then rule.account_id end,
          case when rule.payment_method = 'creditCard' then rule.card_id end,
          null, '', rule.note, rule.is_necessary, rule.origin
        );
        insert into public.recurring_expense_occurrences values (
          rule.user_id, occurrence_id, rule.id, occurrence_month,
          generated_expense_id, due_date
        );

        if rule.payment_method = 'telecomBill' then
          select max((p.paid_at at time zone 'Asia/Taipei')::date)
            into previous_due
          from public.telecom_bill_payments p
          where p.user_id = rule.user_id
            and p.recurring_expense_id = rule.id
            and p.paid_at < due_date::timestamp at time zone 'Asia/Taipei';
          if previous_due is null then
            previous_due := (cycle_month - interval '1 month')::date +
              (least(rule.day_of_month,
                extract(day from cycle_month - interval '1 day')::integer) - 1);
          end if;
          payment_id := 'telecom-payment-' ||
            md5(rule.user_id::text || rule.id || occurrence_month);
          select coalesce(sum(e.amount_minor), 0) into payment_amount
          from public.expenses e
          where e.user_id = rule.user_id and e.payment_method = 'telecomBill'
            and (e.id = generated_expense_id or (
              e.expense_date >= previous_due::timestamp at time zone 'Asia/Taipei'
              and e.expense_date < due_date::timestamp at time zone 'Asia/Taipei'
            ))
            and not exists (select 1 from public.telecom_bill_expenses x
              where x.user_id = e.user_id and x.expense_id = e.id);
          available_balance := public.account_balance_for_schedule(
            rule.user_id, rule.telecom_debit_account_id
          );
          insert into public.telecom_bill_payments values (
            rule.user_id, payment_id, rule.id, occurrence_month,
            payment_amount, due_date::timestamp at time zone 'Asia/Taipei',
            rule.telecom_debit_account_id, available_balance < payment_amount
          );
          position_value := 0;
          for expense_row in
            select e.id from public.expenses e
            where e.user_id = rule.user_id and e.payment_method = 'telecomBill'
              and (e.id = generated_expense_id or (
                e.expense_date >= previous_due::timestamp at time zone 'Asia/Taipei'
                and e.expense_date < due_date::timestamp at time zone 'Asia/Taipei'
              ))
              and not exists (select 1 from public.telecom_bill_expenses x
                where x.user_id = e.user_id and x.expense_id = e.id)
            order by e.expense_date, e.id
          loop
            insert into public.telecom_bill_expenses values (
              rule.user_id, payment_id, expense_row.id, position_value
            );
            position_value := position_value + 1;
          end loop;
        end if;

        update public.finance_sync_state set revision = revision + 1,
          updated_at = now() where user_id = rule.user_id;
        changed_count := changed_count + 1;
      end if;
      cycle_month := (cycle_month + interval '1 month')::date;
    end loop;
  end loop;
  return changed_count;
end
$$;

create or replace function public.line_confirm_expense(
  p_line_user_id text,
  p_command_id uuid,
  p_amount_minor bigint,
  p_item text,
  p_category text,
  p_payment_method text,
  p_account_id text default null,
  p_card_id text default null,
  p_expense_date timestamptz default now()
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  uid uuid := public.line_linked_owner_id(p_line_user_id);
  current_revision bigint;
  next_revision bigint;
  expense_id text := 'line-' || gen_random_uuid()::text;
  prior jsonb;
  result jsonb;
begin
  if uid is null then return jsonb_build_object('status', 'not_linked'); end if;
  select c.result into prior from public.line_finance_commands c
  where c.command_id = p_command_id and c.user_id = uid;
  if prior is not null then return prior || jsonb_build_object('duplicate', true); end if;
  if p_amount_minor <= 0 or p_amount_minor > 999999999999 then
    raise exception 'invalid_amount';
  end if;
  if char_length(trim(p_item)) not between 1 and 80 then
    raise exception 'invalid_item';
  end if;
  if p_payment_method not in (
    'cash', 'transfer', 'debitCard', 'creditCard', 'linePay',
    'jkoPay', 'easyCard', 'iPass', 'telecomBill', 'other'
  ) then raise exception 'invalid_payment_method'; end if;
  if p_account_id is not null and not exists (
    select 1 from public.accounts where user_id = uid
      and id = p_account_id and is_active
  ) then raise exception 'invalid_account'; end if;
  if p_card_id is not null and not exists (
    select 1 from public.credit_cards where user_id = uid
      and id = p_card_id and is_active
  ) then raise exception 'invalid_card'; end if;
  if p_payment_method = 'creditCard' and p_card_id is null then
    raise exception 'card_required';
  end if;
  if p_payment_method = 'telecomBill' and not exists (
    select 1 from public.recurring_expenses where user_id = uid
      and payment_method = 'telecomBill' and is_active
  ) then raise exception 'telecom_bill_not_configured'; end if;

  insert into public.finance_sync_state(user_id, revision)
  values (uid, 0) on conflict (user_id) do nothing;
  select revision into current_revision from public.finance_sync_state
    where user_id = uid for update;
  insert into public.expenses(
    user_id, id, expense_date, amount_minor, payment_method, item, category,
    account_id, card_id, merchant, note, is_necessary, origin
  ) values (
    uid, expense_id, p_expense_date, p_amount_minor, p_payment_method,
    trim(p_item), left(coalesce(nullif(trim(p_category), ''), '其他'), 40),
    case when p_payment_method = 'telecomBill' then null else p_account_id end,
    p_card_id, '', 'LINE 官方帳號建立', false, 'user'
  );
  next_revision := current_revision + 1;
  update public.finance_sync_state set revision = next_revision,
    updated_at = now() where user_id = uid;
  result := jsonb_build_object(
    'status', 'saved', 'expenseId', expense_id, 'revision', next_revision
  );
  insert into public.line_finance_commands(
    command_id, user_id, command_type, result
  ) values (p_command_id, uid, 'create_expense', result);
  return result;
end
$$;

alter function public.line_finance_summary(text) rename to line_finance_summary_v5;
create or replace function public.line_finance_summary(p_line_user_id text)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  uid uuid := public.line_linked_owner_id(p_line_user_id);
  result jsonb;
  telecom_paid bigint;
begin
  result := public.line_finance_summary_v5(p_line_user_id);
  if uid is null or result->>'status' <> 'ok' then return result; end if;
  select coalesce(sum(amount_minor), 0) into telecom_paid
    from public.telecom_bill_payments where user_id = uid;
  return jsonb_set(
    result,
    '{accountBalanceMinor}',
    to_jsonb(coalesce((result->>'accountBalanceMinor')::bigint, 0) - telecom_paid),
    true
  );
end
$$;

revoke all on function public.load_finance_data_v5() from public, anon, authenticated;
revoke all on function public.save_finance_data_v5(bigint, jsonb) from public, anon, authenticated;
revoke all on function public.account_balance_for_schedule(uuid, text) from public, anon, authenticated;
revoke all on function public.process_due_recurring_expenses(date) from public, anon, authenticated;
revoke all on function public.line_finance_summary_v5(text) from public, anon, authenticated;
revoke all on function public.line_finance_summary(text) from public, anon, authenticated;
revoke all on function public.load_finance_data() from public;
revoke all on function public.save_finance_data(bigint, jsonb) from public;
revoke all on function public.clear_finance_data(bigint) from public;
grant execute on function public.load_finance_data() to authenticated;
grant execute on function public.save_finance_data(bigint, jsonb) to authenticated;
grant execute on function public.clear_finance_data(bigint) to authenticated;
grant execute on function public.line_finance_summary(text) to service_role;

create extension if not exists pg_cron with schema pg_catalog;
do $$
begin
  if exists (select 1 from cron.job where jobname = 'quick-ledger-recurring-expenses') then
    perform cron.unschedule('quick-ledger-recurring-expenses');
  end if;
  perform cron.schedule(
    'quick-ledger-recurring-expenses',
    '15 16 * * *',
    $job$select public.process_due_recurring_expenses();$job$
  );
end
$$;
