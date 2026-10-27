-- Apple Pay → 待確認收件匣 → LINE 確認入帳.
--
-- An iPhone Shortcuts "Transaction" automation posts each Apple Pay tap
-- (amount / merchant / Wallet card name) to the apple-pay-ingest Edge
-- Function with a per-user capture token. The function stores the tap here
-- as a pending inbox row and pushes a LINE message; tapping a category in
-- LINE calls line_capture_confirm, which books the expense through the
-- existing line_confirm_expense (same validation, revision bump and
-- idempotency as the LINE quick-expense flow).
--
-- Everything in this migration is service-role only.

create table public.capture_tokens (
  user_id uuid primary key references auth.users(id) on delete cascade,
  -- SHA-256 hex of the token. The plaintext token is shown once in LINE
  -- and never stored.
  token_hash text not null unique check (token_hash ~ '^[0-9a-f]{64}$'),
  created_at timestamptz not null default now(),
  last_used_at timestamptz
);

create table public.capture_inbox (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  source text not null default 'applePay' check (source in ('applePay')),
  amount_minor bigint not null
    check (amount_minor > 0 and amount_minor <= 999999999999),
  currency text not null default 'TWD' check (currency ~ '^[A-Z]{3}$'),
  merchant text not null default '' check (char_length(merchant) <= 80),
  card_label text not null default '' check (char_length(card_label) <= 80),
  card_id text,
  -- card    = card_id identifies the managed card to charge
  -- none    = user chose「不指定卡片」for this Wallet card
  -- unknown = no match yet; LINE asks which card after the category
  card_resolution text not null default 'unknown'
    check (card_resolution in ('card', 'none', 'unknown')),
  pending_category_id text,
  occurred_at timestamptz not null,
  status text not null default 'pending'
    check (status in ('pending', 'confirmed', 'dismissed')),
  expense_id text,
  created_at timestamptz not null default now(),
  resolved_at timestamptz
);

create index capture_inbox_user_status_idx
  on public.capture_inbox(user_id, status, occurred_at desc);
create index capture_inbox_user_created_idx
  on public.capture_inbox(user_id, created_at desc);

-- Remembers which managed card a Wallet card name belongs to, so the card
-- question is asked only once per Wallet card. card_id null =「不指定卡片」.
create table public.capture_card_aliases (
  user_id uuid not null references auth.users(id) on delete cascade,
  card_label text not null check (char_length(card_label) <= 80),
  card_id text,
  updated_at timestamptz not null default now(),
  primary key (user_id, card_label)
);

do $$
declare
  table_name text;
begin
  foreach table_name in array array[
    'capture_tokens', 'capture_inbox', 'capture_card_aliases'
  ]
  loop
    execute format('alter table public.%I enable row level security', table_name);
    execute format('revoke all on public.%I from anon, authenticated', table_name);
  end loop;
end
$$;

-- Same list (ids and names) the LINE quick-expense category picker uses.
create or replace function public.capture_expense_categories(p_user_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  items jsonb;
begin
  select jsonb_agg(jsonb_build_object('id', c.id, 'name', c.name)
    order by c.sort_order, c.name) into items
  from public.bookkeeping_categories c
  where c.user_id = p_user_id and c.category_kind = 'expense' and c.is_active;
  return coalesce(items, jsonb_build_array(
    jsonb_build_object('id', 'legacy-food', 'name', '餐飲'),
    jsonb_build_object('id', 'legacy-transport', 'name', '交通'),
    jsonb_build_object('id', 'legacy-shopping', 'name', '購物'),
    jsonb_build_object('id', 'legacy-entertainment', 'name', '娛樂'),
    jsonb_build_object('id', 'legacy-medical', 'name', '醫療'),
    jsonb_build_object('id', 'legacy-other', 'name', '其他')
  ));
end
$$;

create or replace function public.capture_active_cards(p_user_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', card.id, 'name', card.name, 'lastFour', card.last_four,
    'cardType', coalesce(profile.card_type, 'credit')
  ) order by card.name, card.id), '[]'::jsonb)
  from public.credit_cards card
  left join public.payment_card_profiles profile
    on profile.user_id = card.user_id and profile.card_id = card.id
  where card.user_id = p_user_id and card.is_active
$$;

-- Guess the managed card behind a Wallet card name: a remembered alias
-- first, then a unique last-four / card-name / bank-name match.
create or replace function public.capture_match_card(
  p_user_id uuid,
  p_card_label text,
  out card_id text,
  out resolution text
)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  label text := lower(coalesce(p_card_label, ''));
  alias_card text;
  alias_found boolean := false;
  hits text[];
begin
  select a.card_id, true into alias_card, alias_found
  from public.capture_card_aliases a
  where a.user_id = p_user_id and a.card_label = p_card_label;
  if alias_found then
    if alias_card is null then
      card_id := null; resolution := 'none'; return;
    end if;
    if exists (
      select 1 from public.credit_cards c
      where c.user_id = p_user_id and c.id = alias_card and c.is_active
    ) then
      card_id := alias_card; resolution := 'card'; return;
    end if;
  end if;

  card_id := null; resolution := 'unknown';
  if label = '' then return; end if;

  select array_agg(c.id) into hits from public.credit_cards c
  where c.user_id = p_user_id and c.is_active
    and c.last_four ~ '^\d{4}$' and position(c.last_four in label) > 0;
  if cardinality(hits) = 1 then
    card_id := hits[1]; resolution := 'card'; return;
  end if;

  select array_agg(c.id) into hits from public.credit_cards c
  where c.user_id = p_user_id and c.is_active and trim(c.name) <> ''
    and (position(lower(trim(c.name)) in label) > 0
      or position(label in lower(trim(c.name))) > 0);
  if cardinality(hits) = 1 then
    card_id := hits[1]; resolution := 'card'; return;
  end if;

  select array_agg(c.id) into hits from public.credit_cards c
  where c.user_id = p_user_id and c.is_active and trim(c.bank) <> ''
    and position(lower(trim(c.bank)) in label) > 0;
  if cardinality(hits) = 1 then
    card_id := hits[1]; resolution := 'card'; return;
  end if;
end
$$;

-- Everything the LINE message for one inbox row needs.
create or replace function public.capture_descriptor(p_inbox_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  row_data public.capture_inbox;
  categories jsonb;
  suggested_name text;
  suggested_id text;
  card_name text;
  card_last_four text;
begin
  select * into row_data from public.capture_inbox where id = p_inbox_id;
  if not found then return null; end if;
  categories := public.capture_expense_categories(row_data.user_id);

  -- Learn from history: the category last used for this merchant.
  if row_data.merchant <> '' then
    select e.category into suggested_name from public.expenses e
    where e.user_id = row_data.user_id
      and lower(trim(e.merchant)) = lower(row_data.merchant)
    order by e.expense_date desc limit 1;
  end if;
  if suggested_name is not null then
    select item->>'id' into suggested_id
    from jsonb_array_elements(categories) item
    where lower(trim(item->>'name')) = lower(trim(suggested_name))
    limit 1;
  end if;

  if row_data.card_id is not null then
    select c.name, c.last_four into card_name, card_last_four
    from public.credit_cards c
    where c.user_id = row_data.user_id and c.id = row_data.card_id;
  end if;

  return jsonb_build_object(
    'inboxId', row_data.id,
    'status', row_data.status,
    'amountMinor', row_data.amount_minor,
    'currency', row_data.currency,
    'merchant', row_data.merchant,
    'cardLabel', row_data.card_label,
    'cardResolution', row_data.card_resolution,
    'cardName', card_name,
    'cardLastFour', card_last_four,
    'occurredAt', row_data.occurred_at,
    'suggestedCategoryId', suggested_id,
    'categories', categories
  );
end
$$;

create or replace function public.capture_issue_token(
  p_line_user_id text,
  p_token_hash text
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  uid uuid := public.line_linked_owner_id(p_line_user_id);
begin
  if uid is null then return jsonb_build_object('status', 'not_linked'); end if;
  if p_token_hash !~ '^[0-9a-f]{64}$' then raise exception 'invalid_token_hash'; end if;
  insert into public.capture_tokens(user_id, token_hash, created_at, last_used_at)
  values (uid, p_token_hash, now(), null)
  on conflict (user_id) do update
  set token_hash = excluded.token_hash, created_at = now(), last_used_at = null;
  return jsonb_build_object('status', 'issued');
end
$$;

create or replace function public.capture_ingest(
  p_token_hash text,
  p_amount_minor bigint,
  p_currency text,
  p_merchant text,
  p_card_label text,
  p_occurred_at timestamptz default now()
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  uid uuid;
  merchant_value text :=
    left(trim(regexp_replace(coalesce(p_merchant, ''), '\s+', ' ', 'g')), 80);
  label_value text :=
    left(trim(regexp_replace(coalesce(p_card_label, ''), '\s+', ' ', 'g')), 80);
  currency_value text := upper(coalesce(nullif(trim(p_currency), ''), 'TWD'));
  occurred timestamptz := coalesce(p_occurred_at, now());
  existing_id uuid;
  new_id uuid;
  matched record;
  line_user text;
begin
  select t.user_id into uid from public.capture_tokens t
  where t.token_hash = p_token_hash;
  if uid is null then return jsonb_build_object('status', 'invalid_token'); end if;

  if p_amount_minor is null or p_amount_minor <= 0
    or p_amount_minor > 999999999999 then
    return jsonb_build_object('status', 'invalid_amount');
  end if;
  if currency_value !~ '^[A-Z]{3}$' then currency_value := 'TWD'; end if;
  -- Shortcuts sends the phone's clock; refuse obviously wrong timestamps.
  if occurred > now() + interval '10 minutes'
    or occurred < now() - interval '30 days' then
    occurred := now();
  end if;

  if (select count(*) from public.capture_inbox i
      where i.user_id = uid and i.created_at > now() - interval '1 hour') >= 60 then
    return jsonb_build_object('status', 'rate_limited');
  end if;

  update public.capture_tokens set last_used_at = now() where user_id = uid;

  -- A retried Shortcut run (or a double-fired automation) is not a second
  -- purchase.
  select i.id into existing_id from public.capture_inbox i
  where i.user_id = uid and i.amount_minor = p_amount_minor
    and i.currency = currency_value and i.merchant = merchant_value
    and i.card_label = label_value
    and i.occurred_at between occurred - interval '2 minutes'
                          and occurred + interval '2 minutes'
  order by i.created_at desc limit 1;
  if existing_id is not null then
    return jsonb_build_object('status', 'duplicate', 'inboxId', existing_id);
  end if;

  select * into matched from public.capture_match_card(uid, label_value);
  insert into public.capture_inbox(
    user_id, amount_minor, currency, merchant, card_label, card_id,
    card_resolution, occurred_at
  ) values (
    uid, p_amount_minor, currency_value, merchant_value, label_value,
    matched.card_id, matched.resolution, occurred
  ) returning id into new_id;

  select l.line_user_id into line_user from public.line_account_links l
  where l.user_id = uid and l.enabled;

  return jsonb_build_object(
    'status', 'created',
    'lineUserId', line_user,
    'capture', public.capture_descriptor(new_id)
  );
end
$$;

create or replace function public.line_capture_open(
  p_line_user_id text,
  p_inbox_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  uid uuid := public.line_linked_owner_id(p_line_user_id);
  row_status text;
begin
  if uid is null then return jsonb_build_object('status', 'not_linked'); end if;
  select i.status into row_status from public.capture_inbox i
  where i.id = p_inbox_id and i.user_id = uid;
  if row_status is null then return jsonb_build_object('status', 'not_found'); end if;
  if row_status <> 'pending' then
    return jsonb_build_object('status', 'already_' || row_status);
  end if;
  return jsonb_build_object(
    'status', 'ok', 'capture', public.capture_descriptor(p_inbox_id)
  );
end
$$;

create or replace function public.line_capture_list_pending(p_line_user_id text)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  uid uuid := public.line_linked_owner_id(p_line_user_id);
begin
  if uid is null then return jsonb_build_object('status', 'not_linked'); end if;
  return jsonb_build_object(
    'status', 'ok',
    'total', (select count(*) from public.capture_inbox i
              where i.user_id = uid and i.status = 'pending'),
    'items', coalesce((
      select jsonb_agg(jsonb_build_object(
        'inboxId', p.id, 'amountMinor', p.amount_minor, 'currency', p.currency,
        'merchant', p.merchant, 'occurredAt', p.occurred_at
      ) order by p.occurred_at desc)
      from (
        select * from public.capture_inbox i
        where i.user_id = uid and i.status = 'pending'
        order by i.occurred_at desc limit 12
      ) p
    ), '[]'::jsonb)
  );
end
$$;

-- p_category_id: category chosen in LINE (null = reuse the one stored while
--   waiting for the card answer).
-- p_card_choice: managed card id, '__none__' for「不指定卡片」, or null to
--   use the card matched at ingest. A choice is remembered for this Wallet
--   card name.
create or replace function public.line_capture_confirm(
  p_line_user_id text,
  p_inbox_id uuid,
  p_category_id text default null,
  p_card_choice text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  uid uuid := public.line_linked_owner_id(p_line_user_id);
  row_data public.capture_inbox;
  category_id text;
  category_name text;
  effective_card text;
  effective_resolution text;
  card_type text;
  card_name text;
  method text;
  item_text text;
  saved jsonb;
begin
  if uid is null then return jsonb_build_object('status', 'not_linked'); end if;
  select * into row_data from public.capture_inbox
  where id = p_inbox_id and user_id = uid for update;
  if not found then return jsonb_build_object('status', 'not_found'); end if;
  if row_data.status = 'confirmed' then
    return jsonb_build_object('status', 'already_confirmed');
  end if;
  if row_data.status = 'dismissed' then
    return jsonb_build_object('status', 'already_dismissed');
  end if;
  if row_data.currency <> 'TWD' then
    return jsonb_build_object('status', 'unsupported_currency');
  end if;

  category_id := coalesce(p_category_id, row_data.pending_category_id);
  select item->>'name' into category_name
  from jsonb_array_elements(public.capture_expense_categories(uid)) item
  where item->>'id' = category_id limit 1;
  if category_name is null then
    return jsonb_build_object('status', 'invalid_category');
  end if;

  if p_card_choice is not null then
    if p_card_choice = '__none__' then
      effective_card := null;
      effective_resolution := 'none';
    else
      if not exists (
        select 1 from public.credit_cards c
        where c.user_id = uid and c.id = p_card_choice and c.is_active
      ) then
        return jsonb_build_object('status', 'invalid_card');
      end if;
      effective_card := p_card_choice;
      effective_resolution := 'card';
    end if;
    if row_data.card_label <> '' then
      insert into public.capture_card_aliases(user_id, card_label, card_id, updated_at)
      values (uid, row_data.card_label, effective_card, now())
      on conflict (user_id, card_label) do update
      set card_id = excluded.card_id, updated_at = now();
    end if;
  else
    effective_card := row_data.card_id;
    effective_resolution := row_data.card_resolution;
    -- The matched card may have been deactivated since the tap.
    if effective_resolution = 'card' and not exists (
      select 1 from public.credit_cards c
      where c.user_id = uid and c.id = effective_card and c.is_active
    ) then
      effective_card := null;
      effective_resolution := 'unknown';
    end if;
  end if;

  if effective_resolution = 'unknown' then
    update public.capture_inbox
    set pending_category_id = category_id, card_id = null,
        card_resolution = 'unknown'
    where id = row_data.id;
    return jsonb_build_object(
      'status', 'needs_card',
      'cardLabel', row_data.card_label,
      'cards', public.capture_active_cards(uid)
    );
  end if;

  if effective_resolution = 'card' then
    select coalesce(p.card_type, 'credit'), c.name into card_type, card_name
    from public.credit_cards c
    left join public.payment_card_profiles p
      on p.user_id = c.user_id and p.card_id = c.id
    where c.user_id = uid and c.id = effective_card;
    method := case when card_type = 'debit' then 'debitCard' else 'creditCard' end;
  else
    method := 'other';
  end if;

  item_text := coalesce(nullif(row_data.merchant, ''), 'Apple Pay 消費');
  saved := public.line_confirm_expense(
    p_line_user_id, row_data.id, row_data.amount_minor, item_text,
    category_name, method, null, effective_card, row_data.occurred_at
  );
  if saved->>'status' <> 'saved' then return saved; end if;

  update public.expenses
  set merchant = row_data.merchant, note = 'Apple Pay 捷徑建立'
  where user_id = uid and id = saved->>'expenseId';

  update public.capture_inbox
  set status = 'confirmed', expense_id = saved->>'expenseId',
      card_id = effective_card, card_resolution = effective_resolution,
      pending_category_id = null, resolved_at = now()
  where id = row_data.id;

  return jsonb_build_object(
    'status', 'saved',
    'duplicate', coalesce((saved->>'duplicate')::boolean, false),
    'amountMinor', row_data.amount_minor,
    'merchant', item_text,
    'category', category_name,
    'cardName', card_name
  );
end
$$;

create or replace function public.line_capture_dismiss(
  p_line_user_id text,
  p_inbox_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  uid uuid := public.line_linked_owner_id(p_line_user_id);
  row_status text;
begin
  if uid is null then return jsonb_build_object('status', 'not_linked'); end if;
  select i.status into row_status from public.capture_inbox i
  where i.id = p_inbox_id and i.user_id = uid for update;
  if row_status is null then return jsonb_build_object('status', 'not_found'); end if;
  if row_status <> 'pending' then
    return jsonb_build_object('status', 'already_' || row_status);
  end if;
  update public.capture_inbox
  set status = 'dismissed', resolved_at = now()
  where id = p_inbox_id;
  return jsonb_build_object('status', 'dismissed');
end
$$;

do $$
declare
  signature text;
begin
  foreach signature in array array[
    'capture_expense_categories(uuid)',
    'capture_active_cards(uuid)',
    'capture_match_card(uuid,text)',
    'capture_descriptor(uuid)',
    'capture_issue_token(text,text)',
    'capture_ingest(text,bigint,text,text,text,timestamptz)',
    'line_capture_open(text,uuid)',
    'line_capture_list_pending(text)',
    'line_capture_confirm(text,uuid,text,text)',
    'line_capture_dismiss(text,uuid)'
  ]
  loop
    execute format(
      'revoke all on function public.%s from public, anon, authenticated',
      signature
    );
    execute format('grant execute on function public.%s to service_role', signature);
  end loop;
end
$$;
