-- Add managed debit cards without changing the v7 finance payload contract.
-- Credit cards keep their liability/bill flow; debit cards point at the
-- existing debit_account_id and are charged immediately by the client ledger.

create table public.payment_card_profiles (
  user_id uuid not null references auth.users(id) on delete cascade,
  card_id text not null,
  card_type text not null default 'credit'
    check (card_type in ('credit', 'debit')),
  primary key (user_id, card_id),
  foreign key (user_id, card_id) references public.credit_cards(user_id, id)
    on delete cascade deferrable initially deferred
);

alter table public.payment_card_profiles enable row level security;
create policy payment_card_profiles_owner_policy
on public.payment_card_profiles for all
using (auth.uid() = user_id) with check (auth.uid() = user_id);
revoke all on public.payment_card_profiles from anon, authenticated;

alter function public.load_finance_data()
  rename to load_finance_data_before_payment_cards;
alter function public.save_finance_data(bigint, jsonb)
  rename to save_finance_data_before_payment_cards;

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

  response := public.load_finance_data_before_payment_cards();
  if response->>'status' <> 'ok' then return response; end if;
  payload := coalesce(response->'data', '{}'::jsonb);
  payload := jsonb_set(payload, '{cards}', coalesce((
    select jsonb_agg(item || jsonb_build_object(
      'cardType', coalesce(profile.card_type, 'credit')
    ) order by item->>'name', item->>'id')
    from jsonb_array_elements(coalesce(payload->'cards', '[]'::jsonb)) item
    left join public.payment_card_profiles profile
      on profile.user_id = uid and profile.card_id = item->>'id'
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
  item jsonb;
  card_type text;
begin
  if uid is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;

  result := public.save_finance_data_before_payment_cards(
    expected_revision,
    data
  );
  if result->>'status' = 'conflict' then return result; end if;

  delete from public.payment_card_profiles where user_id = uid;
  for item in select value from jsonb_array_elements(
    coalesce(data->'cards', '[]'::jsonb)
  ) loop
    card_type := coalesce(item->>'cardType', 'credit');
    if card_type not in ('credit', 'debit') then
      raise exception 'invalid_card_type';
    end if;
    insert into public.payment_card_profiles(user_id, card_id, card_type)
    values (uid, item->>'id', card_type);
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
    'schemaVersion', 7, 'settings', '{}'::jsonb,
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

revoke all on function public.load_finance_data_before_payment_cards()
  from public, anon, authenticated;
revoke all on function public.save_finance_data_before_payment_cards(bigint, jsonb)
  from public, anon, authenticated;
revoke all on function public.load_finance_data() from public;
revoke all on function public.save_finance_data(bigint, jsonb) from public;
revoke all on function public.clear_finance_data(bigint) from public;
grant execute on function public.load_finance_data() to authenticated;
grant execute on function public.save_finance_data(bigint, jsonb)
  to authenticated;
grant execute on function public.clear_finance_data(bigint) to authenticated;
