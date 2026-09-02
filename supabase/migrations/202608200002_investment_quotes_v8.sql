-- TWSE instrument catalogue and server-managed daily closing prices.
-- Keep quote data outside user finance revisions and link products through a
-- sidecar table so the legacy positional investment_products inserts remain
-- compatible.

create extension if not exists pg_net with schema extensions;

create table public.market_instruments (
  market text not null check (market in ('TWSE')),
  symbol text not null,
  name text not null,
  normalized_name text not null,
  instrument_type text not null check (instrument_type in ('股票', 'ETF')),
  currency text not null default 'TWD',
  is_active boolean not null default true,
  source_updated_at timestamptz not null default now(),
  primary key (market, symbol)
);

create index market_instruments_symbol_idx
  on public.market_instruments (symbol text_pattern_ops);
create index market_instruments_name_idx
  on public.market_instruments (normalized_name text_pattern_ops);

create table public.market_quote_history (
  market text not null,
  symbol text not null,
  quote_date date not null,
  close_price_minor bigint not null check (close_price_minor > 0),
  fetched_at timestamptz not null default now(),
  primary key (market, symbol, quote_date),
  foreign key (market, symbol) references public.market_instruments(market, symbol)
    on delete cascade
);

create index market_quote_history_latest_idx
  on public.market_quote_history (market, symbol, quote_date desc);

create view public.market_catalogue_with_latest_quotes
with (security_invoker = true)
as
select i.market, i.symbol, i.name, i.normalized_name,
  i.instrument_type, i.currency, i.is_active, i.source_updated_at,
  quote.quote_date, quote.close_price_minor
from public.market_instruments i
left join lateral (
  select q.quote_date, q.close_price_minor
  from public.market_quote_history q
  where q.market = i.market and q.symbol = i.symbol
  order by q.quote_date desc limit 1
) quote on true;

create table public.market_sync_runs (
  market text primary key,
  started_at timestamptz not null,
  completed_at timestamptz,
  status text not null check (status in ('running', 'success', 'failed')),
  quote_date date,
  item_count integer not null default 0,
  error_message text not null default ''
);

create table public.investment_product_quote_links (
  user_id uuid not null references auth.users(id) on delete cascade,
  product_id text not null,
  market text not null,
  symbol text not null,
  linked_at timestamptz not null default now(),
  primary key (user_id, product_id),
  foreign key (user_id, product_id)
    references public.investment_products(user_id, id) on delete cascade
    deferrable initially deferred,
  foreign key (market, symbol)
    references public.market_instruments(market, symbol)
);

alter table public.market_instruments enable row level security;
alter table public.market_quote_history enable row level security;
alter table public.market_sync_runs enable row level security;
alter table public.investment_product_quote_links enable row level security;

create policy investment_product_quote_links_owner_policy
  on public.investment_product_quote_links for all to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());

revoke all on public.market_instruments from anon, authenticated;
revoke all on public.market_quote_history from anon, authenticated;
revoke all on public.market_sync_runs from anon, authenticated;
revoke all on public.investment_product_quote_links from anon, authenticated;
revoke all on public.market_catalogue_with_latest_quotes from anon, authenticated;

alter function public.load_finance_data() rename to load_finance_data_v7;
alter function public.save_finance_data(bigint, jsonb) rename to save_finance_data_v7;

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

  response := public.load_finance_data_v7();
  payload := jsonb_set(
    coalesce(response->'data', '{}'::jsonb),
    '{schemaVersion}', '8'::jsonb, true
  );

  select coalesce(jsonb_agg(
    case when link.product_id is null then
      product_item || jsonb_build_object('priceSource', 'manual')
    else
      product_item || jsonb_build_object(
        'priceSource', 'twse', 'market', link.market,
        'marketSymbol', link.symbol, 'quoteLinkedAt', link.linked_at,
        'name', instrument.name, 'type', instrument.instrument_type,
        'currency', instrument.currency,
        'currentPriceMinor', coalesce(quote.close_price_minor,
          (product_item->>'currentPriceMinor')::bigint),
        'priceUpdatedAt', coalesce(
          quote.quote_date::text,
          product_item->>'priceUpdatedAt'
        )
      )
    end order by product_item->>'id'
  ), '[]'::jsonb)
  into rebuilt
  from jsonb_array_elements(coalesce(payload->'products', '[]'::jsonb)) product_item
  left join public.investment_product_quote_links link
    on link.user_id = uid and link.product_id = product_item->>'id'
  left join public.market_instruments instrument
    on instrument.market = link.market and instrument.symbol = link.symbol
  left join lateral (
    select q.quote_date, q.close_price_minor
    from public.market_quote_history q
    where q.market = link.market and q.symbol = link.symbol
    order by q.quote_date desc limit 1
  ) quote on true;
  payload := jsonb_set(payload, '{products}', rebuilt, true);

  select coalesce(jsonb_agg(item order by sort_date, product_id), '[]'::jsonb)
  into rebuilt
  from (
    select history_item as item,
      history_item->>'date' as sort_date,
      history_item->>'productId' as product_id
    from jsonb_array_elements(
      coalesce(payload->'investmentPriceHistory', '[]'::jsonb)
    ) history_item
    left join public.investment_product_quote_links link
      on link.user_id = uid and link.product_id = history_item->>'productId'
    where link.product_id is null
       or (history_item->>'date')::timestamptz < date_trunc('day', link.linked_at)
    union all
    select jsonb_build_object(
      'productId', link.product_id,
      'priceMinor', quote.close_price_minor,
      'date', quote.quote_date,
      'estimated', false
    ), quote.quote_date::text, link.product_id
    from public.investment_product_quote_links link
    join public.market_quote_history quote
      on quote.market = link.market and quote.symbol = link.symbol
     and quote.quote_date >= link.linked_at::date
    where link.user_id = uid
  ) history;
  payload := jsonb_set(payload, '{investmentPriceHistory}', rebuilt, true);

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
  rebuilt_products jsonb;
  rebuilt_history jsonb;
  product_item jsonb;
  link_item jsonb;
  quote record;
begin
  if uid is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  if jsonb_typeof(data) <> 'object' then
    raise exception 'invalid_finance_data';
  end if;
  version := coalesce((data->>'schemaVersion')::integer, 0);

  if version <> 8 then
    if exists (
      select 1 from public.investment_product_quote_links where user_id = uid
    ) then
      raise exception 'unsupported_schema_version_update_required';
    end if;
    return public.save_finance_data_v7(expected_revision, data);
  end if;

  rebuilt_products := '[]'::jsonb;
  for product_item in select value from jsonb_array_elements(
    coalesce(data->'products', '[]'::jsonb)
  ) loop
    if product_item->>'priceSource' = 'twse' then
      select i.name, i.instrument_type, i.currency,
        q.close_price_minor, q.quote_date
      into quote
      from public.market_instruments i
      left join lateral (
        select h.close_price_minor, h.quote_date
        from public.market_quote_history h
        where h.market = i.market and h.symbol = i.symbol
        order by h.quote_date desc limit 1
      ) q on true
      where i.market = coalesce(product_item->>'market', 'TWSE')
        and i.symbol = product_item->>'marketSymbol';
      if found then
        product_item := product_item || jsonb_build_object(
          'name', quote.name, 'type', quote.instrument_type,
          'currency', quote.currency,
          'currentPriceMinor', coalesce(quote.close_price_minor,
            (product_item->>'currentPriceMinor')::bigint),
          'priceUpdatedAt', coalesce(
            quote.quote_date::text,
            product_item->>'priceUpdatedAt'
          )
        );
      end if;
    end if;
    rebuilt_products := rebuilt_products || jsonb_build_array(product_item);
  end loop;

  select coalesce(jsonb_agg(history_item), '[]'::jsonb)
  into rebuilt_history
  from jsonb_array_elements(
    coalesce(data->'investmentPriceHistory', '[]'::jsonb)
  ) history_item
  left join lateral (
    select value as item from jsonb_array_elements(rebuilt_products)
    where value->>'id' = history_item->>'productId' limit 1
  ) product on true
  where product.item is null
     or product.item->>'priceSource' <> 'twse'
     or (history_item->>'date')::timestamptz < date_trunc(
       'day', coalesce(
         (product.item->>'quoteLinkedAt')::timestamptz,
         now()
       )
     );

  legacy_data := jsonb_set(data, '{schemaVersion}', '7'::jsonb, true);
  legacy_data := jsonb_set(legacy_data, '{products}', rebuilt_products, true);
  legacy_data := jsonb_set(
    legacy_data, '{investmentPriceHistory}', rebuilt_history, true
  );
  result := public.save_finance_data_v7(expected_revision, legacy_data);
  if result->>'status' = 'conflict' then return result; end if;

  for link_item in select value from jsonb_array_elements(rebuilt_products)
  loop
    if link_item->>'priceSource' = 'twse' then
      insert into public.investment_product_quote_links(
        user_id, product_id, market, symbol, linked_at
      ) values (
        uid, link_item->>'id', coalesce(link_item->>'market', 'TWSE'),
        link_item->>'marketSymbol', coalesce(
          (link_item->>'quoteLinkedAt')::timestamptz, now()
        )
      );
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
    'schemaVersion', 8, 'settings', '{}'::jsonb,
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

revoke all on function public.load_finance_data_v7() from public, anon, authenticated;
revoke all on function public.save_finance_data_v7(bigint, jsonb)
  from public, anon, authenticated;
revoke all on function public.load_finance_data() from public;
revoke all on function public.save_finance_data(bigint, jsonb) from public;
revoke all on function public.clear_finance_data(bigint) from public;
grant execute on function public.load_finance_data() to authenticated;
grant execute on function public.save_finance_data(bigint, jsonb) to authenticated;
grant execute on function public.clear_finance_data(bigint) to authenticated;

-- Monday-Friday 18:30 Asia/Taipei (10:30 UTC). The job is inert until
-- project_url and investment_quote_cron_secret exist in Supabase Vault.
do $$
begin
  if exists (select 1 from cron.job where jobname = 'quick-ledger-twse-quotes') then
    perform cron.unschedule('quick-ledger-twse-quotes');
  end if;
  perform cron.schedule(
    'quick-ledger-twse-quotes', '30 10 * * 1-5', $job$
      select net.http_post(
        url := (select decrypted_secret from vault.decrypted_secrets
                where name = 'project_url') || '/functions/v1/investment-quotes',
        headers := jsonb_build_object(
          'Content-Type', 'application/json',
          'x-cron-secret', (select decrypted_secret from vault.decrypted_secrets
                            where name = 'investment_quote_cron_secret')
        ),
        body := '{"action":"refresh"}'::jsonb
      )
      where exists (select 1 from vault.decrypted_secrets where name = 'project_url')
        and exists (select 1 from vault.decrypted_secrets
                    where name = 'investment_quote_cron_secret');
    $job$
  );
end
$$;
