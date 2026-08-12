-- Financial reports v5. Keep the original v4 bulk writer as an internal
-- implementation and wrap it so older clients cannot erase v5-only data.

alter function public.load_finance_data() rename to load_finance_data_v4;
alter function public.save_finance_data(bigint, jsonb) rename to save_finance_data_v4;

create table public.incomes (
  user_id uuid not null references auth.users(id) on delete cascade,
  id text not null,
  income_date timestamptz not null,
  amount_minor bigint not null check (amount_minor > 0),
  item text not null,
  category text not null,
  account_id text not null,
  note text not null default '',
  origin text not null default 'user' check (origin in ('user', 'demo')),
  primary key (user_id, id),
  foreign key (user_id, account_id)
    references public.accounts(user_id, id) on delete cascade
    deferrable initially deferred
);

create table public.investment_price_history (
  user_id uuid not null references auth.users(id) on delete cascade,
  product_id text not null,
  price_date timestamptz not null,
  price_minor bigint not null check (price_minor >= 0),
  estimated boolean not null default false,
  primary key (user_id, product_id, price_date),
  foreign key (user_id, product_id)
    references public.investment_products(user_id, id) on delete cascade
    deferrable initially deferred
);

create table public.fx_rate_history (
  user_id uuid not null references auth.users(id) on delete cascade,
  from_currency text not null,
  to_currency text not null,
  rate_date timestamptz not null,
  rate_micros bigint not null check (rate_micros > 0),
  primary key (user_id, from_currency, to_currency, rate_date)
);

create table public.account_report_metadata (
  user_id uuid not null,
  account_id text not null,
  opening_balance_date timestamptz not null,
  primary key (user_id, account_id),
  foreign key (user_id, account_id)
    references public.accounts(user_id, id) on delete cascade
    deferrable initially deferred
);

create table public.card_bill_report_metadata (
  user_id uuid not null,
  bill_id text not null,
  paid_at timestamptz,
  primary key (user_id, bill_id),
  foreign key (user_id, bill_id)
    references public.card_bills(user_id, id) on delete cascade
    deferrable initially deferred
);

create table public.participant_report_metadata (
  user_id uuid not null,
  order_id text not null,
  participant_id text not null,
  cancelled_at timestamptz,
  primary key (user_id, order_id, participant_id),
  foreign key (user_id, order_id, participant_id)
    references public.order_participants(user_id, order_id, id) on delete cascade
    deferrable initially deferred
);

create index incomes_user_date_idx on public.incomes(user_id, income_date desc);
create index investment_price_history_lookup_idx
  on public.investment_price_history(user_id, product_id, price_date desc);
create index fx_rate_history_lookup_idx
  on public.fx_rate_history(user_id, from_currency, to_currency, rate_date desc);

do $$
declare
  table_name text;
begin
  foreach table_name in array array[
    'incomes', 'investment_price_history', 'fx_rate_history',
    'account_report_metadata', 'card_bill_report_metadata',
    'participant_report_metadata'
  ]
  loop
    execute format('alter table public.%I enable row level security', table_name);
    execute format(
      'create policy %I on public.%I for all to authenticated ' ||
      'using (user_id = auth.uid()) with check (user_id = auth.uid())',
      table_name || '_owner_policy',
      table_name
    );
    execute format('revoke all on public.%I from anon, authenticated', table_name);
  end loop;
end
$$;

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

  response := public.load_finance_data_v4();
  payload := coalesce(response->'data', '{}'::jsonb);
  payload := jsonb_set(payload, '{schemaVersion}', '5'::jsonb, true);

  select coalesce(jsonb_agg(
    account_item || jsonb_build_object(
      'openingBalanceDate', coalesce(
        metadata.opening_balance_date,
        (account_item->>'createdAt')::timestamptz
      )
    ) order by account_item->>'createdAt', account_item->>'id'
  ), '[]'::jsonb)
  into rebuilt
  from jsonb_array_elements(coalesce(payload->'accounts', '[]'::jsonb)) account_item
  left join public.account_report_metadata metadata
    on metadata.user_id = uid and metadata.account_id = account_item->>'id';
  payload := jsonb_set(payload, '{accounts}', rebuilt, true);

  select coalesce(jsonb_agg(
    bill_item || jsonb_build_object('paidAt', metadata.paid_at)
    order by bill_item->>'month', bill_item->>'id'
  ), '[]'::jsonb)
  into rebuilt
  from jsonb_array_elements(coalesce(payload->'bills', '[]'::jsonb)) bill_item
  left join public.card_bill_report_metadata metadata
    on metadata.user_id = uid and metadata.bill_id = bill_item->>'id';
  payload := jsonb_set(payload, '{bills}', rebuilt, true);

  select coalesce(jsonb_agg(
    jsonb_set(
      order_item,
      '{participants}',
      coalesce((
        select jsonb_agg(
          participant_item || jsonb_build_object('cancelledAt', metadata.cancelled_at)
          order by participant_item->>'id'
        )
        from jsonb_array_elements(coalesce(order_item->'participants', '[]'::jsonb)) participant_item
        left join public.participant_report_metadata metadata
          on metadata.user_id = uid
          and metadata.order_id = order_item->>'id'
          and metadata.participant_id = participant_item->>'id'
      ), '[]'::jsonb),
      true
    ) order by order_item->>'date', order_item->>'id'
  ), '[]'::jsonb)
  into rebuilt
  from jsonb_array_elements(coalesce(payload->'orders', '[]'::jsonb)) order_item;
  payload := jsonb_set(payload, '{orders}', rebuilt, true);

  payload := jsonb_set(payload, '{incomes}', coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', i.id, 'userId', i.user_id::text, 'date', i.income_date,
      'amountMinor', i.amount_minor, 'item', i.item, 'category', i.category,
      'accountId', i.account_id, 'note', i.note, 'origin', i.origin
    ) order by i.income_date, i.id)
    from public.incomes i where i.user_id = uid
  ), '[]'::jsonb), true);

  payload := jsonb_set(payload, '{investmentPriceHistory}', coalesce((
    select jsonb_agg(jsonb_build_object(
      'productId', p.product_id, 'priceMinor', p.price_minor,
      'date', p.price_date, 'estimated', p.estimated
    ) order by p.price_date, p.product_id)
    from public.investment_price_history p where p.user_id = uid
  ), '[]'::jsonb), true);

  payload := jsonb_set(
    payload,
    '{settings,fxRates}',
    coalesce((
      select jsonb_agg(jsonb_build_object(
        'from', f.from_currency, 'to', f.to_currency,
        'rateMicros', f.rate_micros, 'updatedAt', f.rate_date
      ) order by f.rate_date, f.from_currency, f.to_currency)
      from public.fx_rate_history f where f.user_id = uid
    ), payload#>'{settings,fxRates}', '[]'::jsonb),
    true
  );

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
  settings_item jsonb;
  latest_rates jsonb;
  item jsonb;
  nested jsonb;
begin
  if uid is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  if jsonb_typeof(data) <> 'object' then
    raise exception 'invalid_finance_data';
  end if;
  if coalesce((data->>'schemaVersion')::integer, 0) <> 5 then
    raise exception 'unsupported_schema_version_update_required';
  end if;

  settings_item := coalesce(data->'settings', '{}'::jsonb);
  select coalesce(jsonb_agg(rate_item), '[]'::jsonb)
  into latest_rates
  from (
    select distinct on (value->>'from', value->>'to') value as rate_item
    from jsonb_array_elements(coalesce(settings_item->'fxRates', '[]'::jsonb))
    order by value->>'from', value->>'to', (value->>'updatedAt')::timestamptz desc
  ) latest;

  legacy_data := jsonb_set(data, '{schemaVersion}', '4'::jsonb, true);
  legacy_data := jsonb_set(legacy_data, '{settings,fxRates}', latest_rates, true);
  result := public.save_finance_data_v4(expected_revision, legacy_data);
  if result->>'status' = 'conflict' then
    return result;
  end if;

  delete from public.fx_rate_history where user_id = uid;

  for item in select value from jsonb_array_elements(coalesce(data->'accounts', '[]'::jsonb))
  loop
    insert into public.account_report_metadata values (
      uid, item->>'id', coalesce(
        (item->>'openingBalanceDate')::timestamptz,
        (item->>'createdAt')::timestamptz
      )
    );
  end loop;

  for item in select value from jsonb_array_elements(coalesce(data->'bills', '[]'::jsonb))
  loop
    insert into public.card_bill_report_metadata values (
      uid, item->>'id', (item->>'paidAt')::timestamptz
    );
  end loop;

  for item in select value from jsonb_array_elements(coalesce(data->'orders', '[]'::jsonb))
  loop
    for nested in select value from jsonb_array_elements(coalesce(item->'participants', '[]'::jsonb))
    loop
      insert into public.participant_report_metadata values (
        uid, item->>'id', nested->>'id', (nested->>'cancelledAt')::timestamptz
      );
    end loop;
  end loop;

  for item in select value from jsonb_array_elements(coalesce(data->'incomes', '[]'::jsonb))
  loop
    insert into public.incomes values (
      uid, item->>'id', (item->>'date')::timestamptz,
      (item->>'amountMinor')::bigint, item->>'item', item->>'category',
      item->>'accountId', coalesce(item->>'note', ''),
      coalesce(item->>'origin', 'user')
    );
  end loop;

  for item in select value from jsonb_array_elements(coalesce(data->'investmentPriceHistory', '[]'::jsonb))
  loop
    insert into public.investment_price_history values (
      uid, item->>'productId', (item->>'date')::timestamptz,
      (item->>'priceMinor')::bigint,
      coalesce((item->>'estimated')::boolean, false)
    );
  end loop;

  for item in select value from jsonb_array_elements(coalesce(settings_item->'fxRates', '[]'::jsonb))
  loop
    insert into public.fx_rate_history values (
      uid, item->>'from', item->>'to', (item->>'updatedAt')::timestamptz,
      (item->>'rateMicros')::bigint
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
  select public.save_finance_data(
    expected_revision,
    jsonb_build_object(
      'schemaVersion', 5,
      'settings', jsonb_build_object(),
      'accounts', '[]'::jsonb,
      'balanceAdjustments', '[]'::jsonb,
      'expenses', '[]'::jsonb,
      'incomes', '[]'::jsonb,
      'cards', '[]'::jsonb,
      'bills', '[]'::jsonb,
      'products', '[]'::jsonb,
      'investmentTransactions', '[]'::jsonb,
      'investmentAdjustments', '[]'::jsonb,
      'investmentPriceHistory', '[]'::jsonb,
      'orders', '[]'::jsonb
    )
  );
$$;

revoke all on function public.load_finance_data_v4() from public, anon, authenticated;
revoke all on function public.save_finance_data_v4(bigint, jsonb) from public, anon, authenticated;
revoke all on function public.load_finance_data() from public;
revoke all on function public.save_finance_data(bigint, jsonb) from public;
revoke all on function public.clear_finance_data(bigint) from public;
grant execute on function public.load_finance_data() to authenticated;
grant execute on function public.save_finance_data(bigint, jsonb) to authenticated;
grant execute on function public.clear_finance_data(bigint) to authenticated;
